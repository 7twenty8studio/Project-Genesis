package com.genesis.core.domain.goals

import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** A daily reading goal: chapters or minutes, as ReadingGoal on iOS (same raw values). */
enum class ReadingGoal(val rawValue: String, val unit: Unit, val target: Int) {
    NONE("none", Unit.CHAPTERS, 0),
    ONE_CHAPTER("oneChapter", Unit.CHAPTERS, 1),
    THREE_CHAPTERS("threeChapters", Unit.CHAPTERS, 3),
    FIVE_MINUTES("fiveMinutes", Unit.MINUTES, 5),
    TEN_MINUTES("tenMinutes", Unit.MINUTES, 10),
    TWENTY_MINUTES("twentyMinutes", Unit.MINUTES, 20),
    ;

    enum class Unit { CHAPTERS, MINUTES }

    /** Today's progress, from chapters opened and seconds in the reader; null with no goal. */
    fun progress(chaptersToday: Int, secondsToday: Int): GoalProgress? {
        if (this == NONE) return null
        val done = if (unit == Unit.CHAPTERS) chaptersToday else secondsToday / 60
        return GoalProgress(this, minOf(done, target), target)
    }

    companion object {
        fun of(raw: String?): ReadingGoal = entries.firstOrNull { it.rawValue == raw } ?: NONE
    }
}

data class GoalProgress(val goal: ReadingGoal, val done: Int, val target: Int) {
    val isMet: Boolean get() = done >= target
    val fraction: Double get() = if (target > 0) done.toDouble() / target else 0.0
    val remaining: Int get() = maxOf(target - done, 0)
}

/** Reading streaks, with streak shields (ReadingStreak.walk on iOS). */
object ReadingStreak {
    data class Walk(val length: Int, val lastShield: LocalDate?)

    /**
     * Walking back from today (or yesterday, as today isn't missed yet), a
     * single missed day between two reading days is covered by a shield, at
     * most once in any seven days. Covered days keep the streak alive but
     * don't add to it. `lastShield` is the most recent covered day.
     */
    fun walk(days: Set<LocalDate>, endingOn: LocalDate, shields: Boolean): Walk {
        var day = if (endingOn in days) endingOn else endingOn.minusDays(1)
        var count = 0
        val covered = mutableListOf<LocalDate>()
        while (true) {
            if (day in days) {
                count++
            } else {
                if (!shields || day.minusDays(1) !in days) break
                val newer = covered.lastOrNull()
                if (newer != null && ChronoUnit.DAYS.between(day, newer) < 7) break
                covered += day
            }
            day = day.minusDays(1)
        }
        return Walk(count, covered.firstOrNull())
    }

    /** Whether a shield is ready: none used in the last seven days. */
    fun shieldReady(lastShield: LocalDate?, on: LocalDate): Boolean =
        lastShield == null || ChronoUnit.DAYS.between(lastShield, on) >= 7

    /** The longest run of consecutive reading days ever. */
    fun longest(days: Set<LocalDate>): Int {
        var best = 0
        var run = 0
        var previous: LocalDate? = null
        for (day in days.sorted()) {
            run = if (previous != null && previous.plusDays(1) == day) run + 1 else 1
            best = maxOf(best, run)
            previous = day
        }
        return best
    }
}

/** Something worth celebrating, once each (Milestone on iOS; same ids). */
data class Milestone(val kind: Kind, val count: Int) {
    enum class Kind(val rawValue: String) { STREAK("streak"), CHAPTERS("chapters"), BOOKS("books"), PRAYERS("prayers"), MEMORISED("memorised") }

    val id: String get() = "${kind.rawValue}.$count"
}

object Milestones {
    const val WHOLE_BIBLE_CHAPTERS = 1_189

    data class Stats(
        val longestStreak: Int = 0,
        val chapters: Int = 0,
        val books: Int = 0,
        val answeredPrayers: Int = 0,
        val memorised: Int = 0,
    )

    val steps: List<Pair<Milestone.Kind, List<Int>>> = listOf(
        Milestone.Kind.STREAK to listOf(3, 7, 30, 100, 365),
        Milestone.Kind.CHAPTERS to listOf(10, 50, 100, 250, 500, 1_000, WHOLE_BIBLE_CHAPTERS),
        Milestone.Kind.BOOKS to listOf(1, 5, 10, 25, 66),
        Milestone.Kind.PRAYERS to listOf(1, 10, 50),
        Milestone.Kind.MEMORISED to listOf(1, 10, 25),
    )

    private fun Stats.value(kind: Milestone.Kind) = when (kind) {
        Milestone.Kind.STREAK -> longestStreak
        Milestone.Kind.CHAPTERS -> chapters
        Milestone.Kind.BOOKS -> books
        Milestone.Kind.PRAYERS -> answeredPrayers
        Milestone.Kind.MEMORISED -> memorised
    }

    /** Every milestone reached, in the order above. */
    fun earned(stats: Stats): List<Milestone> =
        steps.flatMap { (kind, counts) -> counts.filter { stats.value(kind) >= it }.map { Milestone(kind, it) } }

    /** The next milestone of each kind. */
    fun next(stats: Stats): List<Milestone> {
        val earned = earned(stats).map { it.id }.toSet()
        return steps.mapNotNull { (kind, counts) -> counts.map { Milestone(kind, it) }.firstOrNull { it.id !in earned } }
    }

    data class Celebration(val show: Milestone?, val markQuietly: List<String>)

    /**
     * Reached but not yet celebrated. On the first look everything reached
     * so far is marked quietly (no parade for existing readers); after
     * that, one at a time, the last of the fresh ones.
     */
    fun toCelebrate(stats: Stats, celebrated: Set<String>, hasCelebratedAny: Boolean): Celebration {
        val fresh = earned(stats).filter { it.id !in celebrated }
        if (!hasCelebratedAny) return Celebration(null, fresh.map { it.id })
        return Celebration(fresh.lastOrNull(), emptyList())
    }
}
