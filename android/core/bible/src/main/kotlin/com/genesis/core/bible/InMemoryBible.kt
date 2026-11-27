package com.genesis.core.bible

import androidx.sqlite.SQLiteConnection
import androidx.sqlite.execSQL
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.BibleSearchForm
import com.genesis.core.domain.bible.Testament
import com.genesis.core.domain.bible.YouVersionBook

/** Writes a YouVersion Bible's tables into an empty connection, as BibleFileWriter.build on iOS. */
internal object InMemoryBible {
    /** Same as build_bibles.py's SCHEMA_VERSION. */
    private const val SCHEMA_VERSION = 1

    fun write(connection: SQLiteConnection, books: Map<Int, YouVersionBook>, meta: Map<String, String>) {
        // The Porter stemmer is English-only; other languages match whole words and prefixes, accents ignored.
        val english = (meta["language"] ?: "en").startsWith("en")
        val tokenizer = if (english) "porter unicode61 remove_diacritics 2" else "unicode61 remove_diacritics 2"
        for (sql in listOf(
            "PRAGMA journal_mode = OFF",
            "PRAGMA synchronous = OFF",
            "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL) WITHOUT ROWID",
            "CREATE TABLE books (id INTEGER PRIMARY KEY, osis TEXT NOT NULL, name TEXT NOT NULL, testament TEXT NOT NULL, chapter_count INTEGER NOT NULL)",
            "CREATE TABLE verses (id INTEGER PRIMARY KEY, book INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL, text TEXT NOT NULL, paragraph INTEGER NOT NULL DEFAULT 0, poetry INTEGER NOT NULL DEFAULT 0)",
            "CREATE TABLE headings (book INTEGER NOT NULL, chapter INTEGER NOT NULL, before_verse INTEGER NOT NULL, text TEXT NOT NULL)",
            "CREATE INDEX headings_chapter ON headings(book, chapter)",
            "CREATE VIRTUAL TABLE verses_fts USING fts5(text, content='', tokenize='$tokenizer', prefix='2 3 4')",
        )) connection.execSQL(sql)
        val chapters = books.values.flatMap { it.chapters }
        if (chapters.any { it.joinsVerses }) connection.execSQL("CREATE TABLE verse_spans (id INTEGER PRIMARY KEY, last INTEGER NOT NULL)")
        if (chapters.any { it.notes.isNotEmpty() }) {
            connection.execSQL("CREATE TABLE footnotes (verse_id INTEGER NOT NULL, position INTEGER NOT NULL, text TEXT NOT NULL)")
            connection.execSQL("CREATE INDEX footnotes_verse ON footnotes(verse_id)")
        }
        connection.execSQL("BEGIN")
        connection.prepare("INSERT INTO meta VALUES (?, ?)").use { statement ->
            for ((key, value) in meta + ("schema_version" to SCHEMA_VERSION.toString()) + ("source" to "youversion")) {
                statement.reset()
                statement.bindText(1, key)
                statement.bindText(2, value)
                statement.step()
            }
        }
        connection.prepare("INSERT INTO books VALUES (?, ?, ?, ?, ?)").use { statement ->
            for (book in BibleBooks.all) {
                statement.reset()
                statement.bindLong(1, book.id.toLong())
                statement.bindText(2, book.osis)
                statement.bindText(3, book.englishName)
                statement.bindText(4, if (book.testament == Testament.OLD) "old" else "new")
                statement.bindLong(5, (books[book.id]?.chapters?.maxOfOrNull { it.chapter } ?: book.chapterCount).toLong())
                statement.step()
            }
        }
        insert(connection, books.keys.sorted().flatMap { number -> books.getValue(number).chapters.map { number to it } })
        connection.execSQL("COMMIT")
        connection.execSQL("INSERT INTO verses_fts(verses_fts) VALUES ('optimize')")
    }

    private fun tables(connection: SQLiteConnection): Set<String> = buildSet {
        connection.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").use { while (it.step()) add(it.getText(0)) }
    }

