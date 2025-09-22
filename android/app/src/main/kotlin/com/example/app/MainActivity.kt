package com.example.app

import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
  private val CHANNEL = "aleix/usage"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "checkUsagePermission" -> {
          result.success(hasUsageStatsPermission())
        }
        "requestUsagePermission" -> {
          // Obre la pantalla d'accés a l'ús perquè l'usuari l'activi
          startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
          result.success(null)
        }
        "getUsageStats" -> {
          val start = (call.argument<Long>("start") ?: 0L)
          val end = (call.argument<Long>("end") ?: 0L)
          result.success(getUsageStatsMap(start, end))
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun hasUsageStatsPermission(): Boolean {
    val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
    val mode = appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, android.os.Process.myUid(), packageName)
    return mode == AppOpsManager.MODE_ALLOWED
  }

  private fun getUsageStatsMap(start: Long, end: Long): Map<String, Any> {
    val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
    val stats: List<UsageStats> = usageStatsManager.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, start, end)
      ?: emptyList()

    var total: Long = 0L
    val perApp = ArrayList<Map<String, Any>>()
    for (s in stats) {
      val t = s.totalTimeInForeground
      if (t > 0) {
        total += t
        perApp.add(mapOf("packageName" to s.packageName, "totalTime" to t))
      }
    }

    return mapOf("total" to total, "perApp" to perApp)
  }
}
