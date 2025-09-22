import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) => MaterialApp(home: HomePage());
}

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const platform = MethodChannel('aleix/usage');
  String _text = 'Prem el botó per obtenir temps d\'ús';

  Future<bool> checkUsagePermission() async {
    try {
      final granted = await platform.invokeMethod('checkUsagePermission');
      return granted == true;
    } on PlatformException {
      return false;
    }
  }

  Future<void> requestUsagePermission() async {
    try {
      await platform.invokeMethod('requestUsagePermission');
    } on PlatformException {}
  }

  Future<Map<String, dynamic>?> getUsageStats(DateTime start, DateTime end) async {
    try {
      final res = await platform.invokeMethod('getUsageStats', {
        'start': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      });
      return Map<String, dynamic>.from(res);
    } on PlatformException {
      return null;
    }
  }

  String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h}h ${m}m ${s}s';
  }

  Future<void> _onGetUsage() async {
    final has = await checkUsagePermission();
    if (!has) {
      // Obrir la pantalla de configuració perquè l'usuari ho activi
      await requestUsagePermission();
      setState(() => _text = 'Activa "Accés a l\'ús" per a la nostra app i torna a prémer el botó.');
      return;
    }

    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final stats = await getUsageStats(startOfDay, now);
    if (stats == null) {
      setState(() => _text = 'Error llegint les dades.');
      return;
    }

    final totalMs = (stats['total'] ?? 0) as int;
    final duration = Duration(milliseconds: totalMs);
    setState(() => _text = 'Temps d\'ús (avui): ${formatDuration(duration)}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detox - Temps d\'ús')),
      body: Center(child: Text(_text, textAlign: TextAlign.center)),
      floatingActionButton: FloatingActionButton(
        onPressed: _onGetUsage,
        child: Icon(Icons.play_arrow),
      ),
    );
  }
}