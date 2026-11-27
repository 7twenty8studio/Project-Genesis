package com.genesis.core.data

// Rows as sync moves them: every column, deleted ones included. Times are
// milliseconds since 1970 (the server keeps them as timestamptz).

data class HighlightRecord(
    val id: String,
    val verse: Int,
    val color: String,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

data class BookmarkRecord(
    val id: String,
    val verse: Int,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
)

data class NoteRecord(
    val id: String,
    val title: String,
    val body: String,
    val kind: String,
    val anchorType: String,
    val startVerse: Int?,
    val endVerse: Int?,
    val book: Int?,
    val chapter: Int?,
    val theme: String?,
    val createdAt: Long,
    val updatedAt: Long,
    val deletedAt: Long?,
    /** The handwritten page in Versely Ink (docs/HANDWRITING_FORMAT.md), or null. */
    val ink: String? = null,
    /** Pushing: the page was edited here, so the server's PencilKit copy (notes.drawing) is out of date. */
    val inkEdited: Boolean = false,
    /** Pulling: the server has a PencilKit page (notes.drawing). */
    val hasDrawing: Boolean = false,
)

/** A reading plan enrollment as sync moves it (the plan's rules are in core:domain). */
data class PlanRecord(
    val enrollment: com.genesis.core.domain.plans.PlanEnrollment,
    val deletedAt: Long?,
)

/** A prayer as sync moves it. */
data class PrayerRecord(
    val prayer: com.genesis.core.domain.prayer.Prayer,
    val deletedAt: Long?,
)

/** A Memorize passage as sync moves it. */
data class MemoryRecord(
    val verse: com.genesis.core.domain.memorise.MemoryVerse,
    val deletedAt: Long?,
)

/** Sermon notes as sync moves them. */
data class SermonRecord(
    val sermon: com.genesis.core.domain.sermons.Sermon,
    val deletedAt: Long?,
)

data class AttachmentRecord(
    val attachment: com.genesis.core.domain.journal.Attachment,
    val deletedAt: Long?,
)