    /** One chapter replaced: its verses (and their search rows), headings, joined verses and footnotes. */
    fun replace(connection: SQLiteConnection, number: Int, chapter: YouVersionBook.Chapter) {
        var known = tables(connection)
        if (chapter.joinsVerses && "verse_spans" !in known) connection.execSQL("CREATE TABLE verse_spans (id INTEGER PRIMARY KEY, last INTEGER NOT NULL)")
        if (chapter.notes.isNotEmpty() && "footnotes" !in known) {
            connection.execSQL("CREATE TABLE footnotes (verse_id INTEGER NOT NULL, position INTEGER NOT NULL, text TEXT NOT NULL)")
            connection.execSQL("CREATE INDEX footnotes_verse ON footnotes(verse_id)")
        }
        known = tables(connection)
        val first = number * 1_000_000L + chapter.chapter * 1_000L
        val last = first + 999
        connection.execSQL("BEGIN")
        // A contentless search index forgets a row only when told its words.
        val old = buildList {
            connection.prepare("SELECT id, text FROM verses WHERE id BETWEEN ? AND ?").use { statement ->
                statement.bindLong(1, first)
                statement.bindLong(2, last)
                while (statement.step()) add(statement.getLong(0) to statement.getText(1))
            }
        }
        connection.prepare("INSERT INTO verses_fts(verses_fts, rowid, text) VALUES ('delete', ?, ?)").use { forget ->
            for ((id, text) in old) {
                forget.reset()
                forget.bindLong(1, id)
                forget.bindText(2, BibleSearchForm.indexed(text))
                forget.step()
            }
        }
        connection.execSQL("DELETE FROM verses WHERE id BETWEEN $first AND $last")
        connection.execSQL("DELETE FROM headings WHERE book = $number AND chapter = ${chapter.chapter}")
        if ("verse_spans" in known) connection.execSQL("DELETE FROM verse_spans WHERE id BETWEEN $first AND $last")
        if ("footnotes" in known) connection.execSQL("DELETE FROM footnotes WHERE verse_id BETWEEN $first AND $last")
        insert(connection, listOf(number to chapter))
        connection.execSQL("COMMIT")
    }

    private fun insert(connection: SQLiteConnection, chapters: List<Pair<Int, YouVersionBook.Chapter>>) {
        val known = tables(connection)
        val verse = connection.prepare("INSERT INTO verses VALUES (?, ?, ?, ?, ?, ?, ?)")
        val search = connection.prepare("INSERT INTO verses_fts(rowid, text) VALUES (?, ?)")
        val heading = connection.prepare("INSERT INTO headings VALUES (?, ?, ?, ?)")
        val span = if ("verse_spans" in known) connection.prepare("INSERT INTO verse_spans VALUES (?, ?)") else null
        val note = if ("footnotes" in known) connection.prepare("INSERT INTO footnotes VALUES (?, ?, ?)") else null
        try {
            for ((number, chapter) in chapters) {
                run {
                    val seen = mutableSetOf<Int>()
                    fun id(v: Int) = number * 1_000_000L + chapter.chapter * 1_000L + v
                    for (item in chapter.verses) {
                        if (item.text.isEmpty() || !seen.add(item.verse)) continue
                        verse.reset()
                        verse.bindLong(1, id(item.verse))
                        verse.bindLong(2, number.toLong())
                        verse.bindLong(3, chapter.chapter.toLong())
                        verse.bindLong(4, item.verse.toLong())
                        verse.bindText(5, item.text)
                        verse.bindLong(6, if (item.paragraph) 1 else 0)
                        verse.bindLong(7, if (item.poetry) 1 else 0)
                        verse.step()
                        search.reset()
                        search.bindLong(1, id(item.verse))
                        search.bindText(2, BibleSearchForm.indexed(item.text))
                        search.step()
                        val last = item.last
                        if (span != null && last != null && last > item.verse) {
                            span.reset()
                            span.bindLong(1, id(item.verse))
                            span.bindLong(2, id(last))
                            span.step()
                        }
                    }
                    for (item in chapter.headings) {
                        if (item.beforeVerse !in seen) continue
                        heading.reset()
                        heading.bindLong(1, number.toLong())
                        heading.bindLong(2, chapter.chapter.toLong())
                        heading.bindLong(3, item.beforeVerse.toLong())
                        heading.bindText(4, item.text)
                        heading.step()
                    }
                    if (note != null) for (item in chapter.notes) {
                        if (item.verse !in seen || item.text.isEmpty()) continue
                        note.reset()
                        note.bindLong(1, id(item.verse))
                        note.bindLong(2, maxOf(0, item.offset).toLong())
                        note.bindText(3, item.text)
                        note.step()
                    }
                }
            }
        } finally {
            verse.close(); search.close(); heading.close(); span?.close(); note?.close()
        }
    }
}
