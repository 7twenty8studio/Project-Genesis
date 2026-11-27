package com.genesis.core.domain.widgets

import kotlin.math.max
import kotlin.math.min

/**
 * How the person framed their widget photo for one widget shape, as
 * PhotoFraming on iOS: how far it's zoomed in and which point of the photo
 * sits in the middle. Pure, so the editor's gestures and the saved crop agree.
 */
data class PhotoFraming(
    /** 1 fills the shape with the whole photo's width or height; more is closer. */
    val zoom: Double = 1.0,
    /** The middle of the crop, as a fraction of the photo (0…1). */
    val centerX: Double = 0.5,
    val centerY: Double = 0.5,
) {
    data class Crop(val x: Double, val y: Double, val width: Double, val height: Double) {
        val midX: Double get() = x + width / 2
        val midY: Double get() = y + height / 2
    }

    /** The part of the photo (in its pixels) that fills a frame of this shape, always inside the photo. */
    fun crop(imageWidth: Double, imageHeight: Double, aspect: Double): Crop {
        if (imageWidth <= 0 || imageHeight <= 0 || aspect <= 0) return Crop(0.0, 0.0, 0.0, 0.0)
        var width = imageWidth
        var height = width / aspect
        if (height > imageHeight) {
            height = imageHeight
            width = height * aspect
        }
        val zoom = zoom.coerceIn(1.0, MAX_ZOOM)
        width /= zoom
        height /= zoom
        val x = min(max(centerX * imageWidth - width / 2, 0.0), imageWidth - width)
        val y = min(max(centerY * imageHeight - height / 2, 0.0), imageHeight - height)
        return Crop(x, y, width, height)
    }

    /** The same framing with its middle moved back where the crop really is (a pan past the edge doesn't build up). */
    fun clamped(imageWidth: Double, imageHeight: Double, aspect: Double): PhotoFraming {
        if (imageWidth <= 0 || imageHeight <= 0) return this
        val rect = crop(imageWidth, imageHeight, aspect)
        return PhotoFraming(zoom.coerceIn(1.0, MAX_ZOOM), rect.midX / imageWidth, rect.midY / imageHeight)
    }

    /** Dragging the photo by (dx, dy) in a frame of this size: the photo follows the finger, so the crop moves the other way. */
    fun panned(dx: Double, dy: Double, frameWidth: Double, frameHeight: Double, imageWidth: Double, imageHeight: Double): PhotoFraming {
        if (frameWidth <= 0 || frameHeight <= 0) return this
        val aspect = frameWidth / frameHeight
        val rect = crop(imageWidth, imageHeight, aspect)
        val perPoint = rect.width / frameWidth
        return copy(
            centerX = rect.midX / imageWidth - dx * perPoint / imageWidth,
            centerY = rect.midY / imageHeight - dy * perPoint / imageHeight,
        ).clamped(imageWidth, imageHeight, aspect)
    }

    /** Pinching by `factor` (1 = no change), keeping the middle where it is. */
    fun zoomed(factor: Double, imageWidth: Double, imageHeight: Double, aspect: Double): PhotoFraming {
        val start = clamped(imageWidth, imageHeight, aspect)
        return start.copy(zoom = (start.zoom * factor).coerceIn(1.0, MAX_ZOOM)).clamped(imageWidth, imageHeight, aspect)
    }

    /** As saved: "zoom,centerX,centerY". */
    fun encoded(): String = "$zoom,$centerX,$centerY"

    companion object {
        const val MAX_ZOOM = 5.0

        fun decode(text: String?): PhotoFraming {
            val parts = text?.split(',')?.mapNotNull { it.toDoubleOrNull() } ?: return PhotoFraming()
            return if (parts.size == 3) PhotoFraming(parts[0], parts[1], parts[2]) else PhotoFraming()
        }
    }
}
