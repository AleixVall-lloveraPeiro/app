// daily_usage_goal.dart
// Refactor: Continuous background counting of screen‑on time
// -----------------------------------------------------------------------------
// This file contains two classes:
//   1. DailyUsageGoalManager – singleton service that tracks screen‑on time in
//      the background and notifies when the daily limit is reached.
//   2. DailyUsageGoalScreen – UI that visualises the data. It polls the manager
//      every second, so the progress indicator and label update live.
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_state/screen_state.dart';

import 'backend_service_daily_usage_mode.dart';

/*───────────────────────────────────────────────────────────────────────────────
│ Service layer – tracks usage continuously in the background                  │
└──────────────────────────────────────────────────────────────────────────────*/
class DailyUsageGoalManager {
  // Singleton boilerplate
  static final DailyUsageGoalManager _instance = DailyUsageGoalManager._internal();
  factory DailyUsageGoalManager() => _instance;
  DailyUsageGoalManager._internal();

  // Dependencies
  final UsageStorageService _usageService = UsageStorageService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Screen _screen = Screen();

  // Internal state
  StreamSubscription<ScreenStateEvent>? _screenSubscription;
  Timer? _countTimer;
  Duration _dailyLimit = const Duration(hours: 2);
  bool _isCounting = false;
  bool _notificationSent = false;
  bool _initialized = false;

  /*-------------------------------------------------------------------------*/
  Future<void> start() async {
    if (_initialized) return; // Ensure we only wire everything up once.
    _initialized = true;

    await _initializeNotifications();
    await _loadStoredLimit();
    _listenToScreenEvents();
    _startCounting(); // <–– start immediately so the counter works from launch
  }

  /*-------------------------------------------------------------------------*/
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  /*-------------------------------------------------------------------------*/
  Future<void> _loadStoredLimit() async {
    _dailyLimit = await _usageService.getDailyLimit();
  }

  /*-------------------------------------------------------------------------*/
  void _listenToScreenEvents() {
    _screenSubscription = _screen.screenStateStream.listen((event) {
      switch (event) {
        case ScreenStateEvent.SCREEN_ON:
          _startCounting();
          break;
        case ScreenStateEvent.SCREEN_OFF:
          _stopCounting();
          break;
        default:
          break;
      }
    });
  }

  /*-------------------------------------------------------------------------*/
  void _startCounting() {
    if (_isCounting) return;
    _isCounting = true;

    _countTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      await _usageService.addUsage(const Duration(seconds: 1));

      final current = await _usageService.getDailyUsage();
      if (!_notificationSent && current >= _dailyLimit) {
        await _sendLimitReachedNotification();
        _notificationSent = true;
      }
    });
  }

  /*-------------------------------------------------------------------------*/
  void _stopCounting() {
    _isCounting = false;
    _countTimer?.cancel();
  }

  /*-------------------------------------------------------------------------*/
  Future<void> _sendLimitReachedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'limit_channel',
      'Daily Limit Reached',
      channelDescription: 'Notifies when daily usage limit is reached',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0,
      'Limit Reached',
      'You have reached your daily usage goal.',
      details,
    );
  }

  /*-------------------------------------------------------------------------*/
  Future<Duration> getCurrentUsage() => _usageService.getDailyUsage();
  Future<Duration> getDailyLimit() => _usageService.getDailyLimit();

  Future<void> updateDailyLimit(Duration newLimit) async {
    await _usageService.setDailyLimit(newLimit);
    _dailyLimit = newLimit;
    _notificationSent = false; // Allow a fresh notification for the new day.
  }

  void resetNotificationFlag() => _notificationSent = false;
}

/*───────────────────────────────────────────────────────────────────────────────
│ UI layer – visualises the tracked data                                       │
└──────────────────────────────────────────────────────────────────────────────*/
class DailyUsageGoalScreen extends StatefulWidget {
  const DailyUsageGoalScreen({Key? key}) : super(key: key);

  @override
  State<DailyUsageGoalScreen> createState() => _DailyUsageGoalScreenState();
}

class _DailyUsageGoalScreenState extends State<DailyUsageGoalScreen> {
  // References
  final DailyUsageGoalManager _manager = DailyUsageGoalManager();

  // UI state
  Duration _dailyLimit = const Duration(hours: 2);
  Duration _currentUsage = Duration.zero;

  // Polling timer – updates UI once per second
  Timer? _uiRefreshTimer;

  /*-------------------------------------------------------------------------*/
  @override
  void initState() {
    super.initState();
    _manager.start(); // Background tracker (no‑op if already started).
    _syncData();      // Get the latest values immediately.

    // Refresh UI every second to keep the progress indicator smooth.
    _uiRefreshTimer = Timer.periodic(const Duration(seconds: 1), (_) => _syncData());
  }

  /*-------------------------------------------------------------------------*/
  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    super.dispose();
  }

  /*-------------------------------------------------------------------------*/
  Future<void> _syncData() async {
    final usage = await _manager.getCurrentUsage();
    final limit = await _manager.getDailyLimit();
    if (mounted) {
      setState(() {
        _currentUsage = usage;
        _dailyLimit = limit;
      });
    }
  }

  /*-------------------------------------------------------------------------*/
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

  /*-------------------------------------------------------------------------*/
  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = two(d.inHours);
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return '$h:$m:$s';
  }

  /*-------------------------------------------------------------------------*/
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
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