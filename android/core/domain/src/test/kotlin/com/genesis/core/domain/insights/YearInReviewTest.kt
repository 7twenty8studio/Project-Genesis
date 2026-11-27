package com.genesis.core.domain.insights

import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.HighlightColor
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class YearInReviewTest {
    private fun millis(date: LocalDate) = date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli() + 3_600_000

    @Test fun countsTheYear() {
        val days = setOf(LocalDate.of(2026, 3, 1), LocalDate.of(2026, 3, 2), LocalDate.of(2026, 3, 3), LocalDate.of(2026, 5, 1), LocalDate.of(2025, 12, 31))
        val review = YearInReview.make(
            year = 2026,
            readingDays = days,
            readingSeconds = mapOf(LocalDate.of(2026, 3, 1) to 600, LocalDate.of(2026, 3, 2) to 1_800, LocalDate.of(2025, 12, 31) to 9_000),
            // All of Jude (1 chapter), two of Romans.
            chapters = setOf(65_001, 45_001, 45_002),
            highlights = listOf(
                YearInReview.HighlightRecord(millis(LocalDate.of(2026, 4, 1)), VerseId(45, 8, 28), HighlightColor.BLUE),
                YearInReview.HighlightRecord(millis(LocalDate.of(2026, 4, 2)), VerseId(45, 8, 29), HighlightColor.BLUE),
                YearInReview.HighlightRecord(millis(LocalDate.of(2025, 4, 2)), VerseId(1, 1, 1), HighlightColor.YELLOW),
            ),
            notes = listOf(millis(LocalDate.of(2026, 1, 9))),
            prayers = listOf(YearInReview.PrayerRecord(millis(LocalDate.of(2025, 6, 1)), millis(LocalDate.of(2026, 2, 1)))),
            zone = ZoneOffset.UTC,
        )
        assertEquals(4, review.daysRead)
        assertEquals(3, review.longestStreak)
        assertEquals(40, review.minutesRead)
        assertEquals(LocalDate.of(2026, 3, 2), review.longestDay)
        assertEquals(30, review.longestDayMinutes)
        assertEquals(1, review.booksFinished)
        assertEquals(45, review.topBook)
        assertEquals(2, review.highlights)
        assertEquals(45, review.mostHighlightedBook)
        assertEquals(HighlightColor.BLUE, review.favoriteColor)
        assertEquals(1, review.notes)
        assertEquals(0, review.prayersAdded)
        assertEquals(1, review.prayersAnswered)
        assertTrue(review.hasActivity)
    }

    @Test fun emptyYear() {
        val review = YearInReview.make(2026, emptySet(), emptyMap(), emptySet(), emptyList(), emptyList(), emptyList())
        assertFalse(review.hasActivity)
        assertNull(review.topBook)
    }

    @Test fun season() {
        assertTrue(YearInReview.isSeason(LocalDate.of(2026, 12, 3)))
        assertTrue(YearInReview.isSeason(LocalDate.of(2027, 1, 20)))
        assertFalse(YearInReview.isSeason(LocalDate.of(2026, 11, 27)))
        assertEquals(2026, YearInReview.reviewedYear(LocalDate.of(2027, 1, 20)))
        assertEquals(2026, YearInReview.reviewedYear(LocalDate.of(2026, 12, 20)))
    }

    @Test fun weeks() {
        // 2026 starts on a Thursday: three empty cells before it in a Monday week.
        val weeks = YearInReview.readingWeeks(2026, setOf(LocalDate.of(2026, 1, 1)), DayOfWeek.MONDAY)
        assertEquals(listOf(null, null, null, true, false, false, false), weeks.first())
        assertEquals(365, weeks.flatten().count { it != null })
    }

    @Test fun shares() {
        val shares = YearInReview.bookShares(setOf(65_001, 45_001))
        assertEquals(66, shares.size)
        assertEquals(1.0, shares[64])
        assertEquals(1.0 / 16, shares[44], 1e-9)
    }
}
