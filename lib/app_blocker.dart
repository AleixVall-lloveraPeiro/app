import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppBlocker {
  static final AppBlocker _instance = AppBlocker._internal();
  factory AppBlocker() => _instance;
  AppBlocker._internal();

  Set<String> _blockedAppSettings = {}; // Apps blocked via settings
  Set<String> _forceBlockedApps = {};   // Apps temporarily blocked by Focus Mode
  bool _isActive = false;               // Is the main blocker toggle on?
  Timer? _trackingTimer;

  Future<void> initialize() async {
    await _loadSettings();
    if (_isActive) {
      _startAppUsageTracking();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _blockedAppSettings = (prefs.getStringList('blockedAppSettings') ?? []).toSet();
    _isActive = prefs.getBool('appBlockerActive') ?? false;
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('blockedAppSettings', _blockedAppSettings.toList());
    await prefs.setBool('appBlockerActive', _isActive);
  }

  void _startAppUsageTracking() {
    // If the timer is already running, don't start another one.
    if (_trackingTimer?.isActive ?? false) return;

    _trackingTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      // Stop the timer if no blocking is active.
      if (!_isActive && _forceBlockedApps.isEmpty) {
        _stopAppUsageTracking();
        return;
      }

      try {
        final usageStats = await UsageStats.queryUsageStats(
          DateTime.now().subtract(const Duration(seconds: 2)),
          DateTime.now(),
        );

        if (usageStats.isNotEmpty) {
          usageStats.sort((a, b) => b.lastTimeUsed!.compareTo(a.lastTimeUsed!));
          final currentApp = usageStats.first.packageName!;

          final isBlocked = _forceBlockedApps.contains(currentApp) || 
                            (_isActive && _blockedAppSettings.contains(currentApp));

          if (isBlocked) {
            // Bring the app back to the foreground overlay.
            FlutterForegroundTask.launchApp('/inspirationalBlockingOverlay');
          }
        }
      } catch (e) {
        // Handle potential errors from the usage stats plugin.
      }
    });
  }

  void _stopAppUsageTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
  }

  // --- Public API ---

  bool get isActive => _isActive;
  List<String> get blockedApps => _blockedAppSettings.toList();

  Future<void> toggleBlocker(bool active) async {
    _isActive = active;
    await _saveSettings();
    if (_isActive) {
      _startAppUsageTracking();
    }
  }

  Future<void> addBlockedApp(String packageName) async {
    _blockedAppSettings.add(packageName);
    await _saveSettings();
  }

  Future<void> removeBlockedApp(String packageName) async {
    _blockedAppSettings.remove(packageName);
    await _saveSettings();
  }

  /// Called by FocusMode to temporarily block an app.
  void forceBlockApp(String packageName) {
    _forceBlockedApps.add(packageName);
    _startAppUsageTracking(); // Ensure the tracker is running.
  }

  /// Called by FocusMode to stop temporarily blocking an app.
  void forceUnblockApp(String packageName) {
    _forceBlockedApps.remove(packageName);
  }

  void dispose() {
    _stopAppUsageTracking();
  }
}