package com.genesis.core.domain.theme

import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** A point and a size in density-independent pixels, for the pure drawing rules. */
data class SkyPoint(val x: Double, val y: Double)

/** A rectangle (left, top, right, bottom) in dp. */
data class SkyRect(val left: Double, val top: Double, val right: Double, val bottom: Double) {
    val width: Double get() = right - left
    val height: Double get() = bottom - top
}

/**
 * The rules behind Starlight's moving sky, as NightSky.swift: when shooting
 * stars fall, how a star twinkles, the curve things move on, and where the
 * haze thins before the words. Everything is a function of time and fixed
 * random numbers, so the sky is the same every time and on both phones.
 */
object NightSky {
    /** A number in 0..<1 for `index` and `salt` (SplitMix64), always the same. */
    fun unit(index: Int, salt: Long): Double {
        var z = index.toLong().toULong() + (salt.toULong() + 1uL) * 0x9E3779B97F4A7C15uL
        z = (z xor (z shr 30)) * 0xBF58476D1CE4E5B9uL
        z = (z xor (z shr 27)) * 0x94D049BB133111EBuL
        z = z xor (z shr 31)
        return (z shr 11).toDouble() / (1uL shl 53).toDouble()
    }

    /** The strong ease-out, cubic-bezier(0.23, 1, 0.32, 1). */
    fun easeOut(t: Double): Double {
        val x0 = t.coerceIn(0.0, 1.0)
        var low = 0.0
        var high = 1.0
        var u = x0
        repeat(18) {
            u = (low + high) / 2
            val x = 3 * (1 - u) * (1 - u) * u * 0.23 + 3 * (1 - u) * u * u * 0.32 + u * u * u
            if (x < x0) low = u else high = u
        }
        return 3 * (1 - u) * (1 - u) * u + 3 * (1 - u) * u * u + u * u * u
    }

    /**
     * How bright a star is (0.3..1): a quick rise (0.45 s), a slow fall
     * (2.15 s), then rest. With Reduce Motion, a slow, gentle swell instead.
     */
    fun brightness(time: Double, period: Double, offset: Double, reduceMotion: Boolean): Double {
        if (reduceMotion) return 0.5 + 0.3 * sin((time + offset) * 2 * Math.PI / (period * 1.6))
        val p = (time + offset).rem(period + 2.6)
        if (p < 0.45) return 0.3 + 0.7 * easeOut(p / 0.45)
        if (p < 2.6) return 0.3 + 0.7 * (1 - (p - 0.45) / 2.15).pow(2)
        return 0.3
    }

    /** One shooting star: when it starts, how long it takes, and its shape. */
    data class Streak(val seed: Int, val start: Double) {
        val duration: Double get() = 0.6 + 0.3 * unit(seed, 3)

        fun isActive(time: Double): Boolean = time >= start && time < start + duration

        /** Where it starts and how far it goes, inside a band across the top: a shallow fall, never below the band. */
        fun path(width: Double, band: Double): Pair<SkyPoint, SkyPoint> {
            val fromRight = unit(seed, 4) < 0.5
            val across = unit(seed, 5)
            val x = if (fromRight) width * (0.55 + 0.37 * across) else width * (0.08 + 0.37 * across)
            val y = 4 + max(0.0, band - 8) * 0.35 * unit(seed, 6)
            val length = min(width * 0.6, 110 + 80 * unit(seed, 7))
            val angle = 0.32 + (unit(seed, 8) - 0.5) * 0.16
            val dy = min(sin(angle) * length, max(0.0, band - 4 - y))
            return SkyPoint(x, y) to SkyPoint(cos(angle) * length * (if (fromRight) -1 else 1), dy)
        }

        /** The glowing tail's length. */
        val tail: Double get() = 40 + 30 * unit(seed, 9)
    }

    const val SLOT = 5.5
    const val FIRST_DELAY = 3.0
    const val PAIR_DELAY = 0.45

    /** One shooting star per 5.5-second slot, at a random moment in its first 2.5 s; one in six brings a second. */
    fun streaks(slot: Int): List<Streak> {
        if (slot < 0) return emptyList()
        val start = slot * SLOT + FIRST_DELAY + 2.5 * unit(slot, 1)
        val first = Streak(slot * 2, start)
        return if (unit(slot, 2) < 1.0 / 6) listOf(first, Streak(slot * 2 + 1, start + PAIR_DELAY)) else listOf(first)
    }

    /** The shooting stars in the sky at `time` (seconds since the page opened). */
    fun activeStreaks(time: Double): List<Streak> {
        val index = floor((time - FIRST_DELAY) / SLOT).toInt()
        return (index - 1..index).flatMap(::streaks).filter { it.isActive(time) }
    }

    /** How much haze to draw at a point (0..1), fading over about 46 dp as it nears the text, so there's no edge. */
    fun hazeFade(point: SkyPoint, text: SkyRect): Double {
        val dx = max(max(text.left - point.x, 0.0), point.x - text.right)
        val dy = max(max(text.top - point.y, 0.0), point.y - text.bottom)
        val outside = if (dx > 0 || dy > 0) hypot(dx, dy)
        else -minOf(point.x - text.left, text.right - point.x, point.y - text.top, text.bottom - point.y)
        val k = ((outside + 18) / 46).coerceIn(0.0, 1.0)
        return k * k * (3 - 2 * k)
    }

    /** One of the twenty stars, from fixed random numbers. */
    data class Star(val index: Int) {
        val zone: Double get() = unit(index, 20)
        val side: Double get() = unit(index, 27)
        val x: Double get() = unit(index, 21)
        val y: Double get() = unit(index, 22)
        val core: Double get() = 1 + 1.5 * unit(index, 23)
        val period: Double get() = 3 + 6 * unit(index, 24)
        val offset: Double get() = 10 * unit(index, 25)
        val tint: Int get() = (3 * unit(index, 26)).toInt() % 3
        /** The four brightest wear a glint at their peak. */
        val isMajor: Boolean get() = index < 4
    }

    val stars: List<Star> = (0 until 20).map(::Star)

    /** Where a star sits: in the sky band or a side margin, clear of the text (anywhere when there's no text). */
    fun position(star: Star, width: Double, height: Double, text: SkyRect?, band: Double): SkyPoint? {
        if (text == null) return SkyPoint((0.04 + 0.92 * star.x) * width, (0.04 + 0.92 * star.y) * height)
        val left = text.left
        val right = width - text.right
        val hasSky = band >= 20
        val hasLeft = left >= 14
        val hasRight = right >= 14
        if (hasSky && (star.zone < 0.4 || !(hasLeft || hasRight))) {
            return SkyPoint(10 + star.x * (width - 20), 8 + star.y * (band - 12))
        }
        if (!hasLeft && !hasRight) return null
        val onLeft = hasLeft && (!hasRight || star.side < 0.5)
        val x = if (onLeft) 6 + star.x * (left - 12) else text.right + 6 + star.x * (right - 12)
        return SkyPoint(x, (0.1 + 0.82 * star.y) * height)
    }

    /** A spot of the Milky Way: from the top-left corner down the right-hand side. */
    fun hazeSpot(i: Int, salt: Long, jitter: Double, width: Double, height: Double): SkyPoint {
        val u = unit(i, salt)
        return SkyPoint(
            10 + u * (width - 10) + (unit(i, salt + 1) - 0.5) * jitter,
            height * (0.03 + 0.68 * u.pow(2.2)) + (unit(i, salt + 2) - 0.5) * jitter * 0.85,
        )
    }
}
