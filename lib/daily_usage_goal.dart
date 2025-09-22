import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';

class DailyUsageGoalManager {
  static final DailyUsageGoalManager _instance = DailyUsageGoalManager._internal();
  factory DailyUsageGoalManager() => _instance;
  DailyUsageGoalManager._internal();

  static const MethodChannel _platform = MethodChannel('aleix/usage');

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Duration _dailyLimit = const Duration(hours: 2);
  Duration _currentUsage = Duration.zero;
  bool _halfwayNotified = false;
  bool _fifteenLeftNotified = false;
  bool _fiveLeftNotified = false;
  bool _limitReachedNotified = false;

  final StreamController<Duration> _usageStreamController = StreamController.broadcast();

  Stream<Duration> get usageStream => _usageStreamController.stream;

  Future<void> initialize() async {
    await _initializeNotifications();
    await _updateCurrentUsage();
    Timer.periodic(const Duration(seconds: 5), (_) => _updateCurrentUsage());
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _updateCurrentUsage() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    try {
      final Map<dynamic, dynamic> stats = await _platform.invokeMethod('getUsageStats', {
        'start': startOfDay.millisecondsSinceEpoch,
        'end': now.millisecondsSinceEpoch,
      });

      final int totalMs = stats['total'] ?? 0;
      _currentUsage = Duration(milliseconds: totalMs);
      _usageStreamController.add(_currentUsage);
      _handleNotifications();
    } on PlatformException catch (e) {
      print('Error obtenint dades d\'ús: ${e.message}');
    }
  }

  void _handleNotifications() {
    final current = _currentUsage;
    if (!_halfwayNotified && current >= _dailyLimit * 0.5) {
      _sendNotification('Halfway There', 'You\'ve used half of your daily goal.');
      _halfwayNotified = true;
    }

    final remaining = _dailyLimit - current;

    if (!_fifteenLeftNotified && remaining.inMinutes <= 15 && remaining.inMinutes > 5) {
      _sendNotification('Almost Done', 'Only 15 minutes left of your daily usage goal.');
      _fifteenLeftNotified = true;
    }

    if (!_fiveLeftNotified && remaining.inMinutes <= 5 && remaining.inMinutes > 0) {
      _sendNotification('5 Minutes Left', 'Just 5 minutes remaining.');
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

  Duration get currentUsage => _currentUsage;

  void updateDailyLimit(Duration newLimit) {
    _dailyLimit = newLimit;
    _halfwayNotified = false;
    _fifteenLeftNotified = false;
    _fiveLeftNotified = false;
    _limitReachedNotified = false;
  }

  Duration get dailyLimit => _dailyLimit;
}

class DailyUsageGoalScreen extends StatefulWidget {
  const DailyUsageGoalScreen({super.key});

  @override
  State<DailyUsageGoalScreen> createState() => _DailyUsageGoalScreenState();
}

class _DailyUsageGoalScreenState extends State<DailyUsageGoalScreen> {
  final DailyUsageGoalManager _manager = DailyUsageGoalManager();

  Duration _currentUsage = Duration.zero;
  Duration _dailyLimit = const Duration(hours: 2);
  StreamSubscription<Duration>? _usageSubscription;

  @override
  void initState() {
    super.initState();
    _manager.initialize();
    _usageSubscription = _manager.usageStream.listen((usage) {
      setState(() {
        _currentUsage = usage;
        _dailyLimit = _manager.dailyLimit;
      });
    });
  }

  @override
  void dispose() {
    _usageSubscription?.cancel();
    super.dispose();
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
          child: CupertinoTimerPicker(
            initialTimerDuration: _dailyLimit,
            mode: CupertinoTimerPickerMode.hm,
            onTimerDurationChanged: (Duration newDuration) {
              _manager.updateDailyLimit(newDuration);
            },
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}H ${m}min';
  }

  @override
  Widget build(BuildContext context) {
    final double percent = min(_currentUsage.inSeconds / _dailyLimit.inSeconds, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        title: Text('Daily Usage Goal', style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.black87)),
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
                      Text(_formatDuration(_currentUsage), style: GoogleFonts.playfairDisplay(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.blueAccent)),
                      Text('of ${_formatDuration(_dailyLimit)}', style: GoogleFonts.playfairDisplay(fontSize: 14, color: Colors.black54)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _openTimePicker,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text('Set Daily Limit', style: GoogleFonts.playfairDisplay(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}