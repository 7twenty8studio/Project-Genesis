package com.genesis.app.audio

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.annotation.StringRes
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.genesis.app.R
import com.genesis.core.domain.audio.AmbientMix
import com.genesis.core.domain.audio.AmbientRules
import com.genesis.core.domain.audio.AmbientSound
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What ambient sounds are doing, as AmbientSoundService.swift's state. */
data class AmbientState(
    val mix: Map<AmbientSound, Float> = emptyMap(),
    val isPlaying: Boolean = false,
    /** The reader's ambient bar is out (playing or paused, until closed). */
    val showsControls: Boolean = false,
    val timerMinutes: Int? = null,
    val timerEndsAt: Long? = null,
    val isDucked: Boolean = false,
) {
    val currentMix: AmbientMix? get() = AmbientMix.matching(mix)
    fun contains(sound: AmbientSound) = sound in mix
    fun volume(of: AmbientSound): Float = mix[of] ?: of.defaultVolume
}

/**
 * Ambient sounds (Premium, `.ambientSounds`; callers check): the bundled
 * loops shared with iOS, one looping player per sound in the mix, each
 * clipped to its loop's exact length. They play alongside other apps (no
 * audio focus, as iOS mixes with others), keep going with the screen off
 * (AmbientService), sit quieter while the Bible is read aloud and fade out
 * when the timer ends. The mix is remembered.
 */
class AmbientSounds(private val context: Context, listening: Listening) {
    private val prefs = context.getSharedPreferences("ambient", Context.MODE_PRIVATE)
    private val scope = MainScope()
    private val players = mutableMapOf<AmbientSound, ExoPlayer>()
    private val fades = mutableMapOf<AmbientSound, Job>()
    private var timerJob: Job? = null

    private val _state = MutableStateFlow(AmbientState(mix = AmbientRules.decode(prefs.getString(MIX_KEY, null))))
    val state: StateFlow<AmbientState> = _state.asStateFlow()

    init {
        scope.launch {
            listening.state.map { it.isPlaying }.distinctUntilChanged().collect { setDucked(it) }
        }
    }

    /** Adds a sound to the mix (and starts playing), or takes it out. */
    fun toggle(sound: AmbientSound) {
        val mix = AmbientRules.toggle(state.value.mix, sound)
        if (sound !in mix) {
            stop(sound)
            _state.update { it.copy(mix = mix) }
            if (mix.isEmpty()) {
                _state.update { it.copy(isPlaying = false, showsControls = false) }
                setTimer(null)
            }
        } else {
            _state.update { it.copy(mix = mix) }
            if (state.value.isPlaying) start(sound) else play()
        }
        save()
    }

    fun setVolume(volume: Float, sound: AmbientSound) {
        if (sound !in state.value.mix) return
        val clamped = volume.coerceIn(0f, 1f)
        _state.update { it.copy(mix = it.mix + (sound to clamped)) }
        players[sound]?.let { fades[sound]?.cancel(); it.volume = AmbientRules.effective(clamped, state.value.isDucked) }
        save()
    }

    /** Replaces the mix with a ready-made one and plays it. */
    fun choose(preset: AmbientMix) {
        state.value.mix.keys.filter { it !in preset.volumes }.forEach { stop(it) }
        _state.update { it.copy(mix = preset.volumes) }
        save()
        if (state.value.isPlaying) preset.volumes.keys.forEach { start(it) } else play()
    }

    fun play() {
        if (state.value.mix.isEmpty()) return
        _state.update { it.copy(isPlaying = true, showsControls = true) }
        state.value.mix.keys.forEach { start(it) }
        runCatching { ContextCompat.startForegroundService(context, Intent(context, AmbientService::class.java)) }
            .onFailure { Log.w(TAG, "Couldn't keep ambient sounds going in the background", it) }
    }

    fun pause() {
        if (!state.value.isPlaying) return
        _state.update { it.copy(isPlaying = false) }
        players.keys.toList().forEach { stop(it) }
        setTimer(null)
    }

    /** Stops the sounds and puts the reader's bar away. */
    fun close() {
        pause()
        _state.update { it.copy(showsControls = false) }
    }

    fun togglePlayback() = if (state.value.isPlaying) pause() else play()

