package com.genesis.core.cloud

import com.genesis.core.cloud.community.ChallengeChapters
import com.genesis.core.cloud.community.ChallengeDraft
import com.genesis.core.cloud.community.ChallengeKind
import com.genesis.core.cloud.community.ChallengeProgress
import com.genesis.core.cloud.community.ChallengeStatus
import com.genesis.core.cloud.community.ChallengeStreak
import com.genesis.core.cloud.community.ChallengeSummary
import com.genesis.core.cloud.community.GroupChallenge
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ChallengesTest {
    private val start = LocalDate.of(2026, 11, 20)
    private fun challenge(kind: ChallengeKind, days: Int = 7, chapters: List<Int> = emptyList(), ended: String? = null) =
        GroupChallenge("c", "g", null, kind, "t", "", start, days, chapters, endedAt = ended)

    @Test fun statusFollowsTheCalendar() {
        val c = challenge(ChallengeKind.STREAK)
        assertEquals(ChallengeStatus.UPCOMING, c.status(start.minusDays(1)))
        assertEquals(ChallengeStatus.RUNNING, c.status(start))
        assertEquals(ChallengeStatus.RUNNING, c.status(start.plusDays(6)))
        assertEquals(ChallengeStatus.FINISHED, c.status(start.plusDays(7)))
        assertEquals(ChallengeStatus.FINISHED, challenge(ChallengeKind.STREAK, ended = "2026-11-21T00:00:00Z").status(start))
        assertEquals(LocalDate.of(2026, 11, 26), c.end)
    }

    @Test fun ticksAsTheServerAllows() {
        val daily = challenge(ChallengeKind.PRAYER)
        assertTrue(daily.canTick(1, start))
        assertTrue(daily.canTick(2, start)) // a day's slack for time zones
        assertFalse(daily.canTick(3, start))
        val reading = challenge(ChallengeKind.READING, chapters = listOf(41001, 41002))
        assertTrue(reading.canTick(41002, start))
        assertFalse(reading.canTick(41003, start))
        assertFalse(challenge(ChallengeKind.PRAYER, ended = "x").canTick(1, start))
    }

    @Test fun streaks() {
        assertEquals(3, ChallengeStreak.current(setOf(2, 3, 4), 4))
        assertEquals(3, ChallengeStreak.current(setOf(2, 3, 4), 5))
        assertEquals(0, ChallengeStreak.current(setOf(1, 2), 5))
        assertTrue(ChallengeStreak.isAlive(emptySet(), 1))
        assertFalse(ChallengeStreak.isAlive(setOf(1), 3))
    }

    @Test fun summaryWithoutRanking() {
        val c = challenge(ChallengeKind.READING, chapters = listOf(41001, 41002, 41003, 41004))
        val rows = listOf(ChallengeProgress("ME", "Me", 2, listOf(41001, 41002)), ChallengeProgress("you", "You", 4))
        val summary = ChallengeSummary.of(c, rows, "me", start)
        assertEquals(2, summary.myDone)
        assertEquals(6, summary.groupDone)
        assertEquals(0.75f, summary.groupFraction)
        assertEquals(setOf(41001, 41002), summary.myItems)
    }

    @Test fun chapterRangesStayInTheBook() {
        assertEquals(listOf(41015, 41016), ChallengeChapters.range(41, 15, 99, 16))
        assertEquals(emptyList(), ChallengeChapters.range(70, 1, 2, 3))
    }

    @Test fun draftsMatchTheServerRules() {
        val draft = ChallengeDraft(ChallengeKind.STREAK, "Read daily", "", start, 21)
        assertTrue(draft.isValid(start))
        assertFalse(draft.copy(title = " ").isValid(start))
        assertFalse(draft.copy(days = 91).isValid(start))
        assertFalse(draft.copy(start = start.plusDays(61)).isValid(start))
        assertFalse(draft.copy(kind = ChallengeKind.READING).isValid(start))
        assertTrue(draft.copy(kind = ChallengeKind.MEMORISE, verseStart = 19023001, verseEnd = 19023003, translationId = "KJV").isValid(start))
    }
}
