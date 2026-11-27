package com.genesis.app.welcome

import android.content.Context
import androidx.core.content.edit
import com.genesis.core.domain.welcome.MorningWelcomeRules
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.time.LocalDate

/** Settings › Morning Welcome: shown each day, the name to greet, and whether ambient sounds ease in. */
data class MorningWelcomeSettings(
    val isOn: Boolean = true,
    val name: String = "",
    val playsSounds: Boolean = false,
)

/**
 * The Premium morning welcome, as MorningWelcome.swift (same keys): the
 * first time Versely opens each day, a quiet screen greets the person by
 * name, shows today's verse and reading, and eases in their ambient sounds.
 */
class MorningWelcome(context: Context) {
    private val defaults = context.getSharedPreferences("welcome", Context.MODE_PRIVATE)

    private val _settings = MutableStateFlow(
        MorningWelcomeSettings(
            isOn = defaults.getBoolean(IS_ON, true),
            name = defaults.getString(NAME, "") ?: "",
            // Off until the person turns it on; someone already greeted keeps what they heard.
            playsSounds = if (defaults.contains(PLAYS_SOUNDS)) defaults.getBoolean(PLAYS_SOUNDS, false) else defaults.contains(LAST_SHOWN),
        ),
    )
    val settings: StateFlow<MorningWelcomeSettings> = _settings.asStateFlow()

    init {
        if (!defaults.contains(PLAYS_SOUNDS)) defaults.edit { putBoolean(PLAYS_SOUNDS, _settings.value.playsSounds) }
    }

    fun setOn(on: Boolean) {
        _settings.update { it.copy(isOn = on) }
        defaults.edit { putBoolean(IS_ON, on) }
    }

    fun setName(name: String) {
        _settings.update { it.copy(name = name) }
        defaults.edit { putString(NAME, name) }
    }

    fun setPlaysSounds(on: Boolean) {
        _settings.update { it.copy(playsSounds = on) }
        defaults.edit { putBoolean(PLAYS_SOUNDS, on) }
    }

    /** True the first time today the app opens for a Premium member who has it on. */
    fun shouldShow(isPremium: Boolean, today: LocalDate = LocalDate.now()): Boolean =
        MorningWelcomeRules.shouldShow(true, _settings.value.isOn, isPremium, defaults.getString(LAST_SHOWN, null), MorningWelcomeRules.dayKey(today))

    /** Counts today as greeted (also when the app opened from a link, so it doesn't cover where the person meant to go). */
    fun markShown(today: LocalDate = LocalDate.now()) {
        defaults.edit { putString(LAST_SHOWN, MorningWelcomeRules.dayKey(today)) }
    }

    private companion object {
        const val IS_ON = "welcome.isOn"
        const val NAME = "welcome.name"
        const val PLAYS_SOUNDS = "welcome.playsSounds"
        const val LAST_SHOWN = "welcome.lastShownDay"
    }
}
