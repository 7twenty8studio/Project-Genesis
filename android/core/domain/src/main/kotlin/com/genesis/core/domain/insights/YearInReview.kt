package com.genesis.core.domain.insights

import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.HighlightColor
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * A year of reading, worked out from what's on the phone (YearInReview.swift):
 * days read, streaks, time, chapters and books, highlights, notes and prayers.
 */
data class YearInReview(
    val year: Int,
    val daysRead: Int,
    val longestStreak: Int,
    val minutesRead: Int,
    /** The day with the most reading, and how many minutes. */
    val longestDay: LocalDate?,
    val longestDayMinutes: Int,
    val chaptersRead: Int,
    val booksOpened: Int,
    /** Books read from beginning to end this year. */
    val booksFinished: Int,
    /** The book with the most chapters read this year. */
    val topBook: Int?,
    val highlights: Int,
    val mostHighlightedBook: Int?,
    val favoriteColor: HighlightColor?,
    val notes: Int,
    val prayersAdded: Int,
    val prayersAnswered: Int,
) {
    data class HighlightRecord(val createdAt: Long, val verse: VerseId, val color: HighlightColor)
    data class PrayerRecord(val createdAt: Long, val answeredAt: Long?)

    /** True when there's something to show. */
    val hasActivity: Boolean get() = daysRead > 0 || highlights > 0 || notes > 0 || prayersAdded > 0

    companion object {
        fun make(
            year: Int,
            readingDays: Set<LocalDate>,
            readingSeconds: Map<LocalDate, Int>,
            chapters: Set<Int>,
            highlights: List<HighlightRecord>,
            notes: List<Long>,
            prayers: List<PrayerRecord>,
            zone: ZoneId = ZoneId.systemDefault(),
        ): YearInReview {
            val days = readingDays.filter { it.year == year }.sorted()
            var longest = 0
            var run = 0
            var previous: LocalDate? = null
            for (day in days) {
                run = if (previous != null && previous.plusDays(1) == day) run + 1 else 1
                longest = maxOf(longest, run)
                previous = day
            }
            val seconds = readingSeconds.filterKeys { it.year == year }
            val busiest = seconds.maxByOrNull { it.value }

            val byBook = chapters.groupingBy { it / 1_000 }.eachCount()
            val finished = byBook.count { (book, count) -> count >= BibleBooks.withNumber(book).chapterCount }
            // Most chapters; on a tie, the earlier book (as iOS).
            val topBook = byBook.entries.sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key }).firstOrNull()?.key

            fun inYear(millis: Long) = Instant.ofEpochMilli(millis).atZone(zone).year == year
            val yearHighlights = highlights.filter { inYear(it.createdAt) }
            val topHighlighted = yearHighlights.groupingBy { it.verse.book }.eachCount()
                .entries.sortedWith(compareByDescending<Map.Entry<Int, Int>> { it.value }.thenBy { it.key }).firstOrNull()?.key
            val favorite = yearHighlights.groupingBy { it.color }.eachCount()
                .entries.sortedWith(compareByDescending<Map.Entry<HighlightColor, Int>> { it.value }.thenBy { it.key.id }).firstOrNull()?.key

            return YearInReview(
                year = year,
                daysRead = days.size,
                longestStreak = longest,
                minutesRead = seconds.values.sum() / 60,
                longestDay = busiest?.key,
                longestDayMinutes = (busiest?.value ?: 0) / 60,
                chaptersRead = chapters.size,
                booksOpened = byBook.size,
                booksFinished = finished,
                topBook = topBook,
                highlights = yearHighlights.size,
                mostHighlightedBook = topHighlighted,
                favoriteColor = favorite,
                notes = notes.count(::inYear),
                prayersAdded = prayers.count { inYear(it.createdAt) },
                prayersAnswered = prayers.count { it.answeredAt?.let(::inYear) == true },
            )
        }

        /** Year in Review is offered through December and January. */
        fun isSeason(on: LocalDate = LocalDate.now()): Boolean = on.monthValue == 12 || on.monthValue == 1

        /** The year to review: in January, the one just ended. */
        fun reviewedYear(on: LocalDate = LocalDate.now()): Int = if (on.monthValue == 1) on.year - 1 else on.year

        /**
         * The year as calendar weeks (columns of seven from the first
         * weekday). Each cell is true when that day had reading, false when
         * not, and null before 1 January or after 31 December.
         */
        fun readingWeeks(year: Int, readingDays: Set<LocalDate>, firstDayOfWeek: DayOfWeek): List<List<Boolean?>> {
            val first = LocalDate.of(year, 1, 1)
            val leading = (first.dayOfWeek.value - firstDayOfWeek.value + 7) % 7
            val cells = MutableList<Boolean?>(leading) { null }
            var day = first
            while (day.year == year) {
                cells += day in readingDays
                day = day.plusDays(1)
            }
            while (cells.size % 7 != 0) cells += null
            return cells.chunked(7)
        }

        /** For each of the 66 books in order, the share of its chapters read (0..1). */
        fun bookShares(chapters: Set<Int>): List<Double> {
            val byBook = chapters.groupingBy { it / 1_000 }.eachCount()
            return BibleBooks.all.map { book -> minOf((byBook[book.id] ?: 0).toDouble() / maxOf(book.chapterCount, 1), 1.0) }
        }
    }
}
