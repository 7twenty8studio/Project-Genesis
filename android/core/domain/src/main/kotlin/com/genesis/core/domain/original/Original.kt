package com.genesis.core.domain.original

import com.genesis.core.domain.bible.VerseId

/** The language of a word or lexicon entry. Hebrew includes the Bible's Aramaic. */
enum class OriginalLanguage(val raw: String) {
    HEBREW("hebrew"),
    GREEK("greek");

    /** Hebrew (and Aramaic) is written right to left. */
    val isRightToLeft: Boolean get() = this == HEBREW

    /** The language code of the device voices that read it. */
    val speechLanguage: String get() = if (this == HEBREW) "he" else "el"

    companion object {
        fun of(raw: String): OriginalLanguage? = entries.firstOrNull { it.raw == raw }
        fun forBook(book: Int): OriginalLanguage = if (book >= 40) GREEK else HEBREW
    }
}

/**
 * The printed Greek New Testaments WordStudy.sqlite holds, each rebuilt word
 * by word from STEPBible's TAGNT, as GreekEdition.swift. The bits are those
 * of greek_words.editions and .found.
 */
enum class GreekEdition(val bit: Int) {
    /** Nestle-Aland, 28th edition (2012): the modern critical text. */
    NESTLE_ALAND(1),
    /** Westcott and Hort (1881). */
    WESTCOTT_HORT(2),
    /** Scrivener's Textus Receptus (1894): the Greek behind the KJV. */
    TEXTUS_RECEPTUS(4),
    /** Robinson and Pierpont's Byzantine text (2005). */
    BYZANTINE(8);

    /**
     * The edition this one's words are checked against for the dotted
     * marker: the traditional texts with Nestle-Aland, the critical ones with
     * the Textus Receptus.
     */
    val comparison: GreekEdition
        get() = when (this) {
            TEXTUS_RECEPTUS, BYZANTINE -> NESTLE_ALAND
            NESTLE_ALAND, WESTCOTT_HORT -> TEXTUS_RECEPTUS
        }
}

/** The Greek each Bible was translated from, as OriginalSource on iOS. */
object OriginalSource {
    data class Greek(
        val edition: GreekEdition,
        /** Translated from this very edition; false when it's the closest one. */
        val isExact: Boolean,
        /** False when the app doesn't know the Bible's Greek, so the header doesn't claim it. */
        val isKnownSource: Boolean = true,
    )

    fun greek(translationId: String): Greek? = when (translationId) {
        "KJV" -> Greek(GreekEdition.TEXTUS_RECEPTUS, isExact = true)
        "RV1909" -> Greek(GreekEdition.TEXTUS_RECEPTUS, isExact = false)
        "WEB" -> Greek(GreekEdition.BYZANTINE, isExact = true)
        "ASV" -> Greek(GreekEdition.WESTCOTT_HORT, isExact = false)
        "NIV" -> Greek(GreekEdition.NESTLE_ALAND, isExact = false)
        else -> null
    }

    /** Its own source where listed, otherwise Nestle-Aland, not claimed as the Bible's. */
    fun parallelGreek(translationId: String): Greek =
        greek(translationId) ?: Greek(GreekEdition.NESTLE_ALAND, isExact = false, isKnownSource = false)
}

/** One Hebrew or Greek word of a verse, verbatim from the source text. */
data class OriginalWord(
    val verse: VerseId,
    /** Hebrew: 1… in order. Greek: TAGNT's number for the word in the verse. */
    val position: Int,
    /** The word as written, with its pointing or accents. */
    val text: String,
    val transliteration: String,
    /** STEPBible's extended Strong's number (H0430G, G2316), if tagged. */
    val strongs: String?,
    /** The gloss in this context: STEPBible's English, or its translation. */
    val gloss: String,
    /** Morphology code (ETCBC for Hebrew, Robinson style for Greek). */
    val morphology: String,
    /** STEPBible's English gloss when [gloss] is a translation. */
    val englishGloss: String? = null,
    /** The translated gloss awaits qualified review. */
    val awaitsReview: Boolean = false,
    /** The Greek edition the word was read from; null for Hebrew. */
    val edition: GreekEdition? = null,
    /** The Greek editions that have this word here (bits). */
    val foundIn: Int = 0,
) {
    val id: Long get() = verse.rawValue.toLong() * 100 + position
    val language: OriginalLanguage get() = OriginalLanguage.forBook(verse.book)

    /** The gloss as shown: marked "(?)" while it awaits review. */
    val shownGloss: String get() = if (awaitsReview) "$gloss (?)" else gloss

    /** A Greek word the compared edition doesn't have here: dotted. Never Hebrew. */
    val isNotInComparison: Boolean
        get() {
            val edition = edition ?: return false
            return foundIn and edition.comparison.bit == 0
        }
}

