import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:boatnode/services/log_service.dart';
import 'package:boatnode/constants.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:uuid/uuid.dart';

@pragma('vm:entry-point')
class BackgroundService {
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    /// OPTIONAL, using custom notification channel id
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'my_foreground', // id
      'MY FOREGROUND SERVICE', // title
      description:
          'This channel is used for important notifications.', // description
      importance: Importance.low, // importance must be at low or higher level
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // this will be executed when app is in foreground or background in separated isolate
        onStart: onStart,

        // auto start service
        autoStart: true,
        isForegroundMode: true,

        notificationChannelId: 'my_foreground',
        initialNotificationTitle: 'BoatNode Active',
        initialNotificationContent: 'Monitoring SOS signals...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        // auto start service
        autoStart: true,

        // this will be executed when app is in foreground in separated isolate
        onForeground: onStart,

        // you have to enable background fetch capability on xcode project
        onBackground: onIosBackground,
      ),
    );
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    // Only available for flutter 3.0.0 and later
    DartPluginRegistrant.ensureInitialized();
    try {
      // Hardcoded values to ensure isolate has access
      const supabaseUrl = 'https://ltlftxaskaebqwptcbdq.supabase.co';
      const supabaseAnonKey = 'sb_publishable_R9EBVNhFL2rQOAUV2ihJ3A_SaSaPqbz';

      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
        await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
        LogService.i("Background Service v2: Supabase initialized");
      } else {
        LogService.e("Background Service v2: Supabase keys missing.");
      }
    } catch (e) {
      LogService.e(
        "Background Service v2: Supabase init error (might be already init)",
        e,
      );
    }

    if (service is AndroidServiceInstance) {
      service.on('setAsForeground').listen((event) {
        service.setAsForegroundService();
      });

      service.on('setAsBackground').listen((event) {
        service.setAsBackgroundService();
      });
    }

    service.on('stopService').listen((event) {
      service.stopSelf();
    });

    service.on('updateJourneyState').listen((event) async {
      LogService.i("Background Service v2: Refreshing Journey State...");
    });

    // Flag to track if we are already listening
    bool isListeningToSos = false;
    bool hasLoggedMissingUser = false;
    // Track notified signal IDs to prevent duplicate calls
    final Set<String> notifiedSignalIds = {};

    // --- SOS LISTENER SETUP FUNCTION ---
    Future<void> setupSosListener() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id_cache');

        if (userId != null && !isListeningToSos) {
          final supabase = Supabase.instance.client;
          LogService.i(
            "Background Service v2: Setting up SOS listener for user $userId",
          );

          if (isListeningToSos) return; // Double check

          supabase.from('sos_signals').stream(primaryKey: ['id']).eq('receiver_id', userId).listen((
            List<Map<String, dynamic>> data,
          ) async {
            LogService.i(
              "Background Service v2: Stream Activity. Count: ${data.length}",
            );

            for (final signal in data) {
              final signalId = signal['id'];
              final status = signal['status'];

              // Cleanup resolved/cancelled signals from history
              if (status != 'pending') {
                if (notifiedSignalIds.contains(signalId)) {
                  notifiedSignalIds.remove(signalId);
                  LogService.d(
                    "Background Service: Cleared notified ID $signalId",
                  );
                }
                continue;
              }

              LogService.d(
                "Background Service v2: Signal $signalId Status: $status",
              );

              if (status == 'pending' &&
                  !notifiedSignalIds.contains(signalId)) {
                // Check if signal is too old (e.g. created more than 60 mins ago)
                // We use a lenient window to account for time skew between device and server
                final createdAtStr = signal['created_at'] as String?;
                if (createdAtStr != null) {
                  try {
                    final createdAt = DateTime.parse(createdAtStr).toUtc();
                    final now = DateTime.now().toUtc();
                    final diff = now.difference(createdAt);

                    LogService.d(
                      "Background Service: Signal Check - Now: $now, Created: $createdAt, Diff: ${diff.inMinutes}m",
                    );

                    if (diff.inMinutes > 60) {
                      LogService.i(
                        "Background Service: Skipping old SOS (Age: ${diff.inMinutes}m) ID: $signalId",
                      );
                      // Mark as notified so we don't check again
                      notifiedSignalIds.add(signalId);
                      continue;
                    }
                  } catch (e) {
                    LogService.e(
                      "Background Service: Error parsing created_at",
                      e,
                    );
                  }
                }

                LogService.i(
                  "Background Service v2: PENDING SOS detected! ID: $signalId",
                );
                notifiedSignalIds.add(signalId);
                // Await to ensure we don't skip or overlap too fast
                await _showIncomingCall(signal);
              } else if (status == 'pending' &&
                  notifiedSignalIds.contains(signalId)) {
                LogService.d(
                  "Background Service: Skipping duplicate alert for $signalId",
                );
              }
            }
          });

          isListeningToSos = true;
          hasLoggedMissingUser = false;
          LogService.i("Background Service v2: SOS Listener Connected.");
        } else if (userId == null) {
          if (!hasLoggedMissingUser) {
            LogService.d(
              "Background Service v2: No user_id_cache found yet. Waiting...",
            );
            hasLoggedMissingUser = true;
          }
        }
      } catch (e) {
        LogService.e("Background Service: Error setting up SOS listener", e);
        // We will try again next loop
        isListeningToSos = false;
      }
    }

    // Attempt initial setup
    await setupSosListener();

    // Bring up the service loop for Location Updates AND Reconnection
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        // 1. Retry SOS Listener if needed
        if (!isListeningToSos) {
          await setupSosListener();
        }

        final prefsLoop = await SharedPreferences.getInstance();
        final isJourneyActive = prefsLoop.getBool('is_journey_active') ?? false;
        final currentUserId = prefsLoop.getString('user_id_cache');

        // 2. Location Updates (Only if Journey is Active)
        if (isJourneyActive) {
          final position = await Geolocator.getCurrentPosition();

          if (currentUserId != null) {
            // Keep the notification updated
            if (service is AndroidServiceInstance) {
              String statusText = "Journey Active: Tracking";
              if (!isListeningToSos) statusText += " (SOS DC)";

              service.setForegroundNotificationInfo(
                title: "BoatNode Active",
                content:
                    "$statusText | Lat: ${position.latitude.toStringAsFixed(4)}",
              );
            }

            final boatId = prefsLoop.getString('boat_id_cache');
            // Upload to Backend if we have a valid position and user is logged in
            if (boatId != null) {
              // Future: Implement background upload logic here if needed.
              LogService.d(
                "Background Service: Have boatId, could upload location.",
              );
            }
          }
        } else {
          // Journey NOT active
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "BoatNode Active",
              content: "Monitoring SOS signals...",
            );
          }
        }
      } catch (e) {
        LogService.e("Background Service Loop Error", e);
      }
    });
  }

  static Future<void> _showIncomingCall(Map<String, dynamic> signal) async {
    LogService.i(
      "Background Service: Attempting to show CallKit for ${signal['id']}",
    );

    // Extract location from 'extra' jsonb column if it exists, or top level
    Map<String, dynamic> extraData = {};
    if (signal['extra'] != null) {
      extraData = Map<String, dynamic>.from(signal['extra']);
    } else {
      // Fallback
      extraData = {'lat': signal['lat'], 'long': signal['long']};
    }

    final params = CallKitParams(
      id: signal['id'] ?? const Uuid().v4(),
      nameCaller: 'SOS ALERT',
      appName: 'BoatNode',
      avatar: 'https://i.pravatar.cc/300', // Placeholder
      handle: 'Someone nearby needs help!',
      type: 0, // Audio Call
      duration: 30000,
      textAccept: 'View Location',
      textDecline: 'Ignore',
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed SOS Alert',
        callbackText: 'Call back',
      ),
      extra: extraData, // Pass the correct extra data
      headers: <String, dynamic>{'apiKey': 'Abc@123!', 'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#D50000', // Red for SOS
        backgroundUrl: 'assets/test.png',
        actionColor: '#4CAF50',
        incomingCallNotificationChannelName: "SOS Alerts",
        missedCallNotificationChannelName: "Missed SOS",
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: true,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: 'system_ringtone_default',
      ),
    );
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
      LogService.i("Background Service: CallKit show command sent.");
    } catch (e) {
      LogService.e("Background Service: Failed to show CallKit", e);
    }
  }
}
