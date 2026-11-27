package com.genesis.app.settings

import android.content.Context
import com.genesis.core.domain.bible.VerseId
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.LocalDate

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

    /**
     * Days with reading ("progress.readingDays", "yyyy-MM-dd", as iOS), for
     * the daily reading reminder: reading today drops today's nudge.
     */
    val readingDays: Set<LocalDate>
        get() = defaults.getStringSet(DAYS, emptySet()).orEmpty().mapNotNull { runCatching { LocalDate.parse(it) }.getOrNull() }.toSet()

    fun record(verse: VerseId) {
        val today = LocalDate.now().toString()
        val days = defaults.getStringSet(DAYS, emptySet()).orEmpty()
        val newDay = today !in days
        if (_position.value == verse && !newDay) return
        _position.value = verse
        defaults.edit().apply {
            putInt(POSITION, verse.rawValue)
            putLong(LAST_READ, System.currentTimeMillis())
            if (newDay) putStringSet(DAYS, days + today)
        }.apply()
    }

    private companion object {
        const val POSITION = "progress.position"
        const val LAST_READ = "progress.lastReadAt"
        const val DAYS = "progress.readingDays"
    }
}
