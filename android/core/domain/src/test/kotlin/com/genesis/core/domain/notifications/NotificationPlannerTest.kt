package com.genesis.core.domain.notifications

import com.genesis.core.domain.bible.VerseId
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NotificationPlannerTest {
    private val today = LocalDate.of(2026, 11, 27)
    private val morning = today.atTime(6, 0)

    private fun input(vararg kinds: ReminderKind, now: LocalDateTime = morning) =
        NotificationInput(now = now, settings = NotificationSettings(kinds.toSet()))

    @Test
    fun verseOfTheDayForEachDayWithItsVerse() {
        val verse = NotificationInput.VerseText("John 3:16 (KJV)", "For God so loved the world…", VerseId(43, 3, 16))
        val planned = NotificationPlanner.plan(input(ReminderKind.VERSE_OF_THE_DAY).copy(dailyVerses = mapOf(today to verse, today.plusDays(1) to verse)))
        assertEquals(2, planned.size)
        assertEquals(today.atTime(7, 0), planned[0].fireAt)
        assertEquals("versely.reminder.verseOfTheDay.2026-11-27", planned[0].id)
        assertEquals("versely://read/43003016", planned[0].link)
        assertEquals(ReminderMessage.VerseOfTheDay("John 3:16 (KJV)", "For God so loved the world…"), planned[0].message)
    }

    @Test
    fun aTimeAlreadyPassedTodayIsSkipped() {
        val planned = NotificationPlanner.plan(input(ReminderKind.DAILY_READING, now = today.atTime(21, 0)))
        assertEquals(6, planned.size)
        assertEquals(today.plusDays(1), planned.first().fireAt.toLocalDate())
    }

    @Test
    fun readingTodayDropsTodaysNudge() {
        val planned = NotificationPlanner.plan(input(ReminderKind.DAILY_READING).copy(readingDays = setOf(today)))
        assertTrue(planned.none { it.fireAt.toLocalDate() == today })
        assertEquals(6, planned.size)
    }

    @Test
    fun todaysNudgeIsKind() {
        val streak = input(ReminderKind.DAILY_READING).copy(readingDays = setOf(today.minusDays(1), today.minusDays(2)))
        assertEquals(ReminderMessage.Streak(2), NotificationPlanner.plan(streak).first().message)
        val one = input(ReminderKind.DAILY_READING).copy(readingDays = setOf(today.minusDays(1)))
        assertEquals(ReminderMessage.TwoDaysInARow, NotificationPlanner.plan(one).first().message)
        val away = input(ReminderKind.DAILY_READING).copy(readingDays = setOf(today.minusDays(5)))
        assertEquals(ReminderMessage.WelcomeBack, NotificationPlanner.plan(away).first().message)
        val later = NotificationPlanner.plan(away)[1].message
        assertTrue(later is ReminderMessage.Invitation)
    }

    @Test
    fun invitationsRotateAsOnIPhone() {
        // 1 January 2001 is day 730,486 of the era on iOS: 730486 % 4 = 2.
        val day = LocalDate.of(2001, 1, 1)
        assertEquals(ReminderMessage.Invitation(2), NotificationPlanner.readingMessage(1, day, input()))
        assertEquals(ReminderMessage.Invitation(3), NotificationPlanner.readingMessage(1, day.plusDays(1), input()))
    }

    @Test
    fun planRemindersOnlyForUnfinishedDays() {
        val planned = NotificationPlanner.plan(
            input(ReminderKind.READING_PLAN).copy(planTitle = "The Gospels in 30 Days", planReadings = mapOf(today.plusDays(1) to "Matthew 4–6")),
        )
        assertEquals(1, planned.size)
        assertEquals(ReminderMessage.PlanReading("The Gospels in 30 Days", "Matthew 4–6"), planned[0].message)
        assertEquals("versely://plans", planned[0].link)
        assertEquals(today.plusDays(1).atTime(8, 0), planned[0].fireAt)
    }

    @Test
    fun anniversariesAYearOrMoreLater() {
        val prayers = listOf(
            NotificationInput.AnsweredPrayer("New job", LocalDate.of(2024, 11, 28)),
            NotificationInput.AnsweredPrayer("Healing", LocalDate.of(2025, 11, 28)),
            NotificationInput.AnsweredPrayer("This year", LocalDate.of(2026, 11, 28)),
        )
        assertEquals(ReminderMessage.Anniversary(2, "New job", 1), NotificationPlanner.anniversary(LocalDate.of(2026, 11, 28), prayers))
        assertNull(NotificationPlanner.anniversary(LocalDate.of(2026, 11, 29), prayers))
        val leap = listOf(NotificationInput.AnsweredPrayer("Leap", LocalDate.of(2024, 2, 29)))
        assertEquals(ReminderMessage.Anniversary(2, "Leap", 0), NotificationPlanner.anniversary(LocalDate.of(2026, 2, 28), leap))
        assertNull(NotificationPlanner.anniversary(LocalDate.of(2028, 2, 28), leap))
    }

    @Test
    fun kindsLeftOffAreNotPlanned() {
        assertTrue(NotificationPlanner.plan(input()).isEmpty())
    }

    @Test
    fun prayerRemindersRingOnceOrDaily() {
        val now = today.atTime(10, 0)
        assertEquals(today.atTime(12, 0), NotificationPlanner.prayerReminder(false, today.atTime(12, 0), false, now))
        assertNull(NotificationPlanner.prayerReminder(false, today.atTime(9, 0), false, now))
        assertEquals(today.plusDays(1).atTime(9, 0), NotificationPlanner.prayerReminder(false, today.minusDays(3).atTime(9, 0), true, now))
        assertEquals(today.atTime(11, 0), NotificationPlanner.prayerReminder(false, today.minusDays(3).atTime(11, 0), true, now))
        assertNull(NotificationPlanner.prayerReminder(true, today.atTime(12, 0), false, now))
    }

    @Test
    fun almostThereWhenTodaysGoalIsPartlyDone() {
        val goal = com.genesis.core.domain.goals.ReadingGoal.THREE_CHAPTERS.progress(1, 0)
        val planned = NotificationPlanner.plan(input(ReminderKind.DAILY_READING).copy(readingDays = setOf(today), goalToday = goal))
        assertEquals(ReminderMessage.AlmostThere(goal!!), planned.first().message)
        assertEquals(today, planned.first().fireAt.toLocalDate())
        val met = com.genesis.core.domain.goals.ReadingGoal.ONE_CHAPTER.progress(1, 0)
        assertTrue(NotificationPlanner.plan(input(ReminderKind.DAILY_READING).copy(readingDays = setOf(today), goalToday = met)).none { it.fireAt.toLocalDate() == today })
    }

    @Test
    fun memoriseOnlyWhenSomethingIsDue() {
        val due = listOf(today.plusDays(2).atTime(9, 0), today.plusDays(2).atTime(15, 0))
        val planned = NotificationPlanner.plan(input(ReminderKind.MEMORISE).copy(memoryDueDates = due))
        // Day 2 at noon: one due; day 3 on: both.
        assertEquals(ReminderMessage.MemoriseDue(1), planned.first().message)
        assertEquals(today.plusDays(2).atTime(12, 0), planned.first().fireAt)
        assertEquals(ReminderMessage.MemoriseDue(2), planned[1].message)
        assertEquals(5, planned.size)
        assertEquals("versely://memorise", planned.first().link)
    }

    @Test
    fun sermonsAndRecapOnSundaysOnly() {
        val planned = NotificationPlanner.plan(input(ReminderKind.SERMONS, ReminderKind.WEEKLY_RECAP))
        assertEquals(2, planned.size)
        assertTrue(planned.all { it.fireAt.dayOfWeek == java.time.DayOfWeek.SUNDAY })
        assertEquals(LocalDate.of(2026, 11, 29).atTime(8, 30), planned[0].fireAt)
        assertEquals("versely://sermons", planned[0].link)
        assertEquals(ReminderMessage.WeeklyRecap, planned[1].message)
        assertEquals("versely://insights", planned[1].link)
    }

    @Test
    fun streakShieldKeepsTodaysStreakMessage() {
        val days = setOf(today.minusDays(1), today.minusDays(3), today.minusDays(4))
        val shielded = NotificationPlanner.plan(input(ReminderKind.DAILY_READING).copy(readingDays = days, streakShields = true))
        assertEquals(ReminderMessage.Streak(3), shielded.first().message)
        val plain = NotificationPlanner.plan(input(ReminderKind.DAILY_READING).copy(readingDays = days))
        assertEquals(ReminderMessage.TwoDaysInARow, plain.first().message)
    }
}
