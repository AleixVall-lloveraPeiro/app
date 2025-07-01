import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_apps/device_apps.dart';

class MindfulUsageMode {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  Timer? _usageTimer;
  int _usageMinutes = 0;

  MindfulUsageMode() {
    _initializeNotifications();
  }

  void _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  void start() {
    _sendStartNotification();
    _usageMinutes = 0;
    _usageTimer?.cancel();
    _usageTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      bool isPhoneBeingUsed = await _checkIfPhoneIsInUse();
      if (isPhoneBeingUsed) {
        _usageMinutes += 5;
        _sendMindfulNotification();
      }
    });
  }

  void stop() {
    _usageTimer?.cancel();
  }

  Future<bool> _checkIfPhoneIsInUse() async {
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
      'You’ve used your phone for $_usageMinutes minutes. Take a mindful breath. 🌱',
      notificationDetails,
    );
  }

  Future<void> _sendStartNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'mindful_channel_start',
      'Mindful Mode Started',
      channelDescription: 'Notifies when mindful usage mode is activated',
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      1,
      'Mindful Usage Mode Activated',
      'Timer started. We’ll remind you every 5 minutes of continuous usage.',
      notificationDetails,
    );
  }
}