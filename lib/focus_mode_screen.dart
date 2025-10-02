
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'focus_mode.dart';
import 'package:device_apps/device_apps.dart'; // Import device_apps
import 'dart:typed_data'; // For app icons

class FocusModeScreen extends StatefulWidget {
  final FocusMode focusMode;

  const FocusModeScreen({super.key, required this.focusMode});

  @override
  State<FocusModeScreen> createState() => _FocusModeScreenState();
}

class _FocusModeScreenState extends State<FocusModeScreen> {
  Duration _selectedDuration = const Duration(minutes: 30);
  List<Application> _installedApps = [];
  List<String> _selectedAppsToBlock = [];
  bool _isLoadingApps = true;

  @override
  void initState() {
    super.initState();
    _loadInstalledApps();
  }

  Future<void> _loadInstalledApps() async {
    List<Application> apps = await DeviceApps.getInstalledApplications();
    setState(() {
      _installedApps = apps
          .where((app) => 
              !app.systemApp && 
              app.appName.isNotEmpty &&
              app.enabled // Only enabled apps
          )
          .toList()
        ..sort((a, b) => a.appName.compareTo(b.appName));
      _isLoadingApps = false;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$hours:$minutes:$seconds';
  }

  void _showAppSelectionAndDurationPicker() {
    bool isPomodoro = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Text(
                    'Configure Focus Session',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  SwitchListTile(
                    title: Text('Pomodoro Mode'),
                    subtitle: Text('Work in 25-min cycles with 5-min breaks'),
                    value: isPomodoro,
                    onChanged: (value) {
                      setModalState(() {
                        isPomodoro = value;
                      });
                    },
                  ),
                  if (!isPomodoro)
                    SizedBox(
                      height: 100,
                      child: ListWheelScrollView.useDelegate(
                        itemExtent: 50,
                        perspective: 0.005,
                        diameterRatio: 1.2,
                        onSelectedItemChanged: (index) {
                          setModalState(() {
                            _selectedDuration = Duration(minutes: (index + 1) * 5);
                          });
                        },
                        childDelegate: ListWheelChildBuilderDelegate(
                          builder: (context, index) {
                            final minutes = (index + 1) * 5;
                            return Center(
                              child: Text(
                                '$minutes minutes',
                                style: GoogleFonts.playfairDisplay(fontSize: 20),
                              ),
                            );
                          },
                          childCount: 24, // Up to 2 hours
                        ),
                      ),
                    ),
                  SizedBox(height: 24),
                  Text(
                    'Select Apps to Block (Optional)',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Expanded(
                    child: _isLoadingApps
                        ? Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: _installedApps.length,
                            itemBuilder: (context, index) {
                              final app = _installedApps[index];
                              final isSelected = _selectedAppsToBlock.contains(app.packageName);
                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (value) {
                                  setModalState(() {
                                    if (value!) {
                                      _selectedAppsToBlock.add(app.packageName);
                                    } else {
                                      _selectedAppsToBlock.remove(app.packageName);
                                    }
                                  });
                                },
                                title: Text(app.appName),
                                subtitle: Text(app.packageName),
                                secondary: app is ApplicationWithIcon && app.icon != null
                                    ? Image.memory(app.icon!, width: 40, height: 40)
                                    : null,
                              );
                            },
                          ),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.focusMode.start(
                        _selectedDuration,
                        appsToBlock: _selectedAppsToBlock,
                        isPomodoro: isPomodoro,
                      );
                    },
                    child: const Text('Start Focusing'),
                  ),
                ],
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
      appBar: AppBar(
        title: Text('Focus Mode', style: GoogleFonts.playfairDisplay()),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.focusMode.isRunning,
          builder: (context, isRunning, child) {
            if (isRunning) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.focusMode.isWorking,
                    builder: (context, isWorking, child) {
                      return Text(
                        isWorking ? 'Work Time' : 'Break Time',
                        style: GoogleFonts.playfairDisplay(fontSize: 32, fontWeight: FontWeight.w700),
                      );
                    },
                  ),
                  ValueListenableBuilder<Duration>(
                    valueListenable: widget.focusMode.timeLeft,
                    builder: (context, timeLeft, child) {
                      return Text(
                        _formatDuration(timeLeft),
                        style: GoogleFonts.playfairDisplay(fontSize: 60, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: widget.focusMode.completedCycles,
                    builder: (context, completedCycles, child) {
                      return Text(
                        'Completed Cycles: $completedCycles',
                        style: GoogleFonts.playfairDisplay(fontSize: 18),
                      );
                    },
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton(
                    onPressed: () {
                      widget.focusMode.stop();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    ),
                    child: const Text('Stop'),
                  ),
                ],
              );
            } else {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Ready to focus?',
                    style: GoogleFonts.playfairDisplay(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _showAppSelectionAndDurationPicker,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    ),
                    child: const Text('Set Focus Duration and Block Apps'),
                  ),
                ],
              );
            }
          },
        ),
      ),
    );
  }
}

