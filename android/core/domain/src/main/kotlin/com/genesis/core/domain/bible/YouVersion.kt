package com.genesis.core.domain.bible

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull

/**
 * One book of a YouVersion Platform Bible, as the yvp-bible Edge Function
 * returns it (YouVersionBook on iOS): verses verbatim, the translation's
 * headings, bridged verses on their first verse, and the footnotes apart
 * from the text.
 */
@Serializable
data class YouVersionBook(val chapters: List<Chapter>) {
    @Serializable
    data class Chapter(
        val chapter: Int,
        val verses: List<Verse>,
        val headings: List<Heading> = emptyList(),
        val notes: List<Note> = emptyList(),
        /** Seconds the Platform lets this copy be used before it's fetched again when online. */
        val maxAge: Int? = null,
    ) {
        val joinsVerses: Boolean get() = verses.any { (it.last ?: 0) > it.verse }

        /** The same words, headings and notes. */
        fun hasSameText(other: Chapter): Boolean =
            chapter == other.chapter && verses == other.verses && headings == other.headings && notes == other.notes
    }

    @Serializable
    data class Verse(val verse: Int, val last: Int? = null, val text: String, val paragraph: Boolean = false, val poetry: Boolean = false)

    @Serializable
    data class Heading(val beforeVerse: Int, val text: String)

    /** `offset`: the UTF-16 offset in the verse's text where the marker goes. */
    @Serializable
    data class Note(val verse: Int, val offset: Int, val text: String)
}

/** A whole YouVersion Bible as kept (sealed) on the phone: book number → book. */
@Serializable
data class YouVersionBible(val books: Map<Int, YouVersionBook>)

/** The rules shared by building and refreshing a YouVersion Bible, as YouVersionBibleBuilder on iOS. */
object YouVersionBuild {
    /** What a build holds: 2 = footnotes, sealed. Older builds are built again on Wi-Fi. */
    const val FORMAT = 2

    /** USFM codes of the 66 books, in the app's order (book 1 = GEN). */
    val BOOK_CODES = listOf(
        "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI", "1CH", "2CH",
        "EZR", "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER", "LAM", "EZK", "DAN", "HOS",
        "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP", "HAG", "ZEC", "MAL",
        "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL", "EPH", "PHP", "COL", "1TH", "2TH",
        "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE", "2PE", "1JN", "2JN", "3JN", "JUD", "REV",
    )

    /** Books fetched at once: the Platform limits requests per app key, shared by every reader. */
    const val PARALLEL_BOOKS = 2

    /** A saved book of an unfinished download is used for a week. */
    const val SAVED_BOOK_LIFETIME_MS = 7L * 24 * 60 * 60 * 1000

    /** Seconds the server asked us to wait (its `retryAfter`), 30 if unsaid, within 1…600. */
    fun retryAfter(body: String): Double {
        val seconds = runCatching { ((Json.parseToJsonElement(body) as JsonObject)["retryAfter"] as? JsonPrimitive)?.doubleOrNull }.getOrNull() ?: 30.0
        return seconds.coerceIn(1.0, 600.0)
    }

    /** The longest single wait, and all waits together, before a download says it's busy. */
    const val LONGEST_WAIT_SECONDS = 330.0
    const val TOTAL_WAIT_SECONDS = 20 * 60.0

    /** The chapter as kept: verses with words, once each, sorted; headings and notes of those verses only. */
    fun normalized(chapter: YouVersionBook.Chapter): YouVersionBook.Chapter {
        val seen = mutableSetOf<Int>()
        val verses = chapter.verses
            .filter { it.text.isNotEmpty() && seen.add(it.verse) }
            .map { it.copy(last = it.last?.takeIf { last -> last > it.verse }) }
            .sortedBy { it.verse }
        val headings = chapter.headings.withIndex().filter { it.value.beforeVerse in seen }
            .sortedWith(compareBy({ it.value.beforeVerse }, { it.index })).map { it.value }
        val notes = chapter.notes.withIndex().filter { it.value.verse in seen && it.value.text.isNotEmpty() }
            .map { IndexedValue(it.index, it.value.copy(offset = maxOf(0, it.value.offset))) }
            .sortedWith(compareBy({ it.value.verse }, { it.value.offset }, { it.index })).map { it.value }
        return YouVersionBook.Chapter(chapter.chapter, verses, headings, notes)
    }

    /** Whether a chapter fetched again differs from the one kept, so an unchanged chapter is never rewritten. */
    fun differs(stored: YouVersionBook.Chapter, fresh: YouVersionBook.Chapter): Boolean = normalized(stored) != normalized(fresh)
}

/**
 * When each chapter of a YouVersion Bible on this phone must be fetched
 * again if it's opened online: the Platform's Cache-Control lifetime from
 * when it was fetched (following that header is how caching complies).
 * Times only, no text.
 */
@Serializable
data class YouVersionFreshness(val staleAfter: Map<String, Long> = emptyMap()) {
    fun setting(book: Int, chapter: Int, fetchedAt: Long, maxAge: Int?): YouVersionFreshness {
        val lifetime = maxOf(0, maxAge ?: DEFAULT_MAX_AGE) * 1000L
        return copy(staleAfter = staleAfter + ("$book.$chapter" to fetchedAt + lifetime))
    }

    /** True when the chapter should be fetched again before it's trusted online (also when nothing is known). */
    fun isStale(book: Int, chapter: Int, now: Long): Boolean {
        val limit = staleAfter["$book.$chapter"] ?: return true
        return now >= limit
    }

    companion object {
        /** The Platform's usual lifetime, for chapters fetched without one. */
        const val DEFAULT_MAX_AGE = 3600
    }
}

/**
 * The form of a verse kept in the search index, never shown, as
 * build_bibles.py's `search_form`: hyphenated names such as "Beth–lehem"
 * are indexed both joined and as written, so either spelling finds them.
 */
object BibleSearchForm {
    private val hyphenated = Regex("\\w+(?:[\u2010\u2011\u2013\\-]\\w+)+")
    private const val HYPHENS = "\u2010\u2011\u2013-"

    fun indexed(text: String): String = hyphenated.replace(text) { match ->
        match.value + " " + match.value.filter { it !in HYPHENS }
    }

    /** A footnote's letter: a…z, then aa…zz. */
    fun footnoteLabel(number: Int): String {
        val letter = 'a' + number % 26
        return letter.toString().repeat(number / 26 + 1)
    }
}
