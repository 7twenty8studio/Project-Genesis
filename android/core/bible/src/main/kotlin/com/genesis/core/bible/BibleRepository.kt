package com.genesis.core.bible

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.execSQL
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import java.io.File

/**
 * Read access to one translation's database. The connection is used by one
 * thread at a time; callers run it off the main thread.
 */
class BibleRepository private constructor(private val connection: SQLiteConnection) : AutoCloseable {
    private val lock = Any()

    val translation: Translation = synchronized(lock) {
        val meta = buildMap {
            connection.prepare("SELECT key, value FROM meta").use { statement ->
                while (statement.step()) put(statement.getText(0), statement.getText(1))
            }
        }
        Translation(
            id = meta.getValue("abbreviation"),
            name = meta.getValue("name"),
            abbreviation = meta.getValue("abbreviation"),
            language = meta["language"] ?: "en",
            license = meta["license"] ?: "",
            year = meta["year"],
        )
    }

    /** The chapter's verses and headings, verbatim. */
    fun chapter(id: ChapterId): Chapter = synchronized(lock) {
        val range = id.verseRange
        val verses = buildList {
            connection.prepare(
                "SELECT id, text, paragraph, poetry FROM verses WHERE id BETWEEN ? AND ? ORDER BY id",
            ).use { statement ->
                statement.bindLong(1, range.first.toLong())
                statement.bindLong(2, range.last.toLong())
                while (statement.step()) {
                    add(
                        Verse(
                            id = VerseId(statement.getLong(0).toInt()),
                            text = statement.getText(1),
                            startsParagraph = statement.getLong(2) != 0L,
                            isPoetry = statement.getLong(3) != 0L,
                        ),
                    )
                }
            }
        }
        val headings = buildList {
            connection.prepare(
                "SELECT before_verse, text FROM headings WHERE book = ? AND chapter = ? ORDER BY before_verse",
            ).use { statement ->
                statement.bindLong(1, id.book.toLong())
                statement.bindLong(2, id.chapter.toLong())
                while (statement.step()) add(Heading(statement.getLong(0).toInt(), statement.getText(1)))
            }
        }
        Chapter(id, translation, verses, headings)
    }

    override fun close() = synchronized(lock) { connection.close() }

    companion object {
        /** Opens a database file read-only. */
        fun open(file: File): BibleRepository {
            val connection = BundledSQLiteDriver().open(file.path, SQLITE_OPEN_READONLY)
            connection.execSQL("PRAGMA query_only = ON")
            return BibleRepository(connection)
        }

        /** Opens a bundled Bible, copying it out of the app's assets the first time. */
        fun open(context: Context, bible: BundledBible): BibleRepository =
            open(BundledFiles.file(context, bible.asset))
    }
}

/**
 * Bundled databases live in the APK's assets, which SQLite can't open in
 * place, so each is copied once into no-backup storage (it's part of the
 * app, not the person's data). A new app version with a different file
 * size copies it again.
 */
internal object BundledFiles {
    fun file(context: Context, asset: String): File = synchronized(this) {
        val directory = File(context.noBackupFilesDir, "bundled").apply { mkdirs() }
        val target = File(directory, asset)
        val size = context.assets.openFd(asset).use { it.length }
        if (!target.exists() || target.length() != size) {
            val partial = File(directory, "$asset.partial")
            context.assets.open(asset).use { input -> partial.outputStream().use { input.copyTo(it) } }
            check(partial.renameTo(target)) { "Couldn't move $asset into place" }
        }
        target
    }
}
