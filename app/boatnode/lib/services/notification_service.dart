import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _lastNotificationTimeKey = 'last_low_battery_notification_time';
  static const int _notificationIntervalHours = 12;

  Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
      macOS: initializationSettingsDarwin,
    );

    await _flutterLocalNotificationsPlugin.initialize(initializationSettings);

    // Request permissions
    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> checkBatteryAndNotify(int batteryLevel, String title, String body) async {
    if (batteryLevel < 20) {
      final prefs = await SharedPreferences.getInstance();
      final lastTimeStr = prefs.getString(_lastNotificationTimeKey);
      DateTime? lastTime;
      
      if (lastTimeStr != null) {
        lastTime = DateTime.tryParse(lastTimeStr);
      }

      final now = DateTime.now();
      
      // If never notified or last notification was more than 12 hours ago
      if (lastTime == null || now.difference(lastTime).inHours >= _notificationIntervalHours) {
        await showChargingReminder(title, body);
        await prefs.setString(_lastNotificationTimeKey, now.toIso8601String());
      }
    } else {
      // If battery is > 20%, we don't strictly need to clear the timestamp, 
      // but keeping it means if it drops again quickly we might not notify immediately 
      // if we consider "interval" strictly. 
      // However, the requirement says "stop the reminder notification if the next signal... says > 20%".
      // This implies we should reset the cycle or simply not show it.
      // Since we only show it on < 20, we are good. 
      // If we want to allow immediate notification if it drops again after being charged:
      if (batteryLevel > 20) {
         final prefs = await SharedPreferences.getInstance();
         await prefs.remove(_lastNotificationTimeKey);
      }
    }
  }

  Future<void> showChargingReminder(String title, String body) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'battery_channel',
      'Battery Notifications',
      channelDescription: 'Notifications for battery status',
      importance: Importance.max,
      priority: Priority.high,
    );
    
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      0,
      title,
      body,
      platformChannelSpecifics,
    );
  }
}
