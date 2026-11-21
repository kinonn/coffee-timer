package com.kinonn.coffee_timer

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.util.Log

object AlarmAudio {
    const val BUNDLED_ALARM_URI = "app:timer_event"
    private const val TAG = "AlarmAudio"

    fun create(context: Context, uriString: String?, loop: Boolean): MediaPlayer? {
        val mediaPlayer = MediaPlayer()
        return try {
            mediaPlayer.setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            )
            if (uriString == BUNDLED_ALARM_URI) {
                val afd = context.resources.openRawResourceFd(R.raw.timer_event)
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
                mediaPlayer.setDataSource(context, uri)
            }
            mediaPlayer.isLooping = loop
            mediaPlayer.prepare()
            mediaPlayer.start()
            mediaPlayer
        } catch (error: Exception) {
            Log.w(TAG, "Unable to play the selected alarm", error)
            mediaPlayer.release()
            null
        }
    }

    fun release(mediaPlayer: MediaPlayer?) {
        mediaPlayer ?: return
        try {
            if (mediaPlayer.isPlaying) mediaPlayer.stop()
        } catch (_: Exception) {
            // Already stopped.
        }
        mediaPlayer.release()
    }
}
