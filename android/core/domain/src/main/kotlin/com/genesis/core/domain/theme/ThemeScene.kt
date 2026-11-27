package com.genesis.core.domain.theme

import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

/** A size in dp. */
data class SceneSize(val width: Double, val height: Double)

/** A rectangle (origin and size) in dp. */
data class SceneRect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
    val midX: Double get() = x + width / 2
    fun offsetBy(dx: Double, dy: Double = 0.0) = SceneRect(x + dx, y + dy, width, height)
}

/** One copy of a scene's picture. */
data class SceneTile(val frame: SceneRect, val mirrored: Boolean)

/**
 * The scene behind the words in the scene themes (Premium): Forest, Ocean
 * and Hearth, as ThemeScene.swift. Forest and Ocean are the owner-approved
 * illustrations; Hearth is a glow rising from the foot of the screen, drawn
 * (HearthGlow). Everything here is pure, so tests and the still agree.
 */
enum class ThemeScene {
    FOREST, OCEAN, HEARTH;

    /** The colour under the picture (all of Hearth: warm charcoal). */
    val fillHex: Int
        get() = when (this) {
            FOREST -> 0x1E3A2E
            OCEAN -> 0x6A7A93
            HEARTH -> 0x271C18
        }

    /**
     * Where the picture goes on a reading area: Forest fills the height,
     * centred; Ocean is a little taller than the area, lowered with the
     * swells (OceanSwells.sink); Hearth has no picture (the whole area).
     */
    fun artFrame(size: SceneSize): SceneRect = when (this) {
        FOREST -> {
            val width = size.height * ART_ASPECT
            SceneRect((size.width - width) / 2, 0.0, width, size.height)
        }
        OCEAN -> {
            val height = size.height * 1.18
            val width = height * ART_ASPECT
            SceneRect((size.width - width) / 2, OceanSwells.sink(size), width, height)
        }
        HEARTH -> SceneRect(0.0, 0.0, size.width, size.height)
    }

    /** The picture and, where it's narrower than the area, mirrored copies beside it. */
    fun tiles(size: SceneSize): List<SceneTile> = if (this == HEARTH) emptyList() else tiles(artFrame(size), size.width)

    /**
     * Room kept free under the text (on top of the usual footer), so the
     * last lines end above the glow and the swells (none for Forest).
     */
    fun footRoom(size: SceneSize, footHeight: Double): Double {
        val textBottom = size.height - footHeight
        val limit = when (this) {
            FOREST -> return 0.0
            OCEAN -> OceanSwells.top(size) - OceanSwells.RISE - 6
            HEARTH -> size.height * (1 - HearthGlow.BRIGHT_BAND)
        }
        return max(0.0, ceil(textBottom - limit))
    }

    /** The soft shade behind the words: an ellipse of the scene's own dark colour. */
    val shade: SceneShade
        get() = when (this) {
            FOREST -> SceneShade(0x14241F, 0.5, 0.46, 0.75, 0.58, listOf(0.0 to 0.82, 0.7 to 0.62, 1.0 to 0.15))
            OCEAN -> SceneShade(0x161F29, 0.5, 0.44, 0.85, 0.62, listOf(0.0 to 0.76, 0.72 to 0.42, 1.0 to 0.0))
            HEARTH -> SceneShade(0x1A1411, 0.5, 0.42, 0.85, 0.6, listOf(0.0 to 0.72, 0.7 to 0.35, 1.0 to 0.0))
        }

    companion object {
        /** Every tall scene picture is 1536 × 2752 px. */
        const val ART_ASPECT = 1536.0 / 2752.0

        /** The moment shown when nothing moves: a composed still, embers mid-rise. */
        const val STILL_TIME = 7.4

        /** How far the Ocean's clouds are raised, as a share of the height. */
        const val CLOUD_LIFT = 0.08

        /** Where the raised sky fades out, as shares of the lowered picture under it. */
        const val SKY_FADE_START = 0.27
        const val SKY_FADE_END = 0.4

        /** The Ocean's sky: the picture again, raised, shown only down to the fade. */
        fun oceanSky(size: SceneSize): SceneRect {
            val art = OCEAN.artFrame(size)
            return SceneRect(art.x, -size.height * CLOUD_LIFT, art.width, art.height)
        }

        /** The picture itself, then mirrored copies beside it while it's narrower than the area. */
        fun tiles(frame: SceneRect, width: Double): List<SceneTile> {
            if (frame.width <= 0) return emptyList()
            val tiles = mutableListOf(SceneTile(frame, false))
            var step = 1
            while (frame.x - (step - 1) * frame.width > 0 || frame.maxX + (step - 1) * frame.width < width) {
                val mirrored = step % 2 != 0
                val offset = step * frame.width
                tiles += SceneTile(frame.offsetBy(-offset), mirrored)
                tiles += SceneTile(frame.offsetBy(offset), mirrored)
                step++
            }
            return tiles.filter { it.frame.maxX > 0 && it.frame.x < width }
        }

        /** The scene a theme shows, if any. */
        fun of(theme: ReaderTheme): ThemeScene? = when (theme) {
            ReaderTheme.FOREST -> FOREST
            ReaderTheme.OCEAN -> OCEAN
            ReaderTheme.HEARTH -> HEARTH
            else -> null
        }
    }
}

