
import 'dart:async';
import 'package:flutter/material.dart';
import 'app_blocker.dart';

/// Manages a focus mode session, including a countdown timer and application blocking.
///
/// This class allows starting a timed focus session during which specified applications
/// can be blocked to minimize distractions. It provides [ValueNotifier]s to observe
/// the remaining time and the running status of the session.
class FocusMode {
  /// A [ValueNotifier] that holds the remaining time for the current focus session.
  /// It updates every second.
  final ValueNotifier<Duration> timeLeft = ValueNotifier(Duration.zero);

  /// A [ValueNotifier] that indicates whether the focus session is currently running.
  final ValueNotifier<bool> isRunning = ValueNotifier(false);

  /// A [ValueNotifier] that indicates whether the current session is a work session.
  final ValueNotifier<bool> isWorking = ValueNotifier(true);

  /// A [ValueNotifier] that holds the number of completed Pomodoro cycles.
  final ValueNotifier<int> completedCycles = ValueNotifier(0);

  /// An instance of [AppBlocker] used to manage blocking and unblocking applications.
  final AppBlocker _appBlocker = AppBlocker();

  /// A list of application package names that are to be blocked during the focus session.
  List<String> _appsToBlock = [];

  /// The timer instance that decrements the [timeLeft] and manages the session duration.
  Timer? _timer;

  /// The duration of a work session.
  Duration workDuration = const Duration(minutes: 25);

  /// The duration of a rest session.
  Duration restDuration = const Duration(minutes: 5);

  /// A callback function that is called when the Pomodoro session is completed.
  VoidCallback? onPomodoroCompleted;

  /// Starts a new focus mode session.
  ///
  /// [duration] The total duration for the focus session.
  /// [appsToBlock] A list of package names of applications to be blocked during the session.
  /// [isPomodoro] Whether the session is a Pomodoro session with work/rest cycles.
  void start(Duration duration, {required List<String> appsToBlock, bool isPomodoro = false}) {
    if (isRunning.value) return;

    _appsToBlock = appsToBlock;
    for (var appPackageName in _appsToBlock) {
      _appBlocker.forceBlockApp(appPackageName);
    }

    if (isPomodoro) {
      isWorking.value = true;
      completedCycles.value = 0;
      _startSession();
    } else {
      timeLeft.value = duration;
      isRunning.value = true;

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (timeLeft.value.inSeconds <= 0) {
          timer.cancel();
          isRunning.value = false;
          for (var appPackageName in _appsToBlock) {
            _appBlocker.forceUnblockApp(appPackageName);
          }
        } else {
          timeLeft.value = timeLeft.value - const Duration(seconds: 1);
        }
      });
    }
  }

  void _startSession() {
    final sessionDuration = isWorking.value ? workDuration : restDuration;
    timeLeft.value = sessionDuration;
    isRunning.value = true;

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (timeLeft.value.inSeconds == 0) {
        timer.cancel();
        _switchSession();
        return;
      }
      timeLeft.value = timeLeft.value - const Duration(seconds: 1);
    });
  }

  void _switchSession() {
    isWorking.value = !isWorking.value;
    if (isWorking.value) {
      completedCycles.value++;
    }

    if (completedCycles.value >= 4 && isWorking.value) {
      stop();
      if (onPomodoroCompleted != null) {
        onPomodoroCompleted!();
      }
      return;
    }

    _startSession();
  }

  /// Stops the current focus mode session immediately.
  ///
  /// Cancels the timer, sets [isRunning] to `false`, resets [timeLeft] to zero,
  /// and unblocks all applications that were blocked during the session.
  void stop() {
    _timer?.cancel();
    isRunning.value = false;
    timeLeft.value = Duration.zero;
    isWorking.value = true;
    completedCycles.value = 0;
    for (var appPackageName in _appsToBlock) {
      _appBlocker.forceUnblockApp(appPackageName);
    }
  }

  /// Disposes of the [FocusMode] instance, canceling any active timer
  /// and ensuring all blocked applications are unblocked.
  void dispose() {
    _timer?.cancel();
    for (var appPackageName in _appsToBlock) {
      _appBlocker.forceUnblockApp(appPackageName);
    }
  }
}
