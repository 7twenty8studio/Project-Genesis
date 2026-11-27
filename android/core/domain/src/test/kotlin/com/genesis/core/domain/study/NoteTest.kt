package com.genesis.core.domain.study

import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NoteTest {
    private fun john1(verse: Int) = VerseId(43, 1, verse)

    @Test fun bookmarkingAChapterWithoutOneAddsTheVerse() {
        val change = Bookmarks.toggle(setOf(VerseId(43, 2, 1)), john1(5))
        assertEquals(john1(5), change.add)
        assertTrue(change.remove.isEmpty())
    }

    @Test fun bookmarkingAgainRemovesEveryBookmarkInTheChapter() {
        val change = Bookmarks.toggle(setOf(john1(1), john1(9), VerseId(43, 2, 1)), john1(5))
        assertNull(change.add)
        assertEquals(setOf(john1(1), john1(9)), change.remove)
        assertTrue(Bookmarks.isBookmarked(setOf(john1(9)), ChapterId(43, 1)))
        assertFalse(Bookmarks.isBookmarked(setOf(john1(9)), ChapterId(43, 2)))
    }

    @Test fun anchorsRoundTripTheStoredColumns() {
        val anchors = listOf(
            NoteAnchor.Verses(john1(1), john1(3)),
            NoteAnchor.Chapter(ChapterId(43, 1)),
            NoteAnchor.Book(43),
            NoteAnchor.Theme("hope"),
            NoteAnchor.None,
        )
        for (anchor in anchors) {
            val verses = anchor as? NoteAnchor.Verses
            val chapter = (anchor as? NoteAnchor.Chapter)?.chapter
            val book = chapter?.book ?: (anchor as? NoteAnchor.Book)?.book
            val restored = NoteAnchor.of(anchor.type, verses?.start?.rawValue, verses?.end?.rawValue, book, chapter?.chapter, (anchor as? NoteAnchor.Theme)?.theme)
            assertEquals(anchor, restored)
        }
        assertEquals(NoteAnchor.None, NoteAnchor.of("verses", null, null, null, null, null))
    }

    @Test fun theSelectionOpensTheLatestNoteEndingOnIt() {
        val old = Note("a", body = "x", anchor = NoteAnchor.Verses(john1(1), john1(2)), updatedAt = 1)
        val new = Note("b", body = "y", anchor = NoteAnchor.Verses(john1(2), john1(2)), updatedAt = 2)
        val elsewhere = Note("c", body = "z", anchor = NoteAnchor.Verses(john1(1), john1(5)), updatedAt = 3)
        assertEquals(new, Note.forSelection(listOf(old, new, elsewhere), setOf(john1(2))))
        assertNull(Note.forSelection(listOf(old), setOf(john1(1))))
        assertEquals(NoteKind.TEXT, NoteKind.withId("unknown"))
        assertFalse(NoteKind.PRAYER in NoteKind.writable)
    }
}
