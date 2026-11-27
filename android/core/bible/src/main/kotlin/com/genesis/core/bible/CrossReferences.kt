package com.genesis.core.bible

import android.content.Context
import androidx.sqlite.SQLiteConnection
import androidx.sqlite.driver.bundled.BundledSQLiteDriver
import androidx.sqlite.driver.bundled.SQLITE_OPEN_READONLY
import androidx.sqlite.execSQL
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId

/** A link from one verse to a related verse or passage (as CrossReference on iOS). */
data class CrossReference(
    val target: VerseId,
    val targetEnd: VerseId,
    /** Community votes from OpenBible.info; higher means more widely agreed. */
    val votes: Int,
) {
    /** "Romans 5:8" or "1 John 4:9–10"; a passage running into another chapter is named by its first verse. */
    fun description(language: String): String {
        val end = if (targetEnd.chapterId == target.chapterId && targetEnd.rawValue > target.rawValue) targetEnd else target
        return ReferenceParser.describe(target.rawValue, end.rawValue, language)
    }
}

/**
 * Cross references from OpenBible.info (CC-BY), based on the Treasury of
 * Scripture Knowledge: the bundled CrossReferences.sqlite, verse ids only.
 * The attribution is shown wherever they appear.
 */
class CrossReferenceRepository private constructor(private val connection: SQLiteConnection) : AutoCloseable {
    private val lock = Any()

    /** The strongest links first. */
    fun references(from: VerseId, limit: Int = 50): List<CrossReference> = synchronized(lock) {
        buildList {
            connection.prepare(
                "SELECT to_start, to_end, votes FROM cross_references WHERE from_id = ? ORDER BY votes DESC LIMIT ?",
            ).use { statement ->
                statement.bindLong(1, from.rawValue.toLong())
                statement.bindLong(2, limit.toLong())
                while (statement.step()) {
                    add(CrossReference(VerseId(statement.getLong(0).toInt()), VerseId(statement.getLong(1).toInt()), statement.getLong(2).toInt()))
                }
            }
        }
    }

    /** Verses in a chapter that have at least one cross reference. */
    fun versesWithReferences(chapter: ChapterId): Set<VerseId> = synchronized(lock) {
        val range = chapter.verseRange
        buildSet {
            connection.prepare("SELECT DISTINCT from_id FROM cross_references WHERE from_id BETWEEN ? AND ?").use { statement ->
                statement.bindLong(1, range.first.toLong())
                statement.bindLong(2, range.last.toLong())
                while (statement.step()) add(VerseId(statement.getLong(0).toInt()))
            }
        }
    }

    override fun close() = synchronized(lock) { connection.close() }

    companion object {
        const val ASSET = "CrossReferences.sqlite"

        fun open(context: Context): CrossReferenceRepository {
            val connection = BundledSQLiteDriver().open(BundledFiles.file(context, ASSET).path, SQLITE_OPEN_READONLY)
            connection.execSQL("PRAGMA query_only = ON")
            return CrossReferenceRepository(connection)
        }
    }
}
