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
)

object SyncTable {
    const val HIGHLIGHTS = "highlights"
    const val BOOKMARKS = "bookmarks"
    const val NOTES = "notes"
}
