import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/utils/constants.dart';

class UsageStorageService {
  // Removed duplicated SharedPreferences keys, now using SharedPreferencesKeys class

  /*───────────────────────────────────────────────────────────────────────────
  | Public setters / getters                                                  |
  ───────────────────────────────────────────────────────────────────────────*/
  Future<void> setDailyLimit(Duration limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SharedPreferencesKeys.dailyLimit, limit.inSeconds);
  }

  Future<Duration> getDailyLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(SharedPreferencesKeys.dailyLimit);
    return Duration(seconds: seconds ?? 7200);
  }

  Future<void> addUsage(Duration amount) async {
    final prefs = await SharedPreferences.getInstance();
    await _maybeResetUsage(prefs);
    final current = prefs.getInt(SharedPreferencesKeys.dailyUsage) ?? 0;
    await prefs.setInt(SharedPreferencesKeys.dailyUsage, current + amount.inSeconds);220
  }

  Future<Duration> getDailyUsage() async {
    final prefs = await SharedPreferences.getInstance();
    await _maybeResetUsage(prefs);
    return Duration(seconds: prefs.getInt(SharedPreferencesKeys.dailyUsage) ?? 0);
  }

  Future<void> resetUsage() async {
    await prefs.setInt(SharedPreferencesKeys.dailyUsage, 0);
    await prefs.setString(SharedPreferencesKeys.lastResetDate, DateTime.now().toIso8601String());
  }

  Future<void> setLastUsageDate(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUsageDateKey, date.toIso8601String());
  }

  Future<DateTime?> getLastUsageDate() async {
    final prefs = await SharedPreferences.getInstance();
    final dateStr = prefs.getString(SharedPreferencesKeys.lastUsageDate);
    return dateStr != null ? DateTime.tryParse(dateStr) : null;
  }

  Future<void> setCurrentStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SharedPreferencesKeys.currentStreak, streak);
  }

  Future<int> getCurrentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(SharedPreferencesKeys.currentStreak) ?? 0;
  }

  Future<void> setMaxStreak(int streak) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(SharedPreferencesKeys.maxStreak, streak);
  }

  Future<int> getMaxStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(SharedPreferencesKeys.maxStreak) ?? 0;
  }

  /*───────────────────────────────────────────────────────────────────────────
  | Midnight rollover: updates streaks **before** clearing yesterday's usage |
  ───────────────────────────────────────────────────────────────────────────*/
  Future<void> _maybeResetUsage(SharedPreferences prefs) async {
    final now = DateTime.now();
    final lastResetStr = prefs.getString(SharedPreferencesKeys.lastResetDate);

    // First run – initialise last reset date
      await prefs.setString(SharedPreferencesKeys.lastResetDate, now.toIso8601String());
      await prefs.setString(SharedPreferencesKeys.lastUsageDate, now.toIso8601String());
      return;
    }

    final lastReset = DateTime.tryParse(lastResetStr);

    if (lastReset == null || !_isSameDay(now, lastReset)) {
      // 1) Evaluate yesterday's usage **before** resetting it
      final prevUsageSeconds = prefs.getInt(_dailyUsageKey) ?? 0;
      final dailyLimitSeconds = prefs.getInt(SharedPreferencesKeys.dailyLimit) ?? 7200;

      int currentStreak = prefs.getInt(SharedPreferencesKeys.currentStreak) ?? 0;
      int maxStreak = prefs.getInt(SharedPreferencesKeys.maxStreak) ?? 0;

      if (prevUsageSeconds <= dailyLimitSeconds) {
        currentStreak += 1;
        if (currentStreak > maxStreak) {
          maxStreak = currentStreak;
        }
      } else {
        currentStreak = 0;
      }

      await prefs.setInt(SharedPreferencesKeys.currentStreak, currentStreak);
      await prefs.setInt(SharedPreferencesKeys.maxStreak, maxStreak);
      await prefs.setString(SharedPreferencesKeys.lastUsageDate, now.toIso8601String());

      // 2) Clear usage for the new day and mark the reset timestamp
      await prefs.setInt(SharedPreferencesKeys.dailyUsage, 0);
      await prefs.setString(SharedPreferencesKeys.lastResetDate, now.toIso8601String());
    }
  }

  /*───────────────────────────────────────────────────────────────────────────*/
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
