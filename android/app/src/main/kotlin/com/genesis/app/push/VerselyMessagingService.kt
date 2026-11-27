package com.genesis.app.push

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.genesis.app.MainActivity
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.launch

/**
 * Firebase Cloud Messaging: a new token is saved for the account, and a
 * message that arrives while Versely is open is shown like any other
 * (Android shows the rest itself, from group-notify's notification, in the
 * app's "groups" or "nudges" channel; a tap opens its versely:// link).
 */
class VerselyMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        val app = application as VerselyApplication
        app.scope.launch { AndroidPush.sync(app, newToken = token) }
    }

    @SuppressLint("MissingPermission") // areNotificationsEnabled is checked first.
    override fun onMessageReceived(message: RemoteMessage) {
        val shown = message.notification ?: return
        val manager = NotificationManagerCompat.from(this)
        if (!manager.areNotificationsEnabled()) return
        val body = shown.body ?: shown.bodyLocalizationKey?.let { key ->
            val id = resources.getIdentifier(key, "string", packageName)
            if (id == 0) null else getString(id, *(shown.bodyLocalizationArgs ?: emptyArray()))
        }.orEmpty()
        val link = message.data["link"] ?: "versely://home"
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(link))
            .setClass(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val tag = shown.tag ?: link
        val notification = NotificationCompat.Builder(this, shown.channelId ?: "groups")
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFFB9825A.toInt()) // Copper, from the brand.
            .setContentTitle(shown.title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(PendingIntent.getActivity(this, tag.hashCode(), open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            .setAutoCancel(true)
            .build()
        manager.notify(tag, 0, notification)
    }
}
