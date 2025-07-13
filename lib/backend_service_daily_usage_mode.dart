import 'package:shared_preferences/shared_preferences.dart';

class UsageStorageService {
  static const String _dailyLimitKey = 'daily_limit_seconds';
  static const String _dailyUsageKey = 'daily_usage_seconds';
  static const String _lastResetDateKey = 'last_reset_date';
  static const String _currentStreakKey = 'current_streak';
  static const String _maxStreakKey = 'max_streak';
  static const String _lastUsageDateKey = 'last_usage_date';

  /*───────────────────────────────────────────────────────────────────────────
  | Public setters / getters                                                  |
  ───────────────────────────────────────────────────────────────────────────*/
  Future<void> setDailyLimit(Duration limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyLimitKey, limit.inSeconds);
  }

  Future<Duration> getDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(_dailyLimitKey);
    return Duration(seconds: seconds ?? 7200);
  }

  Future<void> addUsage(Duration amount) async {
    final prefs = await SharedPreferences.getInstance();
    await _maybeResetUsage(prefs);
    final current = prefs.getInt(_dailyUsageKey) ?? 0;
    await prefs.setInt(_dailyUsageKey, current + amount.inSeconds);
  }

  Future<Duration> getDailyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await _maybeResetUsage(prefs);
    return Duration(seconds: prefs.getInt(_dailyUsageKey) ?? 0);
  }

  Future<void> resetUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyUsageKey, 0);
    await prefs.setString(_lastResetDateKey, DateTime.now().toIso8601String());
  }

  Future<void> setLastUsageDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUsageDateKey, date.toIso8601String());
  }

  Future<DateTime?> getLastUsageDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(_lastUsageDateKey);
    return dateStr != null ? DateTime.tryParse(dateStr) : null;
  }

  Future<void> setCurrentStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_currentStreakKey, streak);
  }

  Future<int> getCurrentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentStreakKey) ?? 0;
  }

  Future<void> setMaxStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxStreakKey, streak);
  }

  Future<int> getMaxStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxStreakKey) ?? 0;
  }

  /*───────────────────────────────────────────────────────────────────────────
  | Midnight rollover: updates streaks **before** clearing yesterday's usage |
  ───────────────────────────────────────────────────────────────────────────*/
  Future<void> _maybeResetUsage(SharedPreferences prefs) async {
    final now = DateTime.now();
    final lastResetStr = prefs.getString(_lastResetDateKey);

    // First run – initialise last reset date
    if (lastResetStr == null) {
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
      await prefs.setString(_lastUsageDateKey, now.toIso8601String());
      return;
    }

    final lastReset = DateTime.tryParse(lastResetStr);

    if (lastReset == null || !_isSameDay(now, lastReset)) {
      // 1) Evaluate yesterday's usage **before** resetting it
      final prevUsageSeconds = prefs.getInt(_dailyUsageKey) ?? 0;
      final dailyLimitSeconds = prefs.getInt(_dailyLimitKey) ?? 7200;

      int currentStreak = prefs.getInt(_currentStreakKey) ?? 0;
      int maxStreak = prefs.getInt(_maxStreakKey) ?? 0;

      if (prevUsageSeconds <= dailyLimitSeconds) {
        currentStreak += 1;
        if (currentStreak > maxStreak) {
          maxStreak = currentStreak;
        }
      } else {
        currentStreak = 0;
      }

      await prefs.setInt(_currentStreakKey, currentStreak);
      await prefs.setInt(_maxStreakKey, maxStreak);
      await prefs.setString(_lastUsageDateKey, now.toIso8601String());

      // 2) Clear usage for the new day and mark the reset timestamp
      await prefs.setInt(_dailyUsageKey, 0);
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
    }
  }

  /*───────────────────────────────────────────────────────────────────────────*/
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
