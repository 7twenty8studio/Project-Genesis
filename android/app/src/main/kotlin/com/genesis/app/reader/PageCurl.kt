package com.genesis.app.reader

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Matrix
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import kotlinx.coroutines.launch
import kotlin.math.hypot

/**
 * Which page shows, and the page being turned, for [PageCurl]. Turning is
 * animated by moving the turned corner (`finger`) across the page.
 */
@Stable
internal class PageCurlState(initial: Int, private val count: () -> Int) {
    var current by mutableIntStateOf(initial)
        private set
    /** The page being turned and which way, while one turns. */
    internal var turn by mutableStateOf<Turn?>(null)
    internal val finger = Animatable(Offset.Zero, Offset.VectorConverter)
    internal var size = androidx.compose.ui.geometry.Size.Zero

    val isTurning: Boolean get() = turn != null

    internal data class Turn(val forward: Boolean, val corner: Offset)

    fun snapTo(page: Int) {
        turn = null
        current = page.coerceIn(0, (count() - 1).coerceAtLeast(0))
    }

    /** Turns one page forward or back, as a tap on the edge does. */
    suspend fun turn(forward: Boolean) {
        if (turn != null || size.width <= 0f) return
        val target = current + if (forward) 1 else -1
        if (target !in 0 until count()) return
        val corner = Offset(size.width, size.height)
        val flat = corner
        val gone = Offset(-size.width, size.height * 0.92f)
        turn = Turn(forward, corner)
        finger.snapTo(if (forward) flat - Offset(1f, 1f) else gone)
        finger.animateTo(if (forward) gone else flat, tween(DURATION, easing = FastOutSlowInEasing))
        current = target
        turn = null
    }

    companion object { const val DURATION = 420 }
}

/**
 * Page Curl, as iOS's page curl: the page lifts from the corner under the
 * finger and folds back over itself (its back a pale sheet showing the
 * words faintly through), casting a shadow on the page beneath. Drag from
 * the right to turn forward, from the left to turn back; taps are left to
 * the pages (the reader turns on edge taps with [PageCurlState.turn]).
 */
@Composable
internal fun PageCurl(
    state: PageCurlState,
    count: Int,
    backColor: Color,
    modifier: Modifier = Modifier,
    content: @Composable (Int) -> Unit,
) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    BoxWithConstraints(modifier.fillMaxSize()) {
        val width = with(density) { maxWidth.toPx() }
        val height = with(density) { maxHeight.toPx() }
        state.size = androidx.compose.ui.geometry.Size(width, height)
        val turn = state.turn
        val drag = Modifier.pointerInput(count, width, height) {
            val tracker = VelocityTracker()
            var dx = 0f
            detectHorizontalDragGestures(
                onDragStart = {
                    dx = 0f
                    tracker.resetTracking()
                },
                onHorizontalDrag = { change, amount ->
                    change.consume()
                    dx += amount
                    tracker.addPosition(change.uptimeMillis, change.position)
                    val y = change.position.y
                    if (state.turn == null) {
                        val forward = dx < 0
                        val target = state.current + if (forward) 1 else -1
                        if (target !in 0 until count) return@detectHorizontalDragGestures
                        val corner = Offset(width, if (y > height / 2) height else 0f)
                        state.turn = PageCurlState.Turn(forward, corner)
                    }
                    val active = state.turn ?: return@detectHorizontalDragGestures
                    // Forward: the corner follows the finger. Back: the page comes in from the left.
                    val x = if (active.forward) (width + dx * 1.15f) else (-width + dx * 2f)
                    val target = Offset(x.coerceIn(-width, width - 1f), y.coerceIn(0f, height))
                    scope.launch { state.finger.snapTo(target) }
                },
                onDragEnd = {
                    val active = state.turn ?: return@detectHorizontalDragGestures
                    val velocity = tracker.calculateVelocity().x
                    val position = state.finger.value
                    val completes = if (active.forward) position.x < width * 0.45f || velocity < -900f else position.x > -width * 0.1f || velocity > 900f
                    val gone = Offset(-width, active.corner.y * 0.92f)
                    val flat = active.corner
                    val end = if (active.forward == completes) gone else flat
                    scope.launch {
                        state.finger.animateTo(end, tween(260, easing = FastOutSlowInEasing))
                        if (completes) state.snapTo(state.current + if (active.forward) 1 else -1) else state.turn = null
                    }
                },
                onDragCancel = {
                    val active = state.turn ?: return@detectHorizontalDragGestures
                    scope.launch {
                        state.finger.animateTo(if (active.forward) active.corner else Offset(-width, active.corner.y), tween(200))
                        state.turn = null
                    }
                },
            )
        }
        Box(Modifier.fillMaxSize().then(drag)) {
            if (turn == null) {
                key(state.current) { content(state.current) }
            } else {
                // Beneath: the page that's revealed (forward) or the one being covered (back).
                val under = if (turn.forward) state.current + 1 else state.current
                val turning = if (turn.forward) state.current else state.current - 1
                key(under) { content(under) }
                key(turning) { CurlingPage(state, turn.corner, backColor) { content(turning) } }
            }
        }
    }
}

