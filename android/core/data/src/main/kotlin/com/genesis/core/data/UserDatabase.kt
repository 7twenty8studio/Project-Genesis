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
import com.genesis.core.domain.sync.SyncMerge
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import com.genesis.core.domain.plans.PlanEnrollment
import com.genesis.core.domain.prayer.Prayer
import com.genesis.core.domain.prayer.PrayerCategory
import com.genesis.core.domain.prayer.PrayerPassage
import com.genesis.core.domain.plans.ReadingPlan
import java.io.File
import java.time.LocalDate
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
        if (version < 3) {
            // Server rows to mark deleted that have no local row left to carry
            // the deletion (a second highlight for the same verse from
            // another device), as iOS's Tombstones.
            connection.execSQL(
                """
                CREATE TABLE pending_deletions (
                    record_id TEXT NOT NULL,
                    table_name TEXT NOT NULL,
                    PRIMARY KEY (record_id, table_name)
                )
                """.trimIndent(),
            )
            connection.execSQL("PRAGMA user_version = 3")
        }
        if (version < 4) {
            // Reading plans, as reading_plans on the server: the start day as
            // "yyyy-MM-dd", completed days and a custom plan's books as
            // comma-separated numbers.
            connection.execSQL(
                """
                CREATE TABLE reading_plans (
                    id TEXT PRIMARY KEY NOT NULL,
                    plan_id TEXT NOT NULL,
                    title TEXT NOT NULL,
                    start_date TEXT NOT NULL,
                    completed_days TEXT NOT NULL DEFAULT '',
                    custom_books TEXT,
                    custom_days INTEGER,
                    is_active INTEGER NOT NULL DEFAULT 1,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER
                )
                """.trimIndent(),
            )
            connection.execSQL("PRAGMA user_version = 4")
        }
        if (version < 5) {
            // The prayer journal, as prayers on the server; passages as
            // "start-end" verse ids separated by commas (never the text).
            connection.execSQL(
                """
                CREATE TABLE prayers (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL DEFAULT '',
                    body TEXT NOT NULL DEFAULT '',
                    category TEXT NOT NULL,
                    is_answered INTEGER NOT NULL DEFAULT 0,
                    answered_at INTEGER,
                    answer_note TEXT,
                    reminder_at INTEGER,
                    reminder_repeats_daily INTEGER NOT NULL DEFAULT 0,
                    passages TEXT NOT NULL DEFAULT '',
                    last_prayed_at INTEGER,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER
                )
                """.trimIndent(),
            )
            connection.execSQL("PRAGMA user_version = 5")
        }
    }

    private val _localEdits = MutableStateFlow(0L)

    /** Counts the person's own edits (not sync's), so sync can follow them. */
    val localEdits: StateFlow<Long> = _localEdits.asStateFlow()

    private fun edited() = _localEdits.update { it + 1 }

    val highlights = HighlightStore()
    val bookmarks = BookmarkStore()
    val notes = NoteStore()
    val plans = PlanStore()
    val prayers = PrayerStore()
    val sync = SyncAccess()

    /** Reading plans the person follows, the most recently changed first (as Home picks one on iOS). */
    inner class PlanStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<List<PlanEnrollment>> = _all.asStateFlow()

        internal fun reload() {
            _all.value = load()
        }

        private fun load(): List<PlanEnrollment> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $PLAN_COLUMNS FROM reading_plans WHERE deleted_at IS NULL ORDER BY updated_at DESC").use { s ->
                    while (s.step()) readPlan(s)?.let(::add)
                }
            }
        }

        /** Starts a plan today; the new enrollment. */
        fun start(plan: ReadingPlan, title: String, on: LocalDate, now: Long = System.currentTimeMillis()): PlanEnrollment {
            val enrollment = PlanEnrollment.start(plan, UUID.randomUUID().toString(), title, on).copy(createdAt = now, updatedAt = now)
            synchronized(lock) { transaction { writePlan(enrollment, deletedAt = null) } }
            reload()
            edited()
            return enrollment
        }

        fun setDay(day: Int, completed: Boolean, enrollmentId: String, now: Long = System.currentTimeMillis()) =
            change(enrollmentId, now) { it.copy(completedDays = if (completed) it.completedDays + day else it.completedDays - day) }

        /** Starts the plan again from `on`, clearing progress. */
        fun restart(enrollmentId: String, on: LocalDate, now: Long = System.currentTimeMillis()) =
            change(enrollmentId, now) { it.copy(completedDays = emptySet(), startDate = on, isActive = true) }

        fun delete(enrollmentId: String, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                transaction {
                    connection.prepare("UPDATE reading_plans SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL").use {
                        it.bindLong(1, now)
                        it.bindLong(2, now)
                        it.bindText(3, enrollmentId)
                        it.step()
                    }
                }
            }
            reload()
            edited()
        }

        private fun change(id: String, now: Long, update: (PlanEnrollment) -> PlanEnrollment) {
            val current = _all.value.firstOrNull { it.id == id } ?: return
            synchronized(lock) { transaction { writePlan(update(current).copy(updatedAt = now), deletedAt = null) } }
            reload()
            edited()
        }
    }

    /** The private prayer journal, the most recently changed first. Free, with no limits. */
    inner class PrayerStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<List<Prayer>> = _all.asStateFlow()

        internal fun reload() {
            _all.value = load()
        }

        private fun load(): List<Prayer> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $PRAYER_COLUMNS FROM prayers WHERE deleted_at IS NULL ORDER BY updated_at DESC").use { s ->
                    while (s.step()) add(readPrayer(s))
                }
            }
        }

        /** Saves a new or edited prayer, stamping it with the edit time. */
        fun save(prayer: Prayer, now: Long = System.currentTimeMillis()): Prayer {
            val saved = prayer.copy(createdAt = if (prayer.createdAt == 0L) now else prayer.createdAt, updatedAt = now)
            synchronized(lock) { transaction { writePrayer(saved, deletedAt = null) } }
            reload()
            edited()
            return saved
        }

        fun delete(id: String, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                transaction {
                    connection.prepare("UPDATE prayers SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL").use {
                        it.bindLong(1, now)
                        it.bindLong(2, now)
                        it.bindText(3, id)
                        it.step()
                    }
                }
            }
            reload()
            edited()
        }
    }

    private fun readPrayer(s: androidx.sqlite.SQLiteStatement) = Prayer(
        id = s.getText(0),
        title = s.getText(1),
        body = s.getText(2),
        category = PrayerCategory.lenient(s.getText(3)),
        isAnswered = s.getLong(4) != 0L,
        answeredAt = s.longOrNull(5),
        answerNote = if (s.isNull(6)) null else s.getText(6),
        reminderAt = s.longOrNull(7),
        reminderRepeatsDaily = s.getLong(8) != 0L,
        passages = PrayerPassage.decode(s.getText(9)),
        lastPrayedAt = s.longOrNull(10),
        createdAt = s.getLong(11),
        updatedAt = s.getLong(12),
    )

    private fun writePrayer(prayer: Prayer, deletedAt: Long?) {
        connection.prepare(
            """
            INSERT INTO prayers (id, title, body, category, is_answered, answered_at, answer_note, reminder_at, reminder_repeats_daily, passages, last_prayed_at, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                title = excluded.title, body = excluded.body, category = excluded.category,
                is_answered = excluded.is_answered, answered_at = excluded.answered_at, answer_note = excluded.answer_note,
                reminder_at = excluded.reminder_at, reminder_repeats_daily = excluded.reminder_repeats_daily,
                passages = excluded.passages, last_prayed_at = excluded.last_prayed_at,
                created_at = excluded.created_at, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
            """.trimIndent(),
        ).use {
            fun long(index: Int, value: Long?) = if (value == null) it.bindNull(index) else it.bindLong(index, value)
            it.bindText(1, prayer.id)
            it.bindText(2, prayer.title)
            it.bindText(3, prayer.body)
            it.bindText(4, prayer.category.id)
            it.bindLong(5, if (prayer.isAnswered) 1 else 0)
            long(6, prayer.answeredAt)
            prayer.answerNote?.let { note -> it.bindText(7, note) } ?: it.bindNull(7)
            long(8, prayer.reminderAt)
            it.bindLong(9, if (prayer.reminderRepeatsDaily) 1 else 0)
            it.bindText(10, PrayerPassage.encode(prayer.passages))
            long(11, prayer.lastPrayedAt)
            it.bindLong(12, prayer.createdAt)
            it.bindLong(13, prayer.updatedAt)
            long(14, deletedAt)
            it.step()
        }
    }

    private fun readPlan(s: androidx.sqlite.SQLiteStatement): PlanEnrollment? {
        val start = runCatching { LocalDate.parse(s.getText(3)) }.getOrNull() ?: return null
        return PlanEnrollment(
            id = s.getText(0),
            planId = s.getText(1),
            title = s.getText(2),
            startDate = start,
            completedDays = numbers(s.getText(4)).toSet(),
            customBooks = if (s.isNull(5)) null else numbers(s.getText(5)),
            customDays = s.intOrNull(6),
            isActive = s.getLong(7) != 0L,
            createdAt = s.getLong(8),
            updatedAt = s.getLong(9),
        )
    }

    private fun numbers(text: String): List<Int> = text.split(',').mapNotNull { it.trim().toIntOrNull() }

    private fun writePlan(plan: PlanEnrollment, deletedAt: Long?) {
        connection.prepare(
            """
            INSERT INTO reading_plans (id, plan_id, title, start_date, completed_days, custom_books, custom_days, is_active, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                plan_id = excluded.plan_id, title = excluded.title, start_date = excluded.start_date,
                completed_days = excluded.completed_days, custom_books = excluded.custom_books,
                custom_days = excluded.custom_days, is_active = excluded.is_active,
                created_at = excluded.created_at, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
            """.trimIndent(),
        ).use {
            it.bindText(1, plan.id)
            it.bindText(2, plan.planId)
            it.bindText(3, plan.title)
            it.bindText(4, plan.startDate.toString())
            it.bindText(5, plan.completedDays.sorted().joinToString(","))
            plan.customBooks?.let { books -> it.bindText(6, books.joinToString(",")) } ?: it.bindNull(6)
            plan.customDays?.let { days -> it.bindLong(7, days.toLong()) } ?: it.bindNull(7)
            it.bindLong(8, if (plan.isActive) 1 else 0)
            it.bindLong(9, plan.createdAt)
            it.bindLong(10, plan.updatedAt)
            deletedAt?.let { at -> it.bindLong(11, at) } ?: it.bindNull(11)
            it.step()
        }
    }

    /** Bookmarks, one per chapter as on iOS (rules in `Bookmarks`). */
    inner class BookmarkStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<Set<VerseId>> = _all.asStateFlow()

        internal fun reload() {
            _all.value = load()
        }

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
            edited()
            change.add != null
        }
    }

    /** Notes, newest first. */
    inner class NoteStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<List<Note>> = _all.asStateFlow()

        internal fun reload() {
            _all.value = load()
        }

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
            edited()
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
            edited()
        }
    }

    /**
     * Highlights: one per verse, as on iOS (highlighting again changes the
     * colour). The live ones are kept in memory as a map for the reader,
     * the most recently changed first.
     */
    inner class HighlightStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<Map<VerseId, HighlightColor>> = _all.asStateFlow()

        internal fun reload() {
            _all.value = load()
        }

        private fun load(): Map<VerseId, HighlightColor> = synchronized(lock) {
            buildMap {
                connection.prepare("SELECT verse, color FROM highlights WHERE deleted_at IS NULL ORDER BY updated_at DESC").use { statement ->
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
                // Newest first, so Home's Recently Highlighted reads the front.
                _all.value = verses.associateWith { color } + (_all.value - verses.toSet())
                edited()
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
                edited()
            }
        }
    }

    /**
     * What sync reads and writes, as SyncService does with SwiftData on iOS:
     * rows edited since a time (deleted ones too, so the deletion travels),
     * pulled rows merged by the newest edit, and server rows to mark deleted.
     * Applying pulled rows never counts as the person's edit.
     */
    inner class SyncAccess {
        fun highlightsChanged(since: Long): List<HighlightRecord> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT id, verse, color, created_at, updated_at, deleted_at FROM highlights WHERE updated_at > ?").use { s ->
                    s.bindLong(1, since)
                    while (s.step()) add(HighlightRecord(s.getText(0), s.getLong(1).toInt(), s.getText(2), s.getLong(3), s.getLong(4), s.longOrNull(5)))
                }
            }
        }

        fun bookmarksChanged(since: Long): List<BookmarkRecord> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT id, verse, created_at, updated_at, deleted_at FROM bookmarks WHERE updated_at > ?").use { s ->
                    s.bindLong(1, since)
                    while (s.step()) add(BookmarkRecord(s.getText(0), s.getLong(1).toInt(), s.getLong(2), s.getLong(3), s.longOrNull(4)))
                }
            }
        }

        fun notesChanged(since: Long): List<NoteRecord> = synchronized(lock) {
            buildList {
                connection.prepare(
                    """
                    SELECT id, title, body, kind, anchor_type, start_verse, end_verse, book_number, chapter_number, theme, created_at, updated_at, deleted_at
                    FROM notes WHERE updated_at > ?
                    """.trimIndent(),
                ).use { s ->
                    s.bindLong(1, since)
                    while (s.step()) {
                        add(
                            NoteRecord(
                                id = s.getText(0), title = s.getText(1), body = s.getText(2), kind = s.getText(3), anchorType = s.getText(4),
                                startVerse = s.intOrNull(5), endVerse = s.intOrNull(6), book = s.intOrNull(7), chapter = s.intOrNull(8),
                                theme = if (s.isNull(9)) null else s.getText(9),
                                createdAt = s.getLong(10), updatedAt = s.getLong(11), deletedAt = s.longOrNull(12),
                            ),
                        )
                    }
                }
            }
        }

        /**
         * Pulled highlights, newest edit winning. One highlight per verse: a
         * different record for the same verse gives way to the newer one, and
         * the loser is marked deleted on the server too (as iOS does).
         */
        fun applyHighlights(rows: List<HighlightRecord>) = synchronized(lock) {
            if (rows.isEmpty()) return@synchronized
            transaction {
                for (row in rows) {
                    val local = updatedAt("highlights", row.id)
                    when (SyncMerge.decide(row.updatedAt, row.deletedAt != null, local)) {
                        SyncMerge.Decision.KEEP_LOCAL -> Unit
                        SyncMerge.Decision.DELETE_LOCAL -> markDeleted("highlights", row.id, row.deletedAt ?: row.updatedAt, row.updatedAt)
                        SyncMerge.Decision.APPLY_REMOTE -> {
                            val other = connection.prepare("SELECT id, updated_at, deleted_at FROM highlights WHERE verse = ? AND id != ?").use { s ->
                                s.bindLong(1, row.verse.toLong())
                                s.bindText(2, row.id)
                                if (s.step()) Triple(s.getText(0), s.getLong(1), s.longOrNull(2)) else null
                            }
                            if (other != null) {
                                if (other.third == null && other.second > row.updatedAt) {
                                    queueDeletion("highlights", row.id)
                                    continue
                                }
                                queueDeletion("highlights", other.first)
                                connection.prepare("DELETE FROM highlights WHERE id = ?").use { it.bindText(1, other.first); it.step() }
                            }
                            connection.prepare(
                                """
                                INSERT INTO highlights (id, verse, color, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, ?, NULL)
                                ON CONFLICT(id) DO UPDATE SET verse = excluded.verse, color = excluded.color,
                                    created_at = excluded.created_at, updated_at = excluded.updated_at, deleted_at = NULL
                                """.trimIndent(),
                            ).use {
                                it.bindText(1, row.id)
                                it.bindLong(2, row.verse.toLong())
                                it.bindText(3, row.color)
                                it.bindLong(4, row.createdAt)
                                it.bindLong(5, row.updatedAt)
                                it.step()
                            }
                        }
                    }
                }
            }
            highlights.reload()
        }

        fun applyBookmarks(rows: List<BookmarkRecord>) = synchronized(lock) {
            if (rows.isEmpty()) return@synchronized
            transaction {
                for (row in rows) {
                    when (SyncMerge.decide(row.updatedAt, row.deletedAt != null, updatedAt("bookmarks", row.id))) {
                        SyncMerge.Decision.KEEP_LOCAL -> Unit
                        SyncMerge.Decision.DELETE_LOCAL -> markDeleted("bookmarks", row.id, row.deletedAt ?: row.updatedAt, row.updatedAt)
                        SyncMerge.Decision.APPLY_REMOTE -> connection.prepare(
                            """
                            INSERT INTO bookmarks (id, verse, created_at, updated_at, deleted_at) VALUES (?, ?, ?, ?, NULL)
                            ON CONFLICT(id) DO UPDATE SET verse = excluded.verse, created_at = excluded.created_at,
                                updated_at = excluded.updated_at, deleted_at = NULL
                            """.trimIndent(),
                        ).use {
                            it.bindText(1, row.id)
                            it.bindLong(2, row.verse.toLong())
                            it.bindLong(3, row.createdAt)
                            it.bindLong(4, row.updatedAt)
                            it.step()
                        }
                    }
                }
            }
            bookmarks.reload()
        }

        fun applyNotes(rows: List<NoteRecord>) = synchronized(lock) {
            if (rows.isEmpty()) return@synchronized
            transaction {
                for (row in rows) {
                    when (SyncMerge.decide(row.updatedAt, row.deletedAt != null, updatedAt("notes", row.id))) {
                        SyncMerge.Decision.KEEP_LOCAL -> Unit
                        SyncMerge.Decision.DELETE_LOCAL -> markDeleted("notes", row.id, row.deletedAt ?: row.updatedAt, row.updatedAt)
                        SyncMerge.Decision.APPLY_REMOTE -> connection.prepare(
                            """
                            INSERT INTO notes (id, title, body, kind, anchor_type, start_verse, end_verse, book_number, chapter_number, theme, created_at, updated_at, deleted_at)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                            ON CONFLICT(id) DO UPDATE SET
                                title = excluded.title, body = excluded.body, kind = excluded.kind,
                                anchor_type = excluded.anchor_type, start_verse = excluded.start_verse,
                                end_verse = excluded.end_verse, book_number = excluded.book_number,
                                chapter_number = excluded.chapter_number, theme = excluded.theme,
                                created_at = excluded.created_at, updated_at = excluded.updated_at, deleted_at = NULL
                            """.trimIndent(),
                        ).use {
                            fun bind(index: Int, value: Int?) = if (value == null) it.bindNull(index) else it.bindLong(index, value.toLong())
                            it.bindText(1, row.id)
                            it.bindText(2, row.title)
                            it.bindText(3, row.body)
                            it.bindText(4, row.kind)
                            it.bindText(5, row.anchorType)
                            bind(6, row.startVerse)
                            bind(7, row.endVerse)
                            bind(8, row.book)
                            bind(9, row.chapter)
                            if (row.theme == null) it.bindNull(10) else it.bindText(10, row.theme)
                            it.bindLong(11, row.createdAt)
                            it.bindLong(12, row.updatedAt)
                            it.step()
                        }
                    }
                }
            }
            notes.reload()
        }

        fun plansChanged(since: Long): List<PlanRecord> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $PLAN_COLUMNS, deleted_at FROM reading_plans WHERE updated_at > ?").use { s ->
                    s.bindLong(1, since)
                    while (s.step()) readPlan(s)?.let { add(PlanRecord(it, s.longOrNull(10))) }
                }
            }
        }

        fun applyPlans(rows: List<PlanRecord>) = synchronized(lock) {
            if (rows.isEmpty()) return@synchronized
            transaction {
                for (row in rows) {
                    val plan = row.enrollment
                    when (SyncMerge.decide(plan.updatedAt, row.deletedAt != null, updatedAt("reading_plans", plan.id))) {
                        SyncMerge.Decision.KEEP_LOCAL -> Unit
                        SyncMerge.Decision.DELETE_LOCAL -> markDeleted("reading_plans", plan.id, row.deletedAt ?: plan.updatedAt, plan.updatedAt)
                        SyncMerge.Decision.APPLY_REMOTE -> writePlan(plan, deletedAt = null)
                    }
                }
            }
            plans.reload()
        }

        fun prayersChanged(since: Long): List<PrayerRecord> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $PRAYER_COLUMNS, deleted_at FROM prayers WHERE updated_at > ?").use { s ->
                    s.bindLong(1, since)
                    while (s.step()) add(PrayerRecord(readPrayer(s), s.longOrNull(13)))
                }
            }
        }

        /** Pulled prayers. `keepPassages`: rows from a server without the journal's newer columns leave them alone. */
        fun applyPrayers(rows: List<Pair<PrayerRecord, Boolean>>) = synchronized(lock) {
            if (rows.isEmpty()) return@synchronized
            transaction {
                for ((row, keepPassages) in rows) {
                    val prayer = row.prayer
                    when (SyncMerge.decide(prayer.updatedAt, row.deletedAt != null, updatedAt("prayers", prayer.id))) {
                        SyncMerge.Decision.KEEP_LOCAL -> Unit
                        SyncMerge.Decision.DELETE_LOCAL -> markDeleted("prayers", prayer.id, row.deletedAt ?: prayer.updatedAt, prayer.updatedAt)
                        SyncMerge.Decision.APPLY_REMOTE -> {
                            val local = if (keepPassages) {
                                connection.prepare("SELECT $PRAYER_COLUMNS FROM prayers WHERE id = ?").use { s ->
                                    s.bindText(1, prayer.id)
                                    if (s.step()) readPrayer(s) else null
                                }
                            } else null
                            writePrayer(if (local != null) prayer.copy(passages = local.passages, lastPrayedAt = local.lastPrayedAt) else prayer, deletedAt = null)
                        }
                    }
                }
            }
            prayers.reload()
        }

        /** Server rows to mark deleted, by table. */
        fun pendingDeletions(): Map<String, List<String>> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT table_name, record_id FROM pending_deletions").use { s ->
                    while (s.step()) add(s.getText(0) to s.getText(1))
                }
            }.groupBy({ it.first }, { it.second })
        }

        fun clearPendingDeletions(table: String, ids: Collection<String>) = synchronized(lock) {
            transaction {
                for (id in ids) {
                    connection.prepare("DELETE FROM pending_deletions WHERE table_name = ? AND record_id = ?").use {
                        it.bindText(1, table)
                        it.bindText(2, id)
                        it.step()
                    }
                }
            }
        }

        /** Removes everything the person saved from this device (not from the cloud). */
        fun eraseAll() = synchronized(lock) {
            transaction {
                for (table in listOf("highlights", "bookmarks", "notes", "reading_plans", "prayers", "pending_deletions")) connection.execSQL("DELETE FROM $table")
            }
            highlights.reload()
            bookmarks.reload()
            notes.reload()
            plans.reload()
            prayers.reload()
        }

        private fun updatedAt(table: String, id: String): Long? =
            connection.prepare("SELECT updated_at FROM $table WHERE id = ?").use { s ->
                s.bindText(1, id)
                if (s.step()) s.getLong(0) else null
            }

        private fun markDeleted(table: String, id: String, deletedAt: Long, updatedAt: Long) {
            connection.prepare("UPDATE $table SET deleted_at = ?, updated_at = ? WHERE id = ?").use {
                it.bindLong(1, deletedAt)
                it.bindLong(2, updatedAt)
                it.bindText(3, id)
                it.step()
            }
        }

        private fun queueDeletion(table: String, id: String) {
            connection.prepare("INSERT OR IGNORE INTO pending_deletions (record_id, table_name) VALUES (?, ?)").use {
                it.bindText(1, id)
                it.bindText(2, table)
                it.step()
            }
        }
    }

    private fun androidx.sqlite.SQLiteStatement.longOrNull(column: Int): Long? = if (isNull(column)) null else getLong(column)

    private fun androidx.sqlite.SQLiteStatement.intOrNull(column: Int): Int? = if (isNull(column)) null else getLong(column).toInt()

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
        private const val PRAYER_COLUMNS =
            "id, title, body, category, is_answered, answered_at, answer_note, reminder_at, reminder_repeats_daily, passages, last_prayed_at, created_at, updated_at"
        private const val PLAN_COLUMNS =
            "id, plan_id, title, start_date, completed_days, custom_books, custom_days, is_active, created_at, updated_at"

        fun open(file: File): UserDatabase {
            file.parentFile?.mkdirs()
            val connection = BundledSQLiteDriver().open(file.path)
            connection.execSQL("PRAGMA journal_mode = WAL")
            return UserDatabase(connection)
        }

        fun open(context: Context): UserDatabase = open(context.getDatabasePath("userdata.sqlite"))
    }
}
