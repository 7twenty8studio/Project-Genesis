package com.genesis.app.audio

import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.genesis.core.domain.bible.ChapterId
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * Listening as a Media3 player, so the notification, lock screen,
 * headphones and car get Play/Pause, Next and Previous (NowPlayingController
 * on iOS). The playlist is the chapter before, this one and the next, so
 * Next and Previous are always offered; choosing one moves by a chapter.
 */
@androidx.annotation.OptIn(UnstableApi::class)
class ListeningPlayer(private val listening: Listening) : SimpleBasePlayer(Looper.getMainLooper()) {
    fun refresh() = invalidateState()

    override fun getState(): State {
        val current = listening.state.value
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
        val chapter = current.chapter
        if (chapter == null || !current.isActive) {
            return State.Builder().setAvailableCommands(commands).setPlaybackState(STATE_IDLE).build()
        }
        val items = listOfNotNull(chapter.previous, chapter, chapter.next).map { item(it, current, it == chapter) }
        return State.Builder()
            .setAvailableCommands(commands)
            .setPlaylist(items)
            .setCurrentMediaItemIndex(if (chapter.previous != null) 1 else 0)
            .setPlayWhenReady(current.isPlaying, PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)
            .setPlaybackState(if (current.status == ListeningStatus.LOADING) STATE_BUFFERING else STATE_READY)
            .build()
    }

    private fun item(chapter: ChapterId, current: ListeningState, isCurrent: Boolean): MediaItemData {
        val metadata = MediaMetadata.Builder()
            .setTitle(if (isCurrent) current.title else chapter.description(current.language))
            .setArtist(current.abbreviation)
            .build()
        return MediaItemData.Builder("${chapter.book * 1_000 + chapter.chapter}")
            .setMediaItem(MediaItem.Builder().setMediaId("${chapter.book * 1_000 + chapter.chapter}").setMediaMetadata(metadata).build())
            .setMediaMetadata(metadata)
            .build()
    }

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> {
        if (playWhenReady) listening.resume() else listening.pause()
        return Futures.immediateVoidFuture()
    }

    override fun handleStop(): ListenableFuture<*> {
        listening.stop()
        return Futures.immediateVoidFuture()
    }

    override fun handleSeek(mediaItemIndex: Int, positionMs: Long, seekCommand: Int): ListenableFuture<*> {
        val chapter = listening.state.value.chapter
        val currentIndex = if (chapter?.previous != null) 1 else 0
        when {
            mediaItemIndex > currentIndex -> listening.nextChapter()
            mediaItemIndex < currentIndex -> listening.previousChapter()
            // Previous at the start of the first item: back to the start (or the chapter before).
            else -> listening.previousChapter()
        }
        return Futures.immediateVoidFuture()
    }
}
