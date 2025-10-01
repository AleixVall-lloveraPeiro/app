import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:usage_stats/usage_stats.dart';

class AppBlocker {
  static final AppBlocker _instance = AppBlocker._internal();
  factory AppBlocker() => _instance;
  AppBlocker._internal();

  List<String> _blockedApps = [];
  bool _isActive = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  Timer? _trackingTimer;
  Timer? _blockedAppTimer;
  
  String _currentBlockedApp = '';
  int _blockedAppSeconds = 0;
  DateTime _lastAppChange = DateTime.now();
  bool _isInNotificationPeriod = false; // PROTECCIÓN NOTIFICACIONES

  Future<void> initialize() async {
    await _initializeNotifications();
    await _loadBlockedApps();
    await _loadBlockerState();
    
    if (_isActive) {
      _startAppUsageTracking();
    }
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  void _startAppUsageTracking() {
    _stopAppUsageTracking();
    
    _trackingTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      if (!_isActive) return;
      
      // PROTECCIÓN: saltar durante periodo de notificación
      if (_isInNotificationPeriod) {
        print('[APP BLOCKER] Skipping tracking - in notification period');
        return;
      }
      
      try {
        List<UsageInfo> usageStats = await UsageStats.queryUsageStats(
          DateTime.now().subtract(Duration(seconds: 10)),
          DateTime.now(),
        );
        
        if (usageStats.isNotEmpty) {
          var validStats = usageStats.where((stat) => stat.lastTimeUsed != null && stat.packageName != null).toList();
          
          if (validStats.isNotEmpty) {
            validStats.sort((a, b) => b.lastTimeUsed!.compareTo(a.lastTimeUsed!));
            String currentApp = validStats.first.packageName!;
            
            // DEBOUNCE INICIAL: solo cambiar si ha pasado suficiente tiempo
            if (_blockedApps.contains(currentApp)) {
              if (currentApp != _currentBlockedApp) {
                // NUEVA APP BLOQUEADA - esperar 5 segundos para confirmar
                if (DateTime.now().difference(_lastAppChange).inSeconds > 5) {
                  _startBlockedAppTimer(currentApp);
                  _showImmediateNotification(currentApp);
                  _lastAppChange = DateTime.now();
                }
              }
              // Misma app bloqueada - timer sigue
            } else {
              // APP NO BLOQUEADA - solo detener si estamos en una bloqueada
              if (_currentBlockedApp.isNotEmpty) {
                // Esperar 8 segundos para confirmar que realmente salió
                if (DateTime.now().difference(_lastAppChange).inSeconds > 8) {
                  _stopBlockedAppTimer();
                  _lastAppChange = DateTime.now();
                }
              }
            }
          }
        }
      } catch (e) {
        print('[APP BLOCKER] Error: $e');
      }
    });
  }

  void _startBlockedAppTimer(String appPackageName) {
    _blockedAppTimer?.cancel();
    
    _currentBlockedApp = appPackageName;
    _blockedAppSeconds = 0;
    
    _blockedAppTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _blockedAppSeconds++;
      print('[APP BLOCKER] $_currentBlockedApp: $_blockedAppSeconds seconds');
      
      // NOTIFICAR CADA 5 MINUTOS
      if (_blockedAppSeconds % 300 == 0) {
        _showFiveMinuteNotification();
      }
    });
    
    print('[APP BLOCKER] Started timer for: $appPackageName');
  }

  void _stopBlockedAppTimer() {
    _blockedAppTimer?.cancel();
    _blockedAppTimer = null;
    _currentBlockedApp = '';
    _blockedAppSeconds = 0;
    print('[APP BLOCKER] Stopped timer');
  }

  void _stopAppUsageTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _stopBlockedAppTimer();
  }

  Future<void> _showImmediateNotification(String packageName) async {
    String appName = _getAppName(packageName);
    
    const androidDetails = AndroidNotificationDetails(
      'app_blocker_channel',
      'App Blocker Alerts',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Mindful Pause ⏸️',
      'You opened $appName. Timer started.',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _showFiveMinuteNotification() async {
    // ACTIVAR PROTECCIÓN durante 10 segundos después de notificación
    _isInNotificationPeriod = true;
    
    String appName = _getAppName(_currentBlockedApp);
    int minutes = _blockedAppSeconds ~/ 60;
    
    const androidDetails = AndroidNotificationDetails(
      'blocked_app_time_channel', 
      'Blocked App Time Alerts',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Mindful Break 🌱',
      'You\'ve been using $appName for $minutes minutes.',
      const NotificationDetails(android: androidDetails),
    );
    
    print('[APP BLOCKER] $minutes-minute notification for: $appName');
    
    // DESACTIVAR PROTECCIÓN después de 10 segundos
    Timer(Duration(seconds: 10), () {
      _isInNotificationPeriod = false;
      print('[APP BLOCKER] Notification period ended');
    });
  }

  String _getAppName(String packageName) {
    try {
      List<String> parts = packageName.split('.');
      return parts.isNotEmpty ? parts.last : packageName;
    } catch (e) {
      return packageName;
    }
  }

  Future<void> _loadBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    _blockedApps = prefs.getStringList('blockedApps') ?? [];
  }

  Future<void> _loadBlockerState() async {
    final prefs = await SharedPreferences.getInstance();
    _isActive = prefs.getBool('appBlockerActive') ?? false;
  }

  Future<void> _saveBlockedApps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blockedApps', _blockedApps);
  }

  Future<void> _saveBlockerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appBlockerActive', _isActive);
  }

  bool isAppBlocked(String packageName) => _isActive && _blockedApps.contains(packageName);
  List<String> get blockedApps => List.from(_blockedApps);
  bool get isActive => _isActive;

  Future<void> toggleBlocker(bool active) async {
    _isActive = active;
    await _saveBlockerState();
    
    if (active) {
      _startAppUsageTracking();
    } else {
      _stopAppUsageTracking();
    }
  }

  Future<void> addBlockedApp(String packageName) async {
    if (!_blockedApps.contains(packageName)) {
      _blockedApps.add(packageName);
      await _saveBlockedApps();
    }
  }

  Future<void> removeBlockedApp(String packageName) async {
    _blockedApps.remove(packageName);
    await _saveBlockedApps();
  }

  Future<void> clearBlockedApps() async {
    _blockedApps.clear();
    await _saveBlockedApps();
  }

  void dispose() {
    _stopAppUsageTracking();
  }
}