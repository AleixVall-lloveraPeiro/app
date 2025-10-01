import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'home_screen.dart';
import 'daily_usage_goal.dart'; // Import DailyUsageGoalManager

/// Top-level function to be executed by the alarm manager for daily usage reset.
///
/// This function is called daily at midnight (00:00) to reset the user's
/// daily usage statistics and related notification flags.
@pragma('vm:entry-point')
Future<void> onResetDailyUsage() async {
  WidgetsFlutterBinding.ensureInitialized();
  final DailyUsageGoalManager manager = DailyUsageGoalManager();
  await manager.resetDailyUsage();
}

/// Main entry point of the application.
///
/// Initializes Flutter bindings, checks for existing usage permission,
/// initializes the Android Alarm Manager, and then runs the [MyApp] widget,
/// navigating to either [HomeScreen] or [PermissionScreen] based on the
/// permission status. It also schedules the daily usage reset alarm.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Android Alarm Manager
  await AndroidAlarmManager.initialize();

  final prefs = await SharedPreferences.getInstance();
  final bool hasAccess = prefs.getBool('usage_permission_granted') ?? false;

  runApp(MyApp(initialScreen: hasAccess ? HomeScreen() : const PermissionScreen()));

  // Schedule daily usage reset at midnight (00:00)
  await AndroidAlarmManager.periodic(
    const Duration(days: 1),
    0, // An int ID for the alarm
    onResetDailyUsage,
    startAt: DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day).add(const Duration(days: 1)),
    exact: true,
    wakeup: true,
  );
}

/// The root widget of the application.
///
/// This widget sets up the [MaterialApp] and determines the initial screen
/// based on whether usage permissions have been granted.
class MyApp extends StatelessWidget {
  /// The widget to display as the initial screen.
  final Widget initialScreen;

  /// Creates a [MyApp] widget.
  ///
  /// [initialScreen] is required and will be the first screen shown to the user.
  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: initialScreen,
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

  /// Continuously checks for usage permission in a loop.
  ///
  /// Once permission is granted, it saves the permission status and navigates
/// the user to the [HomeScreen]. If permission is not granted, it retries
/// after a short delay.
  Future<void> _checkPermissionLoop() async {
    bool granted = await checkUsagePermission();
    if (granted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('usage_permission_granted', true);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen()),
      );
    } else {
      Future.delayed(const Duration(seconds: 1), _checkPermissionLoop);
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