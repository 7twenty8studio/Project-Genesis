package com.genesis.core.domain.theme

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ThemeSceneTest {
    private val phone = SceneSize(390.0, 760.0)

    @Test fun forestFillsTheHeightCentred() {
        val frame = ThemeScene.FOREST.artFrame(phone)
        assertEquals(760.0, frame.height, 1e-9)
        assertEquals(phone.width / 2, frame.midX, 1e-9)
    }

    @Test fun tilesCoverAWideAreaWithMirroredCopies() {
        val wide = SceneSize(1200.0, 800.0)
        val tiles = ThemeScene.OCEAN.tiles(wide)
        assertTrue(tiles.minOf { it.frame.x } <= 0)
        assertTrue(tiles.maxOf { it.frame.maxX } >= wide.width)
        assertTrue(tiles.any { it.mirrored })
        assertEquals(1, ThemeScene.FOREST.tiles(SceneSize(390.0, 900.0)).size)
        assertTrue(ThemeScene.HEARTH.tiles(phone).isEmpty())
    }

    @Test fun footRoomKeepsTextAboveTheSwellsAndGlow() {
        assertEquals(0.0, ThemeScene.FOREST.footRoom(phone, 28.0))
        val ocean = ThemeScene.OCEAN.footRoom(phone, 28.0)
        assertTrue(phone.height - 28 - ocean <= OceanSwells.top(phone) - OceanSwells.RISE - 6 + 1e-9)
        val hearth = ThemeScene.HEARTH.footRoom(phone, 28.0)
        assertTrue(phone.height - 28 - hearth <= phone.height * 0.9 + 1e-9)
    }

    @Test fun shadeIsStrongestAtTheCentre() {
        val shade = ThemeScene.FOREST.shade
        assertEquals(0.82, shade.opacity(phone.width * 0.5, phone.height * 0.46, phone), 1e-9)
        assertEquals(0.15, shade.opacity(0.0, 0.0, phone), 1e-9)
    }

    @Test fun swellsStayWithinTheirRise() {
        for (step in 0..400) {
            val (x, y) = OceanSwells.offset(near = step % 2 == 0, time = step * 0.37)
            assertTrue(kotlin.math.abs(y) <= OceanSwells.RISE + 1e-9)
            assertTrue(kotlin.math.abs(x) <= OceanSwells.LEAN + 1e-9)
        }
    }

    @Test fun swayIsStillBelowTheCanopy() {
        assertEquals(0.0, ForestSway.offset(ForestSway.CANOPY + 0.01, 3.0))
        assertTrue(kotlin.math.abs(ForestSway.offset(0.0, 1.7)) <= ForestSway.REACH)
    }

    @Test fun wideForestKeepsTreesAtTheEdges() {
        val spread = SceneSize(1180.0, 800.0)
        assertTrue(ForestWide.uses(spread))
        val (left, right) = ForestWide.copies(spread)
        assertEquals(spread.width * ForestWide.EDGE_SHARE, left.x + left.width * ForestWide.TREE_SHARE, 1e-9)
        assertEquals(spread.width * (1 - ForestWide.EDGE_SHARE), right.maxX - right.width * ForestWide.TREE_SHARE, 1e-9)
        val (from, to) = ForestWide.blend(spread)
        assertTrue(from <= to)
    }

    @Test fun sparksFadeAndRestBetweenFlights() {
        var rested = false
        for (step in 0..600) {
            val state = HearthSparks.state(HearthSparks.sparks[0], 0, step * 0.05, 195.0, 764.0, 351.0, 395.0)
            if (state == null) rested = true else {
                assertTrue(state.opacity in 0.0..1.0)
                assertTrue(state.y <= 764.0 + 1e-9)
            }
        }
        assertTrue(rested)
        assertNull(HearthSparks.state(HearthSparks.sparks[0], 0, -100.0, 0.0, 0.0, 0.0, 0.0))
    }
}
