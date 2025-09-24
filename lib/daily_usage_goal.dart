import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyUsageGoalManager {
  static final DailyUsageGoalManager _instance = DailyUsageGoalManager._internal();
  factory DailyUsageGoalManager() => _instance;
  DailyUsageGoalManager._internal();

  // Constants
  static const MethodChannel _platform = MethodChannel('aleix/usage');
  static const String _dailyLimitKey = 'daily_limit_seconds';
  static const String _lastResetDateKey = 'last_reset_date';
  static const String _currentStreakKey = 'current_streak';
  static const String _maxStreakKey = 'max_streak';
  static const String _cachedUsageKey = 'cached_daily_usage';

  // Notifications
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // State variables
  Duration _dailyLimit = const Duration(hours: 2);
  Duration _currentUsage = Duration.zero;
  bool _halfwayNotified = false;
  bool _fifteenLeftNotified = false;
  bool _fiveLeftNotified = false;
  bool _limitReachedNotified = false;

  // Streams
  final StreamController<Duration> _usageStreamController = StreamController.broadcast();
  Stream<Duration> get usageStream => _usageStreamController.stream;

  Future<void> initialize() async {
    await _initializeNotifications();
    await _loadDailyLimit();
    await _checkAndResetDailyUsage();
    await _updateCurrentUsage();
    
    Timer.periodic(const Duration(milliseconds: 10), (_) => _updateCurrentUsage());
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  Future<void> _loadCachedUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedSeconds = prefs.getInt(_cachedUsageKey) ?? 0;
    _currentUsage = Duration(seconds: cachedSeconds);
  }

  Future<void> _saveCachedUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cachedUsageKey, _currentUsage.inSeconds);
  }

  Future<void> _checkAndResetDailyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastResetStr = prefs.getString(_lastResetDateKey);
    
    if (lastResetStr == null) {
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
      _currentUsage = Duration.zero;
      await _saveCachedUsage();
      return;
    }
    
    final lastReset = DateTime.tryParse(lastResetStr);
    if (lastReset == null || !_isSameDay(now, lastReset)) {
      _currentUsage = Duration.zero;
      _resetNotificationFlags();
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
      await _saveCachedUsage();
    } else {
      await _loadCachedUsage();
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _updateCurrentUsage() async {
    try {
      Duration newUsage = await _getUsageWithNewMethod();
      
      if (newUsage.inMinutes == 0) {
        newUsage = await _getUsageWithTraditionalMethod();
      }
      
      if (newUsage > _currentUsage) {
        _currentUsage = newUsage;
        await _saveCachedUsage();
      }
      
      _usageStreamController.add(_currentUsage);
      _handleNotifications();
      
    } catch (e) {
      _usageStreamController.add(_currentUsage);
    }
  }

  Future<Duration> _getUsageWithNewMethod() async {
    try {
      final now = DateTime.now();
      final Map<dynamic, dynamic> stats = await _platform.invokeMethod('getUsageStatsForDay', {
        'year': now.year,
        'month': now.month, 
        'day': now.day,
      });
      return Duration(milliseconds: stats['total'] ?? 0);
    } catch (e) {
      return Duration.zero;
    }
  }

  Future<Duration> _getUsageWithTraditionalMethod() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      
      final Map<dynamic, dynamic> stats = await _platform.invokeMethod('getUsageStats', {
        'start': startOfDay.millisecondsSinceEpoch,
        'end': now.millisecondsSinceEpoch,
      });
      return Duration(milliseconds: stats['total'] ?? 0);
    } catch (e) {
      return Duration.zero;
    }
  }

  Future<void> _loadDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(_dailyLimitKey);
    _dailyLimit = Duration(seconds: seconds ?? 7200);
  }

  Future<void> updateDailyLimit(Duration newLimit) async {
    _dailyLimit = newLimit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyLimitKey, newLimit.inSeconds);
    _resetNotificationFlags();
    _usageStreamController.add(_currentUsage);
  }

  void _resetNotificationFlags() {
    _halfwayNotified = false;
    _fifteenLeftNotified = false;
    _fiveLeftNotified = false;
    _limitReachedNotified = false;
  }

  void _handleNotifications() {
    final current = _currentUsage;
    final remaining = _dailyLimit - current;

    if (!_halfwayNotified && current >= _dailyLimit * 0.5) {
      _sendNotification('Halfway There', 'You\'ve used half of your daily goal.');
      _halfwayNotified = true;
    }

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
    await _notificationsPlugin.show(
      Random().nextInt(1000),
      title, 
      body, 
      details
    );
  }

  Duration get currentUsage => _currentUsage;
  Duration get dailyLimit => _dailyLimit;

  Future<int> getCurrentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentStreakKey) ?? 0;
  }

  Future<int> getMaxStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxStreakKey) ?? 0;
  }
}

// ✅ SOLO UNA DEFINICIÓN DE DailyUsageGoalScreen - BORRA LAS OTRAS
class DailyUsageGoalScreen extends StatefulWidget {
  const DailyUsageGoalScreen({super.key});

  @override
  State<DailyUsageGoalScreen> createState() => _DailyUsageGoalScreenState();
}

class _DailyUsageGoalScreenState extends State<DailyUsageGoalScreen> {
  final DailyUsageGoalManager _manager = DailyUsageGoalManager();
  Duration _currentUsage = Duration.zero;
  Duration _dailyLimit = const Duration(hours: 2);
  int _currentStreak = 0;
  int _maxStreak = 0;
  StreamSubscription<Duration>? _usageSubscription;

  @override
  void initState() {
    super.initState();
    _initializeManager();
  }

  Future<void> _initializeManager() async {
    await _manager.initialize();
    
    _usageSubscription = _manager.usageStream.listen((usage) {
      setState(() {
        _currentUsage = usage;
        _dailyLimit = _manager.dailyLimit;
      });
    });

    _loadStreakData();
  }

  Future<void> _loadStreakData() async {
    final currentStreak = await _manager.getCurrentStreak();
    final maxStreak = await _manager.getMaxStreak();
    
    if (mounted) {
      setState(() {
        _currentStreak = currentStreak;
        _maxStreak = maxStreak;
      });
    }
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
              _loadStreakData();
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
        title: Text(
          'Daily Usage Goal', 
          style: GoogleFonts.playfairDisplay(
            fontSize: 22, 
            fontWeight: FontWeight.w700, 
            color: Colors.black87
          )
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStreakCard('Current Streak', _currentStreak),
                  _buildStreakCard('Max Streak', _maxStreak),
                ],
              ),
              
              const SizedBox(height: 30),
              
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
                        _formatDuration(_currentUsage), 
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 32, 
                          fontWeight: FontWeight.bold, 
                          color: Colors.blueAccent
                        )
                      ),
                      Text(
                        'of ${_formatDuration(_dailyLimit)}', 
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 14, 
                          color: Colors.black54
                        )
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
                child: Text(
                  'Set Daily Limit', 
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18, 
                    fontWeight: FontWeight.w600, 
                    color: Colors.white
                  )
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreakCard(String title, int value) {
    return Column(
      children: [
        Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 14,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$value days',
          style: GoogleFonts.playfairDisplay(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
      ],
    );
  }
}