/** A lexicon entry for one Strong's number. */
data class LexiconEntry(
    val strongs: String,
    val lemma: String,
    val transliteration: String,
    val gloss: String,
    val definition: String,
    /** Strong's note on where the word comes from (Hebrew only). */
    val derivation: String,
    /** How the KJV renders the word (Hebrew only). */
    val usage: String,
    val language: OriginalLanguage,
    /** Gloss, definition and origin are a translation; usage stays English. */
    val isTranslated: Boolean = false,
)

/** A commentary section on a run of verses within one chapter. */
data class CommentaryPassage(
    val id: Int,
    /** "mhcc": Matthew Henry's Concise Commentary. */
    val source: String,
    val start: VerseId,
    val end: VerseId,
    val title: String?,
    /** Paragraphs separated by blank lines. */
    val text: String,
    val isTranslated: Boolean = false,
    /** In a translation, the Bible's own words it quotes (verbatim), shown in italics. */
    val quotations: List<String> = emptyList(),
    val quotationLanguage: String? = null,
) {
    val paragraphs: List<String> get() = text.split("\n\n").filter { it.isNotEmpty() }

    /** Where each quotation falls in a paragraph, to set in italics. */
    fun quotedRanges(paragraph: String): List<IntRange> = buildList {
        for (quotation in quotations) {
            if (quotation.isEmpty()) continue
            var from = 0
            while (true) {
                val at = paragraph.indexOf(quotation, from)
                if (at < 0) break
                add(at until at + quotation.length)
                from = at + quotation.length
            }
        }
    }

    fun covers(verse: VerseId): Boolean = verse in start..end
}

/** Strong's numbers as WordStudy.sqlite stores them: H0430G, H1254A, G2316. */
object StrongsNumber {
    /** "h430" → "H0430", "H1254a" → "H1254A"; null if it isn't one. */
    fun normalized(text: String): String? {
        val trimmed = text.trim().uppercase()
        val letter = trimmed.firstOrNull() ?: return null
        if (letter != 'H' && letter != 'G') return null
        val rest = trimmed.drop(1)
        val digits = rest.takeWhile { it in '0'..'9' }
        val suffix = rest.drop(digits.length)
        if (digits.isEmpty() || digits.length > 5 || suffix.length > 1 || !suffix.all { it in 'A'..'Z' }) return null
        val number = digits.toInt().toString()
        return letter + number.padStart(4, '0') + suffix
    }

    /** "H1254A" → "H1254". */
    fun base(tag: String): String = if (tag.length > 1 && tag.last().isLetter()) tag.dropLast(1) else tag
}

/** "1001001,2,998" → [1001001, 1001003, 1002001]: ascending ids stored as deltas. */
fun decodeVerseDeltas(text: String): List<Int> {
    var total = 0
    return text.split(',').mapNotNull { part ->
        part.toIntOrNull()?.let { total += it; total }
    }
}

/** The key of a gloss in Glosses.sqlite: FNV-1a (64-bit) of "strongs␟morph␟gloss". */
object GlossKey {
    fun of(word: OriginalWord): Long = of(word.strongs ?: "", word.morphology, word.englishGloss ?: word.gloss)

    fun of(strongs: String, morphology: String, gloss: String): Long {
        var hash = -0x340d631b7bdddcdbL // 0xcbf29ce484222325
        for (byte in "$strongs\u001F$morphology\u001F$gloss".encodeToByteArray()) {
            hash = hash xor (byte.toLong() and 0xff)
            hash *= 0x100000001b3L
        }
        return hash
    }
}

/** Which language the Original view's word meanings are shown in, apart from the app's. */
enum class GlossLanguageChoice(val raw: String) {
    BIBLE("bible"), ENGLISH("en"), SPANISH("es"), PORTUGUESE("pt");

    companion object {
        fun of(raw: String?): GlossLanguageChoice = entries.firstOrNull { it.raw == raw } ?: BIBLE
    }
}

object GlossLanguage {
    const val STORAGE_KEY = "reader.original.glossLanguage"
    /** Languages Glosses.sqlite may hold; only these reach the SQL. */
    val LANGUAGES = setOf("es", "pt")

    /** "en", "es" or "pt": the Bible's language by default; the app's plays no part. */
    fun code(choice: GlossLanguageChoice, bibleLanguage: String): String = when (choice) {
        GlossLanguageChoice.BIBLE -> bibleLanguage.substringBefore('-').lowercase().takeIf { it in LANGUAGES } ?: "en"
        else -> choice.raw
    }
}
