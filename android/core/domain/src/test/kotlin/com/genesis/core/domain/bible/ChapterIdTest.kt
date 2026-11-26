package com.genesis.core.domain.bible

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class ChapterIdTest {
    @Test fun verseIdsEncodeBookChapterAndVerse() {
        val id = VerseId(43, 3, 16)
        assertEquals(43003016, id.rawValue)
        assertEquals(43, id.book)
        assertEquals(3, id.chapter)
        assertEquals(16, id.verse)
        assertEquals(ChapterId(43, 3), id.chapterId)
    }

    @Test fun chaptersCrossBookBoundaries() {
        assertEquals(ChapterId(2, 1), ChapterId(1, 50).next)
        assertEquals(ChapterId(1, 50), ChapterId(2, 1).previous)
        assertNull(ChapterId(66, 22).next)
        assertNull(ChapterId.genesis1.previous)
    }

    @Test fun namesFollowTheBiblesLanguage() {
        assertEquals("John 3", ChapterId(43, 3).description("en"))
        assertEquals("Juan 3", ChapterId(43, 3).description("es"))
        assertEquals("João 3", ChapterId(43, 3).description("pt-BR"))
    }
}
