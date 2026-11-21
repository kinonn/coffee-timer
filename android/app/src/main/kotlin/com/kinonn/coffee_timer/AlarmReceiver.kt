package com.kinonn.coffee_timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != AlarmScheduler.ACTION_FIRE) return
        val timer = TimerStore.read(context) ?: return
        if (timer.finished || timer.endAt <= 0L) return
        TimerService.fire(context)
    }
}
