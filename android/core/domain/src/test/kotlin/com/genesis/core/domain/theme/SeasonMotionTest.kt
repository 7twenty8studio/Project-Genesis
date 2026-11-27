package com.genesis.core.domain.theme

import kotlin.math.PI
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SeasonMotionTest {
    @Test fun seededRandomIsFixed() {
        val a = SeededRandom(14)
        val b = SeededRandom(14)
        repeat(20) { assertEquals(a.next(), b.next()) }
        val c = SeededRandom(3)
        repeat(100) { assertTrue(c.next() in 0.0..<1.0) }
    }

    @Test fun wrapGoesRound() {
        assertEquals(5.0, SeasonMotion.wrap(105.0, 100.0), 1e-9)
        assertEquals(95.0, SeasonMotion.wrap(-5.0, 100.0), 1e-9)
    }

    @Test fun gustsNeverJump() {
        var last = SeasonMotion.gustOffset(0.0)
        var t = 0.05
        while (t < 80) {
            val now = SeasonMotion.gustOffset(t)
            assertTrue(now >= last - 1e-9 && now - last < 2, "at $t")
            last = now
            t += 0.05
        }
        assertEquals(76.0, SeasonMotion.gustOffset(25.0), 1e-6)
    }

    @Test fun butterflyCrossesNowAndThen() {
        assertNull(ButterflyFlight.state(20.0, 400.0, 800.0))
        val start = assertNotNull(ButterflyFlight.state(0.0, 400.0, 800.0))
        assertTrue(start.x < 0, "enters off the page")
        val end = assertNotNull(ButterflyFlight.state(15.99, 400.0, 800.0))
        assertTrue(end.x > 400, "leaves off the page")
        val middle = assertNotNull(ButterflyFlight.state(8.0, 400.0, 800.0))
        assertTrue(middle.wingOpen in 0.35..1.0)
        // Flying right, its head (drawn up) turns about a quarter turn.
        assertTrue(middle.angle in (PI / 2 - 1.2)..(PI / 2 + 1.2))
        assertNotNull(ButterflyFlight.state(90.5, 400.0, 800.0))
    }
}
