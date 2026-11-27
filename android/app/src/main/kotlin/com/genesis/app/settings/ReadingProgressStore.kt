package com.genesis.app.settings

import android.content.Context
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.insights.ReadingStats
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.time.LocalDate

/** What Home's Progress and Insights show, read at once from the store. */
data class ReadingRecord(
    val readingDays: Set<LocalDate> = emptySet(),
    /** Chapter keys (book × 1,000 + chapter) opened. */
    val chaptersRead: Set<Int> = emptySet(),
    /** Seconds in the reader per day. */
    val readingSeconds: Map<LocalDate, Int> = emptyMap(),
) {
    val totalSeconds: Long get() = readingSeconds.values.sumOf { it.toLong() }
}

/**
 * Where the person is reading, as ReadingProgress on iOS ("progress.position"):
 * the reader opens there and Home's Continue Reading shows it. Also the days
 * read, the chapters opened and the time spent reading, for streaks and Insights.
 */
class ReadingProgressStore(context: Context) {
    private val defaults = context.getSharedPreferences("progress", Context.MODE_PRIVATE)

    private val _position = MutableStateFlow(
        defaults.getInt(POSITION, 0).takeIf { it > 0 }?.let(::VerseId),
    )

    /** The last verse read, or null before the first chapter is opened. */
    val position: StateFlow<VerseId?> = _position.asStateFlow()

    private val _record = MutableStateFlow(load())

    /** Days read, chapters opened and reading time. */
    val record: StateFlow<ReadingRecord> = _record.asStateFlow()

    /**
     * Days with reading ("progress.readingDays", "yyyy-MM-dd", as iOS), for
     * the daily reading reminder: reading today drops today's nudge.
     */
    val readingDays: Set<LocalDate> get() = _record.value.readingDays

    private fun load() = ReadingRecord(
        readingDays = defaults.getStringSet(DAYS, emptySet()).orEmpty().mapNotNull { runCatching { LocalDate.parse(it) }.getOrNull() }.toSet(),
        chaptersRead = defaults.getStringSet(CHAPTERS, emptySet()).orEmpty().mapNotNull { it.toIntOrNull() }.toSet(),
        readingSeconds = ReadingStats.decodeSeconds(defaults.getStringSet(SECONDS, emptySet()).orEmpty()),
    )

    fun record(verse: VerseId) {
        val today = LocalDate.now()
        val current = _record.value
        val chapter = ReadingStats.chapterKey(verse.book, verse.chapter)
        val newDay = today !in current.readingDays
        val newChapter = chapter !in current.chaptersRead
        if (newDay || newChapter) {
            _record.value = current.copy(
                readingDays = current.readingDays + today,
                chaptersRead = current.chaptersRead + chapter,
            )
        }
        if (_position.value == verse && !newDay && !newChapter) return
        _position.value = verse
        defaults.edit().apply {
            putInt(POSITION, verse.rawValue)
            putLong(LAST_READ, System.currentTimeMillis())
            if (newDay) putStringSet(DAYS, _record.value.readingDays.mapTo(mutableSetOf()) { it.toString() })
            if (newChapter) putStringSet(CHAPTERS, _record.value.chaptersRead.mapTo(mutableSetOf()) { it.toString() })
        }.apply()
    }

    /** Adds a session in the reader, ending today (capped at 45 minutes, as iOS). */
    fun addReadingTime(durationSeconds: Long) {
        val seconds = ReadingStats.sessionSeconds(durationSeconds) ?: return
        val today = LocalDate.now()
        val current = _record.value
        val updated = current.readingSeconds + (today to (current.readingSeconds[today] ?: 0) + seconds)
        _record.value = current.copy(readingSeconds = updated)
        defaults.edit().putStringSet(SECONDS, ReadingStats.encodeSeconds(updated)).apply()
    }

    private companion object {
        const val POSITION = "progress.position"
        const val LAST_READ = "progress.lastReadAt"
        const val DAYS = "progress.readingDays"
        const val CHAPTERS = "progress.chaptersRead"
        const val SECONDS = "progress.readingSeconds"
    }
}
