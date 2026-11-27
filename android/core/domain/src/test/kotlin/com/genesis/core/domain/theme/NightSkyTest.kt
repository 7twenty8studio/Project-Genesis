package com.genesis.core.domain.theme

import com.genesis.core.domain.theme.NightSky
import com.genesis.core.domain.theme.SkyPoint
import com.genesis.core.domain.theme.SkyRect
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NightSkyTest {
    @Test fun unitIsFixedAndInRange() {
        assertEquals(NightSky.unit(3, 7), NightSky.unit(3, 7))
        for (i in 0 until 200) assertTrue(NightSky.unit(i, 5) in 0.0..<1.0)
    }

    @Test fun easeOutSettles() {
        assertEquals(0.0, NightSky.easeOut(0.0), 1e-4)
        assertEquals(1.0, NightSky.easeOut(1.0), 1e-4)
        assertTrue(NightSky.easeOut(0.2) > 0.5, "moves at once")
    }

    @Test fun twinkleRisesQuicklyAndRests() {
        assertEquals(0.3, NightSky.brightness(0.0, 4.0, 0.0, false), 1e-4)
        assertTrue(NightSky.brightness(0.45, 4.0, 0.0, false) > 0.99)
        assertEquals(0.3, NightSky.brightness(3.0, 4.0, 0.0, false), 1e-6)
        val calm = NightSky.brightness(1.0, 4.0, 0.0, true)
        assertTrue(calm in 0.2..0.8)
    }

    @Test fun shootingStarsComeEveryFewSeconds() {
        assertTrue(NightSky.activeStreaks(1.0).isEmpty(), "none in the first three seconds")
        val starts = (0 until 40).flatMap { NightSky.streaks(it) }.map { it.start }
        assertTrue(starts.first() in 3.0..5.5)
        val gaps = starts.zipWithNext { a, b -> b - a }.filter { it > 1 }
        assertTrue(gaps.all { it in 3.0..8.0 }, "gaps $gaps")
        val streak = NightSky.streaks(0).first()
        val (from, travel) = streak.path(400.0, 60.0)
        assertTrue(from.y + travel.y <= 60.0 - 4 + 1e-9, "stays in the band")
        assertTrue(NightSky.activeStreaks(streak.start + 0.1).contains(streak))
    }

    @Test fun hazeThinsBeforeTheWords() {
        val text = SkyRect(28.0, 40.0, 372.0, 700.0)
        assertEquals(0.0, NightSky.hazeFade(SkyPoint(200.0, 300.0), text), 1e-9)
        assertEquals(1.0, NightSky.hazeFade(SkyPoint(200.0, 0.0 - 40), text), 1e-9)
        val edge = NightSky.hazeFade(SkyPoint(20.0, 300.0), text)
        assertTrue(edge > 0 && edge < 1, "fades, no hard edge")
    }

    @Test fun starsKeepOutOfTheText() {
        val text = SkyRect(28.0, 40.0, 372.0, 700.0)
        for (star in NightSky.stars) {
            val point = NightSky.position(star, 400.0, 740.0, text, 34.0)
            assertNotNull(point)
            val inside = point.x > text.left && point.x < text.right && point.y > text.top && point.y < text.bottom
            assertTrue(!inside, "star ${star.index} at $point")
        }
        assertNull(NightSky.position(NightSky.stars[5], 400.0, 740.0, SkyRect(4.0, 40.0, 396.0, 700.0), 0.0))
        assertTrue(abs(NightSky.hazeSpot(1, 40, 30.0, 400.0, 740.0).x) < 500)
    }
}
