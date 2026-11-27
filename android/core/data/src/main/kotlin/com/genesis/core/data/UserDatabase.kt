package com.genesis.core.data

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.Bookmarks
import com.genesis.core.domain.study.HighlightColor
import com.genesis.core.domain.study.Note
import com.genesis.core.domain.study.NoteAnchor
import com.genesis.core.domain.study.NoteKind
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.util.UUID

/**
 * The person's data on this device, in its own SQLite file (backed up, unlike
 * the bundled Bibles). Rows carry what sync will need: an id, updated_at
 * (the edit time, last writer wins) and deleted_at (a soft delete, so a
 * removal reaches the person's other devices, as iOS's tombstones do).
 * One connection, used by one thread at a time.
 */
class UserDatabase private constructor(private val connection: SQLiteConnection) : AutoCloseable {
    private val lock = Any()

    init {
        synchronized(lock) { migrate() }
    }

    private fun migrate() {
        val version = connection.prepare("PRAGMA user_version").use { it.step(); it.getLong(0).toInt() }
        if (version < 1) {
            connection.execSQL(
                """
                CREATE TABLE highlights (
                    id TEXT PRIMARY KEY NOT NULL,
                    verse INTEGER NOT NULL UNIQUE,
                    color TEXT NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER
                )
                """.trimIndent(),
            )
            connection.execSQL("PRAGMA user_version = 1")
        }
        if (version < 2) {
            connection.execSQL(
                """
                CREATE TABLE bookmarks (
                    id TEXT PRIMARY KEY NOT NULL,
                    verse INTEGER NOT NULL,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER
                )
                """.trimIndent(),
            )
            connection.execSQL(
                """
                CREATE TABLE notes (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    anchor_type TEXT NOT NULL,
                    start_verse INTEGER,
                    end_verse INTEGER,
                    book_number INTEGER,
                    chapter_number INTEGER,
                    theme TEXT,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER
                )
                """.trimIndent(),
            )
            connection.execSQL("PRAGMA user_version = 2")
        }
    }

    val highlights = HighlightStore()
    val bookmarks = BookmarkStore()
    val notes = NoteStore()

    /** Bookmarks, one per chapter as on iOS (rules in `Bookmarks`). */
    inner class BookmarkStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<Set<VerseId>> = _all.asStateFlow()

        private fun load(): Set<VerseId> = synchronized(lock) {
            buildSet {
                connection.prepare("SELECT verse FROM bookmarks WHERE deleted_at IS NULL").use { statement ->
                    while (statement.step()) add(VerseId(statement.getLong(0).toInt()))
                }
            }
        }

