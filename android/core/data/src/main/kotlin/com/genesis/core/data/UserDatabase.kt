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
import com.genesis.core.domain.memorise.MemoryGrade
import com.genesis.core.domain.memorise.MemorySchedule
import com.genesis.core.domain.memorise.MemoryVerse
import com.genesis.core.domain.prayer.Prayer
import com.genesis.core.domain.sermons.Sermon
import com.genesis.core.domain.journal.Attachment
import com.genesis.core.domain.journal.AttachmentKind
import com.genesis.core.domain.journal.AttachmentOwner
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
        if (version < 6) {
            // Memorize (Premium), as memory_verses on the server: verse ids and the schedule, never the text.
            connection.execSQL(
                """
                CREATE TABLE memory_verses (
                    id TEXT PRIMARY KEY NOT NULL,
                    start_verse INTEGER NOT NULL,
                    end_verse INTEGER NOT NULL,
                    translation_id TEXT NOT NULL,
                    ease REAL NOT NULL,
                    interval_days REAL NOT NULL,
                    repetitions INTEGER NOT NULL,
                    due_at INTEGER NOT NULL,
                    last_reviewed_at INTEGER,
                    review_count INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER
                )
                """.trimIndent(),
            )
            connection.execSQL("PRAGMA user_version = 6")
        }
        if (version < 7) {
            // Sermon Notes, as sermons on the server: passages as "start-end" ids,
            // never the text. The church sermon id and handouts (JSON) come from
            // the iPhone and are kept as they are.
            connection.execSQL(
                """
                CREATE TABLE sermons (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL DEFAULT '',
                    preacher TEXT NOT NULL DEFAULT '',
                    church TEXT NOT NULL DEFAULT '',
                    preached_at INTEGER NOT NULL,
                    series TEXT,
                    body TEXT NOT NULL DEFAULT '',
                    passages TEXT NOT NULL DEFAULT '',
                    is_favourite INTEGER NOT NULL DEFAULT 0,
                    source_sermon_id TEXT,
                    handouts TEXT,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER
                )
                """.trimIndent(),
            )
            connection.execSQL("PRAGMA user_version = 7")
        }
        if (version < 8) {
            // Journal attachments, as attachments on the server: what each file
            // is and what it belongs to. The file itself is on the device
            // (Attachments/<id>.<ext>), never in the database. Kept on this
            // device for now: these rows aren't synced.
            connection.execSQL(
                """
                CREATE TABLE attachments (
                    id TEXT PRIMARY KEY NOT NULL,
                    owner_kind TEXT NOT NULL,
                    owner_id TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    byte_size INTEGER NOT NULL,
                    duration REAL,
                    page_count INTEGER,
                    caption TEXT,
                    sort_order INTEGER NOT NULL DEFAULT 0,
                    created_at INTEGER NOT NULL,
                    updated_at INTEGER NOT NULL,
                    deleted_at INTEGER
                )
                """.trimIndent(),
            )
            connection.execSQL("CREATE INDEX attachments_owner ON attachments (owner_id)")
            connection.execSQL("PRAGMA user_version = 8")
        }
        if (version < 9) {
            // Attachments sync: where the file is kept beyond this device (the
            // person's Google Drive, or an iPhone's iCloud), and whether this
            // device still has to copy it there.
            connection.execSQL("ALTER TABLE attachments ADD COLUMN storage_path TEXT")
            connection.execSQL("ALTER TABLE attachments ADD COLUMN needs_upload INTEGER NOT NULL DEFAULT 0")
            connection.execSQL("UPDATE attachments SET needs_upload = 1 WHERE deleted_at IS NULL")
            connection.execSQL("PRAGMA user_version = 9")
        }
        if (version < 10) {
            // Handwritten pages in Versely Ink, shared with the iPhone: the page,
            // whether it was edited here since the last push, and whether the
            // server has only an iPhone's PencilKit page.
            connection.execSQL("ALTER TABLE notes ADD COLUMN ink TEXT")
            connection.execSQL("ALTER TABLE notes ADD COLUMN ink_edited INTEGER NOT NULL DEFAULT 0")
            connection.execSQL("ALTER TABLE notes ADD COLUMN iphone_page INTEGER NOT NULL DEFAULT 0")
            connection.execSQL("PRAGMA user_version = 10")
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
    val memory = MemoryStore()
    val sermons = SermonStore()
    val attachments = AttachmentStore()
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

    /** Passages being learned by heart (Memorize), the soonest due first. */
    inner class MemoryStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<List<MemoryVerse>> = _all.asStateFlow()

        internal fun reload() {
            _all.value = load()
        }

        private fun load(): List<MemoryVerse> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $MEMORY_COLUMNS FROM memory_verses WHERE deleted_at IS NULL ORDER BY due_at").use { s ->
                    while (s.step()) add(readMemory(s))
                }
            }
        }

        /** Adds a passage to learn, or returns the one already there. */
        fun memorise(start: VerseId, end: VerseId, translationId: String, now: Long = System.currentTimeMillis()): MemoryVerse {
            val last = maxOf(end, start)
            _all.value.firstOrNull { it.start == start && it.end == last }?.let { return it }
            val verse = MemoryVerse(
                id = UUID.randomUUID().toString(),
                start = start,
                end = last,
                translationId = translationId,
                schedule = MemorySchedule(dueAt = now),
                createdAt = now,
                updatedAt = now,
            )
            synchronized(lock) { transaction { writeMemory(verse, deletedAt = null) } }
            reload()
            edited()
            return verse
        }

        fun review(id: String, grade: MemoryGrade, now: Long = System.currentTimeMillis()) {
            val verse = _all.value.firstOrNull { it.id == id } ?: return
            synchronized(lock) { transaction { writeMemory(verse.reviewed(grade, now), deletedAt = null) } }
            reload()
            edited()
        }

        /**
         * A finished game counts as a review only for a passage that's due:
         * extra practice helps memory without moving the schedule. True when recorded.
         */
        fun recordGame(id: String, grade: MemoryGrade, now: Long = System.currentTimeMillis()): Boolean {
            val verse = _all.value.firstOrNull { it.id == id } ?: return false
            if (!verse.isDue(now)) return false
            review(id, grade, now)
            return true
        }

        fun delete(id: String, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                transaction {
                    connection.prepare("UPDATE memory_verses SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL").use {
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

    /** Photos, recordings and PDFs on prayers and sermon notes; the files are the app's to keep. */
    inner class AttachmentStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<List<Attachment>> = _all.asStateFlow()

        private fun load(): List<Attachment> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $ATTACHMENT_COLUMNS FROM attachments WHERE deleted_at IS NULL ORDER BY sort_order, created_at").use { s ->
                    while (s.step()) readAttachment(s)?.let(::add)
                }
            }
        }

        fun of(owner: AttachmentOwner, ownerId: String): List<Attachment> =
            _all.value.filter { it.owner == owner && it.ownerId == ownerId }

        /** Adds one after the others already on its prayer or sermon. */
        fun add(attachment: Attachment, now: Long = System.currentTimeMillis()): Attachment {
            val order = (of(attachment.owner, attachment.ownerId).maxOfOrNull { it.sortOrder } ?: -1) + 1
            val saved = attachment.copy(sortOrder = order, createdAt = now, updatedAt = now)
            synchronized(lock) { writeAttachment(saved, deletedAt = null, needsUpload = true) }
            _all.value = load()
            return saved
        }

        internal fun reload() {
            _all.value = load()
        }

        /** Files this device still has to copy to the person's Drive. */
        fun pendingUploads(): List<Attachment> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $ATTACHMENT_COLUMNS FROM attachments WHERE deleted_at IS NULL AND needs_upload = 1 ORDER BY created_at").use { s ->
                    while (s.step()) readAttachment(s)?.let(::add)
                }
            }
        }

        /** The file is in the person's Drive: the row says where, so it can sync. */
        fun uploaded(id: String, storagePath: String, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                connection.prepare("UPDATE attachments SET storage_path = ?, needs_upload = 0, updated_at = ? WHERE id = ?").use {
                    it.bindText(1, storagePath)
                    it.bindLong(2, now)
                    it.bindText(3, id)
                    it.step()
                }
            }
            _all.value = load()
            edited()
        }

        /** Marks one removed and returns it, so its file can go too. */
        fun delete(id: String, now: Long = System.currentTimeMillis()): Attachment? {
            val removed = _all.value.firstOrNull { it.id == id } ?: return null
            markDeleted("id = ?", id, now)
            return removed
        }

        /** Everything on a prayer or sermon that was deleted; returns them so their files can go. */
        fun deleteOwner(ownerId: String, now: Long = System.currentTimeMillis()): List<Attachment> {
            val removed = _all.value.filter { it.ownerId == ownerId }
            if (removed.isNotEmpty()) markDeleted("owner_id = ?", ownerId, now)
            return removed
        }

        private fun markDeleted(where: String, value: String, now: Long) {
            synchronized(lock) {
                connection.prepare("UPDATE attachments SET deleted_at = ?, updated_at = ? WHERE $where AND deleted_at IS NULL").use {
                    it.bindLong(1, now)
                    it.bindLong(2, now)
                    it.bindText(3, value)
                    it.step()
                }
            }
            _all.value = load()
            edited()
        }
    }

    private fun readAttachment(s: androidx.sqlite.SQLiteStatement): Attachment? {
        val owner = AttachmentOwner.of(s.getText(1)) ?: return null
        val kind = AttachmentKind.of(s.getText(3)) ?: return null
        return Attachment(
            id = s.getText(0),
            owner = owner,
            ownerId = s.getText(2),
            kind = kind,
            byteSize = s.getLong(4),
            durationSeconds = if (s.isNull(5)) null else s.getDouble(5),
            pageCount = s.intOrNull(6),
            caption = if (s.isNull(7)) null else s.getText(7),
            sortOrder = s.getLong(8).toInt(),
            createdAt = s.getLong(9),
            updatedAt = s.getLong(10),
            storagePath = if (s.isNull(11)) null else s.getText(11),
        )
    }

    private fun writeAttachment(a: Attachment, deletedAt: Long?, needsUpload: Boolean) {
        connection.prepare(
            "INSERT INTO attachments (id, owner_kind, owner_id, kind, byte_size, duration, page_count, caption, sort_order, created_at, updated_at, storage_path, needs_upload, deleted_at) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) " +
                "ON CONFLICT(id) DO UPDATE SET owner_kind = excluded.owner_kind, owner_id = excluded.owner_id, kind = excluded.kind, byte_size = excluded.byte_size, " +
                "duration = excluded.duration, page_count = excluded.page_count, caption = excluded.caption, sort_order = excluded.sort_order, created_at = excluded.created_at, " +
                "updated_at = excluded.updated_at, storage_path = excluded.storage_path, needs_upload = excluded.needs_upload, deleted_at = excluded.deleted_at",
        ).use {
            it.bindText(1, a.id)
            it.bindText(2, a.owner.id)
            it.bindText(3, a.ownerId)
            it.bindText(4, a.kind.id)
            it.bindLong(5, a.byteSize)
            a.durationSeconds?.let { d -> it.bindDouble(6, d) } ?: it.bindNull(6)
            a.pageCount?.let { n -> it.bindLong(7, n.toLong()) } ?: it.bindNull(7)
            a.caption?.let { c -> it.bindText(8, c) } ?: it.bindNull(8)
            it.bindLong(9, a.sortOrder.toLong())
            it.bindLong(10, a.createdAt)
            it.bindLong(11, a.updatedAt)
            a.storagePath?.let { p -> it.bindText(12, p) } ?: it.bindNull(12)
            it.bindLong(13, if (needsUpload) 1 else 0)
            deletedAt?.let { d -> it.bindLong(14, d) } ?: it.bindNull(14)
            it.step()
        }
    }

    /** Sermon Notes, the most recently preached first. Free, with no limits. */
    inner class SermonStore {
        private val _all = MutableStateFlow(load())
        val all: StateFlow<List<Sermon>> = _all.asStateFlow()

        internal fun reload() {
            _all.value = load()
        }

        private fun load(): List<Sermon> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $SERMON_COLUMNS FROM sermons WHERE deleted_at IS NULL ORDER BY preached_at DESC").use { s ->
                    while (s.step()) add(readSermon(s))
                }
            }
        }

        fun get(id: String): Sermon? = _all.value.firstOrNull { it.id == id }

        /** Saves new or edited notes, stamping them with the edit time. */
        fun save(sermon: Sermon, now: Long = System.currentTimeMillis()): Sermon {
            val saved = sermon.copy(createdAt = if (sermon.createdAt == 0L) now else sermon.createdAt, updatedAt = now)
            synchronized(lock) { transaction { writeSermon(saved, deletedAt = null) } }
            reload()
            edited()
            return saved
        }

        fun delete(id: String, now: Long = System.currentTimeMillis()) {
            synchronized(lock) {
                transaction {
                    connection.prepare("UPDATE sermons SET deleted_at = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL").use {
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

    private fun readSermon(s: androidx.sqlite.SQLiteStatement) = Sermon(
        id = s.getText(0),
        title = s.getText(1),
        preacher = s.getText(2),
        church = s.getText(3),
        preachedAt = s.getLong(4),
        series = if (s.isNull(5)) null else s.getText(5),
        body = s.getText(6),
        passages = PrayerPassage.decode(s.getText(7)),
        isFavourite = s.getLong(8) != 0L,
        sourceSermonId = if (s.isNull(9)) null else s.getText(9),
        handoutsJson = if (s.isNull(10)) null else s.getText(10),
        createdAt = s.getLong(11),
        updatedAt = s.getLong(12),
    )

    private fun writeSermon(sermon: Sermon, deletedAt: Long?) {
        connection.prepare(
            """
            INSERT INTO sermons (id, title, preacher, church, preached_at, series, body, passages, is_favourite, source_sermon_id, handouts, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET title = excluded.title, preacher = excluded.preacher, church = excluded.church,
                preached_at = excluded.preached_at, series = excluded.series, body = excluded.body, passages = excluded.passages,
                is_favourite = excluded.is_favourite, source_sermon_id = excluded.source_sermon_id, handouts = excluded.handouts,
                created_at = excluded.created_at, updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
            """.trimIndent(),
        ).use {
            fun text(index: Int, value: String?) = if (value == null) it.bindNull(index) else it.bindText(index, value)
            it.bindText(1, sermon.id)
            it.bindText(2, sermon.title)
            it.bindText(3, sermon.preacher)
            it.bindText(4, sermon.church)
            it.bindLong(5, sermon.preachedAt)
            text(6, sermon.series)
            it.bindText(7, sermon.body)
            it.bindText(8, PrayerPassage.encode(sermon.passages))
            it.bindLong(9, if (sermon.isFavourite) 1 else 0)
            text(10, sermon.sourceSermonId)
            text(11, sermon.handoutsJson)
            it.bindLong(12, sermon.createdAt)
            it.bindLong(13, sermon.updatedAt)
            deletedAt?.let { at -> it.bindLong(14, at) } ?: it.bindNull(14)
            it.step()
        }
    }

    private fun readMemory(s: androidx.sqlite.SQLiteStatement) = MemoryVerse(
        id = s.getText(0),
        start = VerseId(s.getLong(1).toInt()),
        end = VerseId(s.getLong(2).toInt()),
        translationId = s.getText(3),
        schedule = MemorySchedule(s.getDouble(4), s.getDouble(5), s.getLong(6).toInt(), s.getLong(7)),
        lastReviewedAt = s.longOrNull(8),
        reviewCount = s.getLong(9).toInt(),
        createdAt = s.getLong(10),
        updatedAt = s.getLong(11),
    )

    private fun writeMemory(verse: MemoryVerse, deletedAt: Long?) {
        connection.prepare(
            """
            INSERT INTO memory_verses (id, start_verse, end_verse, translation_id, ease, interval_days, repetitions, due_at, last_reviewed_at, review_count, created_at, updated_at, deleted_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET start_verse = excluded.start_verse, end_verse = excluded.end_verse, translation_id = excluded.translation_id,
                ease = excluded.ease, interval_days = excluded.interval_days, repetitions = excluded.repetitions, due_at = excluded.due_at,
                last_reviewed_at = excluded.last_reviewed_at, review_count = excluded.review_count, created_at = excluded.created_at,
                updated_at = excluded.updated_at, deleted_at = excluded.deleted_at
            """.trimIndent(),
        ).use {
            it.bindText(1, verse.id)
            it.bindLong(2, verse.start.rawValue.toLong())
            it.bindLong(3, verse.end.rawValue.toLong())
            it.bindText(4, verse.translationId)
            it.bindDouble(5, verse.schedule.ease)
            it.bindDouble(6, verse.schedule.intervalDays)
            it.bindLong(7, verse.schedule.repetitions.toLong())
            it.bindLong(8, verse.schedule.dueAt)
            verse.lastReviewedAt?.let { at -> it.bindLong(9, at) } ?: it.bindNull(9)
            it.bindLong(10, verse.reviewCount.toLong())
            it.bindLong(11, verse.createdAt)
            it.bindLong(12, verse.updatedAt)
            deletedAt?.let { at -> it.bindLong(13, at) } ?: it.bindNull(13)
            it.step()
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
                    SELECT id, title, body, kind, anchor_type, start_verse, end_verse, book_number, chapter_number, theme, created_at, updated_at,
                        ink IS NOT NULL, iphone_page
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
                                hasPage = s.getLong(12) != 0L,
                                pageOnIPhone = s.getLong(13) != 0L,
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

        /** A note's handwritten page in Versely Ink, or null (read on its own: pages can be large). */
        fun page(id: String): String? = synchronized(lock) {
            connection.prepare("SELECT ink FROM notes WHERE id = ?").use { s ->
                s.bindText(1, id)
                if (s.step() && !s.isNull(0)) s.getText(0) else null
            }
        }

        /** Saves a note's page (null clears it); the note must be saved already. */
        fun savePage(id: String, ink: String?, now: Long = System.currentTimeMillis()) = synchronized(lock) {
            transaction {
                connection.prepare("UPDATE notes SET ink = ?, ink_edited = 1, iphone_page = 0, updated_at = ? WHERE id = ?").use {
                    if (ink == null) it.bindNull(1) else it.bindText(1, ink)
                    it.bindLong(2, now)
                    it.bindText(3, id)
                    it.step()
                }
            }
            _all.value = _all.value.map { if (it.id == id) it.copy(hasPage = ink != null, pageOnIPhone = false, updatedAt = now) else it }
                .sortedByDescending { it.updatedAt }
            edited()
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

        /** Every highlight with the day it was made (Year in Review). */
        fun dated(): List<Triple<VerseId, HighlightColor, Long>> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT verse, color, created_at FROM highlights WHERE deleted_at IS NULL").use { statement ->
                    while (statement.step()) add(Triple(VerseId(statement.getLong(0).toInt()), HighlightColor.withId(statement.getText(1)), statement.getLong(2)))
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
                    SELECT id, title, body, kind, anchor_type, start_verse, end_verse, book_number, chapter_number, theme, created_at, updated_at, deleted_at,
                        ink, ink_edited
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
                                ink = if (s.isNull(13)) null else s.getText(13), inkEdited = s.getLong(14) != 0L,
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
                            INSERT INTO notes (id, title, body, kind, anchor_type, start_verse, end_verse, book_number, chapter_number, theme, created_at, updated_at, deleted_at, ink, ink_edited, iphone_page)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, 0, ?)
                            ON CONFLICT(id) DO UPDATE SET
                                title = excluded.title, body = excluded.body, kind = excluded.kind,
                                anchor_type = excluded.anchor_type, start_verse = excluded.start_verse,
                                end_verse = excluded.end_verse, book_number = excluded.book_number,
                                chapter_number = excluded.chapter_number, theme = excluded.theme,
                                created_at = excluded.created_at, updated_at = excluded.updated_at, deleted_at = NULL,
                                ink = excluded.ink, ink_edited = 0, iphone_page = excluded.iphone_page
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
                            // A page too large to sync never reached the server: it stays here (as iOS).
                            val local = connection.prepare("SELECT ink FROM notes WHERE id = ?").use { s -> s.bindText(1, row.id); if (s.step() && !s.isNull(0)) s.getText(0) else null }
                            val ink = if (!com.genesis.core.domain.study.InkFormat.fitsSync(local) && row.ink == null) local else row.ink
                            if (ink == null) it.bindNull(13) else it.bindText(13, ink)
                            it.bindLong(14, if (ink == null && row.hasDrawing) 1 else 0)
                            it.step()
                        }
                    }
                }
            }
            notes.reload()
        }

        /** The pages pushed: the server's PencilKit copy of them is now cleared. */
        fun inkPushed(ids: List<String>) = synchronized(lock) {
            transaction {
                for (id in ids) connection.prepare("UPDATE notes SET ink_edited = 0 WHERE id = ?").use { it.bindText(1, id); it.step() }
            }
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

        fun memoryChanged(since: Long): List<MemoryRecord> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $MEMORY_COLUMNS, deleted_at FROM memory_verses WHERE updated_at > ?").use { s ->
                    s.bindLong(1, since)
                    while (s.step()) add(MemoryRecord(readMemory(s), s.longOrNull(12)))
                }
            }
        }

        fun applyMemory(rows: List<MemoryRecord>) = synchronized(lock) {
            if (rows.isEmpty()) return@synchronized
            transaction {
                for (row in rows) {
                    val verse = row.verse
                    when (SyncMerge.decide(verse.updatedAt, row.deletedAt != null, updatedAt("memory_verses", verse.id))) {
                        SyncMerge.Decision.KEEP_LOCAL -> Unit
                        SyncMerge.Decision.DELETE_LOCAL -> markDeleted("memory_verses", verse.id, row.deletedAt ?: verse.updatedAt, verse.updatedAt)
                        SyncMerge.Decision.APPLY_REMOTE -> writeMemory(verse, deletedAt = null)
                    }
                }
            }
            memory.reload()
        }

        fun sermonsChanged(since: Long): List<SermonRecord> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $SERMON_COLUMNS, deleted_at FROM sermons WHERE updated_at > ?").use { s ->
                    s.bindLong(1, since)
                    while (s.step()) add(SermonRecord(readSermon(s), s.longOrNull(13)))
                }
            }
        }

        fun applySermons(rows: List<SermonRecord>) = synchronized(lock) {
            if (rows.isEmpty()) return@synchronized
            transaction {
                for (row in rows) {
                    val sermon = row.sermon
                    when (SyncMerge.decide(sermon.updatedAt, row.deletedAt != null, updatedAt("sermons", sermon.id))) {
                        SyncMerge.Decision.KEEP_LOCAL -> Unit
                        SyncMerge.Decision.DELETE_LOCAL -> markDeleted("sermons", sermon.id, row.deletedAt ?: sermon.updatedAt, sermon.updatedAt)
                        SyncMerge.Decision.APPLY_REMOTE -> writeSermon(sermon, deletedAt = null)
                    }
                }
            }
            sermons.reload()
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
        /** Attachment rows edited since then, deletions included; only those whose file is in Drive (or that came from another device) reach the server. */
        fun attachmentsChanged(since: Long): List<AttachmentRecord> = synchronized(lock) {
            buildList {
                connection.prepare("SELECT $ATTACHMENT_COLUMNS, deleted_at FROM attachments WHERE updated_at > ? AND storage_path IS NOT NULL").use { s ->
                    s.bindLong(1, since)
                    while (s.step()) readAttachment(s)?.let { add(AttachmentRecord(it, s.longOrNull(12))) }
                }
            }
        }

        /** Applies pulled rows (newest edit wins); returns the attachments removed here, so their files can go. */
        fun applyAttachments(rows: List<AttachmentRecord>): List<Attachment> = synchronized(lock) {
            if (rows.isEmpty()) return@synchronized emptyList()
            val removed = mutableListOf<Attachment>()
            transaction {
                for (row in rows) {
                    val a = row.attachment
                    when (SyncMerge.decide(a.updatedAt, row.deletedAt != null, updatedAt("attachments", a.id))) {
                        SyncMerge.Decision.KEEP_LOCAL -> Unit
                        SyncMerge.Decision.DELETE_LOCAL -> {
                            attachments.all.value.firstOrNull { it.id == a.id }?.let(removed::add)
                            markDeleted("attachments", a.id, row.deletedAt ?: a.updatedAt, a.updatedAt)
                        }
                        SyncMerge.Decision.APPLY_REMOTE -> writeAttachment(a, deletedAt = null, needsUpload = false)
                    }
                }
            }
            attachments.reload()
            removed
        }

        fun eraseAll() = synchronized(lock) {
            transaction {
                for (table in listOf("highlights", "bookmarks", "notes", "reading_plans", "prayers", "memory_verses", "sermons", "attachments", "pending_deletions")) connection.execSQL("DELETE FROM $table")
            }
            attachments.reload()
            highlights.reload()
            bookmarks.reload()
            notes.reload()
            plans.reload()
            prayers.reload()
            memory.reload()
            sermons.reload()
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
        private const val ATTACHMENT_COLUMNS =
            "id, owner_kind, owner_id, kind, byte_size, duration, page_count, caption, sort_order, created_at, updated_at, storage_path"
        private const val SERMON_COLUMNS =
            "id, title, preacher, church, preached_at, series, body, passages, is_favourite, source_sermon_id, handouts, created_at, updated_at"
        private const val MEMORY_COLUMNS =
            "id, start_verse, end_verse, translation_id, ease, interval_days, repetitions, due_at, last_reviewed_at, review_count, created_at, updated_at"
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
