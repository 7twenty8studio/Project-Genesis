package com.genesis.app.features

import android.content.Context
import androidx.core.content.edit
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.core.domain.features.OptionalFeature
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * What this person wants to see, as FeaturePreferences on iOS (the same
 * keys). Hiding a feature hides its buttons, tabs and Home sections;
 * nothing is deleted. The server's switches still decide whether a feature
 * exists at all: use `shows`.
 */
class FeaturePreferences(context: Context, private val existingUser: () -> Boolean = { false }) {
    private val defaults = context.getSharedPreferences("features", Context.MODE_PRIVATE)

    private val _enabled = MutableStateFlow(load())
    val enabled: StateFlow<Set<OptionalFeature>> = _enabled.asStateFlow()

    /** True once the person has chosen (at setup or in Settings). */
    val hasChosen: Boolean get() = defaults.getBoolean(CHOSEN, false)

    private fun load(): Set<OptionalFeature> {
        // Someone who set Versely up before this choice existed keeps everything they had.
        val saved = defaults.getStringSet(ENABLED, null)
            ?: return if (existingUser()) OptionalFeature.entries.toSet() else OptionalFeature.defaults
        val known = defaults.getStringSet(KNOWN, null) ?: OptionalFeature.entries.map { it.rawValue }.toSet()
        return OptionalFeature.migrated(saved, known)
    }

    fun isOn(feature: OptionalFeature): Boolean = feature in _enabled.value

    fun set(feature: OptionalFeature, on: Boolean) = save(if (on) _enabled.value + feature else _enabled.value - feature)

    /** The choice made during setup. */
    fun choose(features: Set<OptionalFeature>) = save(features)

    private fun save(features: Set<OptionalFeature>) {
        _enabled.value = features
        defaults.edit {
            putStringSet(ENABLED, features.mapTo(mutableSetOf()) { it.rawValue })
            putBoolean(CHOSEN, true)
            putStringSet(KNOWN, OptionalFeature.entries.mapTo(mutableSetOf()) { it.rawValue })
        }
    }

    companion object {
        private const val ENABLED = "features.enabled"
        private const val CHOSEN = "features.chosen"
        private const val KNOWN = "features.known"

        /**
         * Features Versely for Android has today (the rest join as they're
         * built; the study assistant stays out of Android).
         */
        val built: Set<OptionalFeature> = OptionalFeature.entries.toSet() -
            setOf(OptionalFeature.STUDY_ASSISTANT)

        fun offered(flags: Map<String, Boolean>): List<OptionalFeature> =
            OptionalFeature.entries.filter { it in built && OptionalFeature.isAvailable(it, flags) }
    }
}

/** Available and wanted. */
fun Set<OptionalFeature>.shows(feature: OptionalFeature, flags: Map<String, Boolean>): Boolean =
    feature in this && OptionalFeature.isAvailable(feature, flags)

/** Whether a feature shows now (chosen and available), followed as either changes. */
@androidx.compose.runtime.Composable
fun rememberFeatureShows(): (OptionalFeature) -> Boolean {
    val app = androidx.compose.ui.platform.LocalContext.current.applicationContext as com.genesis.app.VerselyApplication
    val enabled = app.features.enabled.collectAsStateWithLifecycle().value
    val flags = app.flags.values.collectAsStateWithLifecycle().value
    return { enabled.shows(it, flags) }
}

/** Reminder kinds that belong to a hidden feature are neither listed nor sent. */
fun com.genesis.core.domain.notifications.ReminderKind.feature(): OptionalFeature? = when (this) {
    com.genesis.core.domain.notifications.ReminderKind.READING_PLAN -> OptionalFeature.PLANS
    com.genesis.core.domain.notifications.ReminderKind.MEMORISE -> OptionalFeature.MEMORISE
    com.genesis.core.domain.notifications.ReminderKind.PRAYER, com.genesis.core.domain.notifications.ReminderKind.PRAYER_ANNIVERSARY -> OptionalFeature.PRAYER
    com.genesis.core.domain.notifications.ReminderKind.SERMONS -> OptionalFeature.SERMONS
    com.genesis.core.domain.notifications.ReminderKind.WEEKLY_RECAP -> OptionalFeature.INSIGHTS
    com.genesis.core.domain.notifications.ReminderKind.GROUPS -> OptionalFeature.TOGETHER
    com.genesis.core.domain.notifications.ReminderKind.NUDGES -> OptionalFeature.NUDGES
    else -> null
}
