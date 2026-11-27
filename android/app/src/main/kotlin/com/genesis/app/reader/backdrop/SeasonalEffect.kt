package com.genesis.app.reader.backdrop

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.semantics.clearAndSetSemantics
import com.genesis.app.reader.backdrop.SeasonShapes.scaled
import com.genesis.core.domain.theme.ButterflyFlight
import com.genesis.core.domain.theme.Season
import com.genesis.core.domain.theme.SeasonMotion
import com.genesis.core.domain.theme.SeededRandom
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * The season drifting gently across the page, as SeasonalEffectView on iOS:
 * maple, oak and birch leaves tumbling down; spring petals and blossoms on
 * a breeze over warm light; snow at three depths with gusts and frost in
 * the corners; or summer's rays, colour washes, dust in the beams and a
 * passing butterfly. Sparse and translucent so the words stay easy to read.
 * It takes no taps, is hidden from TalkBack, holds still in Battery Saver,
 * and with Remove Animations shows one painted still moment. 30 fps.
 */
@Composable
fun SeasonalEffect(season: Season, modifier: Modifier = Modifier) {
    val reduce = rememberReduceMotion()
    val running = !reduce && !rememberPowerSave() && rememberResumed()
    val time by rememberMotionTime(running) { 1.0 / 30 }
    Box(modifier.fillMaxSize().clearAndSetSemantics { }) {
        if (season == Season.WINTER) Canvas(Modifier.fillMaxSize()) { WinterSnow.drawFrost(this) }
        Canvas(Modifier.fillMaxSize()) {
            val t = if (reduce) SeasonMotion.PAINTED_MOMENT else time
            // Fades in when it starts.
            val fade = if (reduce) 1f else min(1.0, t / 1.5).toFloat()
            when (season) {
                Season.AUTUMN -> AutumnLeaves.draw(this, t, fade)
                Season.SPRING -> SpringPetals.draw(this, t, fade)
                Season.WINTER -> WinterSnow.draw(this, t, fade)
                Season.SUMMER -> SummerLight.draw(this, t, fade)
            }
        }
    }
}

private fun hex(value: Long) = Color(0xFF000000 or value)

private fun DrawScope.disc(center: Offset, radius: Float, color: Color) = drawCircle(color, radius, center)

private fun DrawScope.glow(center: Offset, radius: Float, inner: Color, alpha: Float) {
    if (radius <= 0f || alpha <= 0f) return
    drawCircle(Brush.radialGradient(listOf(inner.copy(alpha = alpha.coerceIn(0f, 1f)), inner.copy(alpha = 0f)), center, radius), radius, center)
}

/** Seven leaves falling 14–26 dp a second, swaying and turning over as they go. */
private object AutumnLeaves {
    class Leaf(val x: Double, val offset: Double, val speed: Double, val sway: Double, val swaySpeed: Double, val phase: Double, val size: Double, val spin: Double, val tone: Int, val kind: SeasonShapes.LeafKind)

    val leaves: List<Leaf> = SeededRandom(14).let { r ->
        (0 until 7).map { index ->
            Leaf(r.next(), r.next(), 14 + r.next() * 12, 18 + r.next() * 22, 0.35 + r.next() * 0.35, r.next() * PI * 2, r.next(), (r.next() - 0.5) * 1.2, (r.next() * 3).toInt() % 3, SeasonShapes.LeafKind.mixed(index))
        }
    }
    val colors = listOf(hex(0xB4693A), hex(0xC99541), hex(0x9C4F2E))

    fun draw(scope: DrawScope, t: Double, fade: Float) = with(scope) {
        val d = density
        val width = size.width / d
        val height = size.height / d
        for (leaf in leaves) {
            val travel = height + 60.0
            val y = SeasonMotion.wrap(leaf.offset * travel + t * leaf.speed, travel) - 30
            val x = leaf.x * width + sin(t * leaf.swaySpeed + leaf.phase) * leaf.sway
            val length = (20 + leaf.size * 14).toFloat() * d
            withTransform({
                translate((x * d).toFloat(), (y * d).toFloat())
                rotate(Math.toDegrees(leaf.phase + t * leaf.spin).toFloat(), Offset.Zero)
                scale(max(0.2, abs(cos(t * leaf.swaySpeed * 1.3 + leaf.phase))).toFloat(), 1f, Offset.Zero)
            }) {
                drawPath(SeasonShapes.leaf(leaf.kind).scaled(length), colors[leaf.tone].copy(alpha = 0.45f * fade))
                drawPath(SeasonShapes.leafVeins(leaf.kind).scaled(length), colors[leaf.tone].copy(alpha = 0.6f * fade), style = Stroke(0.8f * d))
            }
        }
    }
}

