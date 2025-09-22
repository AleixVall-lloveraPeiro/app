
import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_state/screen_state.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';

import 'backend_service_daily_usage_mode.dart';

void backgroundCountCallback() async {
  final service = UsageStorageService();
  await service.addUsage(const Duration(seconds: 15));
}

class DailyUsageGoalManager {
  static final DailyUsageGoalManager _instance = DailyUsageGoalManager._internal();
  factory DailyUsageGoalManager() => _instance;
  DailyUsageGoalManager._internal();

  final UsageStorageService _usageService = UsageStorageService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Screen _screen = Screen();

  StreamSubscription<ScreenStateEvent>? _screenSubscription;
  Timer? _countTimer;
  Duration _dailyLimit = const Duration(hours: 2);
  bool _isCounting = false;
  bool _initialized = false;

  bool _halfwayNotified = false;
  bool _fifteenLeftNotified = false;
  bool _fiveLeftNotified = false;
  bool _limitReachedNotified = false;

  int _currentStreak = 0;
  int _maxStreak = 0;

  DateTime _currentDay = DateTime.now();

  Future<void> start() async {
  if (_initialized) return;
  _initialized = true;

  await _initializeNotifications();
  await _loadStoredData();
  _currentDay = DateTime.now();

  await AndroidAlarmManager.periodic(
    const Duration(seconds: 15),
    0,
    backgroundCountCallback,
    wakeup: true,
    exact: true,
    rescheduleOnReboot: true,
  );

  _listenToScreenEvents();
  _startCounting();
}


  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _loadStoredData() async {
    _dailyLimit = await _usageService.getDailyLimit();
    _currentStreak = await _usageService.getCurrentStreak();
    _maxStreak = await _usageService.getMaxStreak();
  }

  void _listenToScreenEvents() {
    _screenSubscription = _screen.screenStateStream.listen((event) {
      if (event == ScreenStateEvent.SCREEN_ON) {
        _startCounting();
      } else if (event == ScreenStateEvent.SCREEN_OFF) {
        _stopCounting();
      }
    });
  }

  void _startCounting() {
    if (_isCounting) return;
    _isCounting = true;

    _countTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      await _usageService.addUsage(const Duration(seconds: 1));
      final current = await _usageService.getDailyUsage();
      _handleProgressNotifications(current);

      final now = DateTime.now();
      if (!_isSameDate(now, _currentDay)) {
        _currentDay = now;
        resetNotificationFlags();
        _currentStreak = await _usageService.getCurrentStreak();
        _maxStreak = await _usageService.getMaxStreak();
      }
    });
  }

  void _stopCounting() {
    _isCounting = false;
    _countTimer?.cancel();
  }

  void _handleProgressNotifications(Duration current) {
    if (!_halfwayNotified && current >= _dailyLimit * 0.5) {
      _sendNotification('Halfway There', 'You’ve used half of your daily goal.');
      _halfwayNotified = true;
    }

    final remaining = _dailyLimit - current;

    if (!_fifteenLeftNotified && remaining.inMinutes <= 15 && remaining.inMinutes > 5) {
      _sendNotification('Almost Done', 'Only 15 minutes left of your daily usage goal.');
      _fifteenLeftNotified = true;
    }

    if (!_fiveLeftNotified && remaining.inMinutes <= 5 && remaining.inMinutes > 0) {
      _sendNotification('5 Minutes Left', 'You’re almost at your limit. Just 5 minutes remaining.');
      _fiveLeftNotified = true;
    }

    if (!_limitReachedNotified && current >= _dailyLimit) {
      _sendNotification('Limit Reached', 'You have reached your daily usage goal.');
      _limitReachedNotified = true;
    }
  }

  Future<void> _sendNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'limit_channel',
      'Daily Usage Alerts',
      channelDescription: 'Notifies about your daily screen time progress',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(0, title, body, details);
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;


  Future<Duration> getCurrentUsage() => _usageService.getDailyUsage();
  Future<Duration> getDailyLimit() => _usageService.getDailyLimit();
  Future<int> getCurrentStreak() async => _currentStreak;
  Future<int> getMaxStreak() async => _maxStreak;

  Future<void> updateDailyLimit(Duration newLimit) async {
    await _usageService.setDailyLimit(newLimit);
    _dailyLimit = newLimit;
    resetNotificationFlags();
  }

  void resetNotificationFlags() {
    _halfwayNotified = false;
    _fifteenLeftNotified = false;
    _fiveLeftNotified = false;
    _limitReachedNotified = false;
  }
}

class DailyUsageGoalScreen extends StatefulWidget {
  const DailyUsageGoalScreen({super.key});

  @override
  State<DailyUsageGoalScreen> createState() => _DailyUsageGoalScreenState();
}

class _DailyUsageGoalScreenState extends State<DailyUsageGoalScreen> {
  final DailyUsageGoalManager _manager = DailyUsageGoalManager();

  Duration _dailyLimit = const Duration(hours: 2);
  Duration _currentUsage = Duration.zero;
  int _currentStreak = 0;
  int _maxStreak = 0;
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _manager.start();
    _syncData();
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _syncData());
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _syncData() async {
    final usage = await _manager.getCurrentUsage();
    final limit = await _manager.getDailyLimit();
    final streak = await _manager.getCurrentStreak();
    final maxStreak = await _manager.getMaxStreak();

    if (mounted) {
      setState(() {
        _currentUsage = usage;
        _dailyLimit = limit;
        _currentStreak = streak;
        _maxStreak = maxStreak;
      });
    }
  }

  void _openTimePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SizedBox(
          height: 250,
          child: Column(
            children: [
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    brightness: Brightness.light,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(color: Colors.black),
                    ),
                  ),
                  child: CupertinoTimerPicker(
                    initialTimerDuration: _dailyLimit,
                    mode: CupertinoTimerPickerMode.hm,
                    onTimerDurationChanged: (Duration newDuration) async {
                      await _manager.updateDailyLimit(newDuration);
                      _syncData();
                    },
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Done',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = two(d.inHours);
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final double percent = min(_currentUsage.inSeconds / _dailyLimit.inSeconds, 1.0);
    final String formattedUsage = _formatDuration(_currentUsage);
    final String formattedLimit = _formatDuration(_dailyLimit);

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        title: Text(
          'Daily Usage Goal',
          style: GoogleFonts.playfairDisplay(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CircularProgressIndicator(
                      value: percent,
                      strokeWidth: 14,
                      backgroundColor: Colors.blue.shade100,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formattedUsage,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                      Text(
                        'of $formattedLimit',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 14,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '🔥 Current streak: $_currentStreak days',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              Text(
                '🏆 Max streak: $_maxStreak days',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 16,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _openTimePicker,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Set Daily Limit',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}