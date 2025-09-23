import 'dart:async';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DailyUsageGoalManager {
  static final DailyUsageGoalManager _instance = DailyUsageGoalManager._internal();
  factory DailyUsageGoalManager() => _instance;
  DailyUsageGoalManager._internal();

  // Constants
  static const MethodChannel _platform = MethodChannel('aleix/usage');
  static const String _dailyLimitKey = 'daily_limit_seconds';
  static const String _lastResetDateKey = 'last_reset_date';
  static const String _currentStreakKey = 'current_streak';
  static const String _maxStreakKey = 'max_streak';
  static const String _cachedDailyUsageKey = 'cached_daily_usage'; // ✅ NUEVO: Cache local

  // Notifications
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // State variables
  Duration _dailyLimit = const Duration(hours: 2);
  Duration _currentUsage = Duration.zero;
  bool _halfwayNotified = false;
  bool _fifteenLeftNotified = false;
  bool _fiveLeftNotified = false;
  bool _limitReachedNotified = false;

  // Streams
  final StreamController<Duration> _usageStreamController = StreamController.broadcast();
  Stream<Duration> get usageStream => _usageStreamController.stream;

  /*───────────────────────────────────────────────────────────────────────────
  | Initialization                                                            |
  ───────────────────────────────────────────────────────────────────────────*/

  Future<void> initialize() async {
    await _initializeNotifications();
    await _loadDailyLimit();
    
    // ✅ NUEVO: Usar cache local en lugar de depender solo del MethodChannel
    await _loadCachedUsage();
    
    await _checkAndResetDailyUsage();
    await _updateCurrentUsage();
    
    Timer.periodic(const Duration(seconds: 10), (_) => _updateCurrentUsage());
  }

  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initSettings);
  }

  /*───────────────────────────────────────────────────────────────────────────
  | CACHE LOCAL - SOLUCIÓN TEMPORAL MIENTRAS SE ARREGLA ANDROID               |
  ───────────────────────────────────────────────────────────────────────────*/

  Future<void> _loadCachedUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedSeconds = prefs.getInt(_cachedDailyUsageKey) ?? 0;
    _currentUsage = Duration(seconds: cachedSeconds);
    print('💾 Uso cargado desde cache: ${_currentUsage.inMinutes} minutos');
  }

  Future<void> _saveCachedUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_cachedDailyUsageKey, _currentUsage.inSeconds);
  }

  /*───────────────────────────────────────────────────────────────────────────
  | Daily Reset Logic - MEJORADA CON CACHE                                    |
  ───────────────────────────────────────────────────────────────────────────*/

  Future<void> _checkAndResetDailyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastResetStr = prefs.getString(_lastResetDateKey);
    
    print('🔄 === VERIFICANDO RESET DIARIO ===');
    
    if (lastResetStr == null) {
      print('📅 Primera ejecución - Configurando fecha actual');
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
      _currentUsage = Duration.zero;
      await _saveCachedUsage();
      return;
    }
    
    final lastReset = DateTime.tryParse(lastResetStr);
    if (lastReset == null) {
      print('❌ Error parseando última fecha - Reseteando');
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
      _currentUsage = Duration.zero;
      await _saveCachedUsage();
      return;
    }
    
    // ✅ CORRECCIÓN: Verificar si es un día diferente
    final daysDifference = now.difference(lastReset).inDays;
    print('📅 Diferencia de días: $daysDifference');
    
    if (daysDifference >= 1) {
      print('🎯 ¡Nuevo día detectado! Reseteando...');
      
      // ✅ GUARDAR USO DEL DÍA ANTERIOR ANTES DE RESETEAR
      final previousDayUsage = _currentUsage;
      print('📊 Uso del día anterior para streak: ${previousDayUsage.inMinutes} minutos');
      
      // Calcular streak con el uso del día anterior (desde cache)
      await _calculateStreak(prefs, previousDayUsage);
      
      // ✅ RESET COMPLETO
      _currentUsage = Duration.zero;
      _resetNotificationFlags();
      
      // Guardar nueva fecha de reset y usage resetado
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
      await _saveCachedUsage();
      
      print('✅ Reset completado. Uso actual: 0 minutos');
    } else {
      print('📊 Continuando con el día actual');
    }
  }

  Future<void> _calculateStreak(SharedPreferences prefs, Duration previousDayUsage) async {
    try {
      print('📈 Calculando streak...');
      
      int currentStreak = prefs.getInt(_currentStreakKey) ?? 0;
      int maxStreak = prefs.getInt(_maxStreakKey) ?? 0;

      // ✅ USAR EL CACHE LOCAL en lugar del MethodChannel defectuoso
      if (previousDayUsage <= _dailyLimit) {
        currentStreak += 1;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
        print('✅ Streak incrementado: $currentStreak días');
      } else {
        currentStreak = 0;
        print('❌ Streak resetado: límite excedido');
      }

      await prefs.setInt(_currentStreakKey, currentStreak);
      await prefs.setInt(_maxStreakKey, maxStreak);
      
    } catch (e) {
      print('❌ Error calculando streak: $e');
    }
  }

  /*───────────────────────────────────────────────────────────────────────────
  | Usage Tracking - CON SOLUCIÓN HÍBRIDA (Cache + MethodChannel)             |
  ───────────────────────────────────────────────────────────────────────────*/

  Future<void> _updateCurrentUsage() async {
    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      print('📱 === ACTUALIZANDO USO ACTUAL ===');
      print('🕐 Consultando desde: ${startOfDay.toIso8601String()}');

      // ✅ SOLUCIÓN HÍBRIDA: Usar MethodChannel pero validar los resultados
      final Map<dynamic, dynamic> stats = await _platform.invokeMethod('getUsageStats', {
        'start': startOfDay.millisecondsSinceEpoch,
        'end': now.millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 10));

      final int totalMs = stats['total'] ?? 0;
      final Duration newUsageFromChannel = Duration(milliseconds: totalMs);
      
      print('📊 Uso del MethodChannel: ${newUsageFromChannel.inMinutes} minutos');
      print('💾 Uso en cache: ${_currentUsage.inMinutes} minutos');

      // ✅ VALIDACIÓN CRÍTICA: Si el channel devuelve menos de 5 minutos, 
      // pero nosotros tenemos más en cache, ignorar el channel
      if (newUsageFromChannel.inMinutes < 5 && _currentUsage.inMinutes > 10) {
        print('⚠️  MethodChannel parece defectuoso - Usando cache local');
        // Incrementar cache local basado en el tiempo transcurrido
        final additionalUsage = const Duration(minutes: 1); // Aproximación
        _currentUsage += additionalUsage;
      } else if (newUsageFromChannel > _currentUsage) {
        // Si el channel devuelve un valor razonable, usarlo
        _currentUsage = newUsageFromChannel;
      }
      // Si el channel devuelve menos que nuestro cache, mantener el cache

      await _saveCachedUsage();
      
      _usageStreamController.add(_currentUsage);
      _handleNotifications();
      
      print('✅ Uso actualizado: ${_currentUsage.inMinutes} minutos');
      
    } on PlatformException catch (e) {
      print('❌ PlatformException: ${e.message}');
      // En caso de error, usar cache local + pequeño incremento
      _currentUsage += const Duration(minutes: 1);
      await _saveCachedUsage();
      _usageStreamController.add(_currentUsage);
    } catch (e) {
      print('❌ Error inesperado: $e');
      _currentUsage += const Duration(minutes: 1);
      await _saveCachedUsage();
      _usageStreamController.add(_currentUsage);
    }
  }

  /*───────────────────────────────────────────────────────────────────────────
  | Daily Limit Management                                                    |
  ───────────────────────────────────────────────────────────────────────────*/

  Future<void> _loadDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(_dailyLimitKey);
    _dailyLimit = Duration(seconds: seconds ?? 7200);
    print('🎯 Límite diario: ${_dailyLimit.inMinutes} minutos');
  }

  Future<void> updateDailyLimit(Duration newLimit) async {
    _dailyLimit = newLimit;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyLimitKey, newLimit.inSeconds);
    
    _resetNotificationFlags();
    _usageStreamController.add(_currentUsage);
  }

  void _resetNotificationFlags() {
    _halfwayNotified = false;
    _fifteenLeftNotified = false;
    _fiveLeftNotified = false;
    _limitReachedNotified = false;
  }

  /*───────────────────────────────────────────────────────────────────────────
  | Notifications                                                             |
  ───────────────────────────────────────────────────────────────────────────*/

  void _handleNotifications() {
    final current = _currentUsage;
    final remaining = _dailyLimit - current;

    if (!_halfwayNotified && current >= _dailyLimit * 0.5) {
      _sendNotification('Halfway There', 'You\'ve used half of your daily goal.');
      _halfwayNotified = true;
    }

    if (!_fifteenLeftNotified && remaining.inMinutes <= 15 && remaining.inMinutes > 5) {
      _sendNotification('Almost Done', 'Only 15 minutes left of your daily usage goal.');
      _fifteenLeftNotified = true;
    }

    if (!_fiveLeftNotified && remaining.inMinutes <= 5 && remaining.inMinutes > 0) {
      _sendNotification('5 Minutes Left', 'Just 5 minutes remaining.');
      _fiveLeftNotified = true;
    }

    if (!_limitReachedNotified && current >= _dailyLimit) {
      _sendNotification('Limit Reached', 'You have reached your daily usage goal.');
      _limitReachedNotified = true;
    }
  }

  Future<void> _sendNotification(String title, String body) async {
    const androidDetails = AndroidNotificationDetails(
      'limit_channel',
      'Daily Usage Alerts',
      channelDescription: 'Notifies about your daily screen time progress',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(
      Random().nextInt(1000),
      title, 
      body, 
      details
    );
  }

  /*───────────────────────────────────────────────────────────────────────────
  | Getters                                                                   |
  ───────────────────────────────────────────────────────────────────────────*/

  Duration get currentUsage => _currentUsage;
  Duration get dailyLimit => _dailyLimit;

  Future<int> getCurrentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentStreakKey) ?? 0;
  }

  Future<int> getMaxStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxStreakKey) ?? 0;
  }

  // ✅ NUEVO: Método para debug y testing
  Future<void> debugResetForTesting() async {
    final prefs = await SharedPreferences.getInstance();
    _currentUsage = Duration.zero;
    await prefs.setString(_lastResetDateKey, DateTime.now().toIso8601String());
    await _saveCachedUsage();
    _usageStreamController.add(_currentUsage);
    print('🔧 Reset manual para testing completado');
  }
}

