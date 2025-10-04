import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_state/screen_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/utils/constants.dart';

/// Manages all logic related to daily usage goals, streaks, and data fetching.
class DailyUsageGoalManager {
  static final DailyUsageGoalManager _instance = DailyUsageGoalManager._internal();
  factory DailyUsageGoalManager() => _instance;
  DailyUsageGoalManager._internal();

  // --- Private State ---
  static const MethodChannel _platform = MethodChannel('aleix/usage');
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Screen _screen = Screen();
  StreamSubscription<ScreenStateEvent>? _screenSubscription;
  Timer? _usageTimer;

  Duration _dailyLimit = const Duration(hours: 2);
  Duration _currentUsage = Duration.zero;

  bool _halfwayNotified = false;
  bool _fifteenLeftNotified = false;
  bool _fiveLeftNotified = false;
  bool _limitReachedNotified = false;

  final StreamController<Duration> _usageStreamController = StreamController.broadcast();
  bool _isInitialized = false;

  // --- Public Accessors ---
  Stream<Duration> get usageStream => _usageStreamController.stream;
  Duration get currentUsage => _currentUsage;
  Duration get dailyLimit => _dailyLimit;

  /// The single entry point to initialize the manager.
  /// Ensures that daily usage is reset and streaks are calculated if it's a new day.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await _initializeNotifications();
    await _loadDailyLimit();

    // Crucial Step: Check if the day has changed and perform reset/streak logic BEFORE any usage is fetched.
    await _checkAndResetDailyUsageIfNeeded();

    // Now, with a clean state for the day, fetch the current usage.
    await _updateCurrentUsage();

    // Start background listeners.
    _listenToScreenEvents();
    _startUsageTimer();

    _isInitialized = true;
  }

  /// Checks if the last reset was on a different day. If so, triggers the reset and streak calculation.
  Future<void> _checkAndResetDailyUsageIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastResetStr = prefs.getString(SharedPreferencesKeys.lastResetDate);

    DateTime? lastResetDate;
    if (lastResetStr != null) {
      lastResetDate = DateTime.tryParse(lastResetStr);
    }

    if (lastResetDate == null || !isSameCalendarDay(now, lastResetDate)) {
      await _performDailyResetAndUpdateStreak(prefs, now, lastResetDate);
    }
  }

  /// Calculates the streak based on the previous day's usage and resets the current day's state.
  Future<void> _performDailyResetAndUpdateStreak(SharedPreferences prefs, DateTime now, DateTime? lastResetDate) async {
    // Only calculate streak if there was a previous day to check against.
    if (lastResetDate != null) {
      final dailyLimit = Duration(seconds: prefs.getInt(SharedPreferencesKeys.dailyLimit) ?? 7200);

      // Define the exact time window for the day that just ended.
      final startOfPreviousDay = DateTime(lastResetDate.year, lastResetDate.month, lastResetDate.day);
      final endOfPreviousDay = startOfPreviousDay.add(const Duration(days: 1)).subtract(const Duration(microseconds: 1));

      // Fetch the definitive usage for that specific window from the OS.
      final Map<dynamic, dynamic> stats = await _platform.invokeMethod('getUsageStats', {
        'start': startOfPreviousDay.millisecondsSinceEpoch,
        'end': endOfPreviousDay.millisecondsSinceEpoch,
      });
      final previousDayUsage = Duration(milliseconds: stats['total'] ?? 0);

      // Perform the streak calculation with the accurate data.
      if (previousDayUsage > Duration.zero && previousDayUsage <= dailyLimit) {
        int currentStreak = (prefs.getInt(SharedPreferencesKeys.currentStreak) ?? 0) + 1;
        await prefs.setInt(SharedPreferencesKeys.currentStreak, currentStreak);
        int maxStreak = prefs.getInt(SharedPreferencesKeys.maxStreak) ?? 0;
        if (currentStreak > maxStreak) {
          await prefs.setInt(SharedPreferencesKeys.maxStreak, currentStreak);
        }
      } else {
        await prefs.setInt(SharedPreferencesKeys.currentStreak, 0);
      }
    }

    // Reset usage for the new day.
    _currentUsage = Duration.zero;
    _resetNotificationFlags();
    await prefs.setString(SharedPreferencesKeys.lastResetDate, now.toIso8601String());
    await _saveCachedUsage();
    _usageStreamController.add(_currentUsage);
  }

  /// Fetches the latest usage for the current day (from midnight to now).
  Future<void> _updateCurrentUsage() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final Map<dynamic, dynamic> stats = await _platform.invokeMethod('getUsageStats', {
        'start': startOfDay.millisecondsSinceEpoch,
        'end': now.millisecondsSinceEpoch,
      });
      final newUsage = Duration(milliseconds: stats['total'] ?? 0);

      if (_currentUsage != newUsage) {
        _currentUsage = newUsage;
        await _saveCachedUsage();
        _usageStreamController.add(_currentUsage);
        _handleNotifications();
      }
    } catch (e) {
      debugPrint('Error updating usage: $e');
    }
  }

  // --- Helper & Background Methods ---

  Future<void> _saveCachedUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SharedPreferencesKeys.cachedUsage, _currentUsage.inSeconds);
  }

  void _listenToScreenEvents() {
    _screenSubscription = _screen.screenStateStream?.listen((event) {
      if (event == ScreenStateEvent.SCREEN_ON) {
        _startUsageTimer();
      } else if (event == ScreenStateEvent.SCREEN_OFF) {
        _stopUsageTimer();
      }
    });
  }

  void _startUsageTimer() {
    _usageTimer?.cancel();
    _usageTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _updateCurrentUsage();
    });
  }

  void _stopUsageTimer() {
    _usageTimer?.cancel();
  }

  Future<void> _loadDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(SharedPreferencesKeys.dailyLimit);
    _dailyLimit = Duration(seconds: seconds ?? 7200);
  }

  Future<void> updateDailyLimit(Duration newLimit) async {
    _dailyLimit = newLimit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SharedPreferencesKeys.dailyLimit, newLimit.inSeconds);
    _resetNotificationFlags();
    _usageStreamController.add(_currentUsage);
  }

  Future<int> getCurrentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(SharedPreferencesKeys.currentStreak) ?? 0;
  }

  Future<int> getMaxStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(SharedPreferencesKeys.maxStreak) ?? 0;
  }

  bool isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  void _resetNotificationFlags() {
    _halfwayNotified = false;
    _fifteenLeftNotified = false;
    _fiveLeftNotified = false;
    _limitReachedNotified = false;
  }

  void _handleNotifications() {
    // Notification logic remains the same...
  }

  Future<void> _initializeNotifications() async {
    // Notification initialization remains the same...
  }

  Future<void> _sendNotification(int id, String title, String body) async {
    // Notification sending remains the same...
  }
}

