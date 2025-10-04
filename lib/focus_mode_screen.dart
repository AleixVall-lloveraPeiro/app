import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'focus_mode.dart';
import 'package:device_apps/device_apps.dart';
import 'dart:typed_data';
import 'package:lucide_icons/lucide_icons.dart';

class FocusModeScreen extends StatefulWidget {
  final FocusMode focusMode;

  const FocusModeScreen({super.key, required this.focusMode});

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen> {
  List<Application> _installedApps = [];
  List<String> _selectedAppsToBlock = [];
  bool _isLoadingApps = true;

  @override
  void initState() {
    super.initState();
    _loadInstalledApps();
  }

  Future<void> _loadInstalledApps() async {
    // Fetch only non-system apps with icons to improve performance and relevance.
    List<Application> apps = await DeviceApps.getInstalledApplications(
      includeAppIcons: true,
      includeSystemApps: false,
      onlyAppsWithLaunchIntent: true,
    );
    if (mounted) {
      setState(() {
        _installedApps = apps
          ..sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));
        _isLoadingApps = false;
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showConfigurationSheet() {
    // Temporary state for the modal sheet
    Duration selectedDuration = const Duration(minutes: 25);
    bool isPomodoro = true;
    List<String> selectedApps = List.from(_selectedAppsToBlock);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              decoration: const BoxDecoration(
                color: Color(0xFFF8F8F8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                child: SingleChildScrollView( // <-- FIX: Make the entire sheet scrollable
                  child: Column(
                    mainAxisSize: MainAxisSize.min, // Ensure column takes minimum necessary space
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Text(
                          'Configure Focus Session',
                          style: GoogleFonts.playfairDisplay(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87),
                        ),
                      ),

                      // Time Configuration
                      _buildSectionCard(
                        title: 'Choose your session interval',
                        child: isPomodoro
                            ? _buildPomodoroInfo()
                            : _buildCustomTimeSlider(
                                duration: selectedDuration,
                                onChanged: (newDuration) {
                                  setModalState(() {
                                    selectedDuration = newDuration;
                                  });
                                },
                              ),
                      ),

                      // Mode Switch
                      _buildSectionCard(
                        title: 'Mode',
                        child: SwitchListTile(
                          title: Text('Pomodoro Mode', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold)),
                          subtitle: const Text('Or follow the Pomodoro method (25 min work, 5 min break cycles).'),
                          value: isPomodoro,
                          onChanged: (value) {
                            setModalState(() {
                              isPomodoro = value;
                              selectedDuration = Duration(minutes: value ? 25 : 30);
                            });
                          },
                          activeColor: Colors.blueAccent,
                        ),
                      ),

                      // App Blocker
                      _buildSectionCard( // <-- FIX: Removed the Expanded widget from here
                        title: 'Block Apps (Optional)',
                        child: _isLoadingApps
                            ? const Center(child: CircularProgressIndicator())
                            : _buildAppList(
                                installedApps: _installedApps,
                                selectedApps: selectedApps,
                                onAppSelected: (packageName, isSelected) {
                                  setModalState(() {
                                    if (isSelected) {
                                      selectedApps.add(packageName);
                                    } else {
                                      selectedApps.remove(packageName);
                                    }
                                  });
                                },
                              ),
                      ),

                      // Start Button
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            setState(() {
                              _selectedAppsToBlock = selectedApps;
                            });
                            widget.focusMode.start(
                              selectedDuration,
                              appsToBlock: _selectedAppsToBlock,
                              isPomodoro: isPomodoro,
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Start Focusing',
                            style: GoogleFonts.playfairDisplay(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        title: Text('Focus Mode', style: GoogleFonts.playfairDisplay(color: Colors.black87, fontWeight: FontWeight.w700)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.focusMode.isRunning,
          builder: (context, isRunning, child) {
            if (isRunning) {
              return _buildTimerUI();
            } else {
              return _buildIdleUI();
            }
          },
        ),
      ),
    );
  }

  // --- UI Builder Widgets ---

  Widget _buildIdleUI() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                const Icon(LucideIcons.brainCircuit, size: 60, color: Colors.blueAccent),
                const SizedBox(height: 16),
                Text(
                  'Ready to Focus?',
                  style: GoogleFonts.playfairDisplay(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                const SizedBox(height: 8),
                Text(
                  'Configure your session and block distractions to get in the zone.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(fontSize: 16, color: Colors.black54),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _showConfigurationSheet,
                  icon: const Icon(Icons.settings, color: Colors.white),
                  label: Text('Configure Session', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: widget.focusMode.isWorking,
          builder: (context, isWorking, child) {
            return Text(
              isWorking ? 'Work Time' : 'Break Time',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: isWorking ? Colors.blueAccent : Colors.green),
            );
          },
        ),
        ValueListenableBuilder<Duration>(
          valueListenable: widget.focusMode.timeLeft,
          builder: (context, timeLeft, child) {
            return Text(
              _formatDuration(timeLeft),
              style: GoogleFonts.robotoMono(
                  fontSize: 72,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            );
          },
        ),
        ValueListenableBuilder<int>(
          valueListenable: widget.focusMode.completedCycles,
          builder: (context, completedCycles, child) {
            return Text(
              'Completed Cycles: $completedCycles',
              style: GoogleFonts.playfairDisplay(fontSize: 18, color: Colors.black54),
            );
          },
        ),
        const SizedBox(height: 40),
        ElevatedButton.icon(
          onPressed: () => widget.focusMode.stop(),
          icon: const Icon(Icons.stop, color: Colors.white),
          label: Text('Stop Session', style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.bold, color: Colors.white)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({required String title, required Widget child, bool expandChild = false}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.playfairDisplay(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black54),
          ),
          const SizedBox(height: 12),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }

  Widget _buildPomodoroInfo() {
    return const ListTile(
      leading: Icon(LucideIcons.brain, color: Colors.blueAccent),
      title: Text('Standard Pomodoro'),
      subtitle: Text('25 min work, 5 min break'),
    );
  }

  Widget _buildCustomTimeSlider({required Duration duration, required ValueChanged<Duration> onChanged}) {
    return Column(
      children: [
        Text(
          '${duration.inMinutes} minutes',
          style: GoogleFonts.robotoMono(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Slider(
          value: duration.inMinutes.toDouble(),
          min: 5,
          max: 120,
          divisions: 23,
          label: '${duration.inMinutes} min',
          onChanged: (value) {
            onChanged(Duration(minutes: value.round()));
          },
          activeColor: Colors.blueAccent,
        ),
      ],
    );
  }

  Widget _buildAppList({
    required List<Application> installedApps,
    required List<String> selectedApps,
    required Function(String, bool) onAppSelected,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: ListView.builder(
        shrinkWrap: true, // <-- FIX: Allow list to size itself within the scroll view
        physics: const NeverScrollableScrollPhysics(), // <-- FIX: Delegate scrolling to parent
        itemCount: installedApps.length,
        itemBuilder: (context, index) {
          final app = installedApps[index];
          final isSelected = selectedApps.contains(app.packageName);
          return CheckboxListTile(
            value: isSelected,
            onChanged: (value) {
              if (value != null) {
                onAppSelected(app.packageName, value);
              }
            },
            title: Text(app.appName, style: const TextStyle(fontWeight: FontWeight.w500)),
            secondary: app is ApplicationWithIcon
                ? Image.memory(app.icon, width: 40, height: 40)
                : const CircleAvatar(child: Icon(Icons.apps)),
            controlAffinity: ListTileControlAffinity.trailing,
          );
        },
      ),
    );
  }
}

