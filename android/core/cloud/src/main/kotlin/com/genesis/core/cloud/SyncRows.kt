package com.genesis.core.cloud

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

// Rows as stored in Supabase (supabase/migrations), as SyncRows.swift on iOS.
// Times are timestamps in text; `server_updated_at` is set by the database
// and kept as the raw string so paging cursors keep full precision.

/** Postgres and GoTrue timestamps, e.g. "2026-09-29T17:46:00.123456+00:00", as Timestamp on iOS. */
object Timestamps {
    /** Milliseconds, as the server stores what iOS sends ("…T17:46:00.123Z"). */
    fun string(millis: Long): String = DateTimeFormatter.ISO_INSTANT.format(Instant.ofEpochMilli(millis).truncatedTo(ChronoUnit.MILLIS))
        .let { if ('.' in it) it else it.removeSuffix("Z") + ".000Z" }

    /** Read at millisecond precision (Postgres may write a space instead of "T"). */
    fun millis(text: String): Long? = runCatching {
        OffsetDateTime.parse(text.trim().replace(' ', 'T').let { if (it.endsWith("+00")) "$it:00" else it }).toInstant().toEpochMilli()
    }.getOrNull()
}

@Serializable
data class RemoteHighlight(
    val id: String,
    @SerialName("user_id") val userId: String,
    val verse: Int,
    val color: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

@Serializable
data class RemoteBookmark(
    val id: String,
    @SerialName("user_id") val userId: String,
    val verse: Int,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

/**
 * A note. Android never sends `drawing` (the handwritten page iOS keeps), so
 * a note edited here keeps its page on the server and on the iPhone.
 */
@Serializable
data class RemoteNote(
    val id: String,
    @SerialName("user_id") val userId: String,
    val title: String = "",
    val body: String = "",
    val kind: String,
    @SerialName("anchor_type") val anchorType: String,
    @SerialName("start_verse") val startVerse: Int? = null,
    @SerialName("end_verse") val endVerse: Int? = null,
    val book: Int? = null,
    val chapter: Int? = null,
    val theme: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
    /** The handwritten page in Versely Ink (docs/HANDWRITING_FORMAT.md). Sent only when there's one or it changed. */
    val ink: String? = null,
    /** An iPhone's PencilKit page (base64); read only to know there is one, never sent but as null. */
    val drawing: String? = null,
)

/** A reading plan enrollment; `start_date` is a day ("yyyy-MM-dd"). */
@Serializable
data class RemotePlan(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("plan_id") val planId: String,
    val title: String = "",
    @SerialName("start_date") val startDate: String,
    @SerialName("completed_days") val completedDays: List<Int> = emptyList(),
    @SerialName("custom_books") val customBooks: List<Int>? = null,
    @SerialName("custom_days") val customDays: Int? = null,
    @SerialName("is_active") val isActive: Boolean = true,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

/** A passage on a prayer, as in prayers.passages (jsonb): verse ids only. */
@Serializable
data class RemotePrayerPassage(
    @SerialName("start_verse") val startVerse: Int,
    @SerialName("end_verse") val endVerse: Int,
)

/**
 * A prayer. `passages` is null in rows from a server without the journal's
 * newer columns; the device's passages are then kept.
 */
@Serializable
data class RemotePrayer(
    val id: String,
    @SerialName("user_id") val userId: String,
    val title: String = "",
    val body: String = "",
    val category: String,
    @SerialName("is_answered") val isAnswered: Boolean = false,
    @SerialName("answered_at") val answeredAt: String? = null,
    @SerialName("answer_note") val answerNote: String? = null,
    @SerialName("reminder_at") val reminderAt: String? = null,
    @SerialName("reminder_repeats_daily") val reminderRepeatsDaily: Boolean = false,
    val passages: List<RemotePrayerPassage>? = null,
    @SerialName("last_prayed_at") val lastPrayedAt: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

/** A passage being memorized: verse ids and the review schedule, never the text. */
@Serializable
data class RemoteMemoryVerse(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("start_verse") val startVerse: Int,
    @SerialName("end_verse") val endVerse: Int,
    @SerialName("translation_id") val translationId: String,
    val ease: Double = 2.5,
    @SerialName("interval_days") val intervalDays: Double = 0.0,
    val repetitions: Int = 0,
    @SerialName("due_at") val dueAt: String,
    @SerialName("last_reviewed_at") val lastReviewedAt: String? = null,
    @SerialName("review_count") val reviewCount: Int = 0,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

/**
 * Sermon notes as pulled. `source_sermon_id` and `handouts` (church sermons,
 * written by the iPhone) are read so they're kept on this device.
 */
@Serializable
data class RemoteSermon(
    val id: String,
    @SerialName("user_id") val userId: String,
    val title: String = "",
    val preacher: String = "",
    val church: String = "",
    @SerialName("preached_at") val preachedAt: String? = null,
    val series: String? = null,
    val body: String = "",
    val passages: List<RemotePrayerPassage> = emptyList(),
    @SerialName("is_favourite") val isFavourite: Boolean = false,
    @SerialName("source_sermon_id") val sourceSermonId: String? = null,
    val handouts: kotlinx.serialization.json.JsonElement? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

/**
 * Sermon notes as pushed. `source_sermon_id` and `handouts` are added only
 * when set (SyncService), so an edit never clears what the iPhone saved.
 */
@Serializable
data class RemoteSermonPush(
    val id: String,
    @SerialName("user_id") val userId: String,
    val title: String,
    val preacher: String,
    val church: String,
    @SerialName("preached_at") val preachedAt: String,
    val series: String?,
    val body: String,
    val passages: List<RemotePrayerPassage>,
    @SerialName("is_favourite") val isFavourite: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
)

/**
 * An attachment's details, as public.attachments (the file itself is in the
 * person's own Google Drive or iCloud, at `storage_path`). Push and pull alike.
 */
@Serializable
data class RemoteAttachment(
    val id: String,
    @SerialName("user_id") val userId: String,
    @SerialName("owner_kind") val ownerKind: String,
    @SerialName("owner_id") val ownerId: String,
    val kind: String,
    @SerialName("storage_path") val storagePath: String,
    val bytes: Long = 0,
    @SerialName("duration_seconds") val durationSeconds: Double? = null,
    @SerialName("page_count") val pageCount: Int? = null,
    val caption: String = "",
    @SerialName("sort_order") val sortOrder: Int = 0,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
    @SerialName("server_updated_at") val serverUpdatedAt: String? = null,
)

object SyncTable {
    const val HIGHLIGHTS = "highlights"
    const val BOOKMARKS = "bookmarks"
    const val NOTES = "notes"
    const val READING_PLANS = "reading_plans"
    const val PRAYERS = "prayers"
    const val MEMORY_VERSES = "memory_verses"
    const val SERMONS = "sermons"
    const val ATTACHMENTS = "attachments"
}
