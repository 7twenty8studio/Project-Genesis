package com.genesis.core.domain.widgets

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class WidgetArtTest {
    @Test fun classicIsFreeAndEverythingElseFallsBack() {
        assertFalse(WidgetArtStyle.CLASSIC.needsPremium)
        assertEquals(WidgetArtStyle.CLASSIC, WidgetArtStyle.AUTUMN.shown(premium = false))
        assertEquals(WidgetArtStyle.AUTUMN, WidgetArtStyle.AUTUMN.shown(premium = true))
    }

    @Test fun idsMatchIOS() {
        assertEquals(WidgetArtStyle.FOREST, WidgetArtStyle.of("forest"))
        assertEquals(null, WidgetArtStyle.of("vintage"))
    }

    @Test fun darkInk() {
        assertTrue(WidgetArtStyle.NIGHT.isDark)
        assertTrue(WidgetArtStyle.OCEAN.isDark)
        assertFalse(WidgetArtStyle.PAPER.isDark)
    }

    @Test fun backgroundFollowsTheAppUnlessChosen() {
        assertEquals(WidgetArtStyle.NIGHT, VerseWidgetBackground.resolve(null, WidgetArtStyle.NIGHT))
        assertEquals(WidgetArtStyle.NIGHT, VerseWidgetBackground.resolve("app", WidgetArtStyle.NIGHT))
        assertEquals(WidgetArtStyle.PAPER, VerseWidgetBackground.resolve("paper", WidgetArtStyle.NIGHT))
        assertEquals(WidgetArtStyle.NIGHT, VerseWidgetBackground.resolve("unknown", WidgetArtStyle.NIGHT))
    }

    @Test fun shapes() {
        assertEquals(WidgetArtShape.SMALL, WidgetArtShape.of(160f, 160f))
        assertEquals(WidgetArtShape.MEDIUM, WidgetArtShape.of(320f, 160f))
        assertEquals(WidgetArtShape.LARGE, WidgetArtShape.of(320f, 330f))
    }
}
