package com.kinonn.coffee_timer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

object AlarmScheduler {
    const val ACTION_FIRE = "com.kinonn.coffee_timer.action.ALARM_FIRED"
    private const val TAG = "AlarmScheduler"
    private const val REQUEST_CODE = 42

    fun schedule(context: Context, endAt: Long) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val operation = pendingIntent(context, PendingIntent.FLAG_UPDATE_CURRENT)
            ?: return
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                !manager.canScheduleExactAlarms()
            ) {
                // The foreground service owns the countdown. This inexact alarm
                // is only a backstop if the process dies, so late is acceptable.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endAt, operation)
                } else {
                    manager.set(AlarmManager.RTC_WAKEUP, endAt, operation)
                }
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endAt, operation)
            } else {
                manager.setExact(AlarmManager.RTC_WAKEUP, endAt, operation)
            }
        } catch (error: SecurityException) {
            Log.w(TAG, "Unable to schedule the alarm", error)
        }
    }

    fun cancel(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java) ?: return
        val operation = pendingIntent(context, PendingIntent.FLAG_NO_CREATE) ?: return
        manager.cancel(operation)
        operation.cancel()
    }

    private fun pendingIntent(context: Context, flags: Int): PendingIntent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(context, TimerService::class.java)
                .setAction(TimerService.ACTION_FIRE)
            PendingIntent.getForegroundService(
                context,
                REQUEST_CODE,
                intent,
                flags or PendingIntent.FLAG_IMMUTABLE
            )
        } else {
            val intent = Intent(context, AlarmReceiver::class.java).setAction(ACTION_FIRE)
            PendingIntent.getBroadcast(
                context,
                REQUEST_CODE,
                intent,
                flags or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }
}
