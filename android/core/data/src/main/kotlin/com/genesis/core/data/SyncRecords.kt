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
