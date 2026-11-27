package com.genesis.app

import android.content.Context
import androidx.core.content.edit
import com.genesis.core.cloud.SupabaseClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext

/**
 * The server's switches (public.feature_flags), as FeatureFlagService on
 * iOS: everything is off until the server says otherwise, and the last
 * answer is kept so an offline start behaves like the one before.
 */
class FeatureFlags(context: Context, private val client: SupabaseClient?) {
    private val defaults = context.getSharedPreferences("featureFlags", Context.MODE_PRIVATE)
    private val _values = MutableStateFlow(KEYS.associateWith { defaults.getBoolean(it, false) })
    val values: StateFlow<Map<String, Boolean>> = _values.asStateFlow()

    fun isOn(key: String): Boolean = _values.value[key] ?: false

    /** Asks the server; keeps the last values offline. */
    suspend fun refresh() {
        val client = client ?: return
        val remote = withContext(Dispatchers.IO) { runCatching { client.featureFlags() }.getOrNull() } ?: return
        val updated = KEYS.associateWith { remote[it] ?: false }
        _values.value = updated
        defaults.edit { updated.forEach { (key, on) -> putBoolean(key, on) } }
    }

    companion object {
        const val GROUPS = "groups"
        const val COMMUNITY = "community"
        const val STUDY_ASSISTANT = "study_assistant"
        const val CHURCH_SERMONS = "church_sermons"
        val KEYS = listOf(GROUPS, COMMUNITY, STUDY_ASSISTANT, CHURCH_SERMONS)
    }
}
