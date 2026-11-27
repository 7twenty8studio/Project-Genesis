package com.genesis.core.domain.insights

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ReadingStatsTest {
    private val day = LocalDate.of(2026, 11, 27)

    @Test
    fun sessionsAreClampedAndShortOnesDropped() {
        assertNull(ReadingStats.sessionSeconds(4))
        assertEquals(5, ReadingStats.sessionSeconds(5))
        assertEquals(45 * 60, ReadingStats.sessionSeconds(3 * 3600))
        assertNull(ReadingStats.sessionSeconds(-10))
    }

    @Test
    fun longestStreakFindsTheLongestRun() {
        val days = setOf(day, day.minusDays(1), day.minusDays(5), day.minusDays(6), day.minusDays(7), day.minusDays(30))
        assertEquals(3, ReadingStats.longestStreak(days))
        assertEquals(0, ReadingStats.longestStreak(emptySet()))
        // Across a month and a year.
        assertEquals(2, ReadingStats.longestStreak(setOf(LocalDate.of(2026, 12, 31), LocalDate.of(2027, 1, 1))))
    }

    @Test
    fun favoriteBooksAreTheMostReadFirst() {
        val chapters = setOf(43_001, 43_002, 43_003, 1_001, 19_023, 19_001)
        val books = ReadingStats.favoriteBooks(chapters)
        assertEquals(listOf(43, 19, 1), books.map { it.book.id })
        assertEquals(listOf(3, 2, 1), books.map { it.chapters })
        assertEquals(1, ReadingStats.favoriteBooks(chapters, limit = 1).size)
    }

    @Test
    fun booksCompletedNeedEveryChapter() {
        val jude = setOf(65_001)
        val obadiah = setOf(31_001)
        val partOfJohn = (1..20).map { 43_000 + it }.toSet()
        assertEquals(2, ReadingStats.booksCompleted(jude + obadiah + partOfJohn))
        assertEquals(1189, ReadingStats.totalChapters)
    }

    @Test
    fun dailyTimeIsOldestFirstWithEmptyDays() {
        val seconds = mapOf(day to 600, day.minusDays(2) to 120)
        val week = ReadingStats.dailyTime(seconds, 3, day)
        assertEquals(listOf(day.minusDays(2) to 120, day.minusDays(1) to 0, day to 600), week)
    }

    @Test
    fun secondsRoundTrip() {
        val seconds = mapOf(day to 600, day.minusDays(1) to 45)
        assertEquals(seconds, ReadingStats.decodeSeconds(ReadingStats.encodeSeconds(seconds)))
        assertEquals(mapOf(day to 1), ReadingStats.decodeSeconds(setOf("$day=1", "nonsense", "2026-02-30=4", "$day=")))
    }

    @Test
    fun hoursAndMinutes() {
        assertEquals(0 to 12, ReadingStats.hoursAndMinutes(12 * 60 + 59))
        assertEquals(3 to 5, ReadingStats.hoursAndMinutes(3 * 3600 + 5 * 60))
    }
}