/** A scene's shade: an ellipse (centre and radii as shares of the area) with opacity stops from the centre out. */
data class SceneShade(
    val hex: Int,
    val centerX: Double,
    val centerY: Double,
    val radiusX: Double,
    val radiusY: Double,
    val stops: List<Pair<Double, Double>>,
) {
    fun opacity(x: Double, y: Double, size: SceneSize): Double {
        if (size.width <= 0 || size.height <= 0) return 0.0
        val dx = (x / size.width - centerX) / radiusX
        val dy = (y / size.height - centerY) / radiusY
        val distance = min(1.0, sqrt(dx * dx + dy * dy))
        val after = stops.indexOfFirst { it.first >= distance }
        if (after < 0) return stops.lastOrNull()?.second ?: 0.0
        if (after == 0) return stops[0].second
        val (al, ao) = stops[after - 1]
        val (bl, bo) = stops[after]
        val t = (distance - al) / max(0.0001, bl - al)
        return ao + (bo - ao) * t
    }
}

/** The Ocean's two swell layers at the foot of the screen, rising and settling out of step. */
object OceanSwells {
    const val CONTENT_WIDTH = 1536.0
    const val FAR_ROWS = 802.0
    const val FAR_LEAD = 120.0
    const val NEAR_ROWS = 352.0
    const val SIDE_PAD = 40.0
    const val BOTTOM_PAD = 80.0
    const val RISE = 5.0
    const val SINK_SHARE = 0.3
    const val LEAN = 7.0

    /** dp per picture pixel: the area's width, unless that makes the swells taller than a quarter of it. */
    fun scale(size: SceneSize): Double = min(size.width / CONTENT_WIDTH, size.height * 0.26 / (FAR_ROWS - FAR_LEAD))

    fun sink(size: SceneSize): Double = (FAR_ROWS - FAR_LEAD) * scale(size) * SINK_SHARE

    /** Where the swells begin (below the lead-in, which is only colour). */
    fun top(size: SceneSize): Double = size.height - (FAR_ROWS - FAR_LEAD) * scale(size) + sink(size)

    /** A layer's frame at rest, padding included, centred. */
    fun frame(near: Boolean, size: SceneSize): SceneRect {
        val s = scale(size)
        val rows = if (near) NEAR_ROWS else FAR_ROWS
        val width = (CONTENT_WIDTH + SIDE_PAD * 2) * s
        return SceneRect((size.width - width) / 2, size.height - rows * s + sink(size), width, (rows + BOTTOM_PAD) * s)
    }

    /** The width one copy covers (without its padding), for repeating. */
    fun period(size: SceneSize): Double = CONTENT_WIDTH * scale(size)

    /** How far a layer is moved at `time` (dx, dy up): the near layer quicker and out of step. */
    fun offset(near: Boolean, time: Double): Pair<Double, Double> {
        val tau = 2 * PI
        return if (near) {
            val y = 0.62 * sin(tau * time / 5.9 + 1.9) + 0.38 * sin(tau * time / 3.7 + 0.4)
            val x = -sin(tau * time / 9.4 + 0.7)
            LEAN * x to RISE * y
        } else {
            val y = 0.7 * sin(tau * time / 7.3) + 0.3 * sin(tau * time / 4.6 + 2.2)
            val x = sin(tau * time / 11.2 + 0.3)
            LEAN * 0.7 * x to RISE * 0.8 * y
        }
    }
}

/** The Forest's mist: two translucent layers of soft puffs drifting slowly sideways between the trunks. */
object ForestMist {
    class Puff(val x: Double, val y: Double, val width: Double, val height: Double, val opacity: Double, val bob: Double)
    class Layer(val puffs: List<Puff>, val speed: Double)
    data class State(val centerX: Double, val centerY: Double, val radiusX: Double, val radiusY: Double, val opacity: Double)

    val layers: List<Layer> = SeededRandom(61).let { random ->
        fun puffs(count: Int, low: Double, high: Double, size: Double, opacity: Double) = (0 until count).map { index ->
            Puff(
                x = (index + random.next() * 0.7) / count,
                y = low + random.next() * (high - low),
                width = size * (0.8 + random.next() * 0.6),
                height = size * (0.28 + random.next() * 0.14),
                opacity = opacity * (0.7 + random.next() * 0.3),
                bob = random.next() * PI * 2,
            )
        }
        listOf(Layer(puffs(6, 0.6, 0.76, 0.2, 0.42), 6.0), Layer(puffs(5, 0.72, 0.9, 0.24, 0.5), 11.0))
    }

    /** Where a puff is at `time`; each layer wraps off screen. */
    fun state(puff: Puff, layer: Layer, time: Double, size: SceneSize): State {
        val radius = puff.width * size.height
        val span = size.width + radius * 2 + size.height * 0.2
        val travelled = (puff.x * span + time * layer.speed).rem(span)
        val bob = sin(time * 0.21 + puff.bob) * size.height * 0.006
        return State(travelled - radius, puff.y * size.height + bob, radius, puff.height * size.height, puff.opacity)
    }
}

