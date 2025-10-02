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

class DailyUsageGoalManager {
  static final DailyUsageGoalManager _instance = DailyUsageGoalManager._internal();
  factory DailyUsageGoalManager() => _instance;
  DailyUsageGoalManager._internal();

  // Constants
  static const MethodChannel _platform = MethodChannel('aleix/usage');

  // Notification IDs
  static const int _halfwayNotificationId = 100;
  static const int _fifteenLeftNotificationId = 101;
  static const int _fiveLeftNotificationId = 102;
  static const int _limitReachedNotificationId = 103;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  final Screen _screen = Screen();
  StreamSubscription<ScreenStateEvent>? _screenSubscription;
  Timer? _usageTimer;

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

  // Cache management
  bool _isInitialized = false;
  Completer<void>? _initializationCompleter;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    if (_initializationCompleter != null) {
      return _initializationCompleter!.future;
    }
    
    _initializationCompleter = Completer<void>();
    
    try {
      await _initializeNotifications();
      await _loadDailyLimit();
      await _loadCachedUsage(); // Cargar caché inmediatamente
      
      // Enviar uso cacheado INSTANTÁNEAMENTE
      _usageStreamController.add(_currentUsage);
      
      _listenToScreenEvents();
      _startUsageTimer();
      
      // Verificar reset en segundo plano sin bloquear la UI
      _checkAndResetDailyUsage();
      
      _isInitialized = true;
      _initializationCompleter!.complete();
    } catch (e) {
      _initializationCompleter!.completeError(e);
      _initializationCompleter = null;
      rethrow;
    }
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
    _usageTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _updateCurrentUsage();
    });
  }

  void _stopUsageTimer() {
    _usageTimer?.cancel();
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  // OPTIMIZADO: Cargar caché más rápido
  Future<void> _loadCachedUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedSeconds = prefs.getInt(SharedPreferencesKeys.cachedUsage) ?? 0;
      _currentUsage = Duration(seconds: cachedSeconds);
    } catch (e) {
      _currentUsage = Duration.zero;
    }
  }

  Future<void> _saveCachedUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(SharedPreferencesKeys.cachedUsage, _currentUsage.inSeconds);
    } catch (e) {
      debugPrint('Error saving cached usage: $e');
    }
  }

  // OPTIMIZADO: Verificar reset sin bloquear
  Future<void> _checkAndResetDailyUsage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final lastResetStr = prefs.getString(SharedPreferencesKeys.lastResetDate);
      
      DateTime? lastResetDate;
      if (lastResetStr != null) {
        lastResetDate = DateTime.tryParse(lastResetStr);
      }

      if (lastResetDate == null || !isSameCalendarDay(now, lastResetDate)) {
        await resetDailyUsage();
      }
    } catch (e) {
      debugPrint('Error checking reset: $e');
    }
  }

  Future<void> resetDailyUsage() async {
    _currentUsage = Duration.zero;
    _resetNotificationFlags();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SharedPreferencesKeys.lastResetDate, DateTime.now().toIso8601String());
      await _saveCachedUsage();
      _usageStreamController.add(_currentUsage);
    } catch (e) {
      debugPrint('Error resetting daily usage: $e');
    }
  }

  bool isSameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // NUEVO: Método rápido para obtener uso actual
  Future<void> updateUsage() async {
    await _updateCurrentUsage();
  }

  // OPTIMIZADO: Actualización más rápida
  Future<void> _updateCurrentUsage() async {
    try {
      Duration newUsage = await _getUsageWithNewMethod();
      
      if (newUsage.inMinutes == 0) {
        newUsage = await _getUsageWithTraditionalMethod();
      }
      
      if (_currentUsage != newUsage) {
        _currentUsage = newUsage;
        await _saveCachedUsage();
        _usageStreamController.add(_currentUsage);
        _handleNotifications();
      }
    } catch (e) {
      debugPrint('Error updating usage: $e');
      // Mantener el valor cacheado si hay error
      _usageStreamController.add(_currentUsage);
    }
  }

  Future<Duration> _getUsageWithNewMethod() async {
    try {
      final now = DateTime.now();
      final Map<dynamic, dynamic> stats = await _platform.invokeMethod('getUsageStatsForDay', {
        'year': now.year,
        'month': now.month - 1, 
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final seconds = prefs.getInt(SharedPreferencesKeys.dailyLimit);
      _dailyLimit = Duration(seconds: seconds ?? 7200);
    } catch (e) {
      _dailyLimit = const Duration(hours: 2);
    }
  }

  Future<void> updateDailyLimit(Duration newLimit) async {
    _dailyLimit = newLimit;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(SharedPreferencesKeys.dailyLimit, newLimit.inSeconds);
      _resetNotificationFlags();
      _usageStreamController.add(_currentUsage);
    } catch (e) {
      debugPrint('Error updating daily limit: $e');
    }
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
      _sendNotification(_halfwayNotificationId, 'Halfway There', 'You\'ve used half of your daily goal.');
      _halfwayNotified = true;
    }

    if (!_fifteenLeftNotified && remaining.inMinutes <= 15 && remaining.inMinutes > 5) {
      _sendNotification(_fifteenLeftNotificationId, 'Almost Done', 'Only 15 minutes left of your daily usage goal.');
      _fifteenLeftNotified = true;
    }

    if (!_fiveLeftNotified && remaining.inMinutes <= 5 && remaining.inMinutes > 0) {
      _sendNotification(_fiveLeftNotificationId, '5 Minutes Left', 'Just 5 minutes remaining.');
      _fiveLeftNotified = true;
    }

    if (!_limitReachedNotified && current >= _dailyLimit) {
      _sendNotification(_limitReachedNotificationId, 'Limit Reached', 'You have reached your daily usage goal.');
      _limitReachedNotified = true;
    }
  }

  Future<void> _sendNotification(int id, String title, String body) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'limit_channel',
        'Daily Usage Alerts',
        channelDescription: 'Notifies about your daily screen time progress',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: androidDetails);
      await _notificationsPlugin.show(id, title, body, details);
    } catch (e) {
      debugPrint('Error sending notification: $e');
    }
  }

  Duration get currentUsage => _currentUsage;
  Duration get dailyLimit => _dailyLimit;

  Future<int> getCurrentStreak() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(SharedPreferencesKeys.currentStreak) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  Future<int> getMaxStreak() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(SharedPreferencesKeys.maxStreak) ?? 0;
    } catch (e) {
      return 0;
    }
  }
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
  int _currentStreak = 0;
  int _maxStreak = 0;
  StreamSubscription<Duration>? _usageSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeManager();
  }

  Future<void> _initializeManager() async {
    // Mostrar datos cacheados inmediatamente
    await _loadCachedData();
    
    _usageSubscription = _manager.usageStream.listen((usage) {
      if (mounted) {
        setState(() {
          _currentUsage = usage;
          _dailyLimit = _manager.dailyLimit;
          _isLoading = false;
        });
      }
    });

    // Inicializar manager en segundo plano
    _manager.initialize().then((_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      _loadStreakData();
    }).catchError((error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  // NUEVO: Cargar datos cacheados inmediatamente
  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Cargar límite diario cacheado
      final seconds = prefs.getInt(SharedPreferencesKeys.dailyLimit);
      _dailyLimit = Duration(seconds: seconds ?? 3600);
      
      // Cargar uso cacheado
      final cachedSeconds = prefs.getInt(SharedPreferencesKeys.cachedUsage) ?? 0;
      _currentUsage = Duration(seconds: cachedSeconds);
      
      // Cargar streaks cacheados
      _currentStreak = prefs.getInt(SharedPreferencesKeys.currentStreak) ?? 0;
      _maxStreak = prefs.getInt(SharedPreferencesKeys.maxStreak) ?? 0;
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // Usar valores por defecto si hay error
      _currentUsage = Duration.zero;
      _dailyLimit = const Duration(hours: 2);
      _currentStreak = 0;
      _maxStreak = 0;
    }
  }

  Future<void> _loadStreakData() async {
    try {
      final currentStreak = await _manager.getCurrentStreak();
      final maxStreak = await _manager.getMaxStreak();
      
      if (mounted) {
        setState(() {
          _currentStreak = currentStreak;
          _maxStreak = maxStreak;
        });
      }
    } catch (e) {
      // Mantener valores cacheados si hay error
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
                      if (_isLoading)
                        const CircularProgressIndicator()
                      else
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