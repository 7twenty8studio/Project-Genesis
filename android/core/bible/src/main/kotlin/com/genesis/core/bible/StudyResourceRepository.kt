package com.genesis.core.bible

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.SQLiteStatement
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.original.StrongsNumber
import com.genesis.core.domain.studyresources.StudyArticle
import com.genesis.core.domain.studyresources.StudyArticleSummary
import com.genesis.core.domain.studyresources.StudyIntroduction
import com.genesis.core.domain.studyresources.StudyLexiconEntry
import com.genesis.core.domain.studyresources.StudyMarkup
import com.genesis.core.domain.studyresources.StudyNote
import com.genesis.core.domain.studyresources.StudyRange
import java.io.File

/**
 * Reads one downloaded study pack, with the same queries as
 * StudyResourceRepository.swift (Tools/StudyResources/build_resources.py
 * describes the format). Packs hold verse ids in the KJV's numbering, never
 * verse text.
 */
class StudyResourceRepository private constructor(private val connection: SQLiteConnection) : AutoCloseable {
    private val lock = Any()

    fun packId(): String? = query("SELECT value FROM info WHERE key = 'id'") { it.getText(0) }.firstOrNull()

    /** Notes and comments that take in the verse, chapter introductions first, then the widest first. */
    fun notes(verse: VerseId): List<StudyNote> {
        val bookStart = VerseId(verse.book, 0, 0).rawValue
        return query(
            "SELECT id, start_verse, end_verse, title, text FROM notes WHERE start_verse BETWEEN ? AND ? AND end_verse >= ? ORDER BY start_verse % 1000 != 0, start_verse, end_verse DESC, id",
            bookStart, verse.rawValue, verse.rawValue,
        ) { StudyNote(it.getLong(0).toInt(), StudyRange.of(VerseId(it.getLong(1).toInt()), VerseId(it.getLong(2).toInt())), it.textOrNull(3), it.getText(4)) }
    }

    fun introduction(book: Int): StudyIntroduction? =
        query("SELECT book, title, text FROM introductions WHERE book = ? LIMIT 1", book) { StudyIntroduction(it.getLong(0).toInt(), it.textOrNull(1), it.getText(2)) }.firstOrNull()

    /** Articles linked to the verse (people, themes, key terms), by title. */
    fun articles(verse: VerseId, limit: Int = 30): List<StudyArticleSummary> {
        val bookStart = VerseId(verse.book, 0, 0).rawValue
        return query(
            """
            SELECT DISTINCT a.id, a.title, a.kind, a.sort_key FROM article_verses v JOIN articles a ON a.id = v.article
            WHERE v.start_verse BETWEEN ? AND ? AND v.end_verse >= ? ORDER BY a.sort_key LIMIT ?
            """.trimIndent(),
            bookStart, verse.rawValue, verse.rawValue, limit, map = ::summary,
        )
    }

    fun article(id: String): StudyArticle? =
        query("SELECT id, title, kind, text FROM articles WHERE id = ? LIMIT 1", id) { StudyArticle(it.getText(0), it.getText(1), it.getText(2), it.getText(3)) }.firstOrNull()

    /** Articles whose titles match, those starting with the words first; accents and case don't matter. */
    fun searchArticles(text: String, limit: Int = 100): List<StudyArticleSummary> {
        val folded = StudyMarkup.folded(text)
        val columns = "SELECT id, title, kind, sort_key FROM articles"
        if (folded.isEmpty()) return query("$columns ORDER BY sort_key LIMIT ?", limit, map = ::summary)
        val pattern = StudyMarkup.likeEscaped(folded)
        val starting = query("$columns WHERE sort_key LIKE ? ESCAPE '\\' ORDER BY sort_key LIMIT ?", "$pattern%", limit, map = ::summary)
        if (starting.size >= limit) return starting
        return starting + query(
            "$columns WHERE sort_key LIKE ? ESCAPE '\\' AND sort_key NOT LIKE ? ESCAPE '\\' ORDER BY sort_key LIMIT ?",
            "%$pattern%", "$pattern%", limit - starting.size, map = ::summary,
        )
    }

    /** Brown-Driver-Briggs or Liddell-Scott-Jones entries for a Strong's number, by its plain number. */
    fun lexicon(strongs: String): List<StudyLexiconEntry> {
        val tag = StrongsNumber.normalized(strongs) ?: return emptyList()
        return query(
            "SELECT rowid, strongs, source, lemma, translit, gloss, definition FROM lexicon WHERE strongs = ? ORDER BY rowid",
            StrongsNumber.base(tag),
        ) { StudyLexiconEntry(it.getLong(0), it.getText(1), it.getText(2), it.getText(3), it.textOrEmpty(4), it.textOrEmpty(5), it.textOrEmpty(6)) }
    }

    private fun summary(row: SQLiteStatement) = StudyArticleSummary(row.getText(0), row.getText(1), row.getText(2))

    private fun SQLiteStatement.textOrNull(column: Int): String? = if (isNull(column)) null else getText(column)
    private fun SQLiteStatement.textOrEmpty(column: Int): String = if (isNull(column)) "" else getText(column)

    private fun <T> query(sql: String, vararg arguments: Any, map: (SQLiteStatement) -> T): List<T> = synchronized(lock) {
        connection.prepare(sql).use { statement ->
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
        synchronized(lock) { connection.close() }
    }

    companion object {
        fun open(file: File): StudyResourceRepository =
            StudyResourceRepository(BundledSQLiteDriver().open(file.path, SQLITE_OPEN_READONLY))
    }
}
