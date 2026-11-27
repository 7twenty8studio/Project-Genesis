package com.genesis.core.domain.home

import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.VerseId
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * The verse of the day from a curated list, the same for everyone on a date
 * and offline: exactly DailyVerse.swift, so an iPhone and an Android phone
 * side by side show the same verse.
 */
object DailyVerse {
    fun verse(date: LocalDate, zone: ZoneId): VerseId {
        // Whole days between local midnights, counted from the local day of
        // 1 January 2001 00:00 UTC (iOS's reference date), as iOS counts.
        val reference = Instant.parse("2001-01-01T00:00:00Z").atZone(zone).toLocalDate()
        val day = ChronoUnit.DAYS.between(reference, date)
        return curated[Math.floorMod(day, curated.size.toLong()).toInt()]
    }

    /** Well-loved verses that stand on their own. Book, chapter, verse. */
    val curated: List<VerseId> = listOf(
        Triple(43, 3, 16), Triple(19, 23, 1), Triple(20, 3, 5), Triple(23, 40, 31), Triple(45, 8, 28), Triple(50, 4, 13),
        Triple(24, 29, 11), Triple(6, 1, 9), Triple(19, 46, 1), Triple(40, 11, 28), Triple(50, 4, 6), Triple(45, 12, 2),
        Triple(58, 11, 1), Triple(46, 13, 4), Triple(48, 5, 22), Triple(19, 119, 105), Triple(25, 3, 22), Triple(23, 41, 10),
        Triple(40, 6, 33), Triple(43, 14, 27), Triple(45, 15, 13), Triple(49, 2, 8), Triple(60, 5, 7), Triple(19, 34, 18),
        Triple(20, 16, 3), Triple(47, 5, 17), Triple(51, 3, 23), Triple(59, 1, 5), Triple(62, 4, 19), Triple(19, 37, 4),
        Triple(33, 6, 8), Triple(43, 16, 33), Triple(45, 5, 8), Triple(19, 27, 1), Triple(23, 26, 3), Triple(40, 5, 9),
        Triple(50, 4, 7), Triple(58, 12, 1), Triple(19, 90, 12), Triple(21, 3, 1), Triple(34, 1, 7), Triple(36, 3, 17),
        Triple(43, 15, 5), Triple(44, 1, 8), Triple(46, 16, 14), Triple(47, 12, 9), Triple(54, 4, 12), Triple(55, 1, 7),
        Triple(19, 139, 14), Triple(40, 28, 20), Triple(42, 1, 37), Triple(43, 8, 12), Triple(45, 10, 9), Triple(62, 1, 9),
        Triple(19, 16, 11), Triple(20, 18, 10), Triple(23, 43, 2), Triple(5, 31, 6), Triple(19, 121, 1), Triple(66, 21, 4),
    ).map { (book, chapter, verse) -> VerseId(book, chapter, verse) }
}

/** The line at the top of Home, by the hour, as HomeGreeting on iOS. */
enum class Greeting {
    MORNING, AFTERNOON, EVENING;

    companion object {
        fun at(hour: Int): Greeting = when (hour) {
            in 4..11 -> MORNING
            in 12..16 -> AFTERNOON
            else -> EVENING
        }
    }
}

/** How far through its book a reading position is, as ReadingProgress on iOS. */
fun progressThroughBook(position: VerseId): Double {
    val book = BibleBooks.withNumber(position.book)
    return (position.chapter - 1).toDouble() / maxOf(book.chapterCount, 1)
}
