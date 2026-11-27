package com.genesis.core.bible

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.execSQL
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.original.CommentaryPassage
import com.genesis.core.domain.original.GlossKey
import com.genesis.core.domain.original.GlossLanguage
import com.genesis.core.domain.original.GreekEdition
import com.genesis.core.domain.original.LexiconEntry
import com.genesis.core.domain.original.OriginalLanguage
import com.genesis.core.domain.original.OriginalWord
import com.genesis.core.domain.original.StrongsNumber
import com.genesis.core.domain.original.decodeVerseDeltas

/**
 * Word study and commentary from the bundled WordStudy.sqlite, with the same
 * queries as WordStudyRepository.swift: the Hebrew and Greek words of every
 * verse (KJV numbering; Greek in four editions), the lexicon and Matthew
 * Henry's Concise Commentary. The word meanings in Spanish and Portuguese
 * come from Glosses.sqlite (OriginalGlosses.swift). No English verse text:
 * verses come from the Bible databases.
 *
 * Data: STEPBible TAHOT, TAGNT, TBESH and TBESG (CC BY 4.0, Tyndale House
 * Cambridge); Strong's Hebrew via Open Scriptures (CC BY 4.0); Matthew
 * Henry's Concise Commentary (public domain).
 */
class WordStudyRepository private constructor(
    private val connection: SQLiteConnection,
    private val glosses: SQLiteConnection?,
    language: String?,
) : AutoCloseable {
    private val lock = Any()
    private val translated = language?.takeIf { it in TRANSLATED }

    /** "es" or "pt" when the database has that language's lexicon; null for English. */
    val language: String? = translated?.takeIf { hasTable("lexicon_translations") }
    /** "es" or "pt" when the database has Matthew Henry in that language. */
    val commentaryLanguage: String? = translated?.takeIf { hasTable("commentary_translations") }
    private val hasQuotations = hasTable("commentary_quotations")

    /** Whether word meanings in [code] are translated ones (the note and credit show). */
    fun hasTranslatedGlosses(code: String): Boolean = code in GlossLanguage.LANGUAGES && glosses != null

    // Words

    fun words(verse: VerseId, edition: GreekEdition = GreekEdition.TEXTUS_RECEPTUS, glossLanguage: String = "en"): List<OriginalWord> =
        words(listOf(verse), edition, glossLanguage)[verse].orEmpty()

    /** The words of several verses (KJV numbering), by verse, each in the original order. */
    fun words(verses: Collection<VerseId>, edition: GreekEdition = GreekEdition.TEXTUS_RECEPTUS, glossLanguage: String = "en"): Map<VerseId, List<OriginalWord>> {
        val low = verses.minOrNull() ?: return emptyMap()
        val high = verses.max()
        val wanted = verses.toSet()
        val rows = mutableListOf<OriginalWord>()
        if (low.book < 40) {
            rows += query("$HEBREW_COLUMNS WHERE w.verse BETWEEN ? AND ? ORDER BY w.verse, w.position", low.rawValue, high.rawValue) {
                OriginalWord(VerseId(it.getInt(0)), it.getInt(1), it.getText(2), it.getText(3), it.textOrNull(4), it.getText(5), it.getText(6))
            }
        }
        if (high.book >= 40) {
            rows += query(
                "$GREEK_COLUMNS WHERE g.verse BETWEEN ? AND ? AND (g.editions & ?) != 0 ORDER BY g.verse, g.slot, g.number",
                low.rawValue, high.rawValue, edition.bit,
            ) {
                OriginalWord(
                    VerseId(it.getInt(0)), it.getInt(1), it.getText(2), it.getText(3), it.textOrNull(4), it.getText(5), it.getText(6),
                    edition = edition, foundIn = it.getInt(7),
                )
            }
        }
        return translatedGlosses(rows.filter { it.verse in wanted }, glossLanguage).groupBy { it.verse }
    }

    /** The word another edition has at the same place as a Greek word, if any. */
    fun reading(word: OriginalWord, edition: GreekEdition): String? {
        if (word.language != OriginalLanguage.GREEK) return null
        return query(
            "SELECT f.text FROM greek_words g JOIN forms f ON f.id = g.form WHERE g.verse = ? AND g.number = ? AND (g.editions & ?) != 0 LIMIT 1",
            word.verse.rawValue, word.position, edition.bit,
        ) { it.getText(0) }.firstOrNull()
    }

    private fun translatedGlosses(words: List<OriginalWord>, code: String): List<OriginalWord> {
        val glosses = glosses ?: return words
        if (code !in GlossLanguage.LANGUAGES || words.isEmpty()) return words
        return runCatching {
            val keys = words.map(GlossKey::of).distinct()
            val found = HashMap<Long, Pair<String, Boolean>>()
            for (chunk in keys.chunked(500)) {
                val marks = chunk.joinToString(", ") { "?" }
                query(glosses, "SELECT key, $code, COALESCE(awaiting, '') FROM glosses WHERE key IN ($marks) AND $code IS NOT NULL", *chunk.toTypedArray()) {
                    found[it.getLong(0)] = it.getText(1) to it.getText(2).split(' ').contains(code)
                }
            }
            if (found.isEmpty()) return words
            val low = words.minOf { it.verse.rawValue }
            val high = words.maxOf { it.verse.rawValue }
            val own = HashMap<String, String>()
            query(glosses, "SELECT verse, position, key, $code FROM occurrence_glosses WHERE verse BETWEEN ? AND ? AND $code IS NOT NULL", low, high) {
                own["${it.getLong(0)}.${it.getLong(1)}.${it.getLong(2)}"] = it.getText(3)
            }
            words.map { word ->
                val key = GlossKey.of(word)
                val usual = found[key] ?: return@map word
                word.copy(
                    englishGloss = word.gloss,
                    gloss = own["${word.verse.rawValue}.${word.position}.$key"] ?: usual.first,
                    awaitsReview = usual.second,
                )
            }
        }.getOrDefault(words)
    }

    // Lexicon

    /** The entry for a Strong's number; an extended number without one falls back to its plain number's first. */
    fun entry(strongs: String): LexiconEntry? {
        val tag = StrongsNumber.normalized(strongs) ?: return null
        query("$entryColumns WHERE lexicon.strongs = ?", tag, map = ::entry).firstOrNull()?.let { return it }
        val (sql, arguments) = family(StrongsNumber.base(tag), "lexicon.strongs")
        return query("$entryColumns WHERE $sql ORDER BY lexicon.strongs LIMIT 1", *arguments, map = ::entry).firstOrNull()
    }

    /** How many words in the Bible carry the number (a plain number counts its extended forms). */
    fun occurrences(strongs: String): Int {
        val (sql, arguments) = filter(strongs) ?: return 0
        return query("SELECT COALESCE(SUM(count), 0) FROM occurrences WHERE $sql", *arguments) { it.getInt(0) }.firstOrNull() ?: 0
    }

    /** Verses that use the number, in canonical order (KJV numbering). */
    fun verses(strongs: String, limit: Int = 200): List<VerseId> {
        val (sql, arguments) = filter(strongs) ?: return emptyList()
        if (limit <= 0) return emptyList()
        val lists = query("SELECT verses FROM occurrences WHERE $sql", *arguments) { it.getText(0) }
        val ids = if (lists.size == 1) decodeVerseDeltas(lists[0]) else lists.flatMap(::decodeVerseDeltas).distinct().sorted()
        return ids.take(limit).map(::VerseId)
    }

    // Commentary

    /** Commentary passages that take in the verse (usually one). */
    fun commentary(verse: VerseId): List<CommentaryPassage> {
        val chapterStart = VerseId(verse.book, verse.chapter, 0).rawValue
        return withQuotations(
            query("$commentaryColumns WHERE c.start_verse BETWEEN ? AND ? AND c.end_verse >= ? ORDER BY c.start_verse, c.id", chapterStart, verse.rawValue, verse.rawValue, map = ::passage),
        )
    }

    fun commentary(chapter: ChapterId): List<CommentaryPassage> {
        val range = chapter.verseRange
        return withQuotations(query("$commentaryColumns WHERE c.start_verse BETWEEN ? AND ? ORDER BY c.start_verse, c.id", range.first, range.last, map = ::passage))
    }

    private fun withQuotations(passages: List<CommentaryPassage>): List<CommentaryPassage> {
        val language = commentaryLanguage ?: return passages
        if (passages.isEmpty() || !hasQuotations) return passages
        val ids = passages.map { it.id }
        val marks = ids.joinToString(", ") { "?" }
        val quotations = query(
            "SELECT id, text FROM commentary_quotations WHERE lang = ? AND id IN ($marks) ORDER BY id, n",
            *(listOf<Any>(language) + ids).toTypedArray(),
        ) { it.getInt(0) to it.getText(1) }
        return passages.map { passage ->
            if (!passage.isTranslated) passage
            else passage.copy(quotations = quotations.filter { it.first == passage.id }.map { it.second }, quotationLanguage = language)
        }
    }

    // Rows

    private val entryColumns: String
        get() = language?.let {
            """
            SELECT lexicon.strongs, lemma, translit, COALESCE(tr.gloss, lexicon.gloss), COALESCE(tr.definition, lexicon.definition),
                COALESCE(tr.derivation, lexicon.derivation), usage, language, tr.strongs IS NOT NULL
            FROM lexicon LEFT JOIN lexicon_translations tr ON tr.lang = '$it' AND tr.strongs = lexicon.strongs
            """.trimIndent()
        } ?: "SELECT lexicon.strongs, lemma, translit, gloss, definition, derivation, usage, language, 0 FROM lexicon"

    private val commentaryColumns: String
        get() = commentaryLanguage?.let {
            """
            SELECT c.id, c.source, c.start_verse, c.end_verse, COALESCE(tr.title, c.title), COALESCE(tr.text, c.text), tr.id IS NOT NULL
            FROM commentary c LEFT JOIN commentary_translations tr ON tr.lang = '$it' AND tr.id = c.id
            """.trimIndent()
        } ?: "SELECT c.id, c.source, c.start_verse, c.end_verse, c.title, c.text, 0 FROM commentary c"

    private fun entry(row: SQLiteStatement): LexiconEntry {
        val strongs = row.getText(0)
        return LexiconEntry(
            strongs = strongs,
            lemma = row.getText(1),
            transliteration = row.getText(2),
            gloss = row.textOrEmpty(3),
            definition = row.textOrEmpty(4),
            derivation = row.textOrEmpty(5),
            usage = row.textOrEmpty(6),
            language = OriginalLanguage.of(row.textOrEmpty(7)) ?: if (strongs.startsWith("G")) OriginalLanguage.GREEK else OriginalLanguage.HEBREW,
            isTranslated = row.getLong(8) != 0L,
        )
    }

    private fun passage(row: SQLiteStatement) = CommentaryPassage(
        id = row.getInt(0),
        source = row.getText(1),
        start = VerseId(row.getInt(2)),
        end = VerseId(row.getInt(3)),
        title = row.textOrNull(4),
        text = row.getText(5),
        isTranslated = row.getLong(6) != 0L,
    )

    /** A number with a letter matches only itself; a plain one, itself and its extended forms. */
    private fun filter(strongs: String): Pair<String, Array<Any>>? {
        val tag = StrongsNumber.normalized(strongs) ?: return null
        return if (tag == StrongsNumber.base(tag)) family(tag) else "strongs = ?" to arrayOf(tag)
    }

    /** "H0430" and "H0430A"…"H0430Z", but not "H04300". */
    private fun family(base: String, column: String = "strongs"): Pair<String, Array<Any>> =
        "($column = ? OR ($column BETWEEN ? AND ? AND length($column) = ?))" to arrayOf(base, base + "A", base + "Z", base.length + 1)

    private fun SQLiteStatement.getInt(column: Int): Int = getLong(column).toInt()
    private fun SQLiteStatement.textOrNull(column: Int): String? = if (isNull(column)) null else getText(column)
    private fun SQLiteStatement.textOrEmpty(column: Int): String = if (isNull(column)) "" else getText(column)

    private fun hasTable(name: String): Boolean =
        query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", name) { true }.isNotEmpty()

    private fun <T> query(sql: String, vararg arguments: Any, map: (SQLiteStatement) -> T): List<T> = query(connection, sql, *arguments, map = map)

    private fun <T> query(on: SQLiteConnection, sql: String, vararg arguments: Any, map: (SQLiteStatement) -> T): List<T> = synchronized(lock) {
        on.prepare(sql).use { statement ->
            arguments.forEachIndexed { index, value ->
                when (value) {
                    is Int -> statement.bindLong(index + 1, value.toLong())
                    is Long -> statement.bindLong(index + 1, value)
                    else -> statement.bindText(index + 1, value.toString())
                }
            }
            buildList { while (statement.step()) add(map(statement)) }
        }
    }

    override fun close() {
        synchronized(lock) {
            connection.close()
            glosses?.close()
        }
    }

    companion object {
        /** Languages the lexicon and commentary are translated into. Only these reach the SQL. */
        val TRANSLATED = setOf("es", "pt")

        /** The bundled database (copied out of the app once per install; about 60 MB). */
        fun open(context: Context, language: String?): WordStudyRepository {
            val driver = BundledSQLiteDriver()
            val connection = driver.open(BundledFiles.file(context, "WordStudy.sqlite").path, SQLITE_OPEN_READONLY)
            connection.execSQL("PRAGMA query_only = ON")
            val glosses = runCatching { driver.open(BundledFiles.file(context, "Glosses.sqlite").path, SQLITE_OPEN_READONLY) }.getOrNull()
            return WordStudyRepository(connection, glosses, language)
        }

        private const val HEBREW_COLUMNS = "SELECT w.verse, w.position, f.text, f.translit, f.strongs, f.gloss, f.morph FROM word_forms w JOIN forms f ON f.id = w.form"
        private const val GREEK_COLUMNS = "SELECT g.verse, g.number, f.text, f.translit, f.strongs, f.gloss, f.morph, g.found FROM greek_words g JOIN forms f ON f.id = g.form"
    }
}
