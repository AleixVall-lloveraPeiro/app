import 'package:shared_preferences/shared_preferences.dart';

class UsageStorageService {
  static const String _dailyLimitKey = 'daily_limit_seconds';
  static const String _dailyUsageKey = 'daily_usage_seconds';
  static const String _lastResetDateKey = 'last_reset_date';

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

  /// Comprueba si debe reiniciarse el contador diario (cuando ha pasado de día)
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

  /// Comprueba si dos fechas están en el mismo día natural
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
