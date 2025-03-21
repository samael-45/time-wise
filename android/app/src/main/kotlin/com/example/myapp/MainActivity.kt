package com.samael.timewise

import android.app.usage.UsageEvents
import android.app.usage.UsageStats
import android.app.usage.UsageStatsManager
import android.app.AppOpsManager
import android.content.Context
import android.os.Build
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar


class MainActivity : FlutterActivity() {
    private val CHANNEL = "screen_time_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getScreenStats" -> result.success(getScreenUsageStats())
                else -> result.notImplemented()
            }
        }
    }

    private fun getScreenUsageStats(): Map<String, Any> {
        if (!checkUsageStatsPermission()) return mapOf("hasPermission" to false)

        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val midnight = getMidnightTime()

        val usageStats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            midnight,
            System.currentTimeMillis()
        )

        val totalScreenTime = usageStats.sumOf { it.totalTimeInForeground / 1000 }
        val unlocks = countUnlocks(usageStatsManager, midnight)
        val longestSession = getLongestSession(usageStatsManager, midnight)
        val topApps = getTopUsedApps(usageStats)
        val peakUsageTime = getPeakUsageTime(usageStatsManager, midnight)

        return mapOf(
            "hasPermission" to true,
            "screenTime" to totalScreenTime,
            "unlocks" to unlocks,
            "longestSession" to longestSession,
            "topApps" to topApps,
            "peakUsageTime" to peakUsageTime
        )
    }

    private fun getLongestSession(usageStatsManager: UsageStatsManager, startTime: Long): Long {
        val eventStats = usageStatsManager.queryEvents(startTime, System.currentTimeMillis())
        val event = UsageEvents.Event()

        var longestSession = 0L
        var sessionStartTime = 0L
        var isScreenOn = false

        while (eventStats.hasNextEvent()) {
            eventStats.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    sessionStartTime = event.timeStamp
                    isScreenOn = true
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    if (isScreenOn) {
                        val sessionLength = event.timeStamp - sessionStartTime
                        longestSession = maxOf(longestSession, sessionLength)
                        isScreenOn = false
                    }
                }
            }
        }
        return longestSession / 1000 // Convert to seconds
    }

    private fun getTopUsedApps(usageStats: List<UsageStats>): List<Map<String, String>> {
        // Step 1: Sort the apps by total screen time in descending order
        val topUsedApps = usageStats
            .filter { it.totalTimeInForeground > 0 }  // Filter out apps that haven't been used
            .sortedByDescending { it.totalTimeInForeground }  // Sort by screen time in descending order
            .take(3)  // Take the top 3 apps

        // Step 2: Return only the package names
        return topUsedApps.map { app ->
            mapOf("packageName" to app.packageName)  // Return only package name
        }
    }


    private fun getPeakUsageTime(usageStatsManager: UsageStatsManager, startTime: Long): String {
        val eventStats = usageStatsManager.queryEvents(startTime, System.currentTimeMillis())
        val event = UsageEvents.Event()

        val usageByHour = mutableMapOf<Int, Long>()
        var lastTimestamp = 0L
        var lastHour = -1

        while (eventStats.hasNextEvent()) {
            eventStats.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.SCREEN_INTERACTIVE -> {
                    lastTimestamp = event.timeStamp
                    lastHour = getHourFromTimestamp(lastTimestamp)
                }
                UsageEvents.Event.SCREEN_NON_INTERACTIVE -> {
                    val screenTime = event.timeStamp - lastTimestamp
                    if (lastHour >= 0) {
                        usageByHour[lastHour] = (usageByHour[lastHour] ?: 0) + screenTime
                    }
                }
            }
        }

        val peakHour = usageByHour.maxByOrNull { it.value }?.key ?: return "N/A"
        return "$peakHour:00 - ${peakHour + 1}:00"
    }

    private fun countUnlocks(usageStatsManager: UsageStatsManager, startTime: Long): Int {
        val eventStats = usageStatsManager.queryEvents(startTime, System.currentTimeMillis())
        val event = UsageEvents.Event()
        var unlocks = 0
        var lastUnlockTime = 0L

        while (eventStats.hasNextEvent()) {
            eventStats.getNextEvent(event)
            if (event.eventType == UsageEvents.Event.SCREEN_INTERACTIVE) {
                if (event.timeStamp - lastUnlockTime > 3000) { // Prevent duplicate counts
                    unlocks++
                    lastUnlockTime = event.timeStamp
                }
            }
        }
        return unlocks
    }


    private fun checkUsageStatsPermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        } else {
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(),
                packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }


    private fun getMidnightTime(): Long {
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
        }
        return calendar.timeInMillis
    }

    private fun getHourFromTimestamp(timestamp: Long): Int {
        val calendar = Calendar.getInstance()
        calendar.timeInMillis = timestamp
        return calendar.get(Calendar.HOUR_OF_DAY)
    }
}
