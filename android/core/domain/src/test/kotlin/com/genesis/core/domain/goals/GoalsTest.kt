package com.genesis.core.domain.goals

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFalse

class GoalsTest {
    private val today = LocalDate.of(2026, 11, 27)
    private fun days(vararg back: Long) = back.map { today.minusDays(it) }.toSet()

    @Test fun goalProgress() {
        assertNull(ReadingGoal.NONE.progress(3, 600))
        val chapters = ReadingGoal.THREE_CHAPTERS.progress(1, 0)!!
        assertEquals(2, chapters.remaining)
        assertFalse(chapters.isMet)
        val minutes = ReadingGoal.TEN_MINUTES.progress(0, 15 * 60)!!
        assertEquals(10, minutes.done)
        assertTrue(minutes.isMet)
        assertEquals(ReadingGoal.FIVE_MINUTES, ReadingGoal.of("fiveMinutes"))
        assertEquals(ReadingGoal.NONE, ReadingGoal.of("nonsense"))
    }

    @Test fun streakWithoutShields() {
        assertEquals(3, ReadingStreak.walk(days(0, 1, 2, 4), today, false).length)
        // Today not read yet: the streak runs to yesterday.
        assertEquals(2, ReadingStreak.walk(days(1, 2), today, false).length)
        assertEquals(0, ReadingStreak.walk(days(2, 3), today, false).length)
    }

    @Test fun shieldCoversOneMissedDay() {
        val walk = ReadingStreak.walk(days(0, 1, 3, 4), today, true)
        assertEquals(4, walk.length)
        assertEquals(today.minusDays(2), walk.lastShield)
        assertFalse(ReadingStreak.shieldReady(walk.lastShield, today))
        // Two days missed in a row: no shield.
        assertEquals(2, ReadingStreak.walk(days(0, 1, 4, 5), today, true).length)
    }

    @Test fun oneShieldPerWeek() {
        // Missed 2 and 5 days ago: only the newer is covered.
        assertEquals(4, ReadingStreak.walk(days(0, 1, 3, 4, 6, 7), today, true).length)
        // Missed 2 and 10 days ago: both covered.
        val far = days(0, 1, 3, 4, 5, 6, 7, 8, 9, 11, 12)
        assertEquals(11, ReadingStreak.walk(far, today, true).length)
        assertTrue(ReadingStreak.shieldReady(today.minusDays(7), today))
    }

    @Test fun longestStreak() {
        assertEquals(3, ReadingStreak.longest(days(0, 1, 5, 6, 7)))
        assertEquals(0, ReadingStreak.longest(emptySet()))
    }

    @Test fun milestones() {
        val stats = Milestones.Stats(longestStreak = 8, chapters = 12, books = 1)
        assertEquals(listOf("streak.3", "streak.7", "chapters.10", "books.1"), Milestones.earned(stats).map { it.id })
        assertEquals(listOf("streak.30", "chapters.50", "books.5", "prayers.1", "memorised.1"), Milestones.next(stats).map { it.id })
        val first = Milestones.toCelebrate(stats, emptySet(), hasCelebratedAny = false)
        assertNull(first.show)
        assertEquals(4, first.markQuietly.size)
        val later = Milestones.toCelebrate(stats.copy(chapters = 50), first.markQuietly.toSet(), hasCelebratedAny = true)
        assertEquals("chapters.50", later.show?.id)
    }
}
