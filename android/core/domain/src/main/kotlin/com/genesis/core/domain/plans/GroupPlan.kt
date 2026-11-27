package com.genesis.core.domain.plans

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/**
 * A group's reading plan, from the group's columns, as GroupSummary.plan
 * and planDay on iOS: a built-in plan by id, or a custom plan from its books
 * and day count (only real books and a sensible length, whatever the
 * server holds).
 */
object GroupPlan {
    fun plan(groupId: String, planId: String?, title: String?, books: List<Int>?, days: Int?): ReadingPlan? {
        planId?.let(ReadingPlan::builtIn)?.let { return it }
        val real = books.orEmpty().filter { it in 1..66 }
        if (real.isEmpty() || days == null || days !in 1..730) return null
        return ReadingPlan.custom(planId ?: "group-${groupId.lowercase()}", title ?: "", real, days)
    }

    /** Today's day (1-based), 0 before it starts; past the end it stays on the last day. */
    fun day(plan: ReadingPlan, start: LocalDate, today: LocalDate): Int {
        val days = ChronoUnit.DAYS.between(start, today)
        if (days < 0) return 0
        return minOf(days + 1, plan.dayCount.toLong()).toInt()
    }

    /** "yyyy-MM-dd" from the server, or null. */
    fun startDate(text: String?): LocalDate? = text?.take(10)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
}
