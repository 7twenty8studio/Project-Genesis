package com.genesis.app.settings

import android.content.Context
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.goals.ReadingStreak
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
    /** Chapter keys opened in each year ("progress.chaptersByYear", as iOS), for Year in Review. */
    val chaptersByYear: Map<Int, Set<Int>> = emptyMap(),
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
        chaptersByYear = defaults.getStringSet(BY_YEAR, emptySet()).orEmpty()
            .mapNotNull { entry -> entry.split(':').takeIf { it.size == 2 }?.let { (year, key) -> year.toIntOrNull()?.let { y -> key.toIntOrNull()?.let { y to it } } } }
            .groupBy({ it.first }, { it.second }).mapValues { it.value.toSet() },
    )

    fun record(verse: VerseId) {
        val today = LocalDate.now()
        val current = _record.value
        val chapter = ReadingStats.chapterKey(verse.book, verse.chapter)
        val newDay = today !in current.readingDays
        val newChapter = chapter !in current.chaptersRead
        val thisYear = current.chaptersByYear[today.year].orEmpty()
        val newInYear = chapter !in thisYear
        if (newDay || newChapter || newInYear) {
            _record.value = current.copy(
                readingDays = current.readingDays + today,
                chaptersRead = current.chaptersRead + chapter,
                chaptersByYear = current.chaptersByYear + (today.year to thisYear + chapter),
            )
        }
        if (newInYear) {
            defaults.edit().putStringSet(BY_YEAR, _record.value.chaptersByYear.flatMapTo(mutableSetOf()) { (year, keys) -> keys.map { "$year:$it" } }).apply()
        }
        recordRecent(today, chapter)
        if (_position.value == verse && !newDay && !newChapter) return
        _position.value = verse
        defaults.edit().apply {
            putInt(POSITION, verse.rawValue)
            putLong(LAST_READ, System.currentTimeMillis())
            if (newDay) putStringSet(DAYS, _record.value.readingDays.mapTo(mutableSetOf()) { it.toString() })
            if (newChapter) putStringSet(CHAPTERS, _record.value.chaptersRead.mapTo(mutableSetOf()) { it.toString() })
        }.apply()
    }

    /** Chapters opened per day ("yyyy-MM-dd:key"), the last two weeks, for the verse widget's From Your Reading. */
    private var chaptersByDay: Set<String> = defaults.getStringSet(BY_DAY, emptySet()).orEmpty()

    private fun recordRecent(today: LocalDate, chapter: Int) {
        val entry = "$today:$chapter"
        if (entry in chaptersByDay) return
        val oldest = today.minusDays(14).toString()
        chaptersByDay = chaptersByDay.filter { it.substringBefore(':') >= oldest }.toSet() + entry
        defaults.edit().putStringSet(BY_DAY, chaptersByDay).apply()
    }

    /**
     * The chapters opened in the last `days` days, most recent day first,
     * each once (chapter keys, book × 1,000 + chapter), as
     * ReadingProgress.recentChapters on iOS.
     */
    fun recentChapters(days: Int = 7, today: LocalDate = LocalDate.now()): List<Int> {
        val byDay = chaptersByDay.groupBy({ it.substringBefore(':') }, { it.substringAfter(':').toIntOrNull() })
        val seen = LinkedHashSet<Int>()
        for (offset in 0 until days.coerceAtLeast(0)) {
            byDay[today.minusDays(offset.toLong()).toString()].orEmpty().filterNotNull().sorted().forEach { seen.add(it) }
        }
        return seen.toList()
    }

    /** Streak shields on (the person's choice in Goals & Streaks); every streak follows it. */
    @Volatile var streakShieldsActive: Boolean = true

    /** Days in a row ending today (or yesterday, before today's reading), with shields when on. */
    fun streak(today: LocalDate = LocalDate.now(), days: Set<LocalDate> = readingDays): Int =
        ReadingStreak.walk(days, today, streakShieldsActive).length

    /** Whether a shield is ready to cover a missed day this week. */
    fun streakShieldReady(today: LocalDate = LocalDate.now()): Boolean =
        ReadingStreak.shieldReady(ReadingStreak.walk(readingDays, today, streakShieldsActive).lastShield, today)

    /** Chapters opened on that day. */
    fun chaptersRead(on: LocalDate = LocalDate.now()): Int = chaptersByDay.count { it.startsWith("$on:") }

    /** Seconds in the reader on that day. */
    fun secondsRead(on: LocalDate = LocalDate.now()): Int = _record.value.readingSeconds[on] ?: 0

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
        const val BY_DAY = "progress.chaptersByDay"
        const val BY_YEAR = "progress.chaptersByYear"
    }
}
