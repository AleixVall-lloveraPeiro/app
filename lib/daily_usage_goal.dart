import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screen_state/screen_state.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:math';
import 'backend_service_daily_usage_mode.dart';

class DailyUsageGoalScreen extends StatefulWidget {
  const DailyUsageGoalScreen({super.key});

  @override
  State<DailyUsageGoalScreen> createState() => _DailyUsageGoalScreenState();
}

class _DailyUsageGoalScreenState extends State<DailyUsageGoalScreen>
    with WidgetsBindingObserver {
  Duration _dailyLimit = const Duration(hours: 2);
  Duration _currentUsage = Duration.zero;
  Timer? _usageTimer;
  final Screen _screen = Screen();
  StreamSubscription<ScreenStateEvent>? _screenSubscription;
  bool _isCounting = false;
  final _usageService = UsageStorageService();
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeNotifications();
    _loadStoredData();
    _listenToScreenEvents();
  }

  Future<void> _loadStoredData() async {
    _dailyLimit = await _usageService.getDailyLimit();
    _currentUsage = await _usageService.getDailyUsage();
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _screenSubscription?.cancel();
    _usageTimer?.cancel();
    super.dispose();
  }

  void _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  void _listenToScreenEvents() {
    _screenSubscription = _screen.screenStateStream.listen((event) {
      if (event == ScreenStateEvent.SCREEN_ON) {
        _startCounting();
      } else if (event == ScreenStateEvent.SCREEN_OFF) {
        _stopCounting();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startCounting();
    } else {
      _stopCounting();
    }
  }

  void _startCounting() {
    if (_isCounting) return;
    _isCounting = true;
    _usageTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _currentUsage += const Duration(seconds: 1);
      await _usageService.addUsage(const Duration(seconds: 1));

      setState(() {});

      if (_currentUsage >= _dailyLimit) {
        _sendLimitReachedNotification();
        _stopCounting();
      }
    });
  }

  void _stopCounting() {
    _isCounting = false;
    _usageTimer?.cancel();
  }

  Future<void> _sendLimitReachedNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'limit_channel',
      'Daily Limit Reached',
      channelDescription: 'Notifies when daily usage limit is reached',
      importance: Importance.high,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      0,
      'Limit Reached',
      'You have reached your daily usage goal.',
      notificationDetails,
    );
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
          child: Column(
            children: [
              Expanded(
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    brightness: Brightness.light,
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(color: Colors.black),
                    ),
                  ),
                  child: CupertinoTimerPicker(
                    initialTimerDuration: _dailyLimit,
                    mode: CupertinoTimerPickerMode.hm,
                    onTimerDurationChanged: (Duration newDuration) async {
                      setState(() => _dailyLimit = newDuration);
                      await _usageService.setDailyLimit(newDuration);
                    },
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _startCounting(); // ⬅ Aquí arranca el conteo al pulsar Done
                },
                child: Text(
                  'Done',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    double percent = min(_currentUsage.inSeconds / _dailyLimit.inSeconds, 1.0);
    String formattedUsage =
        '${_currentUsage.inHours.toString().padLeft(2, '0')}:${(_currentUsage.inMinutes % 60).toString().padLeft(2, '0')}';
    String formattedLimit =
        '${_dailyLimit.inHours.toString().padLeft(2, '0')}:${(_dailyLimit.inMinutes % 60).toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        title: Text(
          'Daily Usage Goal',
          style: GoogleFonts.playfairDisplay(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
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
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        formattedUsage,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueAccent,
                        ),
                      ),
                      Text(
                        'of $formattedLimit',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'Set Daily Limit',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}