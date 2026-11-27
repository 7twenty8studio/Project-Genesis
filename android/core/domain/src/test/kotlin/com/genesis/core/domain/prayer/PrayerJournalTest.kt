package com.genesis.core.domain.prayer

import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PrayerJournalTest {
    private val utc = ZoneOffset.UTC
    private fun at(day: Int, month: Int = 3, hour: Int = 9) =
        LocalDate.of(2026, month, day).atTime(hour, 0).toInstant(utc).toEpochMilli()

    @Test
    fun statistics() {
        val prayers = listOf(
            Prayer("a", title = "A", category = PrayerCategory.FAMILY, createdAt = at(1), isAnswered = true, answeredAt = at(4)),
            Prayer("b", title = "B", category = PrayerCategory.FAMILY, createdAt = at(1)),
            Prayer("c", title = "C", category = PrayerCategory.WORK, createdAt = at(2), isAnswered = true, answeredAt = at(2, hour = 10)),
            Prayer("d", category = PrayerCategory.HEALTH, createdAt = at(2)),
        )
        val stats = PrayerStatistics.of(prayers)
        assertEquals(3, stats.total)
        assertEquals(2, stats.answered)
        assertEquals(1, stats.active)
        assertEquals(67, stats.answeredPercent)
        assertEquals(listOf(PrayerCategory.FAMILY to 2, PrayerCategory.WORK to 1), stats.byCategory)
        assertEquals(1, stats.averageAnswerDays)
        assertNull(PrayerStatistics.of(emptyList()).averageDaysToAnswer)
        assertEquals(0, PrayerStatistics.of(emptyList()).answeredPercent)
    }

    @Test
    fun timelineByMonthNewestFirst() {
        val prayers = listOf(
            Prayer("a", title = "A", createdAt = at(30, month = 1), isAnswered = true, answeredAt = at(2, month = 3)),
            Prayer("b", title = "B", createdAt = at(5, month = 3)),
        )
        val months = PrayerTimeline.months(prayers, utc)
        assertEquals(listOf(YearMonth.of(2026, 3), YearMonth.of(2026, 1)), months.map { it.month })
        assertEquals(listOf("b" to PrayerTimeline.Kind.ASKED, "a" to PrayerTimeline.Kind.ANSWERED), months[0].entries.map { it.prayer.id to it.kind })
    }

    @Test
    fun streakCountsTodayOrThroughYesterday() {
        val today = LocalDate.of(2026, 3, 10)
        val days = setOf(today.minusDays(1), today.minusDays(2), today.minusDays(4))
        assertEquals(2, PrayerStreak.length(days, today))
        assertEquals(3, PrayerStreak.length(days + today, today))
        assertEquals(0, PrayerStreak.length(setOf(today.minusDays(2)), today))
        val fromPrayers = PrayerStreak.days(emptySet(), listOf(Prayer("a", title = "A", createdAt = at(9), lastPrayedAt = at(10))), utc)
        assertEquals(setOf(LocalDate.of(2026, 3, 9), LocalDate.of(2026, 3, 10)), fromPrayers)
    }

    @Test
    fun logKeepsRecentDays() {
        val today = LocalDate.of(2026, 3, 10)
        val raw = PrayerStreak.recording(today, "2024-01-01,2026-03-09,junk")
        assertEquals("2026-03-09,2026-03-10", raw)
        assertEquals(setOf(today, today.minusDays(1)), PrayerStreak.decodeLog(raw))
    }
}