/** One page folded along the line halfway between its corner and the finger. */
@Composable
private fun CurlingPage(state: PageCurlState, corner: Offset, backColor: Color, content: @Composable () -> Unit) {
    val layer = rememberGraphicsLayer()
    Box(
        Modifier
            .fillMaxSize()
            .drawWithContent {
                layer.record { this@drawWithContent.drawContent() }
                val f = state.finger.value
                val n = corner - f
                val length = hypot(n.x, n.y)
                if (length < 1f) {
                    drawLayer(layer)
                    return@drawWithContent
                }
                val unit = Offset(n.x / length, n.y / length)
                val middle = (corner + f) / 2f
                fun side(p: Offset) = (p.x - middle.x) * unit.x + (p.y - middle.y) * unit.y
                val rect = listOf(Offset(0f, 0f), Offset(size.width, 0f), Offset(size.width, size.height), Offset(0f, size.height))
                val flat = clipPolygon(rect) { -side(it) }
                val lifted = clipPolygon(rect) { side(it) }
                fun reflect(p: Offset): Offset {
                    val d = side(p)
                    return p - unit * (2f * d)
                }
                val flap = lifted.map(::reflect)

                // The page still lying flat.
                if (flat.size >= 3) clipPath(flat.toPath()) { drawLayer(layer) }

                // Its shadow on the page beneath, beyond the fold.
                val shadowWidth = 28.dp(this)
                if (lifted.size >= 3) clipPath(lifted.toPath()) {
                    drawRect(
                        Brush.linearGradient(
                            0f to Color.Black.copy(alpha = 0.28f), 1f to Color.Transparent,
                            start = middle, end = middle + unit * shadowWidth,
                        ),
                    )
                }
                if (flap.size >= 3) {
                    val flapPath = flap.toPath()
                    // A soft shadow the flap casts on the flat page.
                    clipPath(flat.toPath()) {
                        drawPath(flapPath, Color.Black.copy(alpha = 0.10f))
                    }
                    // The back of the page: pale, the words faintly through, darker towards the fold.
                    clipPath(flapPath) {
                        val mirror = Matrix().apply {
                            val a = unit.x
                            val b = unit.y
                            val d = 2f * (middle.x * a + middle.y * b)
                            values[Matrix.ScaleX] = 1 - 2 * a * a
                            values[Matrix.SkewX] = -2 * a * b
                            values[Matrix.SkewY] = -2 * a * b
                            values[Matrix.ScaleY] = 1 - 2 * b * b
                            values[Matrix.TranslateX] = d * a
                            values[Matrix.TranslateY] = d * b
                        }
                        withTransform({ transform(mirror) }) { drawLayer(layer) }
                        drawRect(backColor.copy(alpha = 0.9f))
                        drawRect(
                            Brush.linearGradient(
                                0f to Color.Black.copy(alpha = 0.16f), 1f to Color.Transparent,
                                start = middle, end = middle - unit * (shadowWidth * 1.6f),
                            ),
                        )
                    }
                }
            },
    ) { content() }
}

private fun Int.dp(scope: androidx.compose.ui.graphics.drawscope.DrawScope): Float = this * scope.density

private fun List<Offset>.toPath() = Path().apply {
    moveTo(first().x, first().y)
    for (p in drop(1)) lineTo(p.x, p.y)
    close()
}

/** Keeps the part of a convex polygon where `inside` is ≤ 0 (Sutherland–Hodgman against one line). */
private fun clipPolygon(points: List<Offset>, inside: (Offset) -> Float): List<Offset> {
    val out = mutableListOf<Offset>()
    for (i in points.indices) {
        val a = points[i]
        val b = points[(i + 1) % points.size]
        val fa = inside(a)
        val fb = inside(b)
        if (fa <= 0f) out += a
        if ((fa < 0f && fb > 0f) || (fa > 0f && fb < 0f)) {
            val t = fa / (fa - fb)
            out += a + (b - a) * t
        }
    }
    return out
}
