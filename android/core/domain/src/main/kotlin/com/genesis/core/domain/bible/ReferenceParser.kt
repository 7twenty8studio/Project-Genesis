package com.genesis.core.domain.bible

import java.text.Normalizer

/** A book, a chapter or a verse range in one chapter. */
data class PassageReference(
    val book: BibleBook,
    val chapter: Int? = null,
    val verseStart: Int? = null,
    val verseEnd: Int? = null,
) {
    /** Where the reader opens for it: its first verse, or the chapter's start. */
    val firstVerse: VerseId get() = VerseId(book.id, chapter ?: 1, verseStart ?: 1)

    /** "John 3:16–18", "Salmos 23" or "Romans", in a language. */
    fun description(language: String): String {
        val name = book.name(language)
        val chapter = chapter ?: return name
        val start = verseStart ?: return "$name $chapter"
        return ReferenceParser.describe(firstVerse.rawValue, VerseId(book.id, chapter, verseEnd ?: start).rawValue, language)
    }
}

enum class ReferenceStatus { VERIFIED, AMBIGUOUS, UNLINKED }

/** A reference as a sermon block stores it: first and last verse ids when verified. */
data class ResolvedReference(val raw: String, val start: Int?, val end: Int?, val status: ReferenceStatus)

/**
 * Parses typed Bible references such as "John 3:16", "jn 3", "1 Cor 13:4-7",
 * "I John 1:9", "Ps 23", "Juan 3,16", "Sl 23" or "1ª João 1:9", in English,
 * Spanish and Portuguese whatever the app's language.
 *
 * The same reading as ReferenceParser.swift (iOS) and references.ts (web),
 * checked against their shared cases in fixtures/references.json. Pure: no
 * I/O beyond the book list, no verse text.
 */
object ReferenceParser {
    /** Parses a complete reference. Null if the text isn't one. */
    fun parse(input: String, portugueseFirst: Boolean = false): PassageReference? {
        val text = normalize(input)
        if (text.isEmpty()) return null
        val (bookText, numberText) = split(text)
        val book = bookNamed(bookText, portugueseFirst) ?: return null

        val numbers = parseNumbers(numberText)
        if (!numbers.valid) return null
        val first = numbers.chapter ?: return PassageReference(book)

        // Single-chapter books are cited by verse: "Jude 3" means verse 3.
        if (book.chapterCount == 1 && numbers.verse == null && first > 1) {
            return PassageReference(book, 1, first, numbers.verseEnd)
        }
        if (first < 1 || first > book.chapterCount) return null
        val verse = numbers.verse
        val verseEnd = numbers.verseEnd
        if (verse != null && verse < 1) return null
        if (verse != null && verseEnd != null && verseEnd < verse) return null
        return PassageReference(book, first, verse, verseEnd)
    }

    /** Books whose name or abbreviation starts with the typed text, for suggestions while typing. */
    fun booksMatching(input: String, portugueseFirst: Boolean = false): List<BibleBook> {
        val (bookText, numberText) = split(normalize(input))
        if (bookText.isEmpty() || numberText.isNotEmpty()) return emptyList()
        accentedBook(bookText)?.let { return listOf(it) }
        val key = compact(bookText)
        index(portugueseFirst)[key]?.let { return listOf(it) }
        return BibleBooks.all.filter { book ->
            (englishKeys(book) + spanishKeys(book) + portugueseKeys(book)).any { it.startsWith(key) }
        }
    }

    /** Resolves a book from any accepted spelling. */
    fun bookNamed(text: String, portugueseFirst: Boolean = false): BibleBook? {
        accentedBook(text)?.let { return it }
        val key = compact(text)
        if (key.isEmpty()) return null
        index(portugueseFirst)[key]?.let { return it }
        // An unambiguous prefix of a book name ("gene", "phile").
        if (key.codePointCount(0, key.length) < 3) return null
        val matches = BibleBooks.all.filter { book ->
            listOf(book.en.name, book.es.name, book.pt.name).any { compact(it).startsWith(key) }
        }
        return matches.singleOrNull()
    }