/** Twelve petals on one breeze that swells and settles over 50 s, over two slow patches of warm light; one in four a whole blossom. */
private object SpringPetals {
    class Petal(val x: Double, val offset: Double, val fall: Double, val drift: Double, val flutter: Double, val flutterSpeed: Double, val phase: Double, val spin: Double, val size: Double, val tone: Int, val isBlossom: Boolean)

    val petals: List<Petal> = SeededRandom(8).let { r ->
        (0 until 12).map { index ->
            Petal(r.next(), r.next(), 12 + r.next() * 8, 6 + r.next() * 6, 8 + r.next() * 14, 0.5 + r.next() * 0.6, r.next() * PI * 2, (r.next() - 0.5) * 1.4, 6.5 + r.next() * 4, (r.next() * 3).toInt() % 3, index % 4 == 0)
        }
    }
    val colors = listOf(hex(0xE2A9B5), hex(0xEDC4CB), hex(0xD493A2))
    val light = listOf(Triple(0.25, 0.3, hex(0xFFECC8)), Triple(0.75, 0.65, hex(0xF7D6DE)))
    val heart = hex(0xC97D8E)
    val pollen = hex(0xE0B25A)

    fun draw(scope: DrawScope, t: Double, fade: Float) = with(scope) {
        val d = density
        val width = size.width / d
        val height = size.height / d
        light.forEachIndexed { index, (px, py, color) ->
            val center = Offset(((px + 0.12 * sin(t * 0.05 + index * 2)) * width * d).toFloat(), ((py + 0.06 * cos(t * 0.04 + index)) * height * d).toFloat())
            glow(center, (0.57 * width * d).toFloat(), color, 0.2f * fade)
        }
        val breeze = 34 * sin(t * PI * 2 / 50)
        for (petal in petals) {
            val travelY = height + 40.0
            val y = SeasonMotion.wrap(petal.offset * travelY + t * petal.fall, travelY.toDouble()) - 20
            val travelX = width + 40.0
            val x = SeasonMotion.wrap(petal.x * travelX + t * petal.drift + breeze + petal.flutter * sin(t * petal.flutterSpeed + petal.phase), travelX.toDouble()) - 20
            withTransform({
                translate((x * d).toFloat(), (y * d).toFloat())
                rotate(Math.toDegrees(petal.phase + t * petal.spin).toFloat(), Offset.Zero)
                if (petal.isBlossom) scale(max(0.45, abs(cos(t * petal.flutterSpeed * 1.4 + petal.phase))).toFloat(), 1f, Offset.Zero)
                else scale(max(0.2, abs(cos(t * petal.flutterSpeed * 1.4 + petal.phase))).toFloat(), (0.65 + 0.35 * sin(t * petal.flutterSpeed + petal.phase * 2)).toFloat(), Offset.Zero)
            }) {
                if (petal.isBlossom) {
                    val r = (petal.size * 1.9).toFloat() * d
                    drawPath(SeasonShapes.blossomPetals.scaled(r), colors[petal.tone].copy(alpha = 0.6f * fade))
                    drawPath(SeasonShapes.blossomCentre.scaled(r), heart.copy(alpha = 0.6f * fade))
                    drawPath(SeasonShapes.stamens.scaled(r), heart.copy(alpha = 0.6f * fade), style = Stroke(max(0.4f * d, r * 0.04f)))
                    drawPath(SeasonShapes.stamenTips.scaled(r), pollen.copy(alpha = 0.6f * fade))
                } else {
                    drawPath(SeasonShapes.petal.scaled(petal.size.toFloat() * d), colors[petal.tone].copy(alpha = 0.55f * fade))
                }
            }
        }
    }
}

