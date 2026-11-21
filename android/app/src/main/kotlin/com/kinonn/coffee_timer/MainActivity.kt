package com.kinonn.coffee_timer

import android.Manifest
import android.app.AlarmManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var previewPlayer: MediaPlayer? = null
    private var methodChannel: MethodChannel? = null
    private var pendingNotificationAction: String? = null

    private val prefs by lazy { getSharedPreferences("coffee_timer", MODE_PRIVATE) }
    private val defaultPresets = listOf(135, 145, 155)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.navigationBarColor = getColor(R.color.launch_background)
        handleNotificationIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "coffee_timer/native"
        )
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "alarms" -> result.success(alarms())
                "playPreview" -> {
                    val args = call.arguments as? Map<*, *>
                    result.success(playPreview(args?.get("uri") as? String))
                }
                "stopPreview" -> {
                    stopPreview()
                    result.success(null)
                }
                "startTimer" -> {
                    val args = call.arguments as? Map<*, *>
                    val endAt = (args?.get("endAt") as? Number)?.toLong() ?: 0L
                    val started = if (endAt > 0L) {
                        TimerService.start(
                            this,
                            endAt = endAt,
                            totalMs = (args?.get("totalMs") as? Number)?.toLong() ?: 0L,
                            alarmUri = args?.get("alarmUri") as? String,
                            alarmTitle = args?.get("alarmTitle") as? String
                                ?: "Timer Event",
                        )
                    } else {
                        false
                    }
                    result.success(started)
                }
                "cancelTimer" -> {
                    TimerService.stop(this)
                    result.success(null)
                }
                "canScheduleExactAlarms" -> result.success(canScheduleExactAlarms())
                "requestExactAlarms" -> {
                    requestExactAlarms()
                    result.success(null)
                }
                "timerState" -> result.success(timerState())
                "requestNotificationPermission" -> {
                    ensureNotificationPermission()
                    result.success(null)
                }
                "takeNotificationAction" -> {
                    val action = pendingNotificationAction
                    pendingNotificationAction = null
                    result.success(action)
                }
                "loadSettings" -> result.success(loadSettings())
                "saveSettings" -> {
                    saveSettings(call.arguments as? Map<*, *>)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleNotificationIntent(intent: Intent?) {
        val action = intent?.action ?: return
        val dartAction = when (action) {
            BrewNotifications.ACTION_STOP -> "stop"
            BrewNotifications.ACTION_ADD_15 -> "add15"
            else -> return
        }
        intent.action = null
        if (dartAction == "stop") {
            TimerService.stop(this)
        }
        pendingNotificationAction = dartAction
        methodChannel?.invokeMethod(
            "notificationAction",
            dartAction,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    pendingNotificationAction = null
                }

                override fun error(
                    errorCode: String,
                    errorMessage: String?,
                    errorDetails: Any?,
                ) {
                    // Dart isn't ready yet; takeNotificationAction will pick it up.
                }

                override fun notImplemented() {
                    // Dart isn't ready yet; takeNotificationAction will pick it up.
                }
            }
        )
    }

    private fun timerState(): Map<String, Any?> {
        val timer = TimerStore.read(this)
        if (timer == null) {
            return mapOf(
                "running" to false,
                "finished" to false,
                "endAt" to 0L,
                "totalMs" to 0L,
                "alarmUri" to null,
                "alarmTitle" to "Timer Event",
            )
        }
        return mapOf(
            "running" to true,
            "finished" to timer.finished,
            "endAt" to timer.endAt,
            "totalMs" to timer.totalMs,
            "alarmUri" to timer.alarmUri,
            "alarmTitle" to timer.alarmTitle,
        )
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 5001)
    }

    private fun canScheduleExactAlarms(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
    }

    private fun requestExactAlarms() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        if (canScheduleExactAlarms()) return
        try {
            startActivity(
                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM)
                    .setData(Uri.parse("package:$packageName"))
            )
        } catch (error: ActivityNotFoundException) {
            Log.w("MainActivity", "Exact alarm settings unavailable", error)
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        .setData(Uri.parse("package:$packageName"))
                )
            } catch (fallback: ActivityNotFoundException) {
                Log.w("MainActivity", "App settings unavailable", fallback)
            }
        }
    }

    private fun alarms(): List<Map<String, String>> {
        val sounds = mutableListOf<Map<String, String>>()
        val manager = RingtoneManager(this)
        manager.setType(RingtoneManager.TYPE_ALARM)
        val cursor = manager.cursor
        while (cursor.moveToNext()) {
            val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX) ?: continue
            val uri = manager.getRingtoneUri(cursor.position)?.toString() ?: continue
            sounds.add(mapOf("title" to title, "uri" to uri))
        }
        return sounds.sortedBy { it["title"]?.lowercase() }
    }

    private fun playPreview(uriString: String?): Boolean {
        stopPreview()
        val newPlayer = AlarmAudio.create(this, uriString, loop = false) ?: return false
        previewPlayer = newPlayer
        return true
    }

    private fun stopPreview() {
        AlarmAudio.release(previewPlayer)
        previewPlayer = null
    }

    private fun loadSettings(): Map<String, Any?> {
        migrateSettings()
        return mapOf(
            "ratio" to prefs.getInt("ratio", 16),
            "alarmUri" to prefs.getString("alarmUri", AlarmAudio.BUNDLED_ALARM_URI),
            "alarmTitle" to prefs.getString("alarmTitle", "Timer Event"),
            "presets" to defaultPresets.mapIndexed { index, fallback ->
                prefs.getInt("preset${index + 1}", fallback)
            },
        )
    }

    private fun migrateSettings() {
        if (prefs.getInt("settingsVersion", 1) >= 2) return
        val savedTitle = prefs.getString("alarmTitle", null)
        val editor = prefs.edit().putInt("settingsVersion", 2)
        if (savedTitle == null || savedTitle == "System default") {
            editor.putString("alarmUri", AlarmAudio.BUNDLED_ALARM_URI)
            editor.putString("alarmTitle", "Timer Event")
        }
        editor.apply()
    }

    private fun saveSettings(arguments: Map<*, *>?) {
        val ratio = (arguments?.get("ratio") as? Number)?.toInt() ?: 16
        val alarmUri = arguments?.get("alarmUri") as? String
        val alarmTitle = arguments?.get("alarmTitle") as? String ?: "Timer Event"
        val presets = (arguments?.get("presets") as? List<*>)
            ?.mapNotNull { (it as? Number)?.toInt()?.coerceIn(5, 1800) }
            ?: emptyList()
        val editor = prefs.edit()
            .putInt("ratio", ratio)
            .putString("alarmUri", alarmUri)
            .putString("alarmTitle", alarmTitle)
            .putInt("settingsVersion", 2)
        defaultPresets.forEachIndexed { index, fallback ->
            editor.putInt("preset${index + 1}", presets.getOrNull(index) ?: fallback)
        }
        editor.apply()
    }

    override fun onDestroy() {
        methodChannel = null
        stopPreview()
        super.onDestroy()
    }
}
