package com.genesis.core.domain.plans

import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.ChapterId
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** A contiguous run of chapters within one book, e.g. Genesis 1–3. */
data class ChapterSpan(val book: Int, val firstChapter: Int, val lastChapter: Int) {
    val first: ChapterId get() = ChapterId(book, firstChapter)

    val chapters: List<ChapterId> get() = (firstChapter..lastChapter).map { ChapterId(book, it) }

    /** "Genesis 1–3", "Psalms 23" or "Jude" (a one-chapter book), in a language. */
    fun title(language: String): String {
        val name = BibleBooks.withNumber(book).name(language)
        return when {
            BibleBooks.withNumber(book).chapterCount == 1 -> name
            firstChapter == lastChapter -> "$name $firstChapter"
            else -> "$name $firstChapter–$lastChapter"
        }
    }
}

/** One day's reading: one or more spans, e.g. "Genesis 1–3; Matthew 1". */
data class PlanDay(val number: Int, val spans: List<ChapterSpan>) {
    fun title(language: String): String = spans.joinToString("; ") { it.title(language) }

    val chapterCount: Int get() = spans.sumOf { it.lastChapter - it.firstChapter + 1 }
}

/**
 * A reading plan: a fixed schedule of chapters over a number of days, the
 * same schedules as ReadingPlan on iOS (so a plan started on one phone
 * continues on the other). Built-in plans' names and summaries come from the
 * app's strings by id; a custom plan keeps the name the person gave it.
 */
data class ReadingPlan(
    val id: String,
    val days: List<PlanDay>,
    /** The books and day count of a plan the person made, null for built-ins. */
    val custom: Custom? = null,
) {
    data class Custom(val title: String, val books: List<Int>, val days: Int) {
        val chapterCount: Int get() = books.sumOf { BibleBooks.withNumber(it).chapterCount }
    }

    val dayCount: Int get() = days.size

    val isBuiltIn: Boolean get() = custom == null

    companion object {
        const val ONE_YEAR = "one-year"
        const val NEW_TESTAMENT_90 = "nt-90"
        const val CHRONOLOGICAL = "chronological"
        const val GOSPELS = "gospels-30"
        const val PSALMS = "psalms-30"

        /** Books in the approximate order the events happened, as on iOS. */
        val chronologicalBookOrder: List<Int> = listOf(
            1, 18, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 19, 11, 20, 21, 22, 12, 14,
            31, 29, 32, 30, 28, 23, 33, 34, 36, 35, 24, 25, 26, 27, 15, 37, 38, 17, 16, 39,
            40, 41, 42, 43, 44, 59, 48, 52, 53, 46, 47, 45, 49, 50, 51, 57, 54, 56, 60, 58, 55, 61, 65, 62, 63, 64, 66,
        )

        /** The whole Bible in a year: an Old Testament and a New Testament reading each day. */
        val oneYear: ReadingPlan by lazy {
            val old = split(chapters((1..39).toList()), 365)
            val new = split(chapters((40..66).toList()), 365)
            ReadingPlan(ONE_YEAR, (0 until 365).map { PlanDay(it + 1, spans(old[it]) + spans(new[it])) })
        }
        val newTestament90: ReadingPlan by lazy { make(NEW_TESTAMENT_90, (40..66).toList(), 90) }
        val chronological: ReadingPlan by lazy { make(CHRONOLOGICAL, chronologicalBookOrder, 365) }
        val gospels: ReadingPlan by lazy { make(GOSPELS, listOf(40, 41, 42, 43), 30) }
        val psalms: ReadingPlan by lazy { make(PSALMS, listOf(19), 30) }

        val builtIns: List<ReadingPlan> get() = listOf(oneYear, newTestament90, chronological, gospels, psalms)

        fun builtIn(id: String): ReadingPlan? = builtIns.firstOrNull { it.id == id }

        /** A plan through chosen books (in canonical order) over a chosen number of days. */
        fun custom(id: String, title: String, books: List<Int>, days: Int): ReadingPlan {
            val ordered = books.distinct().sorted()
            return make(id, ordered, days).copy(custom = Custom(title, ordered, days))
        }

        /** What an enrollment's columns describe, as PlanEnrollment.plan on iOS. */
        fun of(planId: String, title: String, customBooks: List<Int>?, customDays: Int?): ReadingPlan? =
            if (customDays != null && !customBooks.isNullOrEmpty()) custom(planId, title, customBooks, customDays) else builtIn(planId)

        private fun make(id: String, books: List<Int>, days: Int): ReadingPlan =
            ReadingPlan(id, split(chapters(books), maxOf(1, days)).mapIndexed { index, part -> PlanDay(index + 1, spans(part)) })

        fun chapters(books: List<Int>): List<ChapterId> =
            books.flatMap { book -> (1..BibleBooks.withNumber(book).chapterCount).map { ChapterId(book, it) } }

        /** Splits items into `count` consecutive groups whose sizes differ by at most one. */
        fun <T> split(items: List<T>, count: Int): List<List<T>> {
            if (count <= 0) return emptyList()
            return (0 until count).map { index ->
                items.subList(index * items.size / count, (index + 1) * items.size / count)
            }
        }

        /** Groups consecutive chapters of the same book into spans. */
        fun spans(chapters: List<ChapterId>): List<ChapterSpan> {
            val result = mutableListOf<ChapterSpan>()
            for (chapter in chapters) {
                val last = result.lastOrNull()
                if (last != null && last.book == chapter.book && last.lastChapter + 1 == chapter.chapter) {
                    result[result.lastIndex] = last.copy(lastChapter = chapter.chapter)
                } else {
                    result += ChapterSpan(chapter.book, chapter.chapter, chapter.chapter)
                }
            }
            return result
        }
    }
}

