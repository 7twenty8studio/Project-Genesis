package com.genesis.app.notifications

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.genesis.app.MainActivity
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import kotlinx.coroutines.launch

/**
 * Rings a reminder (shows its notification, a tap opening its versely://
 * link), then plans the week again. Also puts the week back after the
 * phone restarts, Versely is updated, or the clock or time zone changes,
 * since Android forgets alarms then.
 */
class ReminderReceiver : BroadcastReceiver() {
    @SuppressLint("MissingPermission") // areNotificationsEnabled is checked first.
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_RING) {
            val manager = NotificationManagerCompat.from(context)
            val title = intent.getStringExtra(EXTRA_TITLE)
            if (title != null && manager.areNotificationsEnabled()) {
                val body = intent.getStringExtra(EXTRA_BODY).orEmpty()
                val open = Intent(Intent.ACTION_VIEW, Uri.parse(intent.getStringExtra(EXTRA_LINK) ?: "versely://home"))
                    .setClass(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                val id = intent.dataString.orEmpty()
                val notification = NotificationCompat.Builder(context, intent.getStringExtra(EXTRA_KIND) ?: "verseOfTheDay")
                    .setSmallIcon(R.drawable.ic_notification)
                    .setColor(0xFFB9825A.toInt()) // Copper, from the brand.
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                    .setContentIntent(PendingIntent.getActivity(context, id.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
                    .setAutoCancel(true)
                    .build()
                manager.notify(id, 0, notification)
            }
        }
        val pending = goAsync()
        val app = context.applicationContext as VerselyApplication
        app.scope.launch {
            try {
                ReminderScheduler.refresh(app)
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION_RING = "com.genesis.app.REMINDER"
        const val EXTRA_KIND = "kind"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_LINK = "link"
    }
}
