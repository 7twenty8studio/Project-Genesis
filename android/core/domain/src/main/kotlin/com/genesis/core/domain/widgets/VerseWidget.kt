package com.genesis.core.domain.widgets

import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.OriginalVersification
import com.genesis.core.domain.bible.PassageReference
import com.genesis.core.domain.bible.VerseId
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** The themes a Premium verse widget can follow. The raw values are saved in widget settings: never change them. */
enum class VerseCategory(val raw: String) {
    HOPE("hope"), PEACE("peace"), FAITH("faith"), STRENGTH("strength"),
    COMFORT("comfort"), LOVE("love"), GRATITUDE("gratitude"), GUIDANCE("guidance"),
}

/** What the verse widget shows, as VerseWidgetSource on iOS. The raw values are saved in widget settings. */
enum class VerseWidgetSource(val raw: String) {
    /** The default, and what widgets placed before the options show. */
    VERSE_OF_THE_DAY("verseOfTheDay"),
    /** A different encouraging verse every few hours (free). */
    RANDOM("random"),
    /** A verse from a chapter read in the last week (Premium). */
    FROM_YOUR_READING("fromYourReading"),
    HOPE("hope"), PEACE("peace"), FAITH("faith"), STRENGTH("strength"),
    COMFORT("comfort"), LOVE("love"), GRATITUDE("gratitude"), GUIDANCE("guidance");

    val category: VerseCategory? get() = VerseCategory.entries.firstOrNull { it.raw == raw }

    /** Verse of the Day and Random Verse are free; the rest need Premium. */
    val needsPremium: Boolean get() = this != VERSE_OF_THE_DAY && this != RANDOM

    /** Random verses and categories change every few hours; the others daily. */
    val rotates: Boolean get() = this == RANDOM || category != null

    companion object {
        fun of(raw: String?): VerseWidgetSource = entries.firstOrNull { it.raw == raw } ?: VERSE_OF_THE_DAY
    }
}

/** When the verse widget changes: rotating options every three hours (eight a day), the others at local midnight. */
object VerseWidgetSchedule {
    const val HOURS_PER_VERSE = 3
    const val VERSES_PER_DAY = 24 / HOURS_PER_VERSE

    /**
     * Whole days from the same local midnight iOS counts from (the local day
     * of 1 January 2001, 00:00 UTC), so a day's choice matches the iPhone's.
     */
    fun dayNumber(date: LocalDate, zone: ZoneId): Int {
        val reference = Instant.parse("2001-01-01T00:00:00Z").atZone(zone).toLocalDate()
        return ChronoUnit.DAYS.between(reference, date).toInt()
    }

    /** The three-hour block a moment falls in, counted from the same midnight. */
    fun slot(at: LocalDateTime, zone: ZoneId): Int = dayNumber(at.toLocalDate(), zone) * VERSES_PER_DAY + at.hour / HOURS_PER_VERSE

    /** The pool item for a moment: the next one every three hours. */
    fun index(at: LocalDateTime, count: Int, zone: ZoneId): Int? {
        if (count <= 0) return null
        val slot = slot(at, zone)
        return ((slot % count) + count) % count
    }

    /** When the widget next changes: the next three-hour block, or the next midnight. */
    fun nextChange(after: LocalDateTime, rotates: Boolean): LocalDateTime {
        val day = after.toLocalDate().atStartOfDay()
        if (!rotates) return day.plusDays(1)
        val block = after.hour / HOURS_PER_VERSE
        return day.plusHours(((block + 1) * HOURS_PER_VERSE).toLong())
    }
}

/** A whole verse or a short passage (at most three verses, one chapter). Ids only. */
data class CategoryPassage(val start: VerseId, val end: VerseId) {
    val verseIds: List<VerseId> get() = (start.verse..end.verse).map { VerseId(start.book, start.chapter, it) }
    val reference: PassageReference
        get() = PassageReference(BibleBooks.withNumber(start.book), start.chapter, start.verse, if (end.verse == start.verse) null else end.verse)
}

/**
 * The verse widget's themes (Premium) and, all together, the pool its free
 * Random Verse draws from, as VerseCategories on iOS (generated from it):
 * well-known verses that stand on their own, whole sentences in the KJV, no
 * psalm titles. Checked by Tools/WidgetData/check_verse_categories.py.
 */
object VerseCategories {
    fun passages(category: VerseCategory): List<CategoryPassage> = when (category) {
        VerseCategory.HOPE -> hope
        VerseCategory.PEACE -> peace
        VerseCategory.FAITH -> faith
        VerseCategory.STRENGTH -> strength
        VerseCategory.COMFORT -> comfort
        VerseCategory.LOVE -> love
        VerseCategory.GRATITUDE -> gratitude
        VerseCategory.GUIDANCE -> guidance
    }

    /** Every category's passages, each once, in category order. */
    val encouraging: List<CategoryPassage> by lazy { VerseCategory.entries.flatMap(::passages).distinct() }