/** Where someone is in a plan on a given day, as PlanProgress on iOS. */
data class PlanProgress(val plan: ReadingPlan, val startDate: LocalDate, val completedDays: Set<Int>) {
    /** The scheduled day for `date`, 1-based and clamped to the plan. */
    fun scheduledDay(on: LocalDate): Int {
        val elapsed = ChronoUnit.DAYS.between(startDate, on).toInt()
        return (elapsed + 1).coerceIn(1, maxOf(plan.dayCount, 1))
    }

    /** The first unfinished day, or null when the plan is complete. */
    val nextDay: Int? get() = (1..maxOf(plan.dayCount, 1)).firstOrNull { it !in completedDays }

    val fractionComplete: Double
        get() = if (plan.dayCount == 0) 0.0 else completedDays.count { it in 1..plan.dayCount }.toDouble() / plan.dayCount

    val isComplete: Boolean get() = nextDay == null

    /** Unfinished days scheduled before today (today's reading isn't late yet). */
    fun daysBehind(on: LocalDate): Int {
        val scheduled = scheduledDay(on)
        return (1 until scheduled).count { it !in completedDays }
    }

    /** Today's reading: the scheduled day if unfinished, otherwise the next unfinished day. */
    fun todaysDay(on: LocalDate): PlanDay? {
        val scheduled = scheduledDay(on)
        val number = if (scheduled in completedDays) nextDay ?: scheduled else scheduled
        return plan.days.firstOrNull { it.number == number }
    }
}

/**
 * Someone's place in a plan, as PlanEnrollment on iOS (synced as a
 * reading_plans row). Completed days are 1-based day numbers.
 */
data class PlanEnrollment(
    val id: String,
    val planId: String,
    val title: String,
    val startDate: LocalDate,
    val completedDays: Set<Int> = emptySet(),
    val customBooks: List<Int>? = null,
    val customDays: Int? = null,
    val isActive: Boolean = true,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
) {
    val plan: ReadingPlan? get() = ReadingPlan.of(planId, title, customBooks, customDays)

    val progress: PlanProgress? get() = plan?.let { PlanProgress(it, startDate, completedDays) }

    companion object {
        /** A new enrollment in a plan, starting on `date`. */
        fun start(plan: ReadingPlan, id: String, title: String, date: LocalDate) = PlanEnrollment(
            id = id,
            planId = plan.id,
            title = plan.custom?.title ?: title,
            startDate = date,
            customBooks = plan.custom?.books,
            customDays = plan.custom?.days,
        )
    }
}
