package com.genesis.core.domain.prayer

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId

/**
 * A prayer's category, as PrayerCategory on iOS. The ids match the prayers
 * table's check; Family, Church, Work, Health and Personal come first, and
 * Friends stays for prayers saved with it.
 */
enum class PrayerCategory(val id: String) {
    FAMILY("family"),
    CHURCH("church"),
    WORK("work"),
    HEALTH("health"),
    PERSONAL("personal"),
    FRIENDS("friends");

    companion object {
        /** Reads any saved value: a known one, a few likely words, anything else as Personal, so no prayer is lost. */
        fun lenient(raw: String): PrayerCategory {
            val key = raw.trim().lowercase()
            entries.firstOrNull { it.id == key }?.let { return it }
            return when (key) {
                "home", "marriage", "children", "kids", "parents", "relatives" -> FAMILY
                "ministry", "congregation", "mission", "missions" -> CHURCH
                "job", "career", "school", "study", "business" -> WORK
                "healing", "illness", "sickness", "wellbeing", "well-being" -> HEALTH
                "friend", "friendship", "neighbours", "neighbors" -> FRIENDS
                else -> PERSONAL
            }
        }
    }
}

/** A passage a prayer holds: verse ids only, never the text (shown verbatim from the Bible being read). */
data class PrayerPassage private constructor(val start: VerseId, val end: VerseId) {
    val id: String get() = "${start.rawValue}-${end.rawValue}"

    /** "John 3:16" or "Psalms 23:1–3" in a language. */
    fun reference(language: String): String = ReferenceParser.describe(start.rawValue, end.rawValue, language)

    companion object {
        /** The most passages one prayer keeps. */
        const val MAXIMUM_PER_PRAYER = 20

        fun of(start: VerseId, end: VerseId): PrayerPassage = PrayerPassage(minOf(start, end), maxOf(start, end))

        /**
         * "John 3:16" or "Psalm 23:1–3", within one chapter. A whole chapter
         * ("Psalm 23") runs to its last verse, when `lastVerse` knows it.
         */
        fun parse(text: String, portugueseFirst: Boolean = false, lastVerse: (ChapterId) -> Int? = { null }): PrayerPassage? {
            val reference = ReferenceParser.parse(text, portugueseFirst) ?: return null
            val chapter = reference.chapter ?: return null
            val chapterId = ChapterId(reference.book.id, chapter)
            reference.verseStart?.let { first ->
                return of(VerseId(chapterId.book, chapter, first), VerseId(chapterId.book, chapter, maxOf(first, reference.verseEnd ?: first)))
            }
            val last = lastVerse(chapterId)?.takeIf { it >= 1 } ?: return null
            return of(chapterId.firstVerse, VerseId(chapterId.book, chapter, last))
        }

        /** Selected verses, kept within the first one's chapter. */
        fun selection(verses: Collection<VerseId>): PrayerPassage? {
            val first = verses.minOrNull() ?: return null
            val last = verses.max()
            return of(first, if (last.chapterId == first.chapterId) last else first)
        }

        /** Lenient: anything unreadable is skipped, and duplicates are dropped. */
        fun decode(pairs: List<Pair<Int, Int?>>): List<PrayerPassage> {
            val seen = mutableSetOf<String>()
            return pairs.mapNotNull { (first, second) ->
                if (first <= 1_000_000) return@mapNotNull null
                val last = second?.takeIf { it > 1_000_000 } ?: first
                of(VerseId(first), VerseId(last)).takeIf { seen.add(it.id) }
            }
        }

        /** "start-end,start-end", as iOS stores them on the device. */
        fun encode(passages: List<PrayerPassage>): String = passages.joinToString(",") { it.id }

        fun decode(raw: String): List<PrayerPassage> = decode(
            raw.split(',').mapNotNull { part ->
                val bounds = part.split('-').mapNotNull { it.trim().toIntOrNull() }
                bounds.firstOrNull()?.let { it to bounds.getOrNull(1) }
            },
        )
    }
}

/** A prayer request in the private prayer journal, as Prayer on iOS. Times are milliseconds. */
data class Prayer(
    val id: String,
    val title: String = "",
    val body: String = "",
    val category: PrayerCategory = PrayerCategory.PERSONAL,
    val isAnswered: Boolean = false,
    val answeredAt: Long? = null,
    val answerNote: String? = null,
    val reminderAt: Long? = null,
    val reminderRepeatsDaily: Boolean = false,
    val passages: List<PrayerPassage> = emptyList(),
    val lastPrayedAt: Long? = null,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
) {
    val hasContent: Boolean get() = title.isNotBlank() || body.isNotBlank()

    /** The title, or the prayer's first line; null when both are empty (the app says "Prayer"). */
    val displayTitle: String?
        get() = title.trim().ifEmpty { body.lineSequence().firstOrNull()?.trim().orEmpty() }.ifEmpty { null }

    /** Answered (or back to praying); answering clears a reminder, as on iOS. */
    fun answered(answered: Boolean, note: String?, now: Long): Prayer = copy(
        isAnswered = answered,
        answeredAt = if (answered) now else null,
        answerNote = note ?: answerNote,
        reminderAt = if (answered) null else reminderAt,
        reminderRepeatsDaily = if (answered) false else reminderRepeatsDaily,
    )

    /** Attaches a passage once, up to the limit. */
    fun attaching(passage: PrayerPassage): Prayer =
        if (passages.any { it.id == passage.id } || passages.size >= PrayerPassage.MAXIMUM_PER_PRAYER) this else copy(passages = passages + passage)

    fun detaching(passage: PrayerPassage): Prayer = copy(passages = passages.filter { it.id != passage.id })
}

/** The journal's search: title, prayer and how it was answered (case and accents aside). */
object PrayerSearch {
    fun matches(prayer: Prayer, query: String): Boolean {
        val wanted = fold(query.trim())
        if (wanted.isEmpty()) return true
        return listOf(prayer.title, prayer.body, prayer.answerNote.orEmpty()).any { fold(it).contains(wanted) }
    }

    private fun fold(text: String): String =
        java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFD).replace(Regex("\\p{Mn}+"), "").lowercase()
}
