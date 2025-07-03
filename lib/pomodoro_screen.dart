import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pomodoro_mode.dart';

class PomodoroScreen extends StatefulWidget {
  final PomodoroMode pomodoroMode;

  const PomodoroScreen({super.key, required this.pomodoroMode});

  @override
  State<PomodoroScreen> createState() => _PomodoroScreenState();
}

class _PomodoroScreenState extends State<PomodoroScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _backgroundPulseController;
  late Animation<double> _backgroundScale;

  @override
  void initState() {
    super.initState();

    widget.pomodoroMode.onPomodoroCompleted = () {
      _showMotivationalDialog();
    };

    widget.pomodoroMode.start();

    _backgroundPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _backgroundScale = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _backgroundPulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    widget.pomodoroMode.stop();
    _backgroundPulseController.dispose();
    super.dispose();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showMotivationalDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text("Amazing work!", style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.bold)),
        content: Text("You've completed 4 Pomodoro cycles. Time for a well-deserved rest. 🎉",
            style: GoogleFonts.playfairDisplay(fontSize: 16)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text("Back to Home", style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmStop() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        title: Text("Are you sure?",
            style: GoogleFonts.playfairDisplay(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87)),
        content: Text("You're doing great. Are you sure you want to stop focusing now?",
            style: GoogleFonts.playfairDisplay(fontSize: 16, color: Colors.black54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel", style: GoogleFonts.playfairDisplay(color: Colors.grey.shade600)),
          ),
          TextButton(
            onPressed: () {
              widget.pomodoroMode.stop();
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
            child: Text("Yes, stop it",
                style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.pomodoroMode;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _backgroundPulseController,
        builder: (context, child) {
          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFAF3E0), Color(0xFFE0F7FA)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Transform.scale(
              scale: _backgroundScale.value,
              child: Center(
                child: ValueListenableBuilder(
                  valueListenable: mode.timeLeft,
                  builder: (context, Duration time, _) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ValueListenableBuilder(
                          valueListenable: mode.isWorking,
                          builder: (context, bool isWorking, _) {
                            return Text(
                              isWorking ? 'Focus Time' : 'Break Time',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                color: isWorking ? Colors.red.shade300 : Colors.green.shade400,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 30),
                        Text(
                          _formatDuration(time),
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 70,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 50),
                        ElevatedButton(
                          onPressed: _confirmStop,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black.withOpacity(0.05),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 16,
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            'Stop Session',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
