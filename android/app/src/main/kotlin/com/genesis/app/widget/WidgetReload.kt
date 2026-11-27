package com.genesis.app.widget

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.datastore.preferences.core.Preferences
import androidx.glance.currentState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Glance runs provideGlance only when a widget's session starts; an update
 * while the session is still open (for about a minute after the last one)
 * only recomposes. So anything read before provideContent would stay as it
 * was: a new background chosen, frames just drawn, today's reading. Widgets
 * read their data through [reloaded], which loads again on every refresh
 * and whenever the widget's own settings change.
 */
object WidgetReload {
    private val _generation = MutableStateFlow(0L)
    val generation: StateFlow<Long> = _generation.asStateFlow()

    /** Called before widgets update, so open sessions load again. */
    fun bump() { _generation.value += 1 }
}

/** [first] (loaded in provideGlance) until something changes, then [load] again. */
@Composable
internal fun <T> reloaded(first: T, load: suspend () -> T): T {
    val generation by WidgetReload.generation.collectAsState()
    val settings = currentState<Preferences>()
    val start = remember { generation to settings }
    val value by produceState(first, generation, settings) {
        if (generation to settings != start) value = load()
    }
    return value
}
