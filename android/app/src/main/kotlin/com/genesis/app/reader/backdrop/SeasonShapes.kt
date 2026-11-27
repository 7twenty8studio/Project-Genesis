package com.genesis.app.reader.backdrop

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import com.genesis.core.domain.theme.SeasonMotion
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/**
 * The seasons' shapes, as SeasonShapes.swift: maple, oak and birch leaves,
 * six-sided snow crystals, cherry petals and whole blossoms, and summer's
 * butterfly. Every path is built once at unit size, centred on the origin
 * and pointing up; `scaled` sizes a copy.
 */
internal object SeasonShapes {
    enum class LeafKind {
        MAPLE, OAK, BIRCH;

        companion object {
            /** The mix used across the page: maples most often. */
            fun mixed(index: Int): LeafKind = listOf(MAPLE, OAK, BIRCH, MAPLE, BIRCH, OAK, MAPLE)[index % 7]
        }
    }

    fun leaf(kind: LeafKind): Path = when (kind) {
        LeafKind.MAPLE -> maple
        LeafKind.OAK -> oak
        LeafKind.BIRCH -> birch
    }

    fun leafVeins(kind: LeafKind): Path = when (kind) {
        LeafKind.MAPLE -> mapleVeins
        LeafKind.OAK -> oakVeins
        LeafKind.BIRCH -> birchVeins
    }

    private data class Lobe(val angle: Double, val reach: Double, val width: Double)

    private val mapleLobes = listOf(Lobe(0.0, 1.0, 0.36), Lobe(0.9, 0.88, 0.34), Lobe(-0.9, 0.88, 0.34), Lobe(1.85, 0.5, 0.28), Lobe(-1.85, 0.5, 0.28))
    private const val MAPLE_CENTRE = 0.08

    val maple: Path by lazy { mapleOutline(240) }

