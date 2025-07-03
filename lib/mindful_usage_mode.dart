import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:screen_state/screen_state.dart';

class MindfulUsageMode {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Screen _screen = Screen();

  StreamSubscription<ScreenStateEvent>? _screenSubscription;
  Timer? _activeUsageTimer;
  int _activeSeconds = 0;

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
    _listenToScreenEvents();
  }

  void stop() {
    _screenSubscription?.cancel();
    _activeUsageTimer?.cancel();
    _activeSeconds = 0;
  }

  void _listenToScreenEvents() {
    _screenSubscription = _screen.screenStateStream.listen((event) {
      if (event == ScreenStateEvent.SCREEN_ON) {
        _startCounting();
      } else if (event == ScreenStateEvent.SCREEN_OFF) {
        _stopCounting(reset: true);
      }
    });
  }

  void _startCounting() {
    _activeUsageTimer?.cancel();
    _activeSeconds = 0;
    _activeUsageTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _activeSeconds++;
      if (_activeSeconds >= 300) { // 5 minutes
        _sendMindfulNotification();
        _stopCounting(reset: true);
      }
    });
  }

  void _stopCounting({bool reset = false}) {
    _activeUsageTimer?.cancel();
    if (reset) _activeSeconds = 0;
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
      'You’ve been using your phone for 5 minutes straight. Take a mindful pause. 🌱',
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
      'We’ll notify you if you spend 5 minutes straight on your phone.',
      notificationDetails,
    );
  }
}