    private fun p(book: Int, chapter: Int, verse: Int, through: Int) = CategoryPassage(VerseId(book, chapter, verse), VerseId(book, chapter, through))

    private val hope = listOf(
        p(45, 15, 13, 13), p(24, 29, 11, 11), p(25, 3, 22, 23), p(25, 3, 24, 24), p(25, 3, 25, 25), p(19, 42, 11, 11),
        p(19, 31, 24, 24), p(19, 39, 7, 7), p(19, 62, 5, 5), p(19, 71, 14, 14), p(19, 130, 5, 5), p(20, 23, 18, 18),
        p(45, 5, 5, 5), p(45, 8, 28, 28), p(66, 21, 4, 4), p(33, 7, 7, 7), p(19, 147, 11, 11), p(45, 15, 4, 4),
        p(19, 33, 22, 22), p(23, 43, 19, 19), p(19, 16, 9, 9),
    )

    private val peace = listOf(
        p(43, 14, 27, 27), p(50, 4, 6, 7), p(23, 26, 3, 3), p(4, 6, 24, 26), p(19, 4, 8, 8), p(43, 16, 33, 33),
        p(51, 3, 15, 15), p(53, 3, 16, 16), p(19, 29, 11, 11), p(23, 32, 17, 17), p(19, 119, 165, 165), p(19, 3, 5, 5),
        p(23, 54, 10, 10), p(19, 46, 10, 10), p(2, 14, 14, 14), p(19, 37, 37, 37), p(23, 9, 6, 6), p(19, 23, 2, 3),
        p(42, 2, 14, 14), p(23, 26, 12, 12), p(19, 116, 7, 7),
    )

    private val faith = listOf(
        p(58, 11, 1, 1), p(58, 11, 6, 6), p(45, 10, 17, 17), p(49, 2, 8, 9), p(41, 9, 23, 23), p(48, 2, 20, 20),
        p(62, 5, 4, 4), p(40, 19, 26, 26), p(58, 12, 2, 2), p(43, 11, 25, 26), p(43, 20, 29, 29), p(19, 56, 3, 3),
        p(19, 37, 5, 5), p(19, 9, 10, 10), p(24, 17, 7, 7), p(48, 3, 26, 26), p(42, 1, 37, 37), p(46, 16, 13, 13),
        p(49, 6, 16, 16), p(41, 11, 24, 24), p(19, 20, 7, 7),
    )

    private val strength = listOf(
        p(23, 40, 29, 29), p(50, 4, 13, 13), p(23, 41, 10, 10), p(6, 1, 9, 9), p(47, 12, 9, 9), p(19, 28, 7, 7),
        p(19, 73, 26, 26), p(5, 31, 6, 6), p(19, 18, 32, 32), p(23, 12, 2, 2), p(49, 6, 10, 10), p(55, 1, 7, 7),
        p(19, 27, 14, 14), p(13, 16, 11, 11), p(19, 118, 14, 14), p(19, 138, 3, 3), p(10, 22, 33, 33), p(19, 62, 7, 7),
        p(19, 121, 2, 2), p(23, 40, 31, 31),
    )

    private val comfort = listOf(
        p(40, 11, 28, 28), p(60, 5, 7, 7), p(19, 34, 18, 18), p(40, 5, 4, 4), p(47, 1, 3, 4), p(19, 147, 3, 3),
        p(19, 23, 4, 4), p(43, 14, 1, 1), p(23, 41, 13, 13), p(19, 55, 22, 22), p(23, 43, 2, 2), p(19, 94, 19, 19),
        p(40, 6, 34, 34), p(23, 66, 13, 13), p(19, 30, 5, 5), p(19, 34, 4, 4), p(5, 31, 8, 8), p(19, 121, 7, 8),
        p(45, 8, 38, 39), p(19, 9, 9, 9), p(34, 1, 7, 7), p(23, 40, 11, 11), p(40, 6, 26, 26), p(19, 56, 8, 8),
        p(43, 14, 18, 18),
    )

    private val love = listOf(
        p(43, 3, 16, 16), p(62, 4, 19, 19), p(62, 4, 7, 8), p(62, 4, 16, 16), p(45, 5, 8, 8), p(46, 13, 13, 13),
        p(24, 31, 3, 3), p(36, 3, 17, 17), p(43, 15, 13, 13), p(43, 13, 34, 35), p(62, 3, 1, 1), p(60, 4, 8, 8),
        p(51, 3, 14, 14), p(45, 13, 10, 10), p(19, 103, 11, 11), p(62, 4, 18, 18), p(48, 5, 22, 23), p(41, 12, 30, 31),
        p(43, 15, 9, 9), p(46, 16, 14, 14), p(19, 63, 3, 3), p(19, 86, 15, 15),
    )

