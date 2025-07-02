import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pomodoro_mode.dart';

class PomodoroScreen extends StatefulWidget {
  final PomodoroMode pomodoroMode;

  const PomodoroScreen({super.key, required this.pomodoroMode});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen> {
  @override
  void initState() {
    super.initState();
    widget.pomodoroMode.start();
  }

  @override
  void dispose() {
    widget.pomodoroMode.stop();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.pomodoroMode;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pomodoro Focus'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: Center(
        child: ValueListenableBuilder(
          valueListenable: mode.timeLeft,
          builder: (context, Duration time, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ValueListenableBuilder(
                  valueListenable: mode.isWorking,
                  builder: (context, bool isWorking, _) {
                    return Text(
                      isWorking ? 'Focus Time' : 'Break Time',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: isWorking ? Colors.red : Colors.green,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  _formatDuration(time),
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 40),
                ElevatedButton(
                  onPressed: () {
                    mode.stop();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Stop Session'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}