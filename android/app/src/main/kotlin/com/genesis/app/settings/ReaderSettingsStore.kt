package com.genesis.app.settings

import android.content.Context
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.core.content.edit
import com.genesis.core.domain.reader.ReaderPreferences
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

    fun update(change: (ReaderPreferences) -> ReaderPreferences) {
        val next = change(_preferences.value).clamped()
        _preferences.value = next
        prefs.edit { putString(KEY, next.encoded()) }
    }

    private companion object {
        const val KEY = "reader.preferences.v1"
    }
}

/** The reader's settings for the screens below the activity. */
val LocalReaderPreferences = staticCompositionLocalOf { ReaderPreferences() }

/**
 * Premium arrives with Play Billing (phase 4). Until then everything Premium
 * is shown with its tag and can't be chosen, as on iOS without Premium.
 */
object Entitlements {
    const val isPremium: Boolean = false
}
