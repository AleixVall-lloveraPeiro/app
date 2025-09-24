package com.example.app

import android.app.AppOpsManager
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

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
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                "getUsageStats" -> {
                    val start = (call.argument<Long>("start") ?: 0L)
                    val end = (call.argument<Long>("end") ?: 0L)
                    result.success(getUsageStatsMap(start, end))
                }
                "getUsageStatsForDay" -> {
                    val year = call.argument<Int>("year") ?: Calendar.getInstance().get(Calendar.YEAR)
                    val month = call.argument<Int>("month") ?: Calendar.getInstance().get(Calendar.MONTH) + 1
                    val day = call.argument<Int>("day") ?: Calendar.getInstance().get(Calendar.DAY_OF_MONTH)
                    result.success(getUsageStatsForSpecificDay(year, month, day))
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

    // ✅ ÚNICO MÉTODO NUEVO NECESARIO
    private fun getUsageStatsForSpecificDay(year: Int, month: Int, day: Int): Map<String, Any> {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        
        // Calcular rango exacto del día
        val calendar = Calendar.getInstance().apply {
            set(Calendar.YEAR, year)
            set(Calendar.MONTH, month - 1)
            set(Calendar.DAY_OF_MONTH, day)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        
        val startOfDay = calendar.timeInMillis
        calendar.add(Calendar.DAY_OF_MONTH, 1)
        val endOfDay = calendar.timeInMillis

        println("📅 Consultando día específico: $day/$month/$year")

        // Usar INTERVAL_BEST para obtener datos más granulares
        val stats: List<UsageStats> = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST, 
            startOfDay, 
            endOfDay
        ) ?: emptyList()

        var total: Long = 0L
        val perApp = ArrayList<Map<String, Any>>()
        
        for (s in stats) {
            val t = s.totalTimeInForeground
            if (t > 0) {
                total += t
                perApp.add(mapOf("packageName" to s.packageName, "totalTime" to t))
            }
        }

        println("📊 Total del día: ${total/60000} minutos")
        
        return mapOf("total" to total, "perApp" to perApp)
    }
}