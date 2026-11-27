package com.genesis.app.audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.genesis.app.MainActivity
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Keeps ambient sounds playing with the screen off: a foreground service
 * while they play, with the mix and Pause/Play and Stop in a quiet
 * notification. Paused, the notification stays (dismissible) until closed.
 */
class AmbientService : Service() {
    private val scope = MainScope()
    private var started = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.ambient_title), NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val ambient = (application as VerselyApplication).ambient
        when (intent?.action) {
            ACTION_TOGGLE -> ambient.togglePlayback()
            ACTION_CLOSE -> ambient.close()
        }
        val state = ambient.state.value
        if (state.isPlaying) {
            ServiceCompat.startForeground(this, NOTIFICATION, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        }
        if (!started) {
            started = true
            scope.launch {
                ambient.state.collect { now ->
                    val manager = getSystemService(NotificationManager::class.java)
                    when {
                        !now.showsControls || now.mix.isEmpty() -> {
                            ServiceCompat.stopForeground(this@AmbientService, ServiceCompat.STOP_FOREGROUND_REMOVE)
                            manager.cancel(NOTIFICATION)
                            stopSelf()
                        }
                        now.isPlaying -> ServiceCompat.startForeground(this@AmbientService, NOTIFICATION, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
                        else -> {
                            ServiceCompat.stopForeground(this@AmbientService, ServiceCompat.STOP_FOREGROUND_DETACH)
                            manager.notify(NOTIFICATION, notification())
                        }
                    }
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val state = (application as VerselyApplication).ambient.state.value
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val toggle = PendingIntent.getService(this, 1, Intent(this, AmbientService::class.java).setAction(ACTION_TOGGLE), PendingIntent.FLAG_IMMUTABLE)
        val close = PendingIntent.getService(this, 2, Intent(this, AmbientService::class.java).setAction(ACTION_CLOSE), PendingIntent.FLAG_IMMUTABLE)
        val title = state.currentMix?.let { getString(it.title) } ?: state.summary(this)
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(getString(if (state.isPlaying) R.string.ambient_playing else R.string.ambient_paused))
            .setOngoing(state.isPlaying)
            .setSilent(true)
            .setContentIntent(open)
            .setDeleteIntent(close)
            .addAction(0, getString(if (state.isPlaying) R.string.pause else R.string.play), toggle)
            .addAction(0, getString(R.string.stop), close)
            .build()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "ambient"
        private const val NOTIFICATION = 7_003
        private const val ACTION_TOGGLE = "com.genesis.app.ambient.TOGGLE"
        private const val ACTION_CLOSE = "com.genesis.app.ambient.CLOSE"
    }
}
