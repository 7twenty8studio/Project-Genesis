package com.genesis.core.domain.reader

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PageSpreadTest {
    @Test fun onlyWideAndSideways() {
        assertTrue(PageSpread.shows(true, 1180f, 820f))
        assertFalse(PageSpread.shows(false, 1180f, 820f))
        assertFalse(PageSpread.shows(true, 820f, 1180f))
        assertFalse(PageSpread.shows(true, 760f, 400f))
        assertFalse(PageSpread.shows(true, 1180f, 820f, sidePanelShown = true))
    }
}
