import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mindful_usage_mode.dart';
import 'pomodoro_mode.dart';
import 'pomodoro_screen.dart';
import 'daily_usage_goal.dart';
import 'app_blocker_screen.dart';
import 'app_blocker.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  bool isMindfulModeOn = false;
  bool isAppBlockerOn = false;
  final MindfulUsageMode mindfulUsageMode = MindfulUsageMode();
  final PomodoroMode pomodoroMode = PomodoroMode();
  final AppBlocker appBlocker = AppBlocker();
  late AnimationController _playController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _playController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: _playController, curve: Curves.easeInOut),
    );
    
    _loadMindfulModeState();
    _loadAppBlockerState();
  }
  
  Future<void> _loadMindfulModeState() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isMindfulModeOn = prefs.getBool('isMindfulModeOn') ?? false;
    });
    
    if (isMindfulModeOn) {
      mindfulUsageMode.start(silent: true);
    }
  }

  Future<void> _loadAppBlockerState() async {
    await appBlocker.initialize();
    setState(() {
      isAppBlockerOn = appBlocker.isActive;
    });
  }

  Future<void> _saveMindfulModeState(bool state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isMindfulModeOn', state);
  }

  @override
  void dispose() {
    mindfulUsageMode.stop();
    pomodoroMode.stop();
    appBlocker.dispose();
    _playController.dispose();
    super.dispose();
  }

  void _toggleMindfulMode() {
    if (isMindfulModeOn) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: Text(
              'Are you sure?',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            content: Text(
              'You were doing great. Are you sure you want to stop being mindful now?',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Cancel',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    isMindfulModeOn = false;
                    mindfulUsageMode.stop();
                  });
                  _saveMindfulModeState(false);
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Yes, stop it',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      setState(() {
        isMindfulModeOn = true;
        mindfulUsageMode.start(silent: false);
      });
      _saveMindfulModeState(true);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mindful mode activated ✨',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _toggleAppBlocker() {
    if (isAppBlockerOn) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: Text(
              'Turn off App Blocker?',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            content: Text(
              'You\'ll be able to access all apps without mindful pauses. Are you sure?',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16,
                color: Colors.black54,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Cancel',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    isAppBlockerOn = false;
                    appBlocker.toggleBlocker(false);
                  });
                  Navigator.of(context).pop();
                },
                child: Text(
                  'Yes, turn off',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else {
      setState(() {
        isAppBlockerOn = true;
        appBlocker.toggleBlocker(true);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'App Blocker activated 🛡️',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          backgroundColor: Color(0xFFFF6B6B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _startPomodoro() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PomodoroScreen(pomodoroMode: pomodoroMode),
        transitionDuration: const Duration(milliseconds: 600),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeInOut),
            child: child,
          );
        },
      ),
    );
  }

  void _navigateToDailyGoal() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const DailyUsageGoalScreen()),
    );
  }

  void _navigateToAppBlocker() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AppBlockerScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        title: Text(
          'Welcome Back',
          style: GoogleFonts.playfairDisplay(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Choose your presence mode:',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 20,
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            // APP BLOCKER MODE SWITCH - MOVED TO TOP
            _buildOptionSwitch(
              context,
              title: 'App Blocker Mode',
              subtitle: 'Get mindful notifications when opening distracting apps.',
              icon: Icons.block,
              color: const Color(0xFFFF6B6B),
              isActive: isAppBlockerOn,
              onToggle: _toggleAppBlocker,
              maxWidth: screenWidth - 120,
            ),
            const SizedBox(height: 24),
            // MANAGE BLOCKED APPS - MOVED TO TOP
            _buildAppBlockerOption(
              context,
              title: 'Manage Blocked Apps',
              subtitle: 'Select which apps to block when App Blocker is active.',
              icon: Icons.settings,
              color: const Color(0xFF9C27B0),
              maxWidth: screenWidth - 120,
            ),
            const SizedBox(height: 24),
            // DAILY USAGE GOAL
            GestureDetector(
              onTap: _navigateToDailyGoal,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF6EC1E4).withOpacity(0.1),
                      ),
                      child: Icon(Icons.hourglass_bottom, color: const Color(0xFF6EC1E4), size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily Usage Goal',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Set a daily limit to become more aware and disciplined with your time.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // MINDFUL USAGE MODE
            _buildOptionSwitch(
              context,
              title: 'Mindful Usage Mode',
              subtitle: 'Receive a gentle reminder every 5 minutes you\'re using your phone.',
              icon: Icons.timer,
              color: const Color.fromARGB(255, 0, 200, 0),
              isActive: isMindfulModeOn,
              onToggle: _toggleMindfulMode,
              maxWidth: screenWidth - 120,
            ),
            const SizedBox(height: 24),
            // POMODORO FOCUS MODE
            _buildPomodoroButton(
              context,
              title: 'Pomodoro Focus Mode',
              subtitle: '25 min focus + 5 min break ×4. Stay productive effortlessly.',
              icon: LucideIcons.clock9,
              color: const Color.fromARGB(255, 255, 99, 71),
              onPressed: _startPomodoro,
              maxWidth: screenWidth - 120,
            ),
            const SizedBox(height: 40),
            Text(
              '"Clarity begins when noise ends."',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionSwitch(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isActive,
    required VoidCallback onToggle,
    required double maxWidth,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.1),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(
            value: isActive,
            onChanged: (_) => onToggle(),
            activeColor: color,
          ),
        ],
      ),
    );
  }

  Widget _buildPomodoroButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    required double maxWidth,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.1),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTapDown: (_) => _playController.forward(),
            onTapUp: (_) {
              _playController.reverse();
              onPressed();
            },
            onTapCancel: () => _playController.reverse(),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: AnimatedBuilder(
                animation: _scaleAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withOpacity(0.15),
                        boxShadow: [
                          BoxShadow(
                            color: color.withOpacity(0.5),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(Icons.play_arrow, size: 30, color: color),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBlockerOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required double maxWidth,
  }) {
    return GestureDetector(
      onTap: _navigateToAppBlocker,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.1),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withOpacity(0.1),
              ),
              child: Icon(Icons.arrow_forward_ios, size: 20, color: color),
            ),
          ],
        ),
      ),
    );
  }
}