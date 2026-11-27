package com.genesis.app.bibles

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.genesis.app.MainActivity
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.domain.bible.YouVersionBuild
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Keeps a Bible download going after the person leaves Versely, as
 * ContinuedDownloads on iOS: a foreground service with the download's
 * progress ("12 of 66 books") in a quiet notification, and Pause there,
 * which stops it with its books kept. It ends when nothing downloads.
 */
class BibleDownloadService : Service() {
    private val scope = MainScope()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL, getString(R.string.downloads), NotificationManager.IMPORTANCE_LOW))
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val library = (application as VerselyApplication).bibles
        if (intent?.action == ACTION_PAUSE) {
            library.pauseAll()
            return START_NOT_STICKY
        }
        ServiceCompat.startForeground(
            this, NOTIFICATION, notification(null, 0),
            if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0,
        )
        scope.launch {
            combine(library.downloading, library.bookProgress) { downloading, progress -> downloading to progress }.collect { (downloading, progress) ->
                if (downloading.isEmpty()) {
                    ServiceCompat.stopForeground(this@BibleDownloadService, ServiceCompat.STOP_FOREGROUND_REMOVE)
                    stopSelf()
                } else {
                    val id = downloading.first()
                    val name = library.catalog.value.firstOrNull { it.id == id }?.name ?: id
                    getSystemService(NotificationManager::class.java).notify(NOTIFICATION, notification(name, progress[id] ?: 0))
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun notification(name: String?, books: Int): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val pause = PendingIntent.getService(this, 1, Intent(this, BibleDownloadService::class.java).setAction(ACTION_PAUSE), PendingIntent.FLAG_IMMUTABLE)
        val total = YouVersionBuild.BOOK_CODES.size
        return NotificationCompat.Builder(this, CHANNEL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(name?.let { getString(R.string.download_name, it) } ?: getString(R.string.downloading))
            .setContentText(if (books > 0) getString(R.string.downloading_books, books.toLong(), total.toLong()) else getString(R.string.downloading))
            .setProgress(total, books, books == 0)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(open)
            .addAction(0, getString(R.string.pause), pause)
            .build()
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "bible-downloads"
        private const val NOTIFICATION = 7101
        private const val ACTION_PAUSE = "com.genesis.app.bibles.PAUSE"

        fun start(context: Context) {
            runCatching { ContextCompat.startForegroundService(context, Intent(context, BibleDownloadService::class.java)) }
        }
    }
}