    private fun mapleOutline(steps: Int): Path {
        val path = Path()
        for (i in 0..steps) {
            val theta = -PI + 2 * PI * i / steps
            var r = 0.12
            for (lobe in mapleLobes) {
                val d = SeasonMotion.angleBetween(theta, lobe.angle)
                val body = exp(-(d / lobe.width).pow(2))
                val tip = exp(-(d / (lobe.width * 0.28)).pow(2)) * 0.18
                val tooth = exp(-(abs(d) - lobe.width * 0.75).pow(2) / (2 * (lobe.width * 0.09).pow(2))) * 0.10
                r = max(r, 0.12 + lobe.reach * (0.30 * body + tip) + lobe.reach * tooth * body)
            }
            val back = abs(SeasonMotion.angleBetween(theta, PI))
            if (back < 0.45) r = min(r, 0.08 + 0.25 * back)
            val x = (sin(theta) * r).toFloat()
            val y = (-cos(theta) * r + MAPLE_CENTRE).toFloat()
            if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        return path
    }

    val mapleVeins: Path by lazy {
        Path().apply {
            for (lobe in mapleLobes) {
                val r = 0.12 + lobe.reach * 0.42
                moveTo(0f, MAPLE_CENTRE.toFloat())
                lineTo((sin(lobe.angle) * r).toFloat(), (-cos(lobe.angle) * r + MAPLE_CENTRE).toFloat())
            }
            moveTo(0f, MAPLE_CENTRE.toFloat())
            lineTo(0f, 0.45f)
        }
    }

    private fun oakHalfWidth(s: Double): Double {
        val envelope = max(0.0, sin(PI * min(1.0, s * 1.02))).pow(0.8) * 0.34 * (1 - 0.35 * s)
        return envelope * (0.45 + 0.55 * abs(cos(PI * 3.5 * s + 0.3)).pow(0.6))
    }

    private fun birchHalfWidth(s: Double): Double {
        val envelope = sin(PI * s.pow(0.75)) * 0.3
        val saw = (s * 16).rem(1.0)
        val tooth = (if (saw < 0.5) saw else 1 - saw) * 2
        return max(0.0, envelope * (1 + 0.08 * tooth - 0.04))
    }

    val oak: Path by lazy { outline(::oakHalfWidth) }
    val birch: Path by lazy { outline(::birchHalfWidth) }
    val oakVeins: Path by lazy { veins(::oakHalfWidth, 4) }
    val birchVeins: Path by lazy { veins(::birchHalfWidth, 6) }

    /** A symmetrical leaf from its half-width at each point along it (0 tip, 1 base). */
    private fun outline(halfWidth: (Double) -> Double, steps: Int = 80): Path {
        val side = (0..steps).map { i -> val s = i.toDouble() / steps; halfWidth(s) to s - 0.5 }
        return Path().apply {
            moveTo(0f, -0.5f)
            side.forEach { (x, y) -> lineTo(x.toFloat(), y.toFloat()) }
            side.reversed().forEach { (x, y) -> lineTo(-x.toFloat(), y.toFloat()) }
            close()
        }
    }

    /** A midrib running on into the stem, and side veins angled to the tip. */
    private fun veins(halfWidth: (Double) -> Double, pairs: Int): Path = Path().apply {
        moveTo(0f, -0.46f)
        lineTo(0f, 0.62f)
        for (i in 1..pairs) {
            val s = i.toDouble() / (pairs + 1)
            val y = s - 0.5
            val reach = halfWidth(s) * 0.75
            for (side in listOf(1.0, -1.0)) {
                moveTo(0f, (y + 0.04).toFloat())
                lineTo((side * reach).toFloat(), (y - 0.03).toFloat())
            }
        }
    }

    // Snow crystals (radius 1)

    enum class FlakeKind { STELLAR, FERN, PLATE }

    fun flakeArms(kind: FlakeKind): Path = when (kind) {
        FlakeKind.STELLAR -> stellarArms
        FlakeKind.FERN -> fernArms
        FlakeKind.PLATE -> plateArms
    }

    fun flakeCore(kind: FlakeKind): Path? = when (kind) {
        FlakeKind.STELLAR -> null
        FlakeKind.FERN -> fernCore
        FlakeKind.PLATE -> plateCore
    }

    private val stellarArms by lazy { arms(listOf(0.45 to 0.3, 0.72 to 0.2)) }
    private val fernArms by lazy { arms(listOf(0.3 to 0.32, 0.5 to 0.36, 0.7 to 0.26, 0.86 to 0.14)) }
    private val plateArms by lazy { arms(listOf(0.62 to 0.16)) }
    private val fernCore by lazy { hexagon(0.16) }
    private val plateCore by lazy {
        hexagon(0.28).apply {
            for (k in 0 until 6) {
                val tip = Path().apply {
                    moveTo(0f, -1f); lineTo(0.1f, -0.88f); lineTo(0f, -0.76f); lineTo(-0.1f, -0.88f); close()
                }
                addPath(tip.rotated(k * PI / 3))
            }
        }
    }

    /** Six arms, each with side branches at 60° (position along the arm, length). */
    private fun arms(branches: List<Pair<Double, Double>>): Path {
        val arm = Path().apply {
            moveTo(0f, 0f); lineTo(0f, -1f)
            for ((at, length) in branches) for (side in listOf(1.0, -1.0)) {
                moveTo(0f, (-at).toFloat())
                lineTo((side * sin(PI / 3) * length).toFloat(), (-at - cos(PI / 3) * length).toFloat())
            }
        }
        return Path().apply { for (k in 0 until 6) addPath(arm.rotated(k * PI / 3)) }
    }

    private fun hexagon(radius: Double): Path = Path().apply {
        for (k in 0 until 6) {
            val angle = k * PI / 3
            val x = (sin(angle) * radius).toFloat()
            val y = (-cos(angle) * radius).toFloat()
            if (k == 0) moveTo(x, y) else lineTo(x, y)
        }
        close()
    }

    // Blossom (petal: half-length 1; blossom: radius 1)

    val petal: Path by lazy {
        val h = 1f
        val w = h * 0.62f
        Path().apply {
            moveTo(0f, h)
            quadraticTo(w, 0f, w * 0.4f, -h)
            lineTo(0f, -h * 0.68f)
            lineTo(-w * 0.4f, -h)
            quadraticTo(-w, 0f, 0f, h)
        }
    }

    val blossomPetals: Path by lazy {
        // Scaled to 0.55, then moved out from the centre by its own (scaled) length.
        val one = petal.scaled(0.55f).apply { translate(Offset(0f, -0.55f)) }
        Path().apply { for (k in 0 until 5) addPath(one.rotated(k * 2 * PI / 5)) }
    }

    val blossomCentre: Path by lazy { Path().apply { addOval(Rect(-0.18f, -0.18f, 0.18f, 0.18f)) } }

    private val stamenAngles = (0 until 8).map { it * PI / 4 + 0.2 }

    val stamens: Path by lazy {
        Path().apply { for (a in stamenAngles) { moveTo(0f, 0f); lineTo((cos(a) * 0.42).toFloat(), (sin(a) * 0.42).toFloat()) } }
    }

    val stamenTips: Path by lazy {
        Path().apply {
            for (a in stamenAngles) {
                val c = Offset((cos(a) * 0.44).toFloat(), (sin(a) * 0.44).toFloat())
                addOval(Rect(c.x - 0.05f, c.y - 0.05f, c.x + 0.05f, c.y + 0.05f))
            }
        }
    }

    // Butterfly (wingspan about 2, body along y)

    val butterflyUpperWing: Path by lazy {
        Path().apply {
            moveTo(0f, -0.1f)
            cubicTo(0.3f, -0.9f, 1.05f, -0.75f, 0.85f, -0.15f)
            cubicTo(0.75f, 0.05f, 0.3f, 0.05f, 0f, 0f)
            close()
        }
    }

    val butterflyLowerWing: Path by lazy {
        Path().apply {
            moveTo(0f, 0.02f)
            cubicTo(0.55f, 0.05f, 0.75f, 0.55f, 0.4f, 0.7f)
            cubicTo(0.2f, 0.75f, 0.05f, 0.4f, 0f, 0.1f)
            close()
        }
    }

    val butterflyBody: Path by lazy { Path().apply { addOval(Rect(-0.06f, -0.3f, 0.06f, 0.6f)) } }

    val butterflyAntennae: Path by lazy {
        Path().apply {
            for (side in listOf(1f, -1f)) {
                moveTo(0f, -0.25f)
                quadraticTo(side * 0.05f, -0.55f, side * 0.2f, -0.65f)
            }
        }
    }

    /** A unit-size shape at a given size (a copy). */
    fun Path.scaled(size: Float): Path = Path().also { it.addPath(this); it.transform(Matrix().apply { scale(size, size) }) }

    private fun Path.rotated(radians: Double): Path =
        Path().also { it.addPath(this); it.transform(Matrix().apply { rotateZ(Math.toDegrees(radians).toFloat()) }) }
}
