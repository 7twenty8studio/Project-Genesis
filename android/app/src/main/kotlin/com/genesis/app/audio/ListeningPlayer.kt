package com.genesis.app.audio

import android.os.Bundle
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.SessionCommand
import com.genesis.core.domain.bible.ChapterId
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * What's playing, as one Media3 player, so the notification, lock screen,
 * headphones and car show one player for both, as the listening Live
 * Activity does on iOS (one activity, a row for each).
 *
 * While a chapter is read aloud it's the playlist (the chapter before, this
 * one and the next, so Next and Previous are always offered); ambient
 * sounds join it as their own buttons (Pause/Play ambient sounds, Stop
 * ambient sounds) and in the subtitle. With only ambient sounds, the mix is
 * the item and Play/Pause and Stop control it.
 */
@androidx.annotation.OptIn(UnstableApi::class)
class ListeningPlayer(private val listening: Listening) : SimpleBasePlayer(Looper.getMainLooper()) {
    /** Set by AmbientSounds when it's made, so its row joins this player. */
    var ambient: AmbientSounds? = null
        set(value) {
            field = value
            refresh()
        }

    /** Tells the session the ambient buttons changed (set by ListeningService). */
    var onButtonsChanged: ((List<CommandButton>) -> Unit)? = null
    private var lastButtons: List<String> = emptyList()

    /** Names for the notification, in the app's language (set by ListeningService). */
    var labels: Labels? = null

    data class Labels(val ambientTitle: String, val pause: String, val play: String, val stop: String, val summary: (AmbientState) -> String)

    fun refresh() {
        invalidateState()
        publishButtons()
    }

    private val ambientShown: AmbientState?
        get() = ambient?.state?.value?.takeIf { it.showsControls && it.mix.isNotEmpty() }

