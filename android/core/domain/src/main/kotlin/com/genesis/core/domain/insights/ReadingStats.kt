package com.genesis.core.domain.insights

import com.genesis.core.domain.bible.BibleBook
import com.genesis.core.domain.bible.BibleBooks
import java.time.LocalDate

/** A book and how many of its chapters have been opened. */
data class BookReading(val book: BibleBook, val chapters: Int)

/**
 * Reading statistics for Home's Progress and Insights, as ReadingProgress on
 * iOS: chapters are keys book × 1,000 + chapter ("progress.chaptersRead"),
 * reading time is seconds per day ("progress.readingSeconds").
 */
object ReadingStats {
    /** A session longer than this counts as this long, so a reader left open doesn't inflate the total. */
    const val LONGEST_SESSION_SECONDS = 45 * 60

    /** Sessions shorter than this aren't counted. */
    const val SHORTEST_SESSION_SECONDS = 5

    val totalChapters: Int by lazy { BibleBooks.all.sumOf { it.chapterCount } }

    fun chapterKey(book: Int, chapter: Int): Int = book * 1_000 + chapter

    /** The seconds a session adds, or null when it's too short to count. */
    fun sessionSeconds(durationSeconds: Long): Int? {
        val seconds = durationSeconds.coerceIn(0, LONGEST_SESSION_SECONDS.toLong()).toInt()
        return seconds.takeIf { it >= SHORTEST_SESSION_SECONDS }
    }

    /** The longest run of consecutive reading days. */
    fun longestStreak(days: Set<LocalDate>): Int {
        var best = 0
        var run = 0
        var previous: LocalDate? = null
        for (day in days.sorted()) {
            run = if (previous != null && previous.plusDays(1) == day) run + 1 else 1
            best = maxOf(best, run)
            previous = day
        }
        return best
    }

    /** Books by chapters opened, the most read first (ties by book order). */
    fun favoriteBooks(chapters: Set<Int>, limit: Int = 5): List<BookReading> =
        chapters.groupingBy { it / 1_000 }.eachCount()
            .filterKeys { it in 1..BibleBooks.all.size }
            .entries
            .sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key })
            .take(limit)
            .map { BookReading(BibleBooks.withNumber(it.key), it.value) }

    /** Books with every chapter opened. */
    fun booksCompleted(chapters: Set<Int>): Int =
        BibleBooks.all.count { book -> (1..book.chapterCount).all { chapterKey(book.id, it) in chapters } }

    /** Seconds on each of the last [days] days, oldest first. */
    fun dailyTime(seconds: Map<LocalDate, Int>, days: Int, endingOn: LocalDate): List<Pair<LocalDate, Int>> =
        (days - 1 downTo 0).map { offset ->
            val day = endingOn.minusDays(offset.toLong())
            day to (seconds[day] ?: 0)
        }

    /** Stored as a string set of "yyyy-MM-dd=seconds" (SharedPreferences has no map). */
    fun encodeSeconds(seconds: Map<LocalDate, Int>): Set<String> =
        seconds.mapTo(mutableSetOf()) { (day, value) -> "$day=$value" }

    fun decodeSeconds(entries: Set<String>): Map<LocalDate, Int> =
        entries.mapNotNull { entry ->
            val day = entry.substringBefore('=', "")
            val value = entry.substringAfter('=', "").toIntOrNull()
            val date = runCatching { LocalDate.parse(day) }.getOrNull()
            if (date != null && value != null) date to value else null
        }.toMap()

    /** Whole hours and minutes, for "12 min" or "3 h 5 min". */
    fun hoursAndMinutes(seconds: Long): Pair<Int, Int> {
        val minutes = (seconds / 60).toInt()
        return minutes / 60 to minutes % 60
    }
}
