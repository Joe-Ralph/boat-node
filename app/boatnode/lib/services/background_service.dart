import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:boatnode/services/log_service.dart';

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
        autoStart: false,
        isForegroundMode: true,

        notificationChannelId: 'my_foreground',
        initialNotificationTitle: 'BoatNode Active',
        initialNotificationContent: 'Monitoring SOS signals...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        // auto start service
        autoStart: false,

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

    // Initialize Supabase in the isolate
    try {
      const supabaseUrl = String.fromEnvironment(
        'SUPABASE_URL',
        defaultValue: 'https://dummy.supabase.co',
      );
      const supabaseAnonKey = String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: 'dummy-key',
      );

      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
        await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
        LogService.i("Background Service: Supabase initialized");
      } else {
        LogService.e("Background Service: Supabase keys missing in env.");
      }
    } catch (e) {
      LogService.e(
        "Background Service: Supabase init error (might be already init)",
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

    // Flag to track if we are already listening
    bool isListeningToSos = false;

    // --- SOS LISTENER SETUP FUNCTION ---
    Future<void> setupSosListener() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id_cache');

        if (userId != null && !isListeningToSos) {
          final supabase = Supabase.instance.client;
          LogService.i(
            "Background Service: Setting up SOS listener for user $userId",
          );

          supabase
              .from('sos_signals')
              .stream(primaryKey: ['id'])
              .eq('receiver_id', userId)
              .listen((List<Map<String, dynamic>> data) {
                // Log the raw data count for debug
                LogService.i(
                  "Background Service: Recieved ${data.length} sos signals",
                );
                for (final signal in data) {
                  if (signal['status'] == 'pending') {
                    LogService.i(
                      "Background Service: PENDING SOS detected! ID: ${signal['id']}",
                    );
                    _showIncomingCall(signal);
                  }
                }
              });

          isListeningToSos = true;
          LogService.i("Background Service: SOS Listener Connected.");
        } else if (userId == null) {
          LogService.d(
            "Background Service: No user_id_cache found yet. Waiting...",
          );
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

        // 2. Location Updates
        final position = await Geolocator.getCurrentPosition();
        final prefsLoop = await SharedPreferences.getInstance();
        final currentUserId = prefsLoop.getString('user_id_cache');

        if (currentUserId != null) {
          // Keep the notification updated
          if (service is AndroidServiceInstance) {
            String statusText = "SOS Monitoring Active";
            if (!isListeningToSos) statusText += " (Not Connected)";

            service.setForegroundNotificationInfo(
              title: "BoatNode Active",
              content:
                  "$statusText | Lat: ${position.latitude.toStringAsFixed(4)}",
            );
          }
        }
      } catch (e) {
        LogService.e("Background Service Loop Error", e);
      }
    });
  }

  static Future<void> _showIncomingCall(Map<String, dynamic> signal) async {
    final params = CallKitParams(
      id: signal['id'] ?? const Uuid().v4(),
      nameCaller: 'SOS ALERT',
      appName: 'BoatNode',
      avatar: 'https://i. Pravatar.cc/300', // Placeholder
      handle: 'Someone nearby needs help!',
      type: 0, // Audio Call
      duration: 30000,
      textAccept: 'View Location',
      textDecline: 'Ignore',
      missedCallNotification: NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed SOS Alert',
        callbackText: 'Call back',
      ),
      extra: <String, dynamic>{'lat': signal['lat'], 'long': signal['long']},
      headers: <String, dynamic>{'apiKey': 'Abc@123!', 'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#D50000', // Red for SOS
        backgroundUrl: 'assets/test.png',
        actionColor: '#4CAF50',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: '',
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
    await FlutterCallkitIncoming.showCallkitIncoming(params);

    // Listen for call events (Accept/Decline) happens in main app usually if UI is open,
    // but here we just show it. Handling the tap needs to be done via EventListener in main.dart or here.
  }
}