        /** Bookmarks the verse, or takes the chapter's bookmark away. True when one was added. */
        fun toggle(at: VerseId, now: Long = System.currentTimeMillis()): Boolean = synchronized(lock) {
            val change = Bookmarks.toggle(_all.value, at)
            transaction {
                change.add?.let { verse ->
                    connection.prepare("INSERT INTO bookmarks (id, verse, created_at, updated_at) VALUES (?, ?, ?, ?)").use {
                        it.bindText(1, UUID.randomUUID().toString())
                        it.bindLong(2, verse.rawValue.toLong())
                        it.bindLong(3, now)
                        it.bindLong(4, now)
                        it.step()
                    }
                }
                for (verse in change.remove) {
                    connection.prepare("UPDATE bookmarks SET deleted_at = ?, updated_at = ? WHERE verse = ? AND deleted_at IS NULL").use {
                        it.bindLong(1, now)
                        it.bindLong(2, now)
                        it.bindLong(3, verse.rawValue.toLong())
                        it.step()
                    }
                }
            }
            _all.value = _all.value - change.remove + listOfNotNull(change.add)
            change.add != null
        }
    }

    /** Notes, newest first. */
    inner class NoteStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<List<Note>> = _all.asStateFlow()

        private fun load(): List<Note> = synchronized(lock) {
            buildList {
                connection.prepare(
                    """
                    SELECT id, title, body, kind, anchor_type, start_verse, end_verse, book_number, chapter_number, theme, created_at, updated_at
                    FROM notes WHERE deleted_at IS NULL ORDER BY updated_at DESC
                    """.trimIndent(),
                ).use { s ->
                    fun int(column: Int): Int? = if (s.isNull(column)) null else s.getLong(column).toInt()
                    while (s.step()) {
                        add(
                            Note(
                                id = s.getText(0),
                                title = s.getText(1),
                                body = s.getText(2),
                                kind = NoteKind.withId(s.getText(3)),
                                anchor = NoteAnchor.of(s.getText(4), int(5), int(6), int(7), int(8), if (s.isNull(9)) null else s.getText(9)),
                                createdAt = s.getLong(10),
                                updatedAt = s.getLong(11),
                            ),
                        )
                    }
                }
            }
        }

        /** Saves a new or edited note, stamping it with the edit time. */
        fun save(note: Note, now: Long = System.currentTimeMillis()): Note = synchronized(lock) {
            val saved = note.copy(createdAt = if (note.createdAt == 0L) now else note.createdAt, updatedAt = now)
            val anchor = saved.anchor
            val verses = anchor as? NoteAnchor.Verses
            val chapter = (anchor as? NoteAnchor.Chapter)?.chapter
            val book = chapter?.book ?: (anchor as? NoteAnchor.Book)?.book
            transaction {
                connection.prepare(
                    """
                    INSERT INTO notes (id, title, body, kind, anchor_type, start_verse, end_verse, book_number, chapter_number, theme, created_at, updated_at, deleted_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                    ON CONFLICT(id) DO UPDATE SET
                        title = excluded.title, body = excluded.body, kind = excluded.kind,
                        anchor_type = excluded.anchor_type, start_verse = excluded.start_verse,
                        end_verse = excluded.end_verse, book_number = excluded.book_number,
                        chapter_number = excluded.chapter_number, theme = excluded.theme,
                        updated_at = excluded.updated_at, deleted_at = NULL
                    """.trimIndent(),
                ).use {
                    fun bind(index: Int, value: Int?) = if (value == null) it.bindNull(index) else it.bindLong(index, value.toLong())
                    it.bindText(1, saved.id)
                    it.bindText(2, saved.title)
                    it.bindText(3, saved.body)
                    it.bindText(4, saved.kind.id)
                    it.bindText(5, anchor.type)
                    bind(6, verses?.start?.rawValue)
                    bind(7, verses?.end?.rawValue)
                    bind(8, book)
                    bind(9, chapter?.chapter)
                    (anchor as? NoteAnchor.Theme)?.theme?.let { theme -> it.bindText(10, theme) } ?: it.bindNull(10)
                    it.bindLong(11, saved.createdAt)
                    it.bindLong(12, saved.updatedAt)
                    it.step()
                }
            }
            _all.value = listOf(saved) + _all.value.filter { it.id != saved.id }
            saved
        }

        fun delete(id: String, now: Long = System.currentTimeMillis()) = synchronized(lock) {
            transaction {
                connection.prepare("UPDATE notes SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL").use {
                    it.bindLong(1, now)
                    it.bindLong(2, now)
                    it.bindText(3, id)
                    it.step()
                }
            }
            _all.value = _all.value.filter { it.id != id }
        }
    }

    /**
     * Highlights: one per verse, as on iOS (highlighting again changes the
     * colour). The live ones are kept in memory as a map for the reader.
     */
    inner class HighlightStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<Map<VerseId, HighlightColor>> = _all.asStateFlow()

        private fun load(): Map<VerseId, HighlightColor> = synchronized(lock) {
            buildMap {
                connection.prepare("SELECT verse, color FROM highlights WHERE deleted_at IS NULL").use { statement ->
                    while (statement.step()) put(VerseId(statement.getLong(0).toInt()), HighlightColor.withId(statement.getText(1)))
                }
            }
        }

        fun set(verses: Collection<VerseId>, color: HighlightColor, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                transaction {
                    for (verse in verses) {
                        connection.prepare(
                            """
                            INSERT INTO highlights (id, verse, color, created_at, updated_at, deleted_at)
                            VALUES (?, ?, ?, ?, ?, NULL)
                            ON CONFLICT(verse) DO UPDATE SET
                                color = excluded.color,
                                updated_at = excluded.updated_at,
                                created_at = CASE WHEN deleted_at IS NULL THEN created_at ELSE excluded.created_at END,
                                deleted_at = NULL
                            """.trimIndent(),
                        ).use {
                            it.bindText(1, UUID.randomUUID().toString())
                            it.bindLong(2, verse.rawValue.toLong())
                            it.bindText(3, color.id)
                            it.bindLong(4, now)
                            it.bindLong(5, now)
                            it.step()
                        }
                    }
                }
                _all.value = _all.value + verses.associateWith { color }
            }
        }

        fun remove(verses: Collection<VerseId>, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                transaction {
                    for (verse in verses) {
                        connection.prepare("UPDATE highlights SET deleted_at = ?, updated_at = ? WHERE verse = ? AND deleted_at IS NULL").use {
                            it.bindLong(1, now)
                            it.bindLong(2, now)
                            it.bindLong(3, verse.rawValue.toLong())
                            it.step()
                        }
                    }
                }
                _all.value = _all.value - verses.toSet()
            }
        }
    }

    private inline fun transaction(block: () -> Unit) {
        connection.execSQL("BEGIN IMMEDIATE")
        try {
            block()
            connection.execSQL("COMMIT")
        } catch (error: Throwable) {
            connection.execSQL("ROLLBACK")
            throw error
        }
    }

    override fun close() = synchronized(lock) { connection.close() }

    companion object {
        fun open(file: File): UserDatabase {
            file.parentFile?.mkdirs()
            val connection = BundledSQLiteDriver().open(file.path)
            connection.execSQL("PRAGMA journal_mode = WAL")
            return UserDatabase(connection)
        }

        fun open(context: Context): UserDatabase = open(context.getDatabasePath("userdata.sqlite"))
    }
}
