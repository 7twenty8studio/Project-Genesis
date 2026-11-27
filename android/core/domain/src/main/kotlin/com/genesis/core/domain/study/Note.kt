package com.genesis.core.domain.study

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId

/** The kinds a note is written as, as iOS's NoteKind. */
enum class NoteKind(val id: String) {
    TEXT("text"),

    /** Only read from older data: prayers live in the Prayer Journal. */
    PRAYER("prayer"),
    STUDY("study"),
    JOURNAL("journal");

    companion object {
        /** The kinds a note can be written as (prayer is left out, as on iOS). */
        val writable = listOf(TEXT, STUDY, JOURNAL)

        fun withId(id: String): NoteKind = entries.firstOrNull { it.id == id } ?: TEXT
    }
}

/** What a note is about, as iOS's NoteAnchor (stored the same way for sync). */
sealed interface NoteAnchor {
    data class Verses(val start: VerseId, val end: VerseId) : NoteAnchor
    data class Chapter(val chapter: ChapterId) : NoteAnchor
    data class Book(val book: Int) : NoteAnchor
    data class Theme(val theme: String) : NoteAnchor
    data object None : NoteAnchor

    /** "verses", "chapter", "book", "theme" or "none": the notes table's anchor_type. */
    val type: String
        get() = when (this) {
            is Verses -> "verses"
            is Chapter -> "chapter"
            is Book -> "book"
            is Theme -> "theme"
            None -> "none"
        }

    companion object {
        fun of(type: String, startVerse: Int?, endVerse: Int?, book: Int?, chapter: Int?, theme: String?): NoteAnchor = when (type) {
            "verses" -> startVerse?.let { Verses(VerseId(it), VerseId(endVerse ?: it)) } ?: None
            "chapter" -> if (book != null && chapter != null) Chapter(ChapterId(book, chapter)) else None
            "book" -> book?.let(::Book) ?: None
            "theme" -> theme?.let(::Theme) ?: None
            else -> None
        }
    }
}

/** A note: the person's own words, never Scripture. */
data class Note(
    val id: String,
    val title: String = "",
    val body: String = "",
    val kind: NoteKind = NoteKind.TEXT,
    val anchor: NoteAnchor = NoteAnchor.None,
    val createdAt: Long = 0,
    val updatedAt: Long = 0,
) {
    /** Nothing written yet: saving it would only leave an empty note behind. */
    val isEmpty: Boolean get() = title.isBlank() && body.isBlank()

    /** The verse the reader puts the note's mark after (the passage's last). */
    val markedVerse: VerseId? get() = (anchor as? NoteAnchor.Verses)?.end

    companion object {
        /** The note the selection bar opens: one ending on a selected verse, else none. */
        fun forSelection(notes: List<Note>, selection: Set<VerseId>): Note? =
            notes.filter { it.markedVerse in selection }.maxByOrNull { it.updatedAt }
    }
}

/**
 * Bookmarks: one per chapter, as on iOS (StudyStore.toggleBookmark). With
 * none in the chapter, the verse is bookmarked; otherwise every bookmark in
 * the chapter is taken away.
 */
object Bookmarks {
    data class Change(val add: VerseId?, val remove: Set<VerseId>)

    fun toggle(existing: Set<VerseId>, at: VerseId): Change {
        val inChapter = existing.filterTo(mutableSetOf()) { it.chapterId == at.chapterId }
        return if (inChapter.isEmpty()) Change(add = at, remove = emptySet()) else Change(add = null, remove = inChapter)
    }

    fun isBookmarked(existing: Set<VerseId>, chapter: ChapterId): Boolean = existing.any { it.chapterId == chapter }
}
