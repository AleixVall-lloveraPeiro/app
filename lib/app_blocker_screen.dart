import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_blocker.dart';

class AppBlockerScreen extends StatefulWidget {
  const AppBlockerScreen({super.key});

  @override
  State<AppBlockerScreen> createState() => _AppBlockerScreenState();
}

class _AppBlockerScreenState extends State<AppBlockerScreen> {
  final AppBlocker _appBlocker = AppBlocker();
  List<Application> _installedApps = [];
  List<String> _selectedApps = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _appBlocker.initialize();
    await _getInstalledApps();
    setState(() {
      _selectedApps = List.from(_appBlocker.blockedApps); // Create a copy
      _isLoading = false;
    });
  }

  Future<void> _getInstalledApps() async {
    List<Application> apps = await DeviceApps.getInstalledApplications();
    
    // BETTER FILTERING: Exclude system apps and apps without proper names
    setState(() {
      _installedApps = apps
          .where((app) => 
              !app.systemApp && 
              app.appName.isNotEmpty &&
              app.appName != "Sumaia" && // Explicitly exclude Sumaia
              !app.packageName.contains('.sumaia.') && // Exclude by package name
              !app.packageName.startsWith('com.android.') && // Exclude Android system apps
              !app.packageName.startsWith('com.google.android.') && // Exclude Google apps
              !app.packageName.startsWith('com.sec.android.') && // Exclude Samsung apps
              !app.packageName.contains('launcher') && // Exclude launchers
              !app.packageName.contains('setup') && // Exclude setup apps
              app.enabled // Only enabled apps
          )
          .toList()
        ..sort((a, b) => a.appName.compareTo(b.appName));
    });
  }

  void _toggleAppSelection(String packageName, bool selected) {
    setState(() {
      if (selected) {
        if (!_selectedApps.contains(packageName)) {
          _selectedApps.add(packageName);
        }
      } else {
        _selectedApps.remove(packageName);
      }
    });
  }

  Future<void> _saveSelections() async {
    final currentBlocked = _appBlocker.blockedApps;
    final currentSettings = _appBlocker.blockedAppSettings;

    // Remove deselected apps
    for (final packageName in currentBlocked) {
      if (!_selectedApps.contains(packageName)) {
        await _appBlocker.removeBlockedApp(packageName);
      }
    }

    // Add new or update existing apps, preserving old limit if it exists
    for (final packageName in _selectedApps) {
      final existingLimit = currentSettings[packageName];
      await _appBlocker.addOrUpdateBlockedApp(packageName, existingLimit ?? 60); // Default to 60 minutes
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'App blocker settings saved for ${_selectedApps.length} apps',
          style: GoogleFonts.playfairDisplay(),
        ),
        backgroundColor: Colors.green.shade700,
        duration: Duration(seconds: 2),
      ),
    );
    
    // Navigate back with the saved selections
    Navigator.pop(context, _selectedApps);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          'App Blocker',
          style: GoogleFonts.playfairDisplay(
            color: Colors.black87,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Text(
                        'Select apps to block',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'When app blocker is active, you\'ll get mindful notifications when opening these apps',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.black54),
                      ),
                      SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Selected: ${_selectedApps.length} apps',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (_selectedApps.isNotEmpty)
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _selectedApps.clear();
                                });
                              },
                              child: Text('Clear all'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                // App List
                Expanded(
                  child: _installedApps.isEmpty
                      ? Center(
                          child: Text(
                            'No user apps found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _installedApps.length,
                          itemBuilder: (context, index) {
                            final app = _installedApps[index];
                            final isSelected = _selectedApps.contains(app.packageName);
                            
                            return Container(
                              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: CheckboxListTile(
                                value: isSelected,
                                onChanged: (value) => _toggleAppSelection(app.packageName, value!),
                                title: Text(
                                  app.appName,
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  app.packageName,
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                secondary: FutureBuilder<Uint8List?>(
                                  future: _getAppIcon(app),
                                  builder: (context, snapshot) {
                                    if (snapshot.hasData && snapshot.data != null) {
                                      return CircleAvatar(
                                        backgroundColor: Colors.grey.shade100,
                                        child: Image.memory(
                                          snapshot.data!,
                                          width: 24,
                                          height: 24,
                                        ),
                                      );
                                    }
                                    return CircleAvatar(
                                      backgroundColor: Colors.grey.shade100,
                                      child: Icon(Icons.android, size: 20, color: Colors.grey),
                                    );
                                  },
                                ),
                                controlAffinity: ListTileControlAffinity.trailing,
                              ),
                            );
                          },
                        ),
                ),
                // Save Button
                Container(
                  padding: EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: _saveSelections,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF6EC1E4),
                      minimumSize: Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'SAVE ${_selectedApps.length} APPS',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<Uint8List?> _getAppIcon(Application app) async {
    try {
      if (app is ApplicationWithIcon) {
        return app.icon;
      }
    } catch (e) {
      print('Error loading icon for ${app.appName}: $e');
    }
    return null;
  }
}