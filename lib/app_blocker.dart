import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'blocking_overlay.dart';

class AppBlocker {
  static final AppBlocker _instance = AppBlocker._internal();
  factory AppBlocker() => _instance;
  AppBlocker._internal();

  Map<String, int> _blockedAppSettings = {}; // packageName -> limit in minutes
  Set<String> _forceBlockedApps = {}; // Apps force-blocked by Focus Mode
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
    await _loadBlockedAppSettings();
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
      if (!_isActive && _forceBlockedApps.isEmpty) return; // Only track if active or force-blocking
      
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
            
            // Check for force-blocked apps first
            if (_forceBlockedApps.contains(currentApp)) {
              _triggerBlock(currentApp, isForced: true);
              return;
            }

            if (_blockedAppSettings.containsKey(currentApp)) {
              if (currentApp != _currentBlockedApp) {
                if (DateTime.now().difference(_lastAppChange).inSeconds > 5) {
                  _startBlockedAppTimer(currentApp);
                  _showImmediateNotification(currentApp);
                  _lastAppChange = DateTime.now();
                }
              }
            } else {
              if (_currentBlockedApp.isNotEmpty) {
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
      
      final limitInMinutes = _blockedAppSettings[_currentBlockedApp];
      if (limitInMinutes != null && _blockedAppSeconds >= limitInMinutes * 60) {
        _triggerBlock(_currentBlockedApp);
        _stopBlockedAppTimer();
        return;
      }
      
      if (_blockedAppSeconds > 0 && _blockedAppSeconds % 300 == 0) {
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
      "You've been using $appName for $minutes minutes.",
      const NotificationDetails(android: androidDetails),
    );
    
    print('[APP BLOCKER] $minutes-minute notification for: $appName');
    
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

  Future<void> _loadBlockedAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('blockedAppSettings');
    if (jsonString != null) {
      _blockedAppSettings = Map<String, int>.from(json.decode(jsonString));
    } else {
      _blockedAppSettings = {};
    }
  }

  Future<void> _loadBlockerState() async {
    final prefs = await SharedPreferences.getInstance();
    _isActive = prefs.getBool('appBlockerActive') ?? false;
  }

  Future<void> _saveBlockedAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = json.encode(_blockedAppSettings);
    await prefs.setString('blockedAppSettings', jsonString);
  }

  Future<void> _saveBlockerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appBlockerActive', _isActive);
  }

  bool isAppBlocked(String packageName) => _isActive && _blockedAppSettings.containsKey(packageName);
  List<String> get blockedApps => _blockedAppSettings.keys.toList();
  Map<String, int> get blockedAppSettings => Map.from(_blockedAppSettings);
  bool get isActive => _isActive;

  // Method to force block an app (used by Focus Mode)
  void forceBlockApp(String packageName) {
    _forceBlockedApps.add(packageName);
    _triggerBlock(packageName, isForced: true);
  }

  // Method to unblock a force-blocked app
  void forceUnblockApp(String packageName) {
    _forceBlockedApps.remove(packageName);
    FlutterForegroundTask.minimizeApp(); // Minimize if the blocked app is currently active
  }

  // Re-added methods
  Future<void> toggleBlocker(bool active) async {
    _isActive = active;
    await _saveBlockerState();
    
    if (active) {
      _startAppUsageTracking();
    }
    else {
      _stopAppUsageTracking();
    }
  }

  Future<void> addOrUpdateBlockedApp(String packageName, int limitInMinutes) async {
    _blockedAppSettings[packageName] = limitInMinutes;
    await _saveBlockedAppSettings();
  }

  Future<void> removeBlockedApp(String packageName) async {
    _blockedAppSettings.remove(packageName);
    await _saveBlockedAppSettings();
  }

  void _triggerBlock(String packageName, {bool isForced = false}) {
    print('[APP BLOCKER] TRIGGERING BLOCK FOR: $packageName (Forced: $isForced)');
    FlutterForegroundTask.launchApp('/blockingOverlay');
  }

  void dispose() {
    _stopAppUsageTracking();
  }
}