    /**
     * What a sermon block stores for typed text: verified with the first and
     * last verse ids when it names verses that exist (a whole chapter counts;
     * "John 3:16-4:2" crosses chapters), ambiguous when it reads as a book
     * but not as verses that exist, unlinked otherwise.
     */
    fun resolve(input: String, portugueseFirst: Boolean = false): ResolvedReference {
        val raw = input.trim().take(120)
        val unlinked = ResolvedReference(raw, null, null, ReferenceStatus.UNLINKED)
        val ambiguous = ResolvedReference(raw, null, null, ReferenceStatus.AMBIGUOUS)
        val text = normalize(input)
        if (text.isEmpty()) return unlinked
        val (bookText, numberText) = split(text)
        val book = bookNamed(bookText, portugueseFirst) ?: return unlinked

        acrossChapters.matchEntire(numberText)?.let { match ->
            val (c1, v1, c2, v2) = match.destructured.toList().map { it.toInt() }
            if (!exists(book, c1, v1) || !exists(book, c2, v2) || c2 < c1 || (c2 == c1 && v2 < v1)) return ambiguous
            return ResolvedReference(raw, VerseId(book.id, c1, v1).rawValue, VerseId(book.id, c2, v2).rawValue, ReferenceStatus.VERIFIED)
        }

        val ref = parse(input, portugueseFirst) ?: return if (numberText.isNotEmpty()) ambiguous else unlinked
        val chapter = ref.chapter ?: return ambiguous
        val start = ref.verseStart
            ?: return ResolvedReference(
                raw,
                VerseId(book.id, chapter, 1).rawValue,
                VerseId(book.id, chapter, book.verseCount(chapter)).rawValue,
                ReferenceStatus.VERIFIED,
            )
        val last = ref.verseEnd ?: start
        if (!exists(book, chapter, start) || !exists(book, chapter, last)) return ambiguous
        return ResolvedReference(raw, VerseId(book.id, chapter, start).rawValue, VerseId(book.id, chapter, last).rawValue, ReferenceStatus.VERIFIED)
    }

    /** A verse id that exists in the KJV's numbering. */
    fun isValidVerseId(id: Int): Boolean {
        val verse = VerseId(id)
        return verse.book in 1..66 && exists(BibleBooks.withNumber(verse.book), verse.chapter, verse.verse)
    }

    /**
     * A verse range named in a language ("en", "es", "pt"), as the app
     * writes it: "John 3:16–18", "Juan 3:16", "Jude 3", "Psalms 23" (a whole
     * chapter), "John 3:16–4:2".
     */
    fun describe(start: Int, end: Int = start, language: String = "en"): String {
        val a = VerseId(start)
        val b = VerseId(end)
        val book = BibleBooks.withNumber(a.book)
        val name = book.name(language)
        if (book.chapterCount > 1 && a.chapter == b.chapter && a.verse == 1 && b.verse == book.verseCount(a.chapter)) {
            return "$name ${a.chapter}"
        }
        val prefix = if (book.chapterCount == 1) "$name " else "$name ${a.chapter}:"
        return when {
            a.chapter != b.chapter -> "$prefix${a.verse}–${b.chapter}:${b.verse}"
            b.verse != a.verse -> "$prefix${a.verse}–${b.verse}"
            else -> "$prefix${a.verse}"
        }
    }

    // Internals -----------------------------------------------------------------

    private val acrossChapters = Regex("""^(\d+)\s*[:.,]\s*(\d+)\s*-\s*(\d+)\s*[:.,]\s*(\d+)$""")

    private fun exists(book: BibleBook, chapter: Int, verse: Int): Boolean =
        chapter in 1..book.chapterCount && verse >= 1 && verse <= book.verseCount(chapter)

    private val ordinals = listOf(
        "first " to "1", "second " to "2", "third " to "3",
        "1st " to "1", "2nd " to "2", "3rd " to "3",
        "primera de " to "1", "segunda de " to "2", "tercera de " to "3",
        "primera " to "1", "primero " to "1", "segunda " to "2", "segundo " to "2", "tercera " to "3", "tercero " to "3",
        "1ra " to "1", "1ro " to "1", "2da " to "2", "2do " to "2", "3ra " to "3", "3ro " to "3",
        "primeira " to "1", "primeiro " to "1", "terceira " to "3", "terceiro " to "3",
        "1ª " to "1", "1º " to "1", "2ª " to "2", "2º " to "2", "3ª " to "3", "3º " to "3",
        "iii " to "3", "ii " to "2", "i " to "1",
    )

    private fun normalize(input: String): String {
        var text = Normalizer.normalize(input, Normalizer.Form.NFC).lowercase()
            .replace("–", "-").replace("—", "-").trim()
        for ((prefix, digit) in ordinals) {
            if (text.startsWith(prefix)) {
                text = digit + text.substring(prefix.length)
                break
            }
        }
        return text
    }