    private val gratitude = listOf(
        p(52, 5, 16, 18), p(19, 107, 1, 1), p(19, 118, 24, 24), p(19, 100, 4, 5), p(51, 3, 17, 17), p(19, 136, 1, 1),
        p(51, 2, 6, 7), p(19, 95, 2, 2), p(19, 106, 1, 1), p(13, 16, 34, 34), p(59, 1, 17, 17), p(47, 9, 15, 15),
        p(19, 150, 6, 6), p(46, 15, 57, 57), p(19, 139, 14, 14), p(19, 126, 3, 3), p(19, 30, 12, 12), p(19, 105, 1, 1),
        p(19, 147, 1, 1), p(19, 68, 19, 19), p(19, 145, 9, 9), p(19, 23, 6, 6),
    )

    private val guidance = listOf(
        p(19, 32, 8, 8), p(23, 30, 21, 21), p(59, 1, 5, 5), p(20, 16, 9, 9), p(19, 25, 4, 5), p(19, 37, 23, 23),
        p(24, 33, 3, 3), p(23, 58, 11, 11), p(19, 143, 8, 8), p(20, 16, 3, 3), p(19, 16, 11, 11), p(43, 16, 13, 13),
        p(19, 48, 14, 14), p(19, 73, 24, 24), p(23, 42, 16, 16), p(20, 2, 6, 6), p(23, 48, 17, 17), p(19, 25, 9, 9),
        p(45, 12, 2, 2), p(43, 8, 12, 12), p(19, 31, 3, 3), p(33, 6, 8, 8), p(19, 86, 11, 11), p(20, 3, 5, 6),
    )
}

/** The verse widget's pools, as WidgetVerses on iOS: the same verses at the same times on both phones. */
object WidgetVerses {
    /** How many passages Random Verse rotates through in a day. */
    const val RANDOM_POOL_SIZE = 24

    /** A fixed scramble of a number (splitmix64), so pools look random but are the same everywhere. */
    fun mix(value: Int): Long {
        var x = value.toLong().toULong() + 0x9E3779B97F4A7C15uL
        x = (x xor (x shr 30)) * 0xBF58476D1CE4E5B9uL
        x = (x xor (x shr 27)) * 0x94D049BB133111EBuL
        x = x xor (x shr 31)
        return (x % Long.MAX_VALUE.toULong()).toLong()
    }

    /** The encouraging passages in a fixed mixed-up order. */
    val shuffled: List<CategoryPassage> by lazy {
        VerseCategories.encouraging.sortedWith(compareBy({ mix(it.start.rawValue) }, { it.start.rawValue }))
    }

    /** The day's Random Verse pool: the next `count` of the shuffled list, moving on by `count` each day. */
    fun randomPool(day: Int, count: Int = RANDOM_POOL_SIZE): List<CategoryPassage> {
        val all = shuffled
        if (all.isEmpty()) return emptyList()
        val start = (((day.toLong() * count) % all.size + all.size) % all.size).toInt()
        return (0 until minOf(count, all.size)).map { all[(start + it) % all.size] }
    }

    /**
     * Whether a passage is shown from the person's Bible: when it numbers the
     * passage like the KJV (or isn't one whose numbering is mapped);
     * otherwise the KJV, so the reference never shows the wrong verse.
     */
    fun usesOwnBible(passage: CategoryPassage, translationId: String): Boolean {
        val map = OriginalVersification.map(translationId) ?: return true
        return passage.verseIds.all { id -> map.alignment(id).let { it.verses == listOf(id) && it.kjv == listOf(id) } }
    }
}

/**
 * From Your Reading: a verse from a chapter read in the last week that reads
 * well alone on a widget (a whole sentence of comfortable length), the same
 * all day. No AI. As ReadingVersePicker on iOS.
 */
object ReadingVersePicker {
    val lengths = 60..220
    private val opening = setOf('\u201C', '\u2018', '"', '\'', '\u00BF', '\u00A1', '(')
    private val closing = setOf('\u201D', '\u2019', '"', '\'', ')')

    fun isComfortable(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.length !in lengths) return false
        val first = trimmed.firstOrNull { it !in opening } ?: return false
        if (!first.isLetter() || !first.isUpperCase()) return false
        val last = trimmed.lastOrNull { it !in closing } ?: return false
        return last == '.' || last == '!' || last == '?'
    }

    /** The verse for a day: chapters take turns by day; within one, a comfortable verse chosen by the day. */
    fun <V> pick(chapters: List<Int>, day: Int, verses: (Int) -> List<V>, text: (V) -> String): V? {
        if (chapters.isEmpty()) return null
        val start = ((day % chapters.size) + chapters.size) % chapters.size
        for (step in chapters.indices) {
            val candidates = verses(chapters[(start + step) % chapters.size]).filter { isComfortable(text(it)) }
            if (candidates.isNotEmpty()) return candidates[(WidgetVerses.mix(day) % candidates.size).toInt()]
        }
        return null
    }
}
