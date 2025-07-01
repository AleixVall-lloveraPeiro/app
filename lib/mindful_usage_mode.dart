// mindful_usage_mode.dart
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
    _sendActivationNotification();
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
    // Simulate phone usage check
    List<Application> apps = await DeviceApps.getInstalledApplications(includeAppIcons: false);
    return apps.isNotEmpty; // Simulated activity
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

  Future<void> _sendActivationNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'mindful_channel',
      'Mindful Usage Alerts',
      channelDescription: 'Notifies you to be mindful of your phone usage',
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      1,
      'Mindful Usage Mode Activated',
      'You’ve entered mindful mode. Stay aware of your screen time. ⏰',
      notificationDetails,
    );
  }
}