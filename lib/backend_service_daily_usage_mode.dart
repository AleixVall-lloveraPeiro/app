import 'package:shared_preferences/shared_preferences.dart';

class UsageStorageService {
  static const String _dailyLimitKey = 'daily_limit_seconds';
  static const String _dailyUsageKey = 'daily_usage_seconds';
  static const String _lastResetDateKey = 'last_reset_date';
  static const String _currentStreakKey = 'current_streak';
  static const String _maxStreakKey = 'max_streak';
  static const String _lastUsageDateKey = 'last_usage_date';

  /// Guarda el límite diario de uso del móvil en segundos
  Future<void> setDailyLimit(Duration limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyLimitKey, limit.inSeconds);
  }

  /// Recupera el límite diario de uso del móvil. Por defecto, 2 horas
  Future<Duration> getDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(_dailyLimitKey);
    return Duration(seconds: seconds ?? 7200);
  }

  /// Añade segundos al tiempo actual acumulado de uso
  Future<void> addUsage(Duration amount) async {
    final prefs = await SharedPreferences.getInstance();
    await _maybeResetUsage(prefs);
    final current = prefs.getInt(_dailyUsageKey) ?? 0;
    await prefs.setInt(_dailyUsageKey, current + amount.inSeconds);
  }

  /// Devuelve el tiempo acumulado hoy, reseteado automáticamente si ha cambiado el día
  Future<Duration> getDailyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await _maybeResetUsage(prefs);
    return Duration(seconds: prefs.getInt(_dailyUsageKey) ?? 0);
  }

  /// Resetea el uso acumulado y guarda la fecha del reseteo
  Future<void> resetUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyUsageKey, 0);
    await prefs.setString(_lastResetDateKey, DateTime.now().toIso8601String());
  }

  /// Guarda la última data d'ús registrada per al sistema de streaks
  Future<void> setLastUsageDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUsageDateKey, date.toIso8601String());
  }

  /// Recupera la darrera data d'ús
  Future<DateTime?> getLastUsageDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(_lastUsageDateKey);
    return dateStr != null ? DateTime.tryParse(dateStr) : null;
  }

  /// Guarda la ratxa actual de dies en què s'ha complert l'objectiu
  Future<void> setCurrentStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentStreakKey, streak);
  }

  /// Recupera la ratxa actual
  Future<int> getCurrentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentStreakKey) ?? 0;
  }

  /// Guarda la ratxa màxima assolida
  Future<void> setMaxStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxStreakKey, streak);
  }

  /// Recupera la ratxa màxima
  Future<int> getMaxStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxStreakKey) ?? 0;
  }

  Future<Duration> getUsageForDate(DateTime date) async {
  final prefs = await SharedPreferences.getInstance();
  final now = DateTime.now();

  if (_isSameDay(now, date)) {
    await _maybeResetUsage(prefs);
    return Duration(seconds: prefs.getInt(_dailyUsageKey) ?? 0);
  }

  return Duration.zero;
  }

  /// Comprova si cal reiniciar el comptador diari (quan ha passat de dia)
  Future<void> _maybeResetUsage(SharedPreferences prefs) async {
    final now = DateTime.now();
    final lastResetStr = prefs.getString(_lastResetDateKey);
    if (lastResetStr == null) {
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
      return;
    }

    final lastReset = DateTime.tryParse(lastResetStr);
    if (lastReset == null || !_isSameDay(now, lastReset)) {
      await resetUsage();
    }
  }

  /// Comprova si dues dates són del mateix dia natural
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
} 
