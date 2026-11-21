package com.kinonn.coffee_timer

import android.content.Context
import android.content.SharedPreferences

data class StoredTimer(
    val endAt: Long,
    val totalMs: Long,
    val alarmUri: String?,
    val alarmTitle: String,
    val finished: Boolean,
)

object TimerStore {
    private const val PREFS = "coffee_timer"
    private const val KEY_ACTIVE = "timerActive"
    private const val KEY_FINISHED = "timerFinished"
    private const val KEY_END_AT = "timerEndAt"
    private const val KEY_TOTAL = "timerTotalMs"
    private const val KEY_ALARM_URI = "timerAlarmUri"
    private const val KEY_ALARM_TITLE = "timerAlarmTitle"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveRunning(
        context: Context,
        endAt: Long,
        totalMs: Long,
        alarmUri: String?,
        alarmTitle: String,
    ) {
        prefs(context).edit()
            .putBoolean(KEY_ACTIVE, true)
            .putBoolean(KEY_FINISHED, false)
            .putLong(KEY_END_AT, endAt)
            .putLong(KEY_TOTAL, totalMs)
            .putString(KEY_ALARM_URI, alarmUri)
            .putString(KEY_ALARM_TITLE, alarmTitle)
            .commit()
    }

    fun markFinished(context: Context) {
        prefs(context).edit().putBoolean(KEY_FINISHED, true).commit()
    }

    fun read(context: Context): StoredTimer? {
        val prefs = prefs(context)
        if (!prefs.getBoolean(KEY_ACTIVE, false)) return null
        return StoredTimer(
            endAt = prefs.getLong(KEY_END_AT, 0L),
            totalMs = prefs.getLong(KEY_TOTAL, 0L),
            alarmUri = prefs.getString(KEY_ALARM_URI, null),
            alarmTitle = prefs.getString(KEY_ALARM_TITLE, "Timer Event")
                ?: "Timer Event",
            finished = prefs.getBoolean(KEY_FINISHED, false),
        )
    }

    fun clear(context: Context) {
        prefs(context).edit()
            .remove(KEY_ACTIVE)
            .remove(KEY_FINISHED)
            .remove(KEY_END_AT)
            .remove(KEY_TOTAL)
            .remove(KEY_ALARM_URI)
            .remove(KEY_ALARM_TITLE)
            .commit()
    }
}
