package com.cassimtv.jarvis_ai

import android.app.ActivityManager
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceInfo" -> result.success(getDeviceInfo())
                    "openSettings" -> {
                        val section = call.argument<String>("section") ?: "general"
                        try {
                            val action = when (section.lowercase(Locale.ROOT)) {
                                "wifi", "wi-fi", "network" -> Settings.ACTION_WIFI_SETTINGS
                                "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                                "display", "screen" -> Settings.ACTION_DISPLAY_SETTINGS
                                "sound", "audio" -> Settings.ACTION_SOUND_SETTINGS
                                "battery" -> Settings.ACTION_BATTERY_SAVER_SETTINGS
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