// --- UI WIDGET ---

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeAndLoadData();
  }

  @override
  void dispose() {
    _usageSubscription?.cancel();
    super.dispose();
  }

  /// A single, reliable function to initialize the manager and load all data for the UI.
  Future<void> _initializeAndLoadData() async {
    setState(() { _isLoading = true; });

    try {
      // Wait for the manager to complete its setup, including any daily resets or streak calculations.
      await _manager.initialize();

      // Once initialized, fetch the definitive, up-to-date data.
      final currentStreak = await _manager.getCurrentStreak();
      final maxStreak = await _manager.getMaxStreak();
      
      if (mounted) {
        setState(() {
          _currentUsage = _manager.currentUsage;
          _dailyLimit = _manager.dailyLimit;
          _currentStreak = currentStreak;
          _maxStreak = maxStreak;
          _isLoading = false; // Data is ready, hide spinner.
        });
      }

      // Listen for real-time updates to the usage for the rest of the session.
      _usageSubscription = _manager.usageStream.listen((usage) {
        if (mounted) {
          setState(() { _currentUsage = usage; });
        }
      });

    } catch (e) {
      if (mounted) {
        setState(() { _isLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load usage data.'))
        );
      }
    }
  }

  void _openTimePicker() {
    Duration tempDuration = _dailyLimit; // Temporary variable to hold the selected duration.

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return SizedBox(
          height: 280, // Increased height to accommodate the save button
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                    ),
                    TextButton(
                      onPressed: () {
                        // On Save, update the manager and the UI, then close the sheet.
                        _manager.updateDailyLimit(tempDuration);
                        setState(() {
                          _dailyLimit = tempDuration;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoTimerPicker(
                  initialTimerDuration: _dailyLimit,
                  mode: CupertinoTimerPickerMode.hm,
                  onTimerDurationChanged: (Duration newDuration) {
                    // Only update the temporary variable, not the actual state.
                    tempDuration = newDuration;
                  },
                ),
              ),
            ],
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
    final double percent = _dailyLimit.inSeconds > 0 ? min(_currentUsage.inSeconds / _dailyLimit.inSeconds, 1.0) : 0.0;

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
          child: _isLoading
              ? const CircularProgressIndicator()
              : Column(
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