/** The Forest's boughs swaying: the canopy in thin bands moving most at the top, nothing where it ends. */
object ForestSway {
    const val CANOPY = 1266.0 / 2752.0
    const val BANDS = 28
    const val REACH = 3.0

    fun offset(share: Double, time: Double): Double {
        if (share >= CANOPY) return 0.0
        val weight = (1 - max(0.0, share) / CANOPY).pow(1.8)
        val tau = 2 * PI
        val lag = share * 2.2
        val breeze = 0.65 * sin(tau * time / 6.8 - lag) + 0.35 * sin(tau * time / 3.1 + 1.3 - lag * 1.5)
        return REACH * weight * breeze
    }
}

/** The Forest on an area wider than tall: its wide picture, one copy pushed out past each side, blended in the clearing. */
object ForestWide {
    const val ASPECT = 2752.0 / 1536.0
    const val CANOPY = 707.0 / 1536.0
    const val BLEND_SHARE = 0.24
    const val TREE_SHARE = 0.28
    const val EDGE_SHARE = 0.13

    fun uses(size: SceneSize): Boolean = size.height > 0 && size.width >= size.height

    fun copies(size: SceneSize): Pair<SceneRect, SceneRect> {
        val height = max(size.height, size.width / ASPECT)
        val width = height * ASPECT
        val y = size.height - height
        val push = width * TREE_SHARE - size.width * EDGE_SHARE
        return SceneRect(-push, y, width, height) to SceneRect(size.width - width + push, y, width, height)
    }

    /** Where the right copy fades in over the left one (x from, x to). */
    fun blend(size: SceneSize): Pair<Double, Double> {
        val half = size.width * BLEND_SHARE / 2
        val (left, right) = copies(size)
        val lower = max(size.width / 2 - half, right.x + right.width * TREE_SHARE)
        val upper = min(size.width / 2 + half, left.maxX - left.width * TREE_SHARE)
        return lower to max(lower, upper)
    }
}

/** Hearth's glow: rising from the whole foot of the screen, breathing, brighter patches wandering along it. */
object HearthGlow {
    const val HEIGHT = 0.48
    const val BRIGHT_BAND = 0.1
    const val EMBER_WIDTH = 0.9

    fun strength(time: Double): Double = 0.8 + 0.2 * HearthSparks.glow(time)

    /** The two brighter patches: x (share of the width) and strength (0..1). */
    fun patches(time: Double): List<Pair<Double, Double>> = listOf(
        (0.3 + 0.12 * sin(time * 2 * PI / 17)) to (0.6 + 0.4 * sin(time * 2 * PI / 5.3 + 0.4)),
        (0.7 + 0.12 * sin(time * 2 * PI / 23 + 2)) to (0.6 + 0.4 * sin(time * 2 * PI / 4.1 + 2.2)),
    )
}

/** Hearth's embers: small amber sparks leaving the coals at uneven moments, rising and fading. */
object HearthSparks {
    class Spark(val period: Double, val delay: Double, val sway: Double, val swaySpeed: Double, val phase: Double)
    data class State(val x: Double, val y: Double, val radius: Double, val opacity: Double)

    val sparks: List<Spark> = SeededRandom(47).let { random ->
        (0 until 22).map {
            Spark(2.6 + random.next() * 2.8, random.next() * 6, 3 + random.next() * 6, 1.2 + random.next() * 1.6, random.next() * PI * 2)
        }
    }

    /** A spark at `time`, rising from the coals toward `ceiling`; null between flights. */
    fun state(spark: Spark, index: Int, time: Double, sourceX: Double, sourceY: Double, width: Double, ceiling: Double): State? {
        val t = time + spark.delay
        if (t < 0) return null
        val cycle = floor(t / spark.period)
        val seed = index * 13.7 + cycle
        val flight = spark.period * (0.55 + 0.35 * hash(seed))
        val local = t - cycle * spark.period
        if (local >= flight) return null
        val progress = local / flight
        val height = max(0.0, sourceY - ceiling) * (0.45 + 0.55 * hash(seed + 0.3))
        val start = sourceX + (hash(seed + 0.6) - 0.5) * width
        val drift = (hash(seed + 0.9) - 0.5) * 24 * progress
        val x = start + drift + spark.sway * progress * sin(t * spark.swaySpeed + spark.phase)
        val y = sourceY - height * progress.pow(0.85)
        val catchUp = min(1.0, progress / 0.08)
        val flicker = 0.75 + 0.25 * sin(t * 9 + spark.phase)
        val radius = 0.6 + 1.0 * hash(seed + 0.45)
        return State(x, y, radius, catchUp * (1 - progress).pow(1.3) * flicker)
    }

    /** The glow over the coals: slow, shallow breathing (0..1). */
    fun glow(time: Double): Double = 0.5 + 0.32 * sin(time * 2 * PI / 6.5) + 0.18 * sin(time * 2 * PI / 2.3 + 1.1)

    private fun hash(value: Double): Double {
        val x = sin(value * 127.1 + 311.7) * 43758.5453
        return x - floor(x)
    }
}
