package com.kinonn.coffee_timer

import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaPlayer
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log

class TimerService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var endAt = 0L
    private var totalMs = 0L
    private var alarmUri: String? = null
    private var finished = false

    private val tick = object : Runnable {
        override fun run() {
            if (endAt <= 0L) return
            val left = endAt - System.currentTimeMillis()
            if (left <= 0L) {
                fire()
                return
            }
            updateRunning(left)
            handler.postDelayed(this, 1000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        BrewNotifications.ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val end = intent.getLongExtra(EXTRA_END_AT, 0L)
                if (end <= 0L) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startTimer(
                    end = end,
                    total = intent.getLongExtra(EXTRA_TOTAL_MS, 0L),
                    uri = intent.getStringExtra(EXTRA_ALARM_URI),
                    title = intent.getStringExtra(EXTRA_ALARM_TITLE) ?: "Timer Event",
                )
            }

            ACTION_FIRE -> {
                if (!restore()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                resumeOrFire()
            }

            BrewNotifications.ACTION_STOP -> {
                stopTimer()
                return START_NOT_STICKY
            }

            else -> {
                if (!restore()) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                resumeOrFire()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        stopPlayback()
        releaseWakeLock()
        stopForegroundCompat()
        super.onDestroy()
    }

    private fun startTimer(end: Long, total: Long, uri: String?, title: String) {
        stopPlayback()
        releaseWakeLock()
        endAt = end
        totalMs = total
        alarmUri = uri
        finished = false
        TimerStore.saveRunning(this, end, total, uri, title)
        AlarmScheduler.schedule(this, end)
        acquireWakeLock(total)
        BrewNotifications.cancelFinished(this)
        showRunning()
        handler.removeCallbacks(tick)
        handler.post(tick)
    }

    private fun restore(): Boolean {
        val timer = TimerStore.read(this) ?: return false
        if (timer.endAt <= 0L) return false
        endAt = timer.endAt
        totalMs = timer.totalMs
        alarmUri = timer.alarmUri
        finished = timer.finished
        acquireWakeLock(timer.totalMs)
        return true
    }

    private fun resumeOrFire() {
        if (finished || endAt <= System.currentTimeMillis()) {
            fire()
        } else {
            showRunning()
            handler.removeCallbacks(tick)
            handler.post(tick)
            AlarmScheduler.schedule(this, endAt)
        }
    }

    private fun showRunning() {
        val left = endAt - System.currentTimeMillis()
        foreground(
            BrewNotifications.RUNNING_ID,
            BrewNotifications.running(this, formatTime(left))
        )
    }

    private fun updateRunning(left: Long) {
        getSystemService(NotificationManager::class.java)?.notify(
            BrewNotifications.RUNNING_ID,
            BrewNotifications.running(this, formatTime(left))
        )
    }

    private fun fire() {
        if (endAt <= 0L) return
        if (finished && player != null) return
        handler.removeCallbacks(tick)
        if (!finished) {
            finished = true
            TimerStore.markFinished(this)
        }
        AlarmScheduler.cancel(this)
        foreground(BrewNotifications.FINISHED_ID, BrewNotifications.finished(this))
        BrewNotifications.cancelRunning(this)
        if (player == null) {
            player = AlarmAudio.create(this, alarmUri, loop = true)
        }
        acquireWakeLock(totalMs)
    }

    private fun stopTimer() {
        handler.removeCallbacks(tick)
        AlarmScheduler.cancel(this)
        TimerStore.clear(this)
        stopPlayback()
        releaseWakeLock()
        BrewNotifications.cancelAll(this)
        stopSelf()
    }

    private fun stopPlayback() {
        AlarmAudio.release(player)
        player = null
    }

    private fun foreground(id: Int, notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                id,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            )
        } else {
            startForeground(id, notification)
        }
    }

    @Suppress("DEPRECATION")
    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            stopForeground(true)
        }
    }

    private fun acquireWakeLock(timeoutMs: Long) {
        if (wakeLock?.isHeld == true) return
        val manager = getSystemService(PowerManager::class.java) ?: return
        wakeLock = manager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "coffee_timer:timer"
        ).apply {
            setReferenceCounted(false)
            acquire(timeoutMs.coerceAtLeast(MIN_WAKE_LOCK_MS) + WAKE_LOCK_GRACE_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun formatTime(ms: Long): String {
        val seconds = if (ms < 0) (-ms + 999) / 1000 else (ms + 999) / 1000
        val prefix = if (ms < 0) "-" else ""
        return "$prefix%02d:%02d".format(seconds / 60, seconds % 60)
    }

    companion object {
        const val ACTION_START = "com.kinonn.coffee_timer.action.START_TIMER"
        const val ACTION_FIRE = "com.kinonn.coffee_timer.action.FIRE_TIMER"
        const val EXTRA_END_AT = "endAt"
        const val EXTRA_TOTAL_MS = "totalMs"
        const val EXTRA_ALARM_URI = "alarmUri"
        const val EXTRA_ALARM_TITLE = "alarmTitle"
        private const val TAG = "TimerService"
        private const val MIN_WAKE_LOCK_MS = 60_000L
        private const val WAKE_LOCK_GRACE_MS = 60 * 60_000L

        fun start(
            context: Context,
            endAt: Long,
            totalMs: Long,
            alarmUri: String?,
            alarmTitle: String,
        ): Boolean {
            val intent = Intent(context, TimerService::class.java)
                .setAction(ACTION_START)
                .putExtra(EXTRA_END_AT, endAt)
                .putExtra(EXTRA_TOTAL_MS, totalMs)
                .putExtra(EXTRA_ALARM_URI, alarmUri)
                .putExtra(EXTRA_ALARM_TITLE, alarmTitle)
            return startCompat(context, intent)
        }

        fun fire(context: Context) {
            startCompat(
                context,
                Intent(context, TimerService::class.java).setAction(ACTION_FIRE)
            )
        }

        fun stop(context: Context) {
            AlarmScheduler.cancel(context)
            TimerStore.clear(context)
            BrewNotifications.cancelAll(context)
            context.stopService(Intent(context, TimerService::class.java))
        }

        private fun startCompat(context: Context, intent: Intent): Boolean {
            return try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                true
            } catch (error: Exception) {
                Log.w(TAG, "Unable to start the timer service", error)
                false
            }
        }
    }
}
