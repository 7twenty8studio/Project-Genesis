package com.genesis.app.journal

import android.content.Context
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.SystemClock
import com.genesis.core.domain.journal.AttachmentLimits
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File

/**
 * Records a voice note, as VoiceRecorder on iOS: AAC mono at 32 kbps into
 * an .m4a, stopping by itself after four hours. The take waits in the cache
 * until it's saved or thrown away.
 */
internal class VoiceRecorder(private val context: Context) {
    enum class Phase { READY, RECORDING, RECORDED }

    private val _phase = MutableStateFlow(Phase.READY)
    val phase: StateFlow<Phase> = _phase.asStateFlow()

    private var recorder: MediaRecorder? = null
    private var startedAt = 0L
    var seconds: Double = 0.0
        private set

    val take: File = File(context.cacheDir, "recording.m4a")

    /** Seconds recorded so far (or in the finished take). */
    fun elapsed(): Double = if (_phase.value == Phase.RECORDING) (SystemClock.elapsedRealtime() - startedAt) / 1000.0 else seconds

    fun start(): Boolean {
        take.delete()
        val next = MediaRecorder(context)
        return runCatching {
            next.setAudioSource(MediaRecorder.AudioSource.MIC)
            next.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            next.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            next.setAudioChannels(1)
            next.setAudioSamplingRate(22_050)
            next.setAudioEncodingBitRate(AttachmentLimits.RECORDING_BIT_RATE)
            next.setMaxDuration(AttachmentLimits.MAX_RECORDING_SECONDS * 1000)
            next.setOnInfoListener { _, what, _ -> if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) stop() }
            next.setOutputFile(take.path)
            next.prepare()
            next.start()
            recorder = next
            startedAt = SystemClock.elapsedRealtime()
            _phase.value = Phase.RECORDING
        }.onFailure { next.release() }.isSuccess
    }

    fun stop() {
        val current = recorder ?: return
        seconds = (SystemClock.elapsedRealtime() - startedAt) / 1000.0
        recorder = null
        val ok = runCatching { current.stop() }.isSuccess
        current.release()
        _phase.value = if (ok && take.length() > 0) Phase.RECORDED else Phase.READY.also { take.delete() }
    }

    /** Throws the take away (Record Again, Cancel). */
    fun discard() {
        recorder?.let { runCatching { it.stop() }; it.release() }
        recorder = null
        take.delete()
        seconds = 0.0
        _phase.value = Phase.READY
    }
}

/** Plays one recording at a time: a voice note on a prayer or sermon, or a take before it's saved. */
internal class VoiceNotePlayer(private val context: Context) {
    private val _playing = MutableStateFlow<String?>(null)

    /** The key of what's playing (an attachment id, or "take"). */
    val playing: StateFlow<String?> = _playing.asStateFlow()

    private var player: MediaPlayer? = null

    fun toggle(key: String, file: File) {
        if (_playing.value == key) return stop()
        stop()
        // Listening and ambient sounds pause, as AudioSession's voice note user does on iOS.
        (context.applicationContext as? com.genesis.app.VerselyApplication)?.let {
            it.listening.pause()
            it.ambient.pause()
        }
        val next = MediaPlayer()
        runCatching {
            next.setDataSource(file.path)
            next.setOnCompletionListener { stop() }
            next.prepare()
            next.start()
            player = next
            _playing.value = key
        }.onFailure { next.release() }
    }

    fun stop() {
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
        _playing.value = null
    }
}
