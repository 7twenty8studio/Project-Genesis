package com.genesis.core.domain.reader

import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals

class ReaderTapTest {
    private val verse = VerseId(43, 15, 1)
    private fun tap(x: Float, verse: VerseId? = null, selecting: Boolean = false, pages: Boolean = true, left: Boolean = false) =
        ReaderTap.action(x, 400f, 28f, 28f, verse, selecting, pages, left)

    @Test fun edgesTurnPages() {
        assertEquals(38f, ReaderTap.edgeWidth(28f, 400f))
        assertEquals(60f, ReaderTap.edgeWidth(80f, 400f), 0.001f)
        assertEquals(ReaderTap.Action.TurnPage(true), tap(390f, verse))
        assertEquals(ReaderTap.Action.TurnPage(false), tap(10f))
        assertEquals(ReaderTap.Action.TurnPage(true), tap(10f, left = true))
        assertEquals(ReaderTap.Action.TurnPage(true), tap(390f, selecting = true))
    }

    @Test fun middleSelectsOrToggles() {
        assertEquals(ReaderTap.Action.ToggleSelection(verse), tap(200f, verse))
        assertEquals(ReaderTap.Action.ToggleControls, tap(200f))
        assertEquals(ReaderTap.Action.ClearSelection, tap(200f, selecting = true))
        assertEquals(ReaderTap.Action.ToggleControls, tap(10f, pages = false))
    }
}