    /** "1 cor 13:4-7" → ("1 cor", "13:4-7"). A leading 1–3 belongs to the book when letters follow it. */
    private fun split(text: String): Pair<String, String> {
        var index = 0
        if (text.isNotEmpty() && text[0] in "123") {
            var lookahead = 1
            while (lookahead < text.length && text[lookahead] == ' ') lookahead++
            if (lookahead < text.length && text[lookahead].isLetter()) index = lookahead
        }
        while (index < text.length && (text[index].isLetter() || text[index] == ' ' || text[index] == '.')) index++
        val book = text.substring(0, index).replace('.', ' ')
        return book.trim() to text.substring(index).trim()
    }

    private class Numbers(var chapter: Int? = null, var verse: Int? = null, var verseEnd: Int? = null, var valid: Boolean = true)

    /** "3", "3:16", "3.16", "3,16", "3 16", "3:16-18" or "3:16-4:2" (end chapter ignored). */
    private fun parseNumbers(text: String): Numbers {
        val result = Numbers()
        if (text.isEmpty()) return result
        var index = 0
        fun skipSpaces() {
            while (index < text.length && text[index] == ' ') index++
        }
        fun readNumber(): Int? {
            val start = index
            while (index < text.length && text[index].isDigit()) index++
            if (index == start) return null
            val digits = text.substring(start, index)
            return if (digits.all { it in '0'..'9' }) digits.toIntOrNull() else null
        }

        val chapter = readNumber() ?: return result.also { it.valid = false }
        result.chapter = chapter
        skipSpaces()
        if (index < text.length && text[index] in ":.,") {
            index++
            skipSpaces()
        }
        if (index < text.length && text[index].isDigit()) {
            result.verse = readNumber()
            skipSpaces()
            if (index < text.length && text[index] == '-') {
                index++
                skipSpaces()
                val end = readNumber()
                // "3:16-4:2": the number after "-" was a chapter; keep the start verse only.
                if (index < text.length && text[index] == ':') index = text.length else result.verseEnd = end
            }
        }
        skipSpaces()
        if (index < text.length) result.valid = false
        return result
    }

    private val marks = Regex("\\p{M}+")
    private val spacesAndDots = Regex("[\\s.]")

    /** Lowercase, without spaces, dots or accents: "1 Crónicas" → "1cronicas". */
    internal fun compact(text: String): String =
        Normalizer.normalize(text, Normalizer.Form.NFD).replace(marks, "").lowercase().replace(spacesAndDots, "")

    private fun englishKeys(book: BibleBook) = (listOf(book.en.name, book.en.abbreviation, book.osis) + book.en.aliases).map(::compact)
    private fun spanishKeys(book: BibleBook) = (listOf(book.es.name, book.es.abbreviation) + book.es.aliases).map(::compact)

    /** Job is "Jó" and John "Jo" in Portuguese, which fold to the same key: "jo" is John. */
    private fun portugueseKeys(book: BibleBook) =
        (listOf(book.pt.name, book.pt.abbreviation) + book.pt.aliases).map(::compact).filterNot { book.id == JOB && it == "jo" }

    private const val JOB = 18

    private fun accentedBook(text: String): BibleBook? {
        val spelled = Normalizer.normalize(text, Normalizer.Form.NFC).lowercase().replace(spacesAndDots, "")
        return if (spelled == "jó") BibleBooks.withNumber(JOB) else null
    }

    private val indexes = mutableMapOf<Boolean, Map<String, BibleBook>>()

    /** English, then Spanish, then Portuguese; Portuguese first in a Portuguese app ("Mc" Mark, "Jn" Jonah, "Hb" Hebrews). */
    private fun index(portugueseFirst: Boolean): Map<String, BibleBook> = synchronized(indexes) {
        indexes.getOrPut(portugueseFirst) {
            val layers: List<(BibleBook) -> List<String>> =
                if (portugueseFirst) listOf(::portugueseKeys, ::englishKeys, ::spanishKeys)
                else listOf(::englishKeys, ::spanishKeys, ::portugueseKeys)
            buildMap {
                for (keysOf in layers) for (book in BibleBooks.all) for (key in keysOf(book)) putIfAbsent(key, book)
            }
        }
    }
}
