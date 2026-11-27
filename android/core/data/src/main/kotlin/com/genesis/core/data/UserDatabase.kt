package com.genesis.core.data

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.execSQL
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.study.HighlightColor
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
    }

    val highlights = HighlightStore()

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