// ... (el resto del código de la UI permanece igual) ...

// ... (La UI screen permanece igual) ...
/*───────────────────────────────────────────────────────────────────────────────
| UI Screen                                                                    |
───────────────────────────────────────────────────────────────────────────────*/

class DailyUsageGoalScreen extends StatefulWidget {
  const DailyUsageGoalScreen({super.key});

  @override
  State<DailyUsageGoalScreen> createState() => _DailyUsageGoalScreenState();
}

class _DailyUsageGoalScreenState extends State<DailyUsageGoalScreen> {
  final DailyUsageGoalManager _manager = DailyUsageGoalManager();

  Duration _currentUsage = Duration.zero;
  Duration _dailyLimit = const Duration(hours: 2);
  int _currentStreak = 0;
  int _maxStreak = 0;
  
  StreamSubscription<Duration>? _usageSubscription;

  @override
  void initState() {
    super.initState();
    _initializeManager();
  }

  Future<void> _initializeManager() async {
    await _manager.initialize();
    
    _usageSubscription = _manager.usageStream.listen((usage) {
      setState(() {
        _currentUsage = usage;
        _dailyLimit = _manager.dailyLimit;
      });
    });

    // Load streak data
    _loadStreakData();
  }

  Future<void> _loadStreakData() async {
    final currentStreak = await _manager.getCurrentStreak();
    final maxStreak = await _manager.getMaxStreak();
    
    if (mounted) {
      setState(() {
        _currentStreak = currentStreak;
        _maxStreak = maxStreak;
      });
    }
  }

