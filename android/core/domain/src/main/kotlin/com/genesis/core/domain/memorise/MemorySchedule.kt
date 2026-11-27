package com.genesis.core.domain.memorise

import com.genesis.core.domain.bible.PassageReference
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.bible.BibleBooks
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** How well a review went. */
enum class MemoryGrade { AGAIN, HARD, GOOD, EASY }

enum class MemoryMastery {
    NEW, LEARNING, FAMILIAR, MEMORISED;

    /** 0…1 for a progress ring. */
    val fraction: Float get() = ordinal / 3f
}

/**
 * Spaced repetition (a gentle SM-2), as MemorySchedule on iOS: each good
 * review pushes the next one further out; forgetting brings it back the same
 * day. Times are milliseconds since 1970.
 */
data class MemorySchedule(
    val ease: Double = STARTING_EASE,
    val intervalDays: Double = 0.0,
    val repetitions: Int = 0,
    val dueAt: Long,
) {
    fun reviewed(grade: MemoryGrade, now: Long, zone: ZoneId = ZoneId.systemDefault()): MemorySchedule {
        var ease = ease
        val interval: Double
        when (grade) {
            MemoryGrade.AGAIN -> return copy(
                repetitions = 0,
                intervalDays = 0.0,
                ease = maxOf(MINIMUM_EASE, ease - 0.2),
                dueAt = now + 10 * 60 * 1000L,
            )
            MemoryGrade.HARD -> {
                interval = maxOf(1.0, intervalDays * 1.2)
                ease = maxOf(MINIMUM_EASE, ease - 0.15)
            }
            MemoryGrade.GOOD -> interval = when (repetitions) {
                0 -> 1.0
                1 -> 3.0
                else -> maxOf(intervalDays + 1, Math.rint(intervalDays * ease))
            }
            MemoryGrade.EASY -> {
                interval = if (repetitions == 0) 4.0 else maxOf(intervalDays + 2, Math.rint(intervalDays * ease * 1.3))
                ease += 0.15
            }
        }
        // Due at the start of that day, so a verse reviewed in the evening is ready in the morning.
        val day = Instant.ofEpochMilli(now).atZone(zone).toLocalDate()
        val due = day.plusDays(Math.round(interval)).atStartOfDay(zone).toInstant().toEpochMilli()
        return MemorySchedule(ease, interval, repetitions + 1, due)
    }

    val mastery: MemoryMastery get() = when {
        repetitions == 0 -> MemoryMastery.NEW
        intervalDays < 7 -> MemoryMastery.LEARNING
        intervalDays < 21 -> MemoryMastery.FAMILIAR
        else -> MemoryMastery.MEMORISED
    }

    companion object {
        const val STARTING_EASE = 2.5
        const val MINIMUM_EASE = 1.3
    }
}

/**
 * A passage being learned by heart (Premium), synced as memory_verses. Only
 * the reference and the schedule are kept; the words always come from the
 * Bible database in the chosen translation.
 */
data class MemoryVerse(
    val id: String,
    /** First and last verse (one chapter). */
    val start: VerseId,
    val end: VerseId,
    /** The translation being memorized, e.g. "KJV". */
    val translationId: String,
    val schedule: MemorySchedule,
    val lastReviewedAt: Long? = null,
    val reviewCount: Int = 0,
    val createdAt: Long,
    val updatedAt: Long,
) {
    fun isDue(now: Long = System.currentTimeMillis()): Boolean = now >= schedule.dueAt

    val mastery: MemoryMastery get() = schedule.mastery

    val reference: PassageReference
        get() = PassageReference(BibleBooks.withNumber(start.book), start.chapter, start.verse, end.verse)

    /** After a review: the next schedule, stamped. */
    fun reviewed(grade: MemoryGrade, now: Long): MemoryVerse =
        copy(schedule = schedule.reviewed(grade, now), lastReviewedAt = now, reviewCount = reviewCount + 1, updatedAt = now)
}

/** A hint for recalling a passage: its opening words, verbatim, then an ellipsis. Each step reveals a few more. */
object MemoryHint {
    const val WORDS_PER_STEP = 4

    private fun words(text: String) = text.split(' ').filter { it.isNotEmpty() }

    fun opening(text: String, words: Int): String {
        val all = words(text)
        if (words >= all.size) return text
        return all.take(maxOf(words, 1)).joinToString(" ") + "…"
    }

    fun isComplete(text: String, words: Int): Boolean = words >= words(text).size
}

/** Gentle levels by passages memorized, computed from the synced verses. */
enum class MemoryLevel(val threshold: Int) {
    SEED(0), SPROUT(1), SAPLING(5), TREE(12), CEDAR(25);

    val next: MemoryLevel? get() = entries.getOrNull(ordinal + 1)

    companion object {
        fun level(memorised: Int): MemoryLevel = entries.last { memorised >= it.threshold }

        /** 0…1 from this level's threshold to the next (1 at the top). */
        fun progress(memorised: Int): Float {
            val level = level(memorised)
            val next = level.next ?: return 1f
            return ((memorised - level.threshold).toFloat() / (next.threshold - level.threshold)).coerceIn(0f, 1f)
        }
    }
}

/** Days in a row with some Memorize practice (a review or a game), kept on this device only. */
data class PracticeStreak(val count: Int = 0, val longest: Int = 0, val lastDay: LocalDate? = null) {
    /** The streak on `today`: it lasts through the day after the last practice. */
    fun current(today: LocalDate): Int {
        val last = lastDay ?: return 0
        return if (java.time.temporal.ChronoUnit.DAYS.between(last, today) <= 1) count else 0
    }

    fun hasPractised(today: LocalDate): Boolean = lastDay == today

    /** After practising on `today`: unchanged later the same day, one longer the next day, back to 1 after a gap. */
    fun recording(today: LocalDate): PracticeStreak {
        val gap = lastDay?.let { java.time.temporal.ChronoUnit.DAYS.between(it, today) }
        val count = when {
            gap != null && gap <= 0 -> return this
            gap == 1L -> count + 1
            else -> 1
        }
        return PracticeStreak(count, maxOf(longest, count), today)
    }

    /** "count|longest|yyyy-MM-dd". */
    fun encode(): String = "$count|$longest|${lastDay ?: ""}"

    companion object {
        fun decode(text: String?): PracticeStreak {
            val parts = text?.split('|') ?: return PracticeStreak()
            if (parts.size != 3) return PracticeStreak()
            return PracticeStreak(
                parts[0].toIntOrNull() ?: 0,
                parts[1].toIntOrNull() ?: 0,
                runCatching { LocalDate.parse(parts[2]) }.getOrNull(),
            )
        }
    }
}

/** Some well-loved passages to begin with (references only), as MemoriseSuggestions on iOS. */
object MemoriseSuggestions {
    const val MAXIMUM_VERSES = 15

    private fun s(book: Int, chapter: Int, first: Int, last: Int = first) = VerseId(book, chapter, first) to VerseId(book, chapter, last)

    val all: List<Pair<VerseId, VerseId>> = listOf(
        s(43, 3, 16), // John 3:16
        s(19, 119, 105), // Psalm 119:105
        s(20, 3, 5, 6), // Proverbs 3:5–6
        s(6, 1, 9), // Joshua 1:9
        s(23, 40, 31), // Isaiah 40:31
        s(40, 11, 28), // Matthew 11:28
        s(45, 8, 28), // Romans 8:28
        s(50, 4, 6, 7), // Philippians 4:6–7
        s(19, 23, 1), // Psalm 23:1
        s(46, 13, 4, 7), // 1 Corinthians 13:4–7
    )
}