/** Snow at three depths (far dots, crystals in the middle, a few large near ones turning slowly), a gust every 25 s, frost in the corners. */
private object WinterSnow {
    class Flake(val x: Double, val offset: Double, val radius: Double, val fall: Double, val sway: Double, val swaySpeed: Double, val phase: Double, val gust: Double, val opacity: Double, val turn: Double, val isNear: Boolean, val kind: SeasonShapes.FlakeKind?)

    private class Depth(val count: Int, val radius: ClosedFloatingPointRange<Double>, val fall: ClosedFloatingPointRange<Double>, val opacity: Double, val gust: Double, val sway: Double, val near: Boolean, val kinds: List<SeasonShapes.FlakeKind>)

    val flakes: List<Flake> = SeededRandom(21).let { r ->
        val depths = listOf(
            Depth(18, 0.9..1.3, 7.0..11.0, 0.6, 0.35, 6.0, false, emptyList()),
            Depth(12, 3.0..4.2, 13.0..19.0, 0.9, 0.65, 12.0, false, listOf(SeasonShapes.FlakeKind.STELLAR, SeasonShapes.FlakeKind.PLATE)),
            Depth(5, 7.0..10.0, 24.0..32.0, 0.8, 1.0, 20.0, true, listOf(SeasonShapes.FlakeKind.FERN, SeasonShapes.FlakeKind.PLATE, SeasonShapes.FlakeKind.STELLAR)),
        )
        depths.flatMap { depth ->
            (0 until depth.count).map { index ->
                Flake(
                    x = r.next(), offset = r.next(),
                    radius = depth.radius.start + r.next() * (depth.radius.endInclusive - depth.radius.start),
                    fall = depth.fall.start + r.next() * (depth.fall.endInclusive - depth.fall.start),
                    sway = depth.sway, swaySpeed = 0.3 + r.next() * 0.4, phase = r.next() * PI * 2,
                    gust = depth.gust, opacity = depth.opacity, turn = if (index % 2 == 0) 0.15 else -0.15,
                    isNear = depth.near, kind = if (depth.kinds.isEmpty()) null else depth.kinds[index % depth.kinds.size],
                )
            }
        }
    }
    val blue = hex(0x8FA6B8)

    fun draw(scope: DrawScope, t: Double, fade: Float) = with(scope) {
        val d = density
        val width = size.width / d
        val height = size.height / d
        val gust = SeasonMotion.gustOffset(t)
        for (flake in flakes) {
            val travelY = height + 40.0
            val y = SeasonMotion.wrap(flake.offset * travelY + t * flake.fall, travelY) - 20
            val travelX = width + 40.0
            val x = SeasonMotion.wrap(flake.x * travelX + gust * flake.gust + flake.sway * sin(t * flake.swaySpeed + flake.phase), travelX) - 20
            val center = Offset((x * d).toFloat(), (y * d).toFloat())
            val kind = flake.kind
            val opacity = (flake.opacity * fade).toFloat()
            if (kind != null) {
                withTransform({
                    translate(center.x, center.y)
                    rotate(Math.toDegrees(flake.phase + t * flake.turn).toFloat(), Offset.Zero)
                }) {
                    val r = flake.radius.toFloat() * d
                    if (flake.isNear) glow(Offset.Zero, r * 1.3f, blue, 0.25f * fade)
                    val arms = SeasonShapes.flakeArms(kind).scaled(r)
                    val core = SeasonShapes.flakeCore(kind)?.scaled(r)
                    drawPath(arms, blue.copy(alpha = opacity * 0.75f), style = Stroke(max(1.1f * d, r * 0.16f), cap = StrokeCap.Round))
                    core?.let { drawPath(it, blue.copy(alpha = opacity * 0.75f)) }
                    drawPath(arms, Color.White.copy(alpha = 0.95f * opacity), style = Stroke(max(0.45f * d, r * 0.06f), cap = StrokeCap.Round))
                    core?.let { drawPath(it, Color.White.copy(alpha = 0.95f * opacity), style = Stroke(max(0.45f * d, r * 0.06f))) }
                }
            } else {
                val r = flake.radius.toFloat() * d
                disc(center, r, blue.copy(alpha = opacity))
                disc(center, r / 2, Color.White.copy(alpha = 0.85f * fade))
            }
        }
    }

