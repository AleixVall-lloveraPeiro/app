import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_foreground_task/models/foreground_task_event_action.dart';
import 'home_screen.dart';
import 'daily_usage_goal.dart'; // Import DailyUsageGoalManager
import 'inspirational_blocking_overlay.dart';
import 'package:app/utils/constants.dart'; // Import SharedPreferencesKeys

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _initForegroundTask();

  // Start the foreground task, which is necessary for other features.
  await FlutterForegroundTask.startService(
    notificationTitle: 'Sumaia is running in the background',
    notificationText: 'Monitoring app usage',
    callback: null, // No longer need a complex callback
  );

  final prefs = await SharedPreferences.getInstance();
  final bool hasAccess = prefs.getBool(SharedPreferencesKeys.usagePermissionGranted) ?? false;

  runApp(MyApp(initialRoute: hasAccess ? '/' : '/permission'));
}

void _initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'notification_channel_id',
      channelName: 'Foreground Service Notification',
      channelDescription: 'This notification appears when a foreground service is running.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      autoRunOnBoot: true,
      allowWifiLock: true,
      eventAction: ForegroundTaskEventAction.repeat(5000),
    ),
  );
}

/// The root widget of the application.
///
/// This widget sets up the [MaterialApp] and determines the initial screen
/// based on whether usage permissions have been granted.
final navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatelessWidget {
  /// The widget to display as the initial screen.
  final String initialRoute;

  /// Creates a [MyApp] widget.
  ///
  /// [initialScreen] is required and will be the first screen shown to the user.
  const MyApp({super.key, required this.initialRoute});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      initialRoute: initialRoute,
      routes: {
        '/': (context) => const HomeScreen(),
        '/permission': (context) => const PermissionScreen(),
        '/inspirationalBlockingOverlay': (context) => const InspirationalBlockingOverlay(),
      },
    );
  }
}

/// A screen displayed to the user when the application requires usage access permission.
///
/// This screen guides the user to grant the necessary permission to monitor device usage.
class PermissionScreen extends StatefulWidget {
  /// Creates a [PermissionScreen] widget.
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

/// The state for the [PermissionScreen] widget.
///
/// Manages the logic for checking and requesting usage access permission,
/// and navigates to the [HomeScreen] once permission is granted.
class _PermissionScreenState extends State<PermissionScreen> {
  /// Platform channel for communicating with native code to check and request usage permissions.
  static const platform = MethodChannel('aleix/usage');

  @override
  void initState() {
    super.initState();
    _checkPermissionLoop();
  }

  Future<void> _checkPermissionLoop() async {
    if (!mounted) return; // Stop if the widget is disposed
    bool granted = await checkUsagePermission();
    if (granted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(SharedPreferencesKeys.usagePermissionGranted, true);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      // Check again after a delay
      Future.delayed(const Duration(seconds: 1), _checkPermissionLoop);
    }
  }

  /// Checks if the application has been granted usage access permission.
  ///
  /// Returns `true` if permission is granted, `false` otherwise.
  Future<bool> checkUsagePermission() async {
    try {
      final granted = await platform.invokeMethod('checkUsagePermission');
      return granted == true;
    } on PlatformException {
      return false;
    }
  }

  /// Requests usage access permission from the user.
  ///
  /// This method invokes a native method to open the system settings where
  /// the user can grant the required permission.
  Future<void> _requestUsagePermission() async {
    try {
      await platform.invokeMethod('requestUsagePermission');
    } on PlatformException catch (e) {
      debugPrint('Error requesting permission: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_clock, size: 80, color: Colors.blueAccent),
              const SizedBox(height: 24),
              const Text(
                "Per poder mostrar el temps d'ús, cal que donis accés a l'ús del dispositiu.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.black87),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _requestUsagePermission,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Colors.blueAccent,
                ),
                child: const Text('Concedir accés', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}