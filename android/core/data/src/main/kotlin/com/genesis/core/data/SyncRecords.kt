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
