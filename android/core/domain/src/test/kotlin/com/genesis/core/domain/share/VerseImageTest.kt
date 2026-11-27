package com.genesis.core.domain.share

import com.genesis.core.domain.theme.ReaderTheme
import kotlin.test.Test
import kotlin.test.assertEquals

class VerseImageTest {
    @Test fun styles() {
        assertEquals(ReaderTheme.SEPIA, VerseImageStyle.PAPER.theme(ReaderTheme.SEPIA))
        assertEquals(ReaderTheme.PAPER, VerseImageStyle.PAPER.theme(ReaderTheme.NIGHT))
        assertEquals(ReaderTheme.MIDNIGHT, VerseImageStyle.PHOTO.theme(ReaderTheme.PAPER))
        assertEquals(com.genesis.core.domain.theme.Season.WINTER, VerseImageStyle.WINTER.season)
    }

    @Test fun textSizeFollowsLengthAndChoice() {
        assertEquals(69.6f, VerseImageText.size(80, VerseImageShape.SQUARE, 1.0), 0.01f)
        assertEquals(58f, VerseImageText.size(200, VerseImageShape.SQUARE, 1.0), 0.01f)
        assertEquals(66f * 0.66f * 1.4f, VerseImageText.size(900, VerseImageShape.LOCK_SCREEN, 2.0), 0.01f)
        assertEquals(2796 * 0.37f, VerseImageShape.LOCK_SCREEN.textTop, 0.01f)
    }
}
