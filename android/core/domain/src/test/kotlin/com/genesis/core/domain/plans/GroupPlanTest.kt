package com.genesis.core.domain.plans

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GroupPlanTest {
    @Test fun builtInById() {
        assertEquals(ReadingPlan.GOSPELS, GroupPlan.plan("g", "gospels-30", "Gospels", null, null)?.id)
    }

    @Test fun customFromBooksAndDays() {
        val plan = GroupPlan.plan("ABC", null, "Romans", listOf(45, 99), 8)!!
        assertEquals("group-abc", plan.id)
        assertEquals(8, plan.dayCount)
        assertEquals(listOf(45), plan.custom?.books)
    }

    @Test fun noPlanWithoutSensibleColumns() {
        assertNull(GroupPlan.plan("g", null, null, null, null))
        assertNull(GroupPlan.plan("g", "x", null, listOf(45), 0))
        assertNull(GroupPlan.plan("g", "x", null, listOf(45), 731))
        assertNull(GroupPlan.plan("g", "x", null, listOf(70), 10))
    }

    @Test fun dayCountsFromTheStart() {
        val plan = ReadingPlan.gospels
        val start = LocalDate.of(2026, 11, 20)
        assertEquals(0, GroupPlan.day(plan, start, LocalDate.of(2026, 11, 19)))
        assertEquals(1, GroupPlan.day(plan, start, start))
        assertEquals(8, GroupPlan.day(plan, start, LocalDate.of(2026, 11, 27)))
        assertEquals(30, GroupPlan.day(plan, start, LocalDate.of(2027, 6, 1)))
    }

    @Test fun readsStartDates() {
        assertEquals(LocalDate.of(2026, 11, 20), GroupPlan.startDate("2026-11-20"))
        assertNull(GroupPlan.startDate("soon"))
    }
}
