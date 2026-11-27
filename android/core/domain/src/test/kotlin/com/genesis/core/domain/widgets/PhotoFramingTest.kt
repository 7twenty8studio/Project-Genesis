package com.genesis.core.domain.widgets

import kotlin.test.Test
import kotlin.test.assertEquals

class PhotoFramingTest {
    @Test fun wholeWidthAtZoomOne() {
        val crop = PhotoFraming().crop(2000.0, 1000.0, 1.0)
        assertEquals(PhotoFraming.Crop(500.0, 0.0, 1000.0, 1000.0), crop)
    }

    @Test fun wideShapeOnATallPhoto() {
        val crop = PhotoFraming().crop(1000.0, 2000.0, 2.0)
        assertEquals(PhotoFraming.Crop(0.0, 750.0, 1000.0, 500.0), crop)
    }

    @Test fun zoomStaysInside() {
        val crop = PhotoFraming(zoom = 2.0, centerX = 0.0, centerY = 0.0).crop(1000.0, 1000.0, 1.0)
        assertEquals(PhotoFraming.Crop(0.0, 0.0, 500.0, 500.0), crop)
        assertEquals(5.0, PhotoFraming().zoomed(10.0, 1000.0, 1000.0, 1.0).zoom)
    }

    @Test fun panFollowsTheFinger() {
        val moved = PhotoFraming(zoom = 2.0).panned(100.0, 0.0, 200.0, 200.0, 1000.0, 1000.0)
        // 100 points in a 200-point frame showing 500 pixels: 250 pixels the other way.
        assertEquals(0.25, moved.centerX, 1e-9)
        assertEquals(0.5, moved.centerY, 1e-9)
    }

    @Test fun panPastTheEdgeDoesNotBuildUp() {
        val far = PhotoFraming().panned(-5000.0, 0.0, 200.0, 200.0, 2000.0, 1000.0)
        assertEquals(0.75, far.centerX, 1e-9)
    }

    @Test fun savedAndRead() {
        val framing = PhotoFraming(1.5, 0.3, 0.7)
        assertEquals(framing, PhotoFraming.decode(framing.encoded()))
        assertEquals(PhotoFraming(), PhotoFraming.decode("nonsense"))
    }
}
