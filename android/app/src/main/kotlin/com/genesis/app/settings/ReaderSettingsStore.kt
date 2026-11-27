package com.genesis.app.settings

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.genesis.app.BuildConfig
import androidx.core.content.edit
import com.genesis.core.domain.reader.ReaderPreferences
import com.genesis.core.domain.study.HighlightColor
import com.genesis.core.domain.study.RecentHighlightColors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The reader's settings on this device, as iOS keeps them in UserDefaults
 * ("reader.preferences.v1", JSON). One store for the app process.
 */
class ReaderSettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("reader", Context.MODE_PRIVATE)
    private val _preferences = MutableStateFlow(ReaderPreferences.decoded(prefs.getString(KEY, null)))
    val preferences: StateFlow<ReaderPreferences> = _preferences.asStateFlow()

    private val _recentColors = MutableStateFlow(
        prefs.getString(RECENT_COLORS, null).orEmpty().split(',').filter { it.isNotEmpty() }.map(HighlightColor::withId),
    )

    /** The highlight colours used most recently, first in the selection bar. */
    val recentColors: StateFlow<List<HighlightColor>> = _recentColors.asStateFlow()

    fun used(color: HighlightColor) {
        val next = RecentHighlightColors.after(color, _recentColors.value)
        _recentColors.value = next
        prefs.edit { putString(RECENT_COLORS, next.joinToString(",") { it.id }) }
    }

    /** The Bible being read ("library.currentTranslation" on iOS), or null before setup. */
    var currentBible: String?
        get() = prefs.getString(CURRENT_BIBLE, null)
        set(value) = prefs.edit { putString(CURRENT_BIBLE, value) }

    private val _onboardingComplete = MutableStateFlow(prefs.getBoolean(ONBOARDING, false))

    /** True once first-launch setup is done ("onboarding.complete" on iOS). */
    val onboardingComplete: StateFlow<Boolean> = _onboardingComplete.asStateFlow()

    fun completeOnboarding() {
        _onboardingComplete.value = true
        prefs.edit { putBoolean(ONBOARDING, true) }
    }

    fun update(change: (ReaderPreferences) -> ReaderPreferences) {
        val next = change(_preferences.value).clamped()
        _preferences.value = next
        prefs.edit { putString(KEY, next.encoded()) }
    }

    private companion object {
        const val KEY = "reader.preferences.v1"
        const val RECENT_COLORS = "highlights.recentColors"
        const val CURRENT_BIBLE = "library.currentTranslation"
        const val ONBOARDING = "onboarding.complete"
    }
}

/** The highlight colours used most recently, for the selection bar. */
val LocalRecentColors = staticCompositionLocalOf<androidx.compose.runtime.State<List<HighlightColor>>> {
    androidx.compose.runtime.mutableStateOf(emptyList())
}

/**
 * The reader's settings for the screens below the activity, as they apply
 * now: night reading's theme in place of the day theme while it's night,
 * and the text size fixed when it doesn't follow the phone's font size.
 */
val LocalReaderPreferences = staticCompositionLocalOf { ReaderPreferences() }

/** The settings as the person chose them (the Aa sheet shows and changes these). */
val LocalChosenReaderPreferences = staticCompositionLocalOf { ReaderPreferences() }

/**
 * The settings as they apply now: night reading's theme (ReaderSettings.effectiveTheme
 * on iOS), and the size held still against the phone's font scale when it isn't followed.
 */
@androidx.compose.runtime.Composable
fun rememberEffectivePreferences(chosen: ReaderPreferences): ReaderPreferences {
    val systemIsDark = androidx.compose.foundation.isSystemInDarkTheme()
    val fontScale = androidx.compose.ui.platform.LocalDensity.current.fontScale
    // Moved on at each edge of the night window, so the theme switches on time.
    var clock by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(java.time.ZonedDateTime.now()) }
    androidx.compose.runtime.LaunchedEffect(chosen.nightReading, clock) {
        val next = com.genesis.core.domain.reader.NightReading.nextChange(clock, chosen.nightReading) ?: return@LaunchedEffect
        kotlinx.coroutines.delay(java.time.Duration.between(java.time.ZonedDateTime.now(), next).toMillis().coerceAtLeast(1_000) + 500)
        clock = java.time.ZonedDateTime.now()
    }
    val theme = com.genesis.core.domain.reader.NightReading.theme(chosen.nightReading, chosen.theme, clock.toLocalDateTime(), systemIsDark, Entitlements.isPremium)
    return chosen.copy(
        theme = theme,
        fontSize = if (chosen.followsDynamicType) chosen.fontSize else chosen.fontSize / fontScale,
    )
}

/**
 * Premium arrives with Play Billing. Until then everything Premium is shown
 * with its tag and can't be chosen, as on iOS without Premium; debug builds
 * have Settings › Developer › Test as Premium, as iOS's DEBUG builds do.
 */
object Entitlements {
    var isPremium: Boolean by mutableStateOf(false)
        private set

    private const val TEST_KEY = "premium.testAsPremium"

    fun load(context: Context) {
        if (!BuildConfig.DEBUG) return
        isPremium = context.getSharedPreferences("premium", Context.MODE_PRIVATE).getBoolean(TEST_KEY, false)
    }

    fun setTestingPremium(context: Context, on: Boolean) {
        if (!BuildConfig.DEBUG) return
        context.getSharedPreferences("premium", Context.MODE_PRIVATE).edit { putBoolean(TEST_KEY, on) }
        isPremium = on
    }
}
