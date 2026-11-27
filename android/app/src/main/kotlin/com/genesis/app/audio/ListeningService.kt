package com.genesis.app.audio

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.genesis.app.MainActivity
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.domain.link.GenesisLink
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * Keeps what's playing going with the screen off, and shows one player for
 * it in the notification and on the lock screen: the chapter read aloud
 * with the ambient sounds' buttons beside it, or the ambient sounds alone
 * (the listening Live Activity on iOS). Tapping it opens the reader.
 */
@androidx.annotation.OptIn(UnstableApi::class)
class ListeningService : MediaSessionService() {
    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        val app = application as VerselyApplication
        val player = app.listening.player
        player.labels = ListeningPlayer.Labels(
            ambientTitle = getString(R.string.ambient_title),
            pause = getString(R.string.pause_ambient_sounds),
            play = getString(R.string.play_ambient_sounds),
            stop = getString(R.string.ambient_stop),
            summary = { it.summary(this) },
        )
        // Made now, so its sounds join this player even before the reader opens.
        app.ambient
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(Intent.ACTION_VIEW, Uri.parse(GenesisLink.CONTINUE_READING), this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val built = MediaSession.Builder(this, player)
            .setSessionActivity(open)
            .setCallback(object : MediaSession.Callback {
                override fun onConnect(session: MediaSession, controller: MediaSession.ControllerInfo): MediaSession.ConnectionResult {
                    val commands = MediaSession.ConnectionResult.DEFAULT_SESSION_COMMANDS.buildUpon()
                        .add(SessionCommand(ListeningPlayer.COMMAND_AMBIENT_TOGGLE, Bundle.EMPTY))
                        .add(SessionCommand(ListeningPlayer.COMMAND_AMBIENT_STOP, Bundle.EMPTY))
                        .build()
                    return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
                        .setAvailableSessionCommands(commands)
                        .setMediaButtonPreferences(player.ambientButtons())
                        .build()
                }

                override fun onCustomCommand(session: MediaSession, controller: MediaSession.ControllerInfo, customCommand: SessionCommand, args: Bundle): ListenableFuture<SessionResult> =
                    Futures.immediateFuture(
                        SessionResult(if (player.handleAmbientCommand(customCommand.customAction)) SessionResult.RESULT_SUCCESS else SessionError.ERROR_NOT_SUPPORTED),
                    )
            })
            .build()
        session = built
        player.onButtonsChanged = { buttons -> built.setMediaButtonPreferences(buttons) }
        player.refresh()
        setMediaNotificationProvider(DefaultMediaNotificationProvider.Builder(this).build().apply { setSmallIcon(R.drawable.ic_notification) })
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        // Swiped away while paused: nothing left to control.
        if (session?.player?.playWhenReady != true) stopSelf()
    }

    override fun onDestroy() {
        (application as VerselyApplication).listening.player.onButtonsChanged = null
        session?.release()
        session = null
        super.onDestroy()
    }
}

private typealias SessionError = androidx.media3.session.SessionError
