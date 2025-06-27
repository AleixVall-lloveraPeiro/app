import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_apps/device_apps.dart';

class MindfulUsageMode {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  Timer? _usageTimer;

  MindfulUsageMode() {
    _initializeNotifications();
  }

  void _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  void start() {
    _usageTimer?.cancel();
    _usageTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      bool isPhoneBeingUsed = await _checkIfPhoneIsInUse();
      if (isPhoneBeingUsed) {
        _sendMindfulNotification();
      }
    });
  }

  void stop() {
    _usageTimer?.cancel();
  }

  Future<bool> _checkIfPhoneIsInUse() async {
    // Here we simulate phone usage check.
    // In a full implementation, you might use a plugin like `usage_stats` (Android-only)
    // to check screen time or app foreground usage.

    List<Application> apps = await DeviceApps.getInstalledApplications(includeAppIcons: false);
    return apps.isNotEmpty; // Simulated "activity"
  }

  Future<void> _sendMindfulNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'mindful_channel',
      'Mindful Usage Alerts',
      channelDescription: 'Notifies you to be mindful of your phone usage',
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0,
      'Stay Present',
      'You’ve been on your phone for 5 minutes. Take a mindful breath. 🌱',
      notificationDetails,
    );
  }
}