    /** Fine frost in each corner: a soft white glow and a few branching crystals, small so they stay clear of the text. */
    fun drawFrost(scope: DrawScope) = with(scope) {
        val d = density
        val corners = listOf(Triple(Offset.Zero, 1f, 1f), Triple(Offset(size.width, 0f), -1f, 1f), Triple(Offset(0f, size.height), 1f, -1f), Triple(Offset(size.width, size.height), -1f, -1f))
        for ((corner, sx, sy) in corners) {
            glow(corner, 70 * d, Color.White, 0.6f)
            withTransform({
                translate(corner.x, corner.y)
                scale(sx * d, sy * d, Offset.Zero)
            }) { drawPath(crystals, blue.copy(alpha = 0.16f), style = Stroke(0.5f)) }
        }
    }

    /** Five branching crystals growing out from a top-left corner (in dp). */
    val crystals: Path = SeededRandom(3).let { r ->
        Path().apply {
            repeat(5) {
                var px = 0.0
                var py = 0.0
                var angle = PI / 4 + (r.next() - 0.5) * 1.5
                moveTo(0f, 0f)
                repeat(5) {
                    val nx = px + cos(angle) * 9
                    val ny = py + sin(angle) * 9
                    lineTo(nx.toFloat(), ny.toFloat())
                    for (side in listOf(-1.0, 1.0)) {
                        moveTo(nx.toFloat(), ny.toFloat())
                        lineTo((nx + cos(angle + side * 0.9) * 4).toFloat(), (ny + sin(angle + side * 0.9) * 4).toFloat())
                    }
                    moveTo(nx.toFloat(), ny.toFloat())
                    px = nx
                    py = ny
                    angle += (r.next() - 0.5) * 0.4
                }
            }
        }
    }
}

/** Summer: slow rays from the top corner over warm washes of colour, dust twinkling in the beams, and now and then a butterfly. */
private object SummerLight {
    class Wash(val x: Double, val y: Double, val radius: Double, val driftX: Double, val driftY: Double, val speed: Double, val phase: Double, val color: Color)
    class Shaft(val angle: Double, val width: Double, val reach: Double, val phase: Double)
    class Mote(val beam: Int, val start: Double, val speed: Double, val jitter: Double, val radius: Double, val twinkle: Double, val phase: Double)

    val washes: List<Wash> = SeededRandom(41).let { r ->
        listOf(0xF2C98AL, 0xEFB9A0L, 0xB9D5C9L, 0xF4DE9EL, 0xEAC27EL, 0xC9DDC0L).map { value ->
            Wash(r.next(), r.next(), 0.28 + r.next() * 0.22, 0.04 + r.next() * 0.08, 0.03 + r.next() * 0.06, 0.05 + r.next() * 0.06, r.next() * PI * 2, hex(value))
        }
    }
    val shafts: List<Shaft> = SeededRandom(23).let { r ->
        (0 until 9).map { index -> Shaft(PI * 0.615 + index * 0.047 + (r.next() - 0.5) * 0.02, 0.004 + r.next() * 0.008, 0.5 + r.next() * 0.3, r.next() * PI * 2) }
    }
    val motes: List<Mote> = SeededRandom(5).let { r ->
        (0 until 50).map { Mote((r.next() * 6).toInt() % 6, r.next(), 0.004 + r.next() * 0.007, (r.next() - 0.5) * 0.08, 1.3 + r.next() * 1.4, 0.6 + r.next(), r.next() * PI * 2) }
    }
    val rayLayers = listOf(3.2 to 0.22, 1.9 to 0.45, 1.0 to 1.0)
    val ray = hex(0xF0C25E)
    val moteCore = hex(0xFFF6DC)
    val moteHalo = hex(0xE9BE73)
    val wingUpper = hex(0xD99A4E)
    val wingLower = hex(0xC9813C)
    val wingSpot = hex(0xFFF5E1)
    val body = hex(0x6B4A2E)

    fun beamAngle(index: Int) = PI * 0.62 + index * 0.075

