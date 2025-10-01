
import 'dart:async';
import 'package:flutter/material.dart';
import 'app_blocker.dart';

class FocusMode {
  final ValueNotifier<Duration> timeLeft = ValueNotifier(Duration.zero);
  final ValueNotifier<bool> isRunning = ValueNotifier(false);
  final AppBlocker _appBlocker = AppBlocker();
  List<String> _appsToBlock = [];
  Timer? _timer;

  void start(Duration duration, {required List<String> appsToBlock}) {
    if (isRunning.value) return;
    
    _appsToBlock = appsToBlock;
    for (var appPackageName in _appsToBlock) {
      _appBlocker.forceBlockApp(appPackageName);
    }

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

  void stop() {
    _timer?.cancel();
    isRunning.value = false;
    timeLeft.value = Duration.zero;
    for (var appPackageName in _appsToBlock) {
      _appBlocker.forceUnblockApp(appPackageName);
    }
  }

  void dispose() {
    _timer?.cancel();
    for (var appPackageName in _appsToBlock) {
      _appBlocker.forceUnblockApp(appPackageName);
    }
  }
}
