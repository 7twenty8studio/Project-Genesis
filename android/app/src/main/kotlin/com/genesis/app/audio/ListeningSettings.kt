package com.genesis.app.audio

import android.content.Context
import androidx.core.content.edit
import com.genesis.core.domain.audio.Narration
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

/** Listening preferences, kept on this device (iOS's AudioSettings keys). */
data class ListeningPreferences(
    /** 0.5× to 2×. */
    val speed: Double = 1.0,
    /** Turn pages and mark the verse being read. */
    val followsAlong: Boolean = true,
    /** Carry on into the next chapter. */
    val continuesToNextChapter: Boolean = true,
)

class ListeningSettings(context: Context) {
    private val defaults = context.getSharedPreferences("audio", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow(
        ListeningPreferences(
            speed = Narration.clampSpeed(defaults.getFloat(SPEED, 1f).toDouble()),
            followsAlong = defaults.getBoolean(FOLLOW, true),
            continuesToNextChapter = defaults.getBoolean(CONTINUES, true),
        ),
    )
    val state: StateFlow<ListeningPreferences> = _state.asStateFlow()

    fun setSpeed(speed: Double) {
        val value = Narration.clampSpeed(speed)
        _state.update { it.copy(speed = value) }
        defaults.edit { putFloat(SPEED, value.toFloat()) }
    }

    fun setFollowsAlong(on: Boolean) {
        _state.update { it.copy(followsAlong = on) }
        defaults.edit { putBoolean(FOLLOW, on) }
    }

    fun setContinuesToNextChapter(on: Boolean) {
        _state.update { it.copy(continuesToNextChapter = on) }
        defaults.edit { putBoolean(CONTINUES, on) }
    }

    private companion object {
        const val SPEED = "audio.speed"
        const val FOLLOW = "audio.followsAlong"
        const val CONTINUES = "audio.continues"
    }
}