    fun draw(scope: DrawScope, t: Double, fade: Float) = with(scope) {
        val d = density
        val width = size.width / d
        val height = size.height / d
        val scale = max(width, height)
        for (wash in washes) {
            val center = Offset(
                ((wash.x + sin(t * wash.speed + wash.phase) * wash.driftX) * width * d).toFloat(),
                ((wash.y + cos(t * wash.speed * 0.8 + wash.phase) * wash.driftY) * height * d).toFloat(),
            )
            glow(center, (wash.radius * scale * d).toFloat(), wash.color, 0.3f * fade)
        }
        val sx = width * 1.05
        val sy = -height * 0.08
        val source = Offset((sx * d).toFloat(), (sy * d).toFloat())
        val length = scale * 1.5
        shafts.forEachIndexed { index, shaft ->
            val angle = shaft.angle + sin(t * 0.12 + index * 1.7) * 0.02
            val breathe = 0.5 + 0.5 * sin(t * 0.3 + shaft.phase)
            val strength = 0.05 + 0.11 * breathe
            val end = Offset(((sx + cos(angle) * length * shaft.reach) * d).toFloat(), ((sy + sin(angle) * length * shaft.reach) * d).toFloat())
            for ((widen, share) in rayLayers) {
                val spread = shaft.width * widen
                val path = Path().apply {
                    moveTo(source.x, source.y)
                    lineTo(((sx + cos(angle - spread) * length) * d).toFloat(), ((sy + sin(angle - spread) * length) * d).toFloat())
                    lineTo(((sx + cos(angle + spread) * length) * d).toFloat(), ((sy + sin(angle + spread) * length) * d).toFloat())
                    close()
                }
                drawPath(path, Brush.linearGradient(listOf(ray.copy(alpha = (strength * share).toFloat() * fade), ray.copy(alpha = 0f)), source, end))
            }
        }
        motes.forEachIndexed { index, mote ->
            val along = (mote.start + t * mote.speed).rem(1.0)
            val angle = beamAngle(mote.beam) + mote.jitter
            val distance = length * (0.1 + 0.85 * along) * 0.75
            val center = Offset(
                ((sx + cos(angle) * distance + sin(t * 0.3 + index) * 8) * d).toFloat(),
                ((sy + sin(angle) * distance + cos(t * 0.25 + index) * 6) * d).toFloat(),
            )
            val opacity = ((0.42 + 0.3 * abs(sin(t * mote.twinkle + mote.phase))) * sin(PI * along)).toFloat() * fade
            val glowRadius = (mote.radius * 2.6).toFloat() * d
            if (opacity > 0f) drawCircle(
                Brush.radialGradient(
                    0f to moteCore.copy(alpha = opacity),
                    0.22f to moteCore.copy(alpha = opacity * 0.9f),
                    0.45f to moteHalo.copy(alpha = opacity * 0.55f),
                    1f to moteHalo.copy(alpha = 0f),
                    center = center, radius = glowRadius,
                ),
                glowRadius, center,
            )
        }
        drawButterfly(width, height, t, fade)
    }

    private fun DrawScope.drawButterfly(width: Float, height: Float, t: Double, fade: Float) {
        val flight = ButterflyFlight.state(t, width.toDouble(), height.toDouble()) ?: return
        val d = density
        val s = 11f * d
        val alpha = 0.6f * fade
        withTransform({
            translate((flight.x * d).toFloat(), (flight.y * d).toFloat())
            rotate(Math.toDegrees(flight.angle).toFloat(), Offset.Zero)
        }) {
            for (side in listOf(1f, -1f)) {
                withTransform({ scale(side * flight.wingOpen.toFloat(), 1f, Offset.Zero) }) {
                    drawPath(SeasonShapes.butterflyUpperWing.scaled(s), wingUpper.copy(alpha = alpha))
                    drawPath(SeasonShapes.butterflyLowerWing.scaled(s), wingLower.copy(alpha = alpha))
                    drawCircle(wingSpot.copy(alpha = 0.8f * alpha), s * 0.09f, Offset(s * 0.6f, -s * 0.45f))
                }
            }
            drawPath(SeasonShapes.butterflyBody.scaled(s), body.copy(alpha = alpha))
            drawPath(SeasonShapes.butterflyAntennae.scaled(s), body.copy(alpha = alpha), style = Stroke(max(0.4f * d, s * 0.03f)))
        }
    }
}
