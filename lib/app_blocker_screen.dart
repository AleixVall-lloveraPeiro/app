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
  List<Application> _filteredApps = [];
  List<String> _selectedApps = [];
  bool _isLoading = true;
  bool _isBlockerActive = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeData();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredApps = _installedApps
          .where((app) => app.appName.toLowerCase().contains(query))
          .toList();
    });
  }

  Future<void> _initializeData() async {
    await _appBlocker.initialize();
    await _getInstalledApps();
    setState(() {
      _selectedApps = List.from(_appBlocker.blockedApps); // Create a copy
      _isBlockerActive = _appBlocker.isActive;
      _isLoading = false;
    });
  }

  Future<void> _getInstalledApps() async {
    List<Application> apps = await DeviceApps.getInstalledApplications(
      includeAppIcons: true,
      includeSystemApps: true,
      onlyAppsWithLaunchIntent: true,
    );
    
    setState(() {
      _installedApps = apps
          .where((app) => 
              app.appName != "Sumaia" && // Explicitly exclude Sumaia
              app.enabled // Only enabled apps
          )
          .toList()
        ..sort((a, b) => a.appName.compareTo(b.appName));
      _filteredApps = _installedApps;
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

    // Remove deselected apps
    for (final packageName in currentBlocked) {
      if (!_selectedApps.contains(packageName)) {
        await _appBlocker.removeBlockedApp(packageName);
      }
    }

    // Add new apps
    for (final packageName in _selectedApps) {
      if (!currentBlocked.contains(packageName)) {
        await _appBlocker.addBlockedApp(packageName);
      }
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
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: Text(
                            'App Blocker',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text('Enable or disable the app blocker'),
                          value: _isBlockerActive,
                          onChanged: (value) {
                            setState(() {
                              _isBlockerActive = value;
                            });
                            _appBlocker.toggleBlocker(value);
                          },
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
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search apps...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                      ),
                    ),
                  ),
                  // App List
                  _filteredApps.isEmpty
                      ? Center(
                          child: Text(
                            'No apps found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredApps.length,
                          itemBuilder: (context, index) {
                            final app = _filteredApps[index];
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