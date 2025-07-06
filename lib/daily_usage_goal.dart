import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:screen_state/screen_state.dart';

class DailyUsageGoalScreen extends StatefulWidget {
  const DailyUsageGoalScreen({super.key});

  @override
  State<DailyUsageGoalScreen> createState() => _DailyUsageGoalScreenState();
}

class _DailyUsageGoalScreenState extends State<DailyUsageGoalScreen> {
  final Screen _screen = Screen();
  StreamSubscription<ScreenStateEvent>? _screenSubscription;
  Timer? _usageTimer;

  int _activeSeconds = 0;
  int _goalSeconds = 7200; // Default goal: 2h

  @override
  void initState() {
    super.initState();
    _listenToScreenEvents();
  }

  @override
  void dispose() {
    _screenSubscription?.cancel();
    _usageTimer?.cancel();
    super.dispose();
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

  void _startCounting() {
    _usageTimer?.cancel();
    _usageTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _activeSeconds++;
      });
    });
  }

  void _stopCounting() {
    _usageTimer?.cancel();
  }

  void _updateGoal(Duration newGoal) {
    setState(() {
      _goalSeconds = newGoal.inSeconds;
    });
  }

  @override
  Widget build(BuildContext context) {
    double percent = (_activeSeconds / _goalSeconds).clamp(0.0, 1.0);
    Duration active = Duration(seconds: _activeSeconds);
    Duration goal = Duration(seconds: _goalSeconds);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Daily Usage Goal"),
        backgroundColor: Colors.lightBlue.shade100,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "Set your daily phone usage goal",
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _buildTimeSelector(),
            const SizedBox(height: 32),
            CircularPercentIndicator(
              radius: 120.0,
              lineWidth: 14.0,
              percent: percent,
              progressColor: Colors.lightBlueAccent,
              backgroundColor: Colors.grey.shade200,
              circularStrokeCap: CircularStrokeCap.round,
              center: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatDuration(active),
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "/ ${_formatDuration(goal)}",
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 16,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelector() {
    return Column(
      children: [
        Slider(
          value: _goalSeconds.toDouble(),
          min: 1800,
          max: 21600,
          divisions: 39,
          label: _formatDuration(Duration(seconds: _goalSeconds)),
          activeColor: Colors.lightBlueAccent,
          onChanged: (value) {
            _updateGoal(Duration(seconds: value.toInt()));
          },
        ),
        Text(
          "Goal: ${_formatDuration(Duration(seconds: _goalSeconds))}",
          style: GoogleFonts.playfairDisplay(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    int h = d.inHours;
    int m = d.inMinutes.remainder(60);
    return h > 0 ? "${twoDigits(h)}h ${twoDigits(m)}m" : "${twoDigits(m)}m";
  }
}