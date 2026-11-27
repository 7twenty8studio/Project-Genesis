package com.genesis.app.settings

import android.content.Context
import com.genesis.core.domain.bible.VerseId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Where the person is reading, as ReadingProgress on iOS ("progress.position"):
 * the reader opens there and Home's Continue Reading shows it.
 */
class ReadingProgressStore(context: Context) {
    private val defaults = context.getSharedPreferences("progress", Context.MODE_PRIVATE)

    private val _position = MutableStateFlow(
        defaults.getInt(POSITION, 0).takeIf { it > 0 }?.let(::VerseId),
    )

    /** The last verse read, or null before the first chapter is opened. */
    val position: StateFlow<VerseId?> = _position.asStateFlow()

    fun record(verse: VerseId) {
        if (_position.value == verse) return
        _position.value = verse
        defaults.edit().putInt(POSITION, verse.rawValue).putLong(LAST_READ, System.currentTimeMillis()).apply()
    }

    private companion object {
        const val POSITION = "progress.position"
        const val LAST_READ = "progress.lastReadAt"
    }
}