    /** Fades the sounds out after this many minutes (null: no timer). */
    fun setTimer(minutes: Int?) {
        timerJob?.cancel()
        timerJob = null
        val chosen = minutes?.takeIf { state.value.isPlaying }
        if (chosen == null) {
            _state.update { it.copy(timerMinutes = null, timerEndsAt = null) }
            return
        }
        _state.update { it.copy(timerMinutes = chosen, timerEndsAt = System.currentTimeMillis() + chosen * 60_000L) }
        timerJob = scope.launch {
            delay(chosen * 60_000L)
            timerJob = null
            _state.update { it.copy(timerMinutes = null, timerEndsAt = null) }
            pause()
        }
    }

    /** Bible narration started or stopped: sit quieter beneath it. */
    private fun setDucked(ducked: Boolean) {
        if (ducked == state.value.isDucked) return
        _state.update { it.copy(isDucked = ducked) }
        if (!state.value.isPlaying) return
        state.value.mix.forEach { (sound, volume) -> players[sound]?.let { fade(sound, it, AmbientRules.effective(volume, ducked), FADE_MS) } }
    }

    private fun start(sound: AmbientSound) {
        val volume = state.value.mix[sound] ?: return
        val target = AmbientRules.effective(volume, state.value.isDucked)
        val player = players[sound] ?: runCatching { newPlayer(sound) }
            .onFailure { Log.e(TAG, "Couldn't play ${sound.id}", it) }
            .getOrNull()?.also { players[sound] = it } ?: return
        fade(sound, player, target, FADE_MS)
    }

    /** Fades a sound out and lets its player go. */
    private fun stop(sound: AmbientSound) {
        val player = players.remove(sound) ?: return
        fade(sound, player, 0f, FADE_OUT_MS) { player.release() }
    }

    private fun newPlayer(sound: AmbientSound): ExoPlayer {
        val attributes = AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build()
        val item = MediaItem.Builder()
            .setUri("asset:///${sound.fileName}")
            .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setEndPositionMs((sound.loopSeconds * 1000).toLong()).build())
            .build()
        return ExoPlayer.Builder(context)
            .setAudioAttributes(attributes, false)
            .setWakeMode(C.WAKE_MODE_LOCAL)
            .build()
            .apply {
                repeatMode = Player.REPEAT_MODE_ONE
                volume = 0f
                setMediaItem(item)
                prepare()
                play()
            }
    }

    private fun fade(sound: AmbientSound, player: ExoPlayer, to: Float, millis: Long, then: (() -> Unit)? = null) {
        val previous = fades.remove(sound)
        previous?.cancel()
        val job = scope.launch {
            val from = player.volume
            val steps = (millis / STEP_MS).coerceAtLeast(1)
            for (step in 1..steps) {
                delay(STEP_MS)
                player.volume = from + (to - from) * step / steps
            }
            then?.invoke()
        }
        // A player stopped for good keeps its own fade, so a new one for the same sound can start.
        if (then == null) fades[sound] = job
    }

    private fun save() {
        prefs.edit().putString(MIX_KEY, AmbientRules.encode(state.value.mix)).apply()
    }

    companion object {
        private const val TAG = "AmbientSounds"
        private const val MIX_KEY = "ambient.mix"
        private const val FADE_MS = 1_200L
        private const val FADE_OUT_MS = 800L
        private const val STEP_MS = 40L
    }
}

/** The sound's name, as iOS's AmbientSound.title. */
@get:StringRes
val AmbientSound.title: Int
    get() = when (this) {
        AmbientSound.RAIN -> R.string.ambient_rain
        AmbientSound.WAVES -> R.string.ambient_waves
        AmbientSound.WIND -> R.string.ambient_wind
        AmbientSound.FIREPLACE -> R.string.ambient_fireplace
        AmbientSound.BIRDSONG -> R.string.ambient_birdsong
        AmbientSound.PAD -> R.string.ambient_pad
    }

/** The mix's name, as iOS's AmbientMix.title. */
@get:StringRes
val AmbientMix.title: Int
    get() = when (id) {
        "fireside" -> R.string.ambient_mix_fireside
        "garden" -> R.string.ambient_mix_garden
        "seaside" -> R.string.ambient_mix_seaside
        "sanctuary" -> R.string.ambient_mix_sanctuary
        else -> R.string.ambient_mix_quiet_rain
    }

/** "Rain, Fireplace": the sounds in the mix, in their usual order. */
fun AmbientState.summary(context: Context): String =
    AmbientSound.entries.filter { it in mix }.joinToString(", ") { context.getString(it.title) }