    override fun getState(): State {
        val current = listening.state.value
        val sounds = ambientShown
        val chapter = current.chapter
        if (chapter != null && current.isActive) {
            val commands = Player.Commands.Builder()
                .addAll(
                    COMMAND_PLAY_PAUSE,
                    COMMAND_STOP,
                    COMMAND_GET_CURRENT_MEDIA_ITEM,
                    COMMAND_GET_METADATA,
                    COMMAND_GET_TIMELINE,
                    COMMAND_SEEK_TO_NEXT,
                    COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
                    COMMAND_SEEK_TO_PREVIOUS,
                    COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
                    COMMAND_SEEK_TO_MEDIA_ITEM,
                )
                .build()
            // "KJV · Rain, Fireplace" while both play, as the accessory's subtitle on iOS.
            val subtitle = listOfNotNull(current.abbreviation.ifEmpty { null }, sounds?.takeIf { it.isPlaying }?.let { labels?.summary?.invoke(it) }).joinToString(" · ")
            val items = listOfNotNull(chapter.previous, chapter, chapter.next).map { chapterItem(it, current, it == chapter, subtitle) }
            return State.Builder()
                .setAvailableCommands(commands)
                .setPlaylist(items)
                .setCurrentMediaItemIndex(if (chapter.previous != null) 1 else 0)
                // Playing while either plays, so the session keeps the sounds going with the screen off.
                .setPlayWhenReady(current.isPlaying || sounds?.isPlaying == true, PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
                .setPlaybackState(if (current.status == ListeningStatus.LOADING) STATE_BUFFERING else STATE_READY)
                .build()
        }
        if (sounds != null) {
            val commands = Player.Commands.Builder()
                .addAll(COMMAND_PLAY_PAUSE, COMMAND_STOP, COMMAND_GET_CURRENT_MEDIA_ITEM, COMMAND_GET_METADATA, COMMAND_GET_TIMELINE)
                .build()
            val metadata = MediaMetadata.Builder()
                .setTitle(labels?.summary?.invoke(sounds).orEmpty())
                .setArtist(labels?.ambientTitle.orEmpty())
                .build()
            val item = MediaItemData.Builder(AMBIENT_ITEM)
                .setMediaItem(MediaItem.Builder().setMediaId(AMBIENT_ITEM).setMediaMetadata(metadata).build())
                .setMediaMetadata(metadata)
                .build()
            return State.Builder()
                .setAvailableCommands(commands)
                .setPlaylist(listOf(item))
                .setCurrentMediaItemIndex(0)
                .setPlayWhenReady(sounds.isPlaying, PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
                .setPlaybackState(STATE_READY)
                .build()
        }
        return State.Builder()
            .setAvailableCommands(Player.Commands.Builder().addAll(COMMAND_PLAY_PAUSE, COMMAND_STOP).build())
            .setPlaybackState(STATE_IDLE)
            .build()
    }

    private fun chapterItem(chapter: ChapterId, current: ListeningState, isCurrent: Boolean, subtitle: String): MediaItemData {
        val metadata = MediaMetadata.Builder()
            .setTitle(if (isCurrent) current.title else chapter.description(current.language))
            .setArtist(subtitle)
            .build()
        return MediaItemData.Builder("${chapter.book * 1_000 + chapter.chapter}")
            .setMediaItem(MediaItem.Builder().setMediaId("${chapter.book * 1_000 + chapter.chapter}").setMediaMetadata(metadata).build())
            .setMediaMetadata(metadata)
            .build()
    }

    /** The ambient row's buttons, only while a chapter is read too (otherwise Play/Pause and Stop are the sounds'). */
    fun ambientButtons(): List<CommandButton> {
        val sounds = ambientShown ?: return emptyList()
        if (!listening.state.value.isActive) return emptyList()
        val words = labels ?: return emptyList()
        return listOf(
            CommandButton.Builder(if (sounds.isPlaying) CommandButton.ICON_PAUSE else CommandButton.ICON_PLAY)
                .setDisplayName(if (sounds.isPlaying) words.pause else words.play)
                .setSessionCommand(SessionCommand(COMMAND_AMBIENT_TOGGLE, Bundle.EMPTY))
                .setSlots(CommandButton.SLOT_OVERFLOW)
                .build(),
            CommandButton.Builder(CommandButton.ICON_STOP)
                .setDisplayName(words.stop)
                .setSessionCommand(SessionCommand(COMMAND_AMBIENT_STOP, Bundle.EMPTY))
                .setSlots(CommandButton.SLOT_OVERFLOW)
                .build(),
        )
    }

    private fun publishButtons() {
        val buttons = ambientButtons()
        val key = buttons.map { "${it.sessionCommand?.customAction}:${it.displayName}" }
        if (key == lastButtons) return
        lastButtons = key
        onButtonsChanged?.invoke(buttons)
    }

    /** Pausing pauses everything; Play picks the chapter up again (and the sounds, if they were out). */
    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        val sounds = ambientShown
        if (listening.state.value.isActive) {
            if (playWhenReady) {
                listening.resume()
                if (sounds != null && !sounds.isPlaying) ambient?.play()
            } else {
                listening.pause()
                ambient?.pause()
            }
        } else if (sounds != null) {
            if (playWhenReady) ambient?.play() else ambient?.pause()
        }
        return Futures.immediateVoidFuture()
    }

    override fun handleStop(): ListenableFuture<*> {
        if (listening.state.value.isActive) listening.stop() else ambient?.close()
        return Futures.immediateVoidFuture()
    }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        val chapter = listening.state.value.chapter ?: return Futures.immediateVoidFuture()
        val currentIndex = if (chapter.previous != null) 1 else 0
        when {
            mediaItemIndex > currentIndex -> listening.nextChapter()
            mediaItemIndex < currentIndex -> listening.previousChapter()
            // Previous at the start of the first item: back to the start (or the chapter before).
            else -> listening.previousChapter()
        }
        return Futures.immediateVoidFuture()
    }

    /** A button from the ambient row in the notification. */
    fun handleAmbientCommand(action: String): Boolean {
        when (action) {
            COMMAND_AMBIENT_TOGGLE -> ambient?.togglePlayback()
            COMMAND_AMBIENT_STOP -> ambient?.close()
            else -> return false
        }
        return true
    }

    companion object {
        const val COMMAND_AMBIENT_TOGGLE = "com.genesis.app.ambient.TOGGLE"
        const val COMMAND_AMBIENT_STOP = "com.genesis.app.ambient.STOP"
        private const val AMBIENT_ITEM = "ambient"
    }
}
