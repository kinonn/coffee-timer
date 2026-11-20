package com.kinonn.coffee_timer

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.widget.RemoteViews
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var player: MediaPlayer? = null
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
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "coffee_timer/native")
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "alarms" -> result.success(alarms())
                "playAlarm" -> {
                    val args = call.arguments as? Map<*, *>
                    val uri = args?.get("uri") as? String
                    val loop = args?.get("loop") as? Boolean ?: false
                    result.success(playAlarm(uri, loop))
                }
                "playPreview" -> {
                    val args = call.arguments as? Map<*, *>
                    result.success(playPreview(args?.get("uri") as? String))
                }
                "stopPreview" -> {
                    stopPreview()
                    result.success(null)
                }
                "stopAlarm" -> {
                    stopAlarm()
                    result.success(null)
                }
                "showTimerNotification" -> {
                    showTimerNotification()
                    result.success(null)
                }
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
            ACTION_STOP -> "stop"
            ACTION_ADD_15 -> "add15"
            else -> return
        }
        intent.action = null
        stopAlarm()
        pendingNotificationAction = dartAction
        methodChannel?.invokeMethod("notificationAction", dartAction, object : MethodChannel.Result {
            override fun success(result: Any?) {
                pendingNotificationAction = null
            }

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                // Dart isn't ready yet; takeNotificationAction will pick it up.
            }

            override fun notImplemented() {
                // Dart isn't ready yet; takeNotificationAction will pick it up.
            }
        })
    }

    @Suppress("DEPRECATION")
    private fun showTimerNotification() {
        ensureNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }

        val contentIntent = PendingIntent.getActivity(
            this,
            10,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = PendingIntent.getActivity(
            this,
            11,
            Intent(this, MainActivity::class.java).apply {
                action = ACTION_STOP
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val addIntent = PendingIntent.getActivity(
            this,
            12,
            Intent(this, MainActivity::class.java).apply {
                action = ACTION_ADD_15
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this).setPriority(Notification.PRIORITY_HIGH)
        }

        val contentView = RemoteViews(packageName, R.layout.notification_brew)
        contentView.setOnClickPendingIntent(R.id.notification_stop, stopIntent)
        contentView.setOnClickPendingIntent(R.id.notification_add, addIntent)
        val nightMode = resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        contentView.setTextColor(
            R.id.notification_title,
            if (nightMode == Configuration.UI_MODE_NIGHT_YES) {
                Color.parseColor("#FAF3E9")
            } else {
                Color.parseColor("#33221A")
            }
        )

        builder
            .setSmallIcon(R.drawable.ic_stat_coffee)
            .setContentTitle("Enjoy!")
            .setColor(Color.parseColor("#33221A"))
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setOngoing(false)
            .addAction(R.drawable.ic_stat_stop, "Stop", stopIntent)
            .addAction(R.drawable.ic_stat_add, "+15 s", addIntent)
            .setCustomContentView(contentView)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            builder.setSound(null)
        }

        getSystemService(NotificationManager::class.java)
            ?.notify(NOTIFICATION_ID, builder.build())
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Brew timer",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Alerts when the French press timer finishes"
            setSound(null, null)
            enableVibration(false)
            setShowBadge(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun ensureNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 5001)
    }

    private fun cancelTimerNotification() {
        getSystemService(NotificationManager::class.java)?.cancel(NOTIFICATION_ID)
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

    private fun playAlarm(uriString: String?, loop: Boolean): Boolean {
        stopAlarm()
        stopPreview()
        val newPlayer = createPlayer(uriString, loop) ?: return false
        player = newPlayer
        return true
    }

    private fun playPreview(uriString: String?): Boolean {
        stopPreview()
        val newPlayer = createPlayer(uriString, false) ?: return false
        previewPlayer = newPlayer
        return true
    }

    private fun createPlayer(uriString: String?, loop: Boolean): MediaPlayer? {
        val mediaPlayer = MediaPlayer()
        return try {
            mediaPlayer.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            if (uriString == BUNDLED_ALARM_URI) {
                val afd = resources.openRawResourceFd(R.raw.timer_event)
                if (afd == null) {
                    mediaPlayer.release()
                    return null
                }
                afd.use {
                    mediaPlayer.setDataSource(it.fileDescriptor, it.startOffset, it.length)
                }
            } else {
                val defaultUri: Uri? = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                val uri: Uri? = if (uriString.isNullOrEmpty()) defaultUri else Uri.parse(uriString)
                if (uri == null) {
                    mediaPlayer.release()
                    return null
                }
                mediaPlayer.setDataSource(this, uri)
            }
            mediaPlayer.isLooping = loop
            mediaPlayer.prepare()
            mediaPlayer.start()
            mediaPlayer
        } catch (_: Exception) {
            mediaPlayer.release()
            null
        }
    }

    private fun stopAlarm() {
        releasePlayer(player)
        player = null
        cancelTimerNotification()
    }

    private fun stopPreview() {
        releasePlayer(previewPlayer)
        previewPlayer = null
    }

    private fun releasePlayer(mediaPlayer: MediaPlayer?) {
        mediaPlayer ?: return
        try {
            if (mediaPlayer.isPlaying) mediaPlayer.stop()
        } catch (_: Exception) {
            // Already stopped.
        }
        mediaPlayer.release()
    }

    private fun loadSettings(): Map<String, Any?> {
        migrateSettings()
        return mapOf(
            "ratio" to prefs.getInt("ratio", 16),
            "alarmUri" to prefs.getString("alarmUri", BUNDLED_ALARM_URI),
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
            editor.putString("alarmUri", BUNDLED_ALARM_URI)
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
        stopAlarm()
        stopPreview()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL_ID = "brew_timer"
        const val NOTIFICATION_ID = 2401
        const val ACTION_STOP = "com.kinonn.coffee_timer.action.STOP_TIMER"
        const val ACTION_ADD_15 = "com.kinonn.coffee_timer.action.ADD_15_SECONDS"
        const val BUNDLED_ALARM_URI = "app:timer_event"
    }
}
