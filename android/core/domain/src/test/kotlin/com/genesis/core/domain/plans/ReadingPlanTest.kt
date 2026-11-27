package com.genesis.core.domain.plans

import com.genesis.core.domain.bible.ChapterId
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The same cases as iOS's Phase2LogicTests (reading plans). */
class ReadingPlanTest {
    @Test
    fun builtInPlansCoverTheirBooksExactlyOnce() {
        for ((id, chapters, days) in listOf(
            Triple(ReadingPlan.ONE_YEAR, 1189, 365),
            Triple(ReadingPlan.CHRONOLOGICAL, 1189, 365),
            Triple(ReadingPlan.NEW_TESTAMENT_90, 260, 90),
            Triple(ReadingPlan.GOSPELS, 89, 30),
            Triple(ReadingPlan.PSALMS, 150, 30),
        )) {
            val plan = ReadingPlan.builtIn(id)!!
            assertEquals(days, plan.dayCount, id)
            val all = plan.days.flatMap { day -> day.spans.flatMap { it.chapters } }
            assertEquals(chapters, all.size, id)
            assertEquals(chapters, all.toSet().size, "$id: no chapter repeats")
            assertEquals((1..days).toList(), plan.days.map { it.number })
        }
    }

    @Test
    fun chronologicalOrderHasEveryBookOnce() {
        assertEquals((1..66).toList(), ReadingPlan.chronologicalBookOrder.sorted())
    }

    @Test
    fun dayTitlesReadNaturally() {
        assertEquals("Psalms 1–5", ReadingPlan.psalms.days[0].title("en"))
        val spans = ReadingPlan.spans(listOf(ChapterId(1, 50), ChapterId(2, 1), ChapterId(2, 2)))
        assertEquals("Genesis 50; Exodus 1–2", PlanDay(1, spans).title("en"))
        assertEquals("Jude", ChapterSpan(65, 1, 1).title("en"))
    }

    @Test
    fun splitIsEven() {
        val groups = ReadingPlan.split((1..10).toList(), 3)
        assertEquals(listOf(3, 3, 4), groups.map { it.size }.sorted())
        assertEquals((1..10).toList(), groups.flatten())
    }

    @Test
    fun customPlan() {
        val plan = ReadingPlan.custom("custom-1", "Paul", listOf(46, 45), 10)
        assertEquals(10, plan.dayCount)
        assertEquals(32, plan.days.flatMap { day -> day.spans.flatMap { it.chapters } }.size)
        assertEquals(32, plan.custom!!.chapterCount)
        assertEquals(listOf(45, 46), plan.custom!!.books)
    }

    @Test
    fun enrollmentsRebuildTheirPlan() {
        assertEquals(ReadingPlan.GOSPELS, PlanEnrollment("a", ReadingPlan.GOSPELS, "x", LocalDate.of(2026, 9, 1)).plan?.id)
        val custom = PlanEnrollment("b", "custom-9", "Paul", LocalDate.of(2026, 9, 1), customBooks = listOf(45), customDays = 4)
        assertEquals(4, custom.plan?.dayCount)
        assertEquals(null, PlanEnrollment("c", "unknown", "x", LocalDate.of(2026, 9, 1)).plan)
    }

    @Test
    fun progressThroughAPlan() {
        val progress = PlanProgress(ReadingPlan.gospels, LocalDate.of(2026, 9, 1), setOf(1, 2, 5))
        val today = LocalDate.of(2026, 9, 5)
        assertEquals(5, progress.scheduledDay(today))
        assertEquals(2, progress.daysBehind(today))
        // Today's reading is done, so the next unfinished day is offered.
        assertEquals(3, progress.todaysDay(today)?.number)
        assertEquals(0.1, progress.fractionComplete, 0.0001)
        assertFalse(progress.isComplete)
        assertEquals(1, progress.scheduledDay(LocalDate.of(2026, 8, 1)))
        assertTrue(PlanProgress(ReadingPlan.gospels, today, (1..30).toSet()).isComplete)
    }
}
