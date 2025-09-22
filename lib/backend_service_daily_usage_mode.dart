import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UsageStorageService {
  static const String _dailyLimitKey = 'daily_limit_seconds';
  static const String _lastResetDateKey = 'last_reset_date';
  static const String _currentStreakKey = 'current_streak';
  static const String _maxStreakKey = 'max_streak';

  static const MethodChannel _channel = MethodChannel('aleix/usage');

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

  Future<Duration> getDailyUsage() async {
    await _maybeResetUsage();

    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final stats = await _channel.invokeMethod<List>('getUsageStats', {
        'start': DateTime(now).subtract(const Duration(days: 1)).millisecondsSinceEpoch,
        'end': now,
      });

      int totalSeconds = 0;
      if (stats != null) {
        for (final app in stats) {
          final map = Map<String, dynamic>.from(app);
          totalSeconds += (map['totalTime'] as int) ~/ 1000;
        }
      }
      return Duration(seconds: totalSeconds);
    } catch (e) {
      return Duration.zero;
    }
  }

  Future<int> getCurrentStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_currentStreakKey) ?? 0;
  }

  Future<int> getMaxStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_maxStreakKey) ?? 0;
  }

  /*───────────────────────────────────────────────────────────────────────────
  | Midnight rollover: updates streaks based on daily usage                     |
  ───────────────────────────────────────────────────────────────────────────*/

  Future<void> _maybeResetUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastResetStr = prefs.getString(_lastResetDateKey);

    if (lastResetStr == null) {
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
      return;
    }

    final lastReset = DateTime.tryParse(lastResetStr);
    if (lastReset == null || !_isSameDay(now, lastReset)) {
      final usageDuration = await getDailyUsage();
      final dailyLimit = await getDailyLimit();

      int currentStreak = prefs.getInt(_currentStreakKey) ?? 0;
      int maxStreak = prefs.getInt(_maxStreakKey) ?? 0;

      if (usageDuration <= dailyLimit) {
        currentStreak += 1;
        if (currentStreak > maxStreak) maxStreak = currentStreak;
      } else {
        currentStreak = 0;
      }

      await prefs.setInt(_currentStreakKey, currentStreak);
      await prefs.setInt(_maxStreakKey, maxStreak);
      await prefs.setString(_lastResetDateKey, now.toIso8601String());
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
