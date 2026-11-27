package com.genesis.core.bible

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.execSQL
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.search.SearchOrder
import com.genesis.core.domain.search.SearchScope
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

    /** Verses by id, verbatim (Home's and Library's lists); missing ids are left out. */
    fun verses(ids: Collection<VerseId>): Map<VerseId, Verse> = synchronized(lock) {
        if (ids.isEmpty()) return@synchronized emptyMap()
        buildMap {
            for (chunk in ids.distinct().chunked(500)) {
                val marks = chunk.joinToString(",") { "?" }
                connection.prepare("SELECT id, text, paragraph, poetry FROM verses WHERE id IN ($marks)").use { statement ->
                    chunk.forEachIndexed { index, id -> statement.bindLong(index + 1, id.rawValue.toLong()) }
                    while (statement.step()) {
                        val verse = Verse(
                            id = VerseId(statement.getLong(0).toInt()),
                            text = statement.getText(1),
                            startsParagraph = statement.getLong(2) != 0L,
                            isPoetry = statement.getLong(3) != 0L,
                        )
                        put(verse.id, verse)
                    }
                }
            }
        }
    }

    /** The verses from one id through another, in order, verbatim (cross references). */
    fun passage(from: VerseId, through: VerseId, limit: Int = 200): List<Verse> = synchronized(lock) {
        buildList {
            connection.prepare("SELECT id, text, paragraph, poetry FROM verses WHERE id BETWEEN ? AND ? ORDER BY id LIMIT ?").use { statement ->
                statement.bindLong(1, from.rawValue.toLong())
                statement.bindLong(2, maxOf(from.rawValue, through.rawValue).toLong())
                statement.bindLong(3, limit.toLong())
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
    }

    /**
     * Verses matching an FTS5 expression (from `FullTextQuery`, never typed
     * text), verbatim, best match first or in Bible order.
     */
    fun search(matchExpression: String, scope: SearchScope, order: SearchOrder, limit: Int): List<Verse> = synchronized(lock) {
        val range = scope.idRange
        val orderBy = if (order == SearchOrder.RELEVANCE) "f.rank" else "f.rowid"
        buildList {
            connection.prepare(
                """
                SELECT v.id, v.text, v.paragraph, v.poetry
                FROM verses_fts f JOIN verses v ON v.id = f.rowid
                WHERE verses_fts MATCH ? AND f.rowid BETWEEN ? AND ?
                ORDER BY $orderBy
                LIMIT ?
                """.trimIndent(),
            ).use { statement ->
                statement.bindText(1, matchExpression)
                statement.bindLong(2, range.first.toLong())
                statement.bindLong(3, range.last.toLong())
                statement.bindLong(4, limit.toLong())
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
    }

    fun countMatches(matchExpression: String, scope: SearchScope): Int = synchronized(lock) {
        val range = scope.idRange
        connection.prepare("SELECT count(*) FROM verses_fts WHERE verses_fts MATCH ? AND rowid BETWEEN ? AND ?").use { statement ->
            statement.bindText(1, matchExpression)
            statement.bindLong(2, range.first.toLong())
            statement.bindLong(3, range.last.toLong())
            if (statement.step()) statement.getLong(0).toInt() else 0
        }
    }

    /** How many verses the file holds (a whole Bible has over 30,000). */
    fun verseCount(): Int = synchronized(lock) {
        connection.prepare("SELECT count(*) FROM verses").use { if (it.step()) it.getLong(0).toInt() else 0 }
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

        /** Opens a Bible on this phone, bundled or downloaded. */
        fun open(context: Context, bible: InstalledBible): BibleRepository = when {
            bible.bundled != null -> open(context, bible.bundled)
            bible.file != null -> open(bible.file)
            else -> error("${bible.id} has no file")
        }
    }
}

/**
 * Bundled databases live in the APK's assets, which SQLite can't open in
 * place, so each is copied once into no-backup storage (it's part of the
 * app, not the person's data). It's copied again whenever the app is
 * installed or updated (the package's lastUpdateTime, kept beside the copy),
 * so a new Bible file always replaces the old one. Assets are only read as
 * streams: openFd fails on compressed assets.
 */
internal object BundledFiles {
    fun file(context: Context, asset: String): File = synchronized(this) {
        val directory = File(context.noBackupFilesDir, "bundled").apply { mkdirs() }
        val target = File(directory, asset)
        val stamp = File(directory, "$asset.installed")
        val installed = context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime.toString()
        val current = target.exists() && stamp.exists() && stamp.readText() == installed
        if (!current) {
            val partial = File(directory, "$asset.partial")
            context.assets.open(asset).use { input -> partial.outputStream().use { input.copyTo(it) } }
            check(partial.renameTo(target)) { "Couldn't move $asset into place" }
            stamp.writeText(installed)
        }
        target
    }
}
