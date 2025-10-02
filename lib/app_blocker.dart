import 'dart:async';
import 'dart:convert';
import 'package:device_apps/device_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class AppBlocker {
  static final AppBlocker _instance = AppBlocker._internal();
  factory AppBlocker() => _instance;
  AppBlocker._internal();

  // Constants
  static const Duration _trackingInterval = Duration(seconds: 5);
  static const Duration _usageQueryWindow = Duration(seconds: 5);
  static const Duration _appChangeDebounce = Duration(seconds: 5);
  static const Duration _stopTimerDebounce = Duration(seconds: 8);
  static const int _fiveMinuteInSeconds = 300;
  static const Duration _notificationPeriod = Duration(seconds: 10);

  Set<String> _blockedAppSettings = {}; // packageName
  Set<String> _forceBlockedApps = {}; // Apps force-blocked by Focus Mode
  bool _isActive = false;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Timer? _trackingTimer;

  Future<void> initialize() async {
    await _initializeNotifications();
    await _loadBlockedAppSettings();
    await _loadBlockerState();

    if (_isActive) {
      _startAppUsageTracking();
    }
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );
    await _notificationsPlugin.initialize(initializationSettings);
  }

  void _startAppUsageTracking() {
    _stopAppUsageTracking();

    _trackingTimer = Timer.periodic(_trackingInterval, (timer) async {
      if (!_isActive && _forceBlockedApps.isEmpty) return;

      try {
        List<UsageInfo> usageStats = await UsageStats.queryUsageStats(
          DateTime.now().subtract(_usageQueryWindow),
          DateTime.now(),
        );

        if (usageStats.isNotEmpty) {
          var validStats = usageStats
              .where(
                (stat) => stat.lastTimeUsed != null && stat.packageName != null,
              )
              .toList();

          if (validStats.isNotEmpty) {
            validStats.sort(
              (a, b) => b.lastTimeUsed!.compareTo(a.lastTimeUsed!),
            );
            String currentApp = validStats.first.packageName!;

            if (_forceBlockedApps.contains(currentApp) ||
                _blockedAppSettings.contains(currentApp)) {
              _triggerBlock(currentApp);
              return;
            }
          }
        }
      } catch (e) {
        print('[APP BLOCKER] Error: $e');
      }
    });
  }

  void _stopAppUsageTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  Future<String> _getAppName(String packageName) async {
    try {
      Application? app = await DeviceApps.getApp(packageName);
      return app?.appName ?? packageName;
    } catch (e) {
      return packageName;
    }
  }

  Future<void> _loadBlockedAppSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final dynamic blockedAppsData = prefs.get('blockedAppSettings');

    if (blockedAppsData is List<String>) {
      _blockedAppSettings = blockedAppsData.toSet();
    } else if (blockedAppsData is String) {
      // Handle old data format (JSON string of a Map)
      try {
        final Map<String, dynamic> blockedAppsMap = json.decode(
          blockedAppsData,
        );
        _blockedAppSettings = blockedAppsMap.keys.toSet();
        // Resave in the new format
        await _saveBlockedAppSettings();
      } catch (e) {
        _blockedAppSettings = {};
      }
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
    await prefs.setStringList(
      'blockedAppSettings',
      _blockedAppSettings.toList(),
    );
  }

  Future<void> _saveBlockerState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('appBlockerActive', _isActive);
  }

  bool isAppBlocked(String packageName) =>
      _isActive && _blockedAppSettings.contains(packageName);
  List<String> get blockedApps => _blockedAppSettings.toList();
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
    } else {
      _stopAppUsageTracking();
    }
  }

  Future<void> addBlockedApp(String packageName) async {
    _blockedAppSettings.add(packageName);
    await _saveBlockedAppSettings();
  }

  Future<void> removeBlockedApp(String packageName) async {
    _blockedAppSettings.remove(packageName);
    await _saveBlockedAppSettings();
  }

  void _triggerBlock(String packageName, {bool isForced = false}) {
    print(
      '[APP BLOCKER] TRIGGERING BLOCK FOR: $packageName (Forced: $isForced)',
    );
    FlutterForegroundTask.launchApp('/inspirationalBlockingOverlay');
  }

  void dispose() {
    _stopAppUsageTracking();
  }
}