  @override
  void dispose() {
    _usageSubscription?.cancel();
    super.dispose();
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
          child: CupertinoTimerPicker(
            initialTimerDuration: _dailyLimit,
            mode: CupertinoTimerPickerMode.hm,
            onTimerDurationChanged: (Duration newDuration) {
              _manager.updateDailyLimit(newDuration);
              _loadStreakData(); // Reload streaks after limit change
            },
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}H ${m}min';
  }

  @override
  Widget build(BuildContext context) {
    final double percent = min(_currentUsage.inSeconds / _dailyLimit.inSeconds, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFFDFDFD),
      appBar: AppBar(
        title: Text(
          'Daily Usage Goal', 
          style: GoogleFonts.playfairDisplay(
            fontSize: 22, 
            fontWeight: FontWeight.w700, 
            color: Colors.black87
          )
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
              // Streak Info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStreakCard('Current Streak', _currentStreak),
                  _buildStreakCard('Max Streak', _maxStreak),
                ],
              ),
              
              const SizedBox(height: 30),
              
              // Progress Circle
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
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.blueAccent),
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatDuration(_currentUsage), 
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 32, 
                          fontWeight: FontWeight.bold, 
                          color: Colors.blueAccent
                        )
                      ),
                      Text(
                        'of ${_formatDuration(_dailyLimit)}', 
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 14, 
                          color: Colors.black54
                        )
                      ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 40),
              
              // Set Limit Button
              ElevatedButton(
                onPressed: _openTimePicker,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent, 
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                ),
                child: Text(
                  'Set Daily Limit', 
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18, 
                    fontWeight: FontWeight.w600, 
                    color: Colors.white
                  )
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreakCard(String title, int value) {
    return Column(
      children: [
        Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 14,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$value days',
          style: GoogleFonts.playfairDisplay(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
      ],
    );
  }
}