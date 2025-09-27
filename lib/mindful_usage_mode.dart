import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:screen_state/screen_state.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MindfulUsageMode {
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Screen _screen = Screen();

  StreamSubscription<ScreenStateEvent>? _screenSubscription;
  Timer? _activeUsageTimer;
  int _activeSeconds = 0;
  bool _isRunning = false;

  MindfulUsageMode() {
    _initializeNotifications();
  }

  void _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  // MODIFIED: Added optional silent parameter
  Future<void> start({bool silent = false}) async {
    print('[MINDFUL] Starting Mindful Usage Mode...');
    
    // Only send notification if not silent mode (user manually activated)
    if (!silent) {
      _sendStartNotification();
    }
    
    // Save state to persistent storage
    await _saveRunningState(true);
    
    // Start foreground service
    await _startForegroundService();
    
    _listenToScreenEvents();
    _startCounting();
    _isRunning = true;
    print('[MINDFUL] Mindful Usage Mode started successfully ${silent ? '(silent)' : ''}');
  }

  Future<void> stop() async {
    print('[MINDFUL] Stopping Mindful Usage Mode...');
    _screenSubscription?.cancel();
    _activeUsageTimer?.cancel();
    _activeSeconds = 0;
    _isRunning = false;
    
    // Save state to persistent storage
    await _saveRunningState(false);
    
    // Stop foreground service
    await FlutterForegroundTask.stopService();
    print('[MINDFUL] Mindful Usage Mode stopped');
  }

  Future<void> _saveRunningState(bool isRunning) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('mindfulModeRunning', isRunning);
  }

  Future<bool> wasRunning() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('mindfulModeRunning') ?? false;
  }

  Future<void> _startForegroundService() async {
    print('[MINDFUL] Starting foreground service...');
    
    await FlutterForegroundTask.startService(
      notificationTitle: 'Mindful Usage Mode Active',
      notificationText: 'Tracking your screen time',
    );
    
    print('[MINDFUL] Foreground service started');
  }

  // ... rest of your methods remain exactly the same ...

  void _listenToScreenEvents() {
    _screenSubscription = _screen.screenStateStream?.listen((event) {
      if (event == ScreenStateEvent.SCREEN_ON) {
        print('[MINDFUL] Pantalla ENCENDIDA');
        _startCounting();
      } else if (event == ScreenStateEvent.SCREEN_OFF) {
        print('[MINDFUL] Pantalla APAGADA');
        _stopCounting(reset: true);
      }
    });
  }

  void _startCounting() {
    _activeUsageTimer?.cancel();
    _activeUsageTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _activeSeconds++;
      print('[MINDFUL] Segundos activos: $_activeSeconds');
      if (_activeSeconds % 300 == 0) { // Cada 5 minutos seguidos
        _sendMindfulNotification();
      }
    });
  }

  void _stopCounting({bool reset = false}) {
    _activeUsageTimer?.cancel();
    if (reset) {
      _activeSeconds = 0;
    }
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
      'You\'ve been using your phone for 5 minutes straight. Take a mindful pause. 🌱',
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
      'We\'ll notify you if you spend 5 minutes straight on your phone.',
      notificationDetails,
    );
  }

  bool get isRunning => _isRunning;
}