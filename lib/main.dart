import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final bool hasAccess = prefs.getBool('usage_permission_granted') ?? false;

  runApp(MyApp(initialScreen: hasAccess ? HomeScreen() : const PermissionScreen()));
}

class MyApp extends StatelessWidget {
  final Widget initialScreen;
  const MyApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: initialScreen,
    );
  }
}

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  static const platform = MethodChannel('aleix/usage');

  @override
  void initState() {
    super.initState();
    _checkPermissionLoop();
  }

  Future<bool> checkUsagePermission() async {
    try {
      final granted = await platform.invokeMethod('checkUsagePermission');
      return granted == true;
    } on PlatformException {
      return false;
    }
  }

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