package com.cassimtv.jarvis_ai

import android.Manifest
import android.app.ActivityManager
import android.media.AudioManager
import android.content.pm.PackageManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterActivity() {
    private val channelName = "jarvis/device"

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 4101)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceInfo" -> result.success(getDeviceInfo())
                    "lowerVolume" -> {
                        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                        val stream = AudioManager.STREAM_MUSIC
                        val current = audio.getStreamVolume(stream)
                        val target = (current - 2).coerceAtLeast(0)
                        audio.setStreamVolume(stream, target, 0)
                        result.success(mapOf("before" to current, "after" to target, "max" to audio.getStreamMaxVolume(stream)))
                    }
                    "getCpuUsage" -> result.success(getCpuUsage())
                    "openApp" -> {
                        val requested = call.argument<String>("app")?.trim().orEmpty()
                        try {
                            val match = packageManager.getInstalledApplications(PackageManager.GET_META_DATA)
                                .mapNotNull { info ->
                                    val label = packageManager.getApplicationLabel(info).toString()
                                    if (label.equals(requested, ignoreCase = true) ||
                                        info.packageName.equals(requested, ignoreCase = true) ||
                                        label.contains(requested, ignoreCase = true)) Pair(label, info.packageName) else null
                                }
                                .sortedBy { if (it.first.equals(requested, ignoreCase = true) || it.second.equals(requested, ignoreCase = true)) 0 else 1 }
                                .firstOrNull()
                            if (match == null) {
                                result.error("APP_NOT_FOUND", "No installed app matched '$requested'.", null)
                            } else {
                                val launch = packageManager.getLaunchIntentForPackage(match.second)
                                if (launch == null) result.error("APP_NOT_LAUNCHABLE", "${match.first} has no launch activity.", null)
                                else {
                                    launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(launch)
                                    result.success(match.first)
                                }
                            }
                        } catch (error: Exception) {
                            result.error("APP_LAUNCH_FAILED", error.message, null)
                        }
                    }
                    "openSettings" -> {
                        val section = call.argument<String>("section") ?: "general"
                        try {
                            val action = when (section.lowercase(Locale.ROOT)) {
                                "wifi", "wi-fi", "network" -> Settings.ACTION_WIFI_SETTINGS
                                "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                                "display", "screen" -> Settings.ACTION_DISPLAY_SETTINGS
                                "sound", "audio" -> Settings.ACTION_SOUND_SETTINGS
                                "battery" -> "android.intent.action.POWER_USAGE_SUMMARY"
                                "apps", "applications" -> Settings.ACTION_APPLICATION_SETTINGS
                                else -> Settings.ACTION_SETTINGS
                            }
                            startActivity(Intent(action))
                            result.success(true)
                        } catch (error: Exception) {
                            result.error("SETTINGS_FAILED", error.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun getCpuUsage(): Map<String, Any?> {
        fun readCpu(): LongArray {
            val fields = java.io.File("/proc/stat").readLines().first().trim().split(Regex("\\s+"))
            val values = fields.drop(1).take(8).map { it.toLongOrNull() ?: 0L }
            return longArrayOf(values.sum(), values[3] + values[4])
        }
        val first = readCpu()
        Thread.sleep(250)
        val second = readCpu()
        val total = second[0] - first[0]
        val idle = second[1] - first[1]
        val usage = if (total > 0) ((total - idle).toDouble() / total * 100).coerceIn(0.0, 100.0) else -1.0
        return mapOf("cpuPercent" to usage)
    }

    private fun getDeviceInfo(): Map<String, Any?> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memory = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memory)

        val stat = StatFs(Environment.getDataDirectory().absolutePath)
        val totalStorage = stat.totalBytes
        val freeStorage = stat.availableBytes

        val batteryIntent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val batteryLevel = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val batteryScale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val batteryPercent = if (batteryLevel >= 0 && batteryScale > 0) {
            (batteryLevel * 100f / batteryScale).toInt()
        } else -1
        val batteryStatus = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = batteryStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
            batteryStatus == BatteryManager.BATTERY_STATUS_FULL

        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val activeNetwork = connectivity.activeNetwork
        val capabilities = activeNetwork?.let { connectivity.getNetworkCapabilities(it) }
        val network = when {
            capabilities == null -> "Offline"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile data"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> "Connected"
        }

        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "androidVersion" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "totalRamMb" to (memory.totalMem / (1024 * 1024)),
            "availableRamMb" to (memory.availMem / (1024 * 1024)),
            "lowMemory" to memory.lowMemory,
            "storageTotalGb" to String.format(Locale.US, "%.1f", totalStorage / 1_073_741_824.0),
            "storageFreeGb" to String.format(Locale.US, "%.1f", freeStorage / 1_073_741_824.0),
            "batteryPercent" to batteryPercent,
            "charging" to charging,
            "network" to network
        )
    }
}
