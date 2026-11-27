package com.genesis.core.domain.theme

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sin

/** xorshift64*, seeded as SeededRandom on iOS, so the seasons' pieces are the same on both phones. */
class SeededRandom(seed: Long) {
    private var state: ULong = (seed.toULong() * 0x9E3779B97F4A7C15uL) or 1uL

    /** A number in 0..<1. */
    fun next(): Double {
        state = state xor (state shr 12)
        state = state xor (state shl 25)
        state = state xor (state shr 27)
        val value = state * 0x2545F4914F6CDD1DuL
        return (value shr 11).toDouble() / (1uL shl 53).toDouble()
    }
}

/** Small rules shared by the seasons' motion, as SeasonalEffectView on iOS. */
object SeasonMotion {
    /** The moment shown when it holds still: every season looks settled here. */
    const val PAINTED_MOMENT = 7.3

    /** Wraps a position into 0..<length, going round when it leaves. */
    fun wrap(value: Double, length: Double): Double {
        val r = value.rem(length)
        return if (r < 0) r + length else r
    }

    /** How far winter's gusts have pushed the snow by `t`: a 4-second sin² swell every 25 s, added up so it never jumps. */
    fun gustOffset(t: Double): Double {
        val period = 25.0
        val g = t.rem(period)
        val done = floor(t / period) * 2
        val current = if (g < 4) g / 2 - sin(PI * g / 2) / PI else 2.0
        return 38 * (done + current)
    }

    /** The signed angle from b to a, in -π..π. */
    fun angleBetween(a: Double, b: Double): Double = atan2(sin(a - b), cos(a - b))
}

/**
 * Summer's butterfly, as ButterflyFlight on iOS: now and then it crosses
 * the page from left to right on an unsteady, wandering path, lifting a
 * little with each wingbeat, flapping in bursts between glides on open
 * wings, its head turned the way it flies.
 */
object ButterflyFlight {
    /** Seconds between crossings, and how long a crossing takes. */
    const val PERIOD = 90.0
    const val CROSSING = 16.0

    /** Wingbeats per second × 2π (abs(sin) beats twice a turn). */
    const val BEAT_SPEED = 7.0

    /** Where it is: its rotation (head drawn pointing up) and how open its wings are (0.35..1). */
    data class State(val x: Double, val y: Double, val angle: Double, val wingOpen: Double)

    /** Where it is at `time` on a page `width` × `height`, or null between crossings. */
    fun state(time: Double, width: Double, height: Double): State? {
        val phase = time.rem(PERIOD)
        if (phase < 0 || phase >= CROSSING) return null
        val flap = flapping(phase)
        val beat = sin(phase * BEAT_SPEED)
        val (x, y) = course(phase, width, height)
        return State(x, y - 2.5 * flap * beat, heading(phase, width, height), 1 - 0.65 * flap * abs(beat))
    }

    /** 0..1: flapping hard, or 0 while it glides on open wings. */
    fun flapping(phase: Double): Double {
        val glide = sin(phase * 0.9 + 1.3) * 0.6 + sin(phase * 2.3) * 0.4
        val x = ((glide - 0.35) / 0.3).coerceIn(0.0, 1.0)
        return 1 - x * x * (3 - 2 * x)
    }

    /** The smooth course: across and a little up the page, wandering, entering and leaving off the page. */
    fun course(phase: Double, width: Double, height: Double): Pair<Double, Double> {
        val progress = phase / CROSSING
        val envelope = sin(PI * progress.coerceIn(0.0, 1.0))
        val span = min(width, height)
        val wanderX = span * (0.09 * sin(phase * 0.55 + 0.4) + 0.05 * sin(phase * 1.35 + 2.1))
        val wanderY = span * (0.07 * sin(phase * 0.8 + 1) + 0.035 * sin(phase * 1.9 + 0.3))
        return (-20 + (width + 40) * progress + envelope * wanderX) to (height * (0.7 - 0.25 * progress) + envelope * wanderY)
    }

    /** The direction it's flying, turned so the drawing's head leads, banking a little into turns. */
    fun heading(phase: Double, width: Double, height: Double): Double {
        val step = 0.12
        val before = course(phase - step, width, height)
        val now = course(phase, width, height)
        val after = course(phase + step, width, height)
        val incoming = atan2(now.second - before.second, now.first - before.first)
        val outgoing = atan2(after.second - now.second, after.first - now.first)
        val direction = atan2(after.second - before.second, after.first - before.first)
        val turn = SeasonMotion.angleBetween(outgoing, incoming)
        return direction + PI / 2 + (turn * 2).coerceIn(-0.3, 0.3)
    }
}
