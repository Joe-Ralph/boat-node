import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:boatnode/services/backend_service.dart';
import 'package:boatnode/services/log_service.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        initialNotificationTitle: 'Journey Mode Active',
        initialNotificationContent: 'Tracking your location...',
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
    // We need the keys. Ideally passed via args, but for now we use the known keys from main.dart
    // Note: In a real app, use environment variables or pass via platform channel.
    try {
      const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
      const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

      if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
        await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
      } else {
        LogService.e("Background Service: Supabase keys missing in env.");
      }
    } catch (e) {
      LogService.e(
        "Background Service: Supabase init error (might be already init)",
        e,
      );
    }

    // Initialize dependencies in the isolate
    // Note: Supabase needs to be initialized if we use it.
    // However, passing config to isolate is tricky.
    // Ideally, we should initialize Supabase here with the same keys.
    // For now, let's assume we can access SharedPreferences to get session/config?
    // Or we might need to rely on HTTP calls if Supabase init is complex.
    // But BackendService uses Supabase.instance.

    // TODO: Initialize Supabase here.
    // Since I don't have the keys handy in this context without reading main.dart or config,
    // I will assume for this task that we might need to pass them or hardcode for now.
    // Let's try to read from main.dart or config if possible, but for now I'll add a placeholder.
    // Actually, let's look at main.dart to see how it's initialized.

    // For now, let's implement the loop.

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

    // Bring up the service loop
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (service is AndroidServiceInstance) {
        if (!(await service.isForegroundService())) {
          // Optional: Check if foreground
        }
      }

      try {
        // 1. Get Location
        final position = await Geolocator.getCurrentPosition();

        // 2. Get User/Boat Info (Need SharedPreferences in Isolate)
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString(
          'user_id_cache',
        ); // We need to cache this!

        if (userId != null) {
          // We need to initialize Supabase to use BackendService
          // Or use raw HTTP.
          // Let's try to use BackendService if we can init Supabase.
          // Assuming we can't easily init Supabase without keys, let's print for now
          // and mark as "Native Tracking Active".

          LogService.i(
            "Background Service: Location ${position.latitude}, ${position.longitude}",
          );

          // Update Notification
          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: "Journey Mode Active",
              content: "Lat: ${position.latitude}, Lng: ${position.longitude}",
            );
          }

          // Transmit Location
          // Try to get cached boat_id first
          String? boatId = prefs.getString('boat_id_cache');

          if (boatId == null) {
            // Fallback: Fetch boats from backend
            try {
              final boats = await BackendService.getUserBoats(userId);
              if (boats.isNotEmpty) {
                boatId = boats.first['id'] as String;
                // Cache it for next time
                await prefs.setString('boat_id_cache', boatId);
              }
            } catch (e) {
              LogService.e("Background Service: Error fetching boats", e);
            }
          }

          if (boatId != null) {
            try {
              await BackendService.updateLiveLocation(
                lat: position.latitude,
                lon: position.longitude,
                battery: 100, // Mock battery for background
                boatId: boatId,
                speed: position.speed,
                heading: position.heading,
              );
              LogService.i(
                "Background Service: Location sent for boat $boatId",
              );
            } catch (e) {
              LogService.e("Background Service: Transmission error", e);
            }
          } else {
            LogService.w(
              "Background Service: No boat ID found for user $userId",
            );
          }
        }
      } catch (e) {
        LogService.e("Background Service Error", e);
      }
    });
  }
}
