package com.kinonn.coffee_timer

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews

object BrewNotifications {
    const val CHANNEL_ID = "brew_timer"
    const val RUNNING_ID = 2402
    const val FINISHED_ID = 2401
    const val ACTION_STOP = "com.kinonn.coffee_timer.action.STOP_TIMER"
    const val ACTION_ADD_15 = "com.kinonn.coffee_timer.action.ADD_15_SECONDS"

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
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

    fun running(context: Context, time: String): Notification {
        ensureChannel(context)
        val builder = builder(context, Notification.PRIORITY_LOW)
            .setSmallIcon(R.drawable.ic_stat_coffee)
            .setContentTitle("Brewing")
            .setContentText(time)
            .setColor(Color.parseColor("#33221A"))
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(activityIntent(context, 13, null))
            .setAutoCancel(false)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) builder.setSound(null)
        return builder.build()
    }

    fun finished(context: Context): Notification {
        ensureChannel(context)
        val contentView = RemoteViews(context.packageName, R.layout.notification_brew)
        contentView.setOnClickPendingIntent(R.id.notification_stop, stopIntent(context))
        contentView.setOnClickPendingIntent(
            R.id.notification_add,
            activityIntent(context, 12, ACTION_ADD_15)
        )
        val nightMode = context.resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK
        contentView.setTextColor(
            R.id.notification_title,
            if (nightMode == Configuration.UI_MODE_NIGHT_YES) {
                Color.parseColor("#FAF3E9")
            } else {
                Color.parseColor("#33221A")
            }
        )

        val builder = builder(context, Notification.PRIORITY_HIGH)
            .setSmallIcon(R.drawable.ic_stat_coffee)
            .setContentTitle("Enjoy!")
            .setColor(Color.parseColor("#33221A"))
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setContentIntent(activityIntent(context, 10, null))
            .setAutoCancel(false)
            .setOngoing(true)
            .setShowWhen(false)
            .addAction(
                R.drawable.ic_stat_stop,
                "Stop",
                stopIntent(context)
            )
            .addAction(
                R.drawable.ic_stat_add,
                "+15 s",
                activityIntent(context, 12, ACTION_ADD_15)
            )
            .setCustomContentView(contentView)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) builder.setSound(null)
        return builder.build()
    }

    fun cancelRunning(context: Context) {
        getManager(context)?.cancel(RUNNING_ID)
    }

    fun cancelFinished(context: Context) {
        getManager(context)?.cancel(FINISHED_ID)
    }

    fun cancelAll(context: Context) {
        getManager(context)?.let {
            it.cancel(RUNNING_ID)
            it.cancel(FINISHED_ID)
        }
    }

    private fun getManager(context: Context): NotificationManager? =
        context.getSystemService(NotificationManager::class.java)

    @Suppress("DEPRECATION")
    private fun builder(context: Context, priority: Int): Notification.Builder {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
        } else {
            Notification.Builder(context).setPriority(priority)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder
    }

    private fun stopIntent(context: Context): PendingIntent {
        val intent = Intent(context, TimerService::class.java).setAction(ACTION_STOP)
        return PendingIntent.getService(
            context,
            11,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun activityIntent(
        context: Context,
        requestCode: Int,
        action: String?,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            if (action != null) this.action = action
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
