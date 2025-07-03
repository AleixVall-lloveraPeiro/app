import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PomodoroMode {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  final ValueNotifier<Duration> timeLeft = ValueNotifier(const Duration(minutes: 25));
  final ValueNotifier<bool> isWorking = ValueNotifier(true);
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  final ValueNotifier<int> completedCycles = ValueNotifier(0);

  Timer? _timer;

  final Duration workDuration = const Duration(seconds: 5);
  final Duration restDuration = const Duration(seconds: 5);

  VoidCallback? onPomodoroCompleted;

  PomodoroMode({this.onPomodoroCompleted}) {
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
    );

    await _notificationsPlugin.initialize(settings);
  }

  Future<void> _showNotification(String title, String body) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'pomodoro_channel',
      'Pomodoro Notifications',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(0, title, body, notificationDetails);
  }

  void start() {
    if (isRunning.value) return;
    isRunning.value = true;
    _startSession();
  }

  void _startSession() {
    final sessionDuration = isWorking.value ? workDuration : restDuration;
    timeLeft.value = sessionDuration;

    _showNotification(
      isWorking.value ? 'Work session started' : 'Break time!',
      isWorking.value ? 'Focus for 25 minutes' : 'Relax for 5 minutes',
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeft.value.inSeconds == 0) {
        timer.cancel();
        _switchSession();
        return;
      }
      timeLeft.value = timeLeft.value - const Duration(seconds: 1);
    });
  }

  void _switchSession() {
    isWorking.value = !isWorking.value;
    if (isWorking.value) {
      completedCycles.value++;
    }

    if (completedCycles.value >= 4 && isWorking.value) {
      stop();
      if (onPomodoroCompleted != null) {
        onPomodoroCompleted!();
      }
      return;
    }

    _startSession();
  }

  void stop() {
    _timer?.cancel();
    isRunning.value = false;
    timeLeft.value = workDuration;
    isWorking.value = true;
    completedCycles.value = 0;
  }
}
