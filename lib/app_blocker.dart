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
  String _lastApp = '';

  // Initialize the blocker
  Future<void> initialize() async {
    await _initializeNotifications();
    await _loadBlockedApps();
    await _loadBlockerState();
    
    // Start tracking if blocker is active
    if (_isActive) {
      _startAppUsageTracking();
    }
    
    print('[APP BLOCKER] Initialized with ${_blockedApps.length} blocked apps');
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  // START APP USAGE TRACKING
  void _startAppUsageTracking() {
    // Stop any existing tracking
    _stopAppUsageTracking();
    
    // Check every 3 seconds which app is in foreground
    _trackingTimer = Timer.periodic(Duration(seconds: 3), (timer) async {
      if (!_isActive) return;
      
      try {
        // Get recent events
        DateTime end = DateTime.now();
        DateTime start = end.subtract(Duration(seconds: 10));
        
        List<UsageInfo> usageStats = await UsageStats.queryUsageStats(start, end);
        
        if (usageStats.isNotEmpty) {
          // Filter out null values and sort by last time used
          var validStats = usageStats.where((stat) => stat.lastTimeUsed != null && stat.packageName != null).toList();
          
          if (validStats.isNotEmpty) {
            validStats.sort((a, b) => b.lastTimeUsed!.compareTo(a.lastTimeUsed!));
            
            // Get the most recently used app
            UsageInfo mostRecent = validStats.first;
            
            if (mostRecent.packageName != _lastApp) {
              _lastApp = mostRecent.packageName!;
              
              // Check if this app is blocked
              if (_blockedApps.contains(_lastApp)) {
                await showMindfulPauseNotification(_lastApp);
              }
            }
          }
        }
      } catch (e) {
        print('[APP BLOCKER] Error tracking app usage: $e');
      }
    });
    
    print('[APP BLOCKER] Started app usage tracking');
  }

  // STOP APP USAGE TRACKING
  void _stopAppUsageTracking() {
    _trackingTimer?.cancel();
    _trackingTimer = null;
    _lastApp = '';
    print('[APP BLOCKER] Stopped app usage tracking');
  }

  // Show mindful notification when blocked app is detected
  Future<void> showMindfulPauseNotification(String packageName) async {
    // Prevent multiple notifications for the same app in short time
    if (_shouldShowNotification(packageName)) {
      String appName = _getAppName(packageName);
      
      const androidDetails = AndroidNotificationDetails(
        'app_blocker_channel',
        'App Blocker Alerts',
        channelDescription: 'Notifies you when trying to open blocked apps',
        importance: Importance.high,
        priority: Priority.high,
        timeoutAfter: 10000,
      );

      const notificationDetails = NotificationDetails(android: androidDetails);

      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        'Mindful Pause ⏸️',
        'You opened $appName. Take a deep breath and consider if this is necessary.',
        notificationDetails,
      );

      _updateLastNotificationTime(packageName);
      print('[APP BLOCKER] Showed notification for: $appName');
    }
  }

  // Simple app name extraction
  String _getAppName(String packageName) {
    try {
      List<String> parts = packageName.split('.');
      if (parts.length > 1) {
        String lastPart = parts.last;
        if (lastPart.isNotEmpty) {
          return lastPart[0].toUpperCase() + lastPart.substring(1);
        }
      }
      return packageName;
    } catch (e) {
      return packageName;
    }
  }

  // Prevent spam notifications
  Map<String, DateTime> _lastNotificationTimes = {};
  
  bool _shouldShowNotification(String packageName) {
    final lastTime = _lastNotificationTimes[packageName];
    if (lastTime == null) return true;
    
    return DateTime.now().difference(lastTime).inMinutes >= 2;
  }
  
  void _updateLastNotificationTime(String packageName) {
    _lastNotificationTimes[packageName] = DateTime.now();
  }

  // Load blocked apps from storage
  Future<void> _loadBlockedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedApps = prefs.getStringList('blockedApps') ?? [];
      _blockedApps = savedApps;
      print('[APP BLOCKER] Loaded blocked apps: $_blockedApps');
    } catch (e) {
      print('[APP BLOCKER] Error loading blocked apps: $e');
      _blockedApps = [];
    }
  }

  // Load blocker active state
  Future<void> _loadBlockerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isActive = prefs.getBool('appBlockerActive') ?? false;
      print('[APP BLOCKER] Blocker active: $_isActive');
    } catch (e) {
      print('[APP BLOCKER] Error loading blocker state: $e');
      _isActive = false;
    }
  }

  // Save blocked apps to storage
  Future<void> _saveBlockedApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('blockedApps', _blockedApps);
      print('[APP BLOCKER] Saved blocked apps: $_blockedApps');
    } catch (e) {
      print('[APP BLOCKER] Error saving blocked apps: $e');
    }
  }

  // Save blocker state
  Future<void> _saveBlockerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('appBlockerActive', _isActive);
      print('[APP BLOCKER] Saved blocker state: $_isActive');
    } catch (e) {
      print('[APP BLOCKER] Error saving blocker state: $e');
    }
  }

  // Check if an app is blocked
  bool isAppBlocked(String packageName) {
    return _isActive && _blockedApps.contains(packageName);
  }

  // Getter for blocked apps
  List<String> get blockedApps => List.from(_blockedApps);

  // Getter for active state
  bool get isActive => _isActive;

  // Toggle blocker on/off
  Future<void> toggleBlocker(bool active) async {
    _isActive = active;
    await _saveBlockerState();
    
    if (active) {
      _startAppUsageTracking();
      await _showBlockerActivatedNotification();
    } else {
      _stopAppUsageTracking();
      await _showBlockerDeactivatedNotification();
    }
    
    print('[APP BLOCKER] Blocker ${active ? 'activated' : 'deactivated'}');
  }

  Future<void> _showBlockerActivatedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'app_blocker_status',
      'App Blocker Status',
      channelDescription: 'Shows app blocker status changes',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      3,
      'App Blocker Activated 🛡️',
      'Mindful pauses will appear when you open blocked apps.',
      notificationDetails,
    );
  }

  Future<void> _showBlockerDeactivatedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'app_blocker_status',
      'App Blocker Status',
      channelDescription: 'Shows app blocker status changes',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      4,
      'App Blocker Deactivated',
      'You can now access all apps freely.',
      notificationDetails,
    );
  }

  // Add app to blocked list
  Future<void> addBlockedApp(String packageName) async {
    if (!_blockedApps.contains(packageName)) {
      _blockedApps.add(packageName);
      await _saveBlockedApps();
      print('[APP BLOCKER] Added blocked app: $packageName');
    }
  }

  // Remove app from blocked list
  Future<void> removeBlockedApp(String packageName) async {
    _blockedApps.remove(packageName);
    await _saveBlockedApps();
    print('[APP BLOCKER] Removed blocked app: $packageName');
  }

  // Clear all blocked apps
  Future<void> clearBlockedApps() async {
    _blockedApps.clear();
    await _saveBlockedApps();
    print('[APP BLOCKER] Cleared all blocked apps');
  }

  // Dispose method to clean up
  void dispose() {
    _stopAppUsageTracking();
  }
}