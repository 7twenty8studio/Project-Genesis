package com.genesis.app.reader

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.VectorConverter
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.ui.graphics.drawscope.DrawScope
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

/**
 * Which page shows, and the page being turned, for [PageCurl]. A turn is
 * the point of the page that was taken hold of (`grab`, on the page's
 * outer edge) and where it is now (`finger`); the page rolls over a
 * cylinder between the two, as UIPageViewController's page curl does.
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

    /** `grab`: the point of the turning page held (on its outer edge, or a corner). */
    internal data class Turn(val forward: Boolean, val grab: Offset)

    fun snapTo(page: Int) {
        turn = null
        current = page.coerceIn(0, (count() - 1).coerceAtLeast(0))
    }

    /** Turns one page forward or back, as a tap on the edge does: from the bottom corner, as on iOS. */
    suspend fun turn(forward: Boolean) {
        if (turn != null || size.width <= 0f) return
        val target = current + if (forward) 1 else -1
        if (target !in 0 until count()) return
        val grab = Offset(size.width, size.height)
        val gone = Offset(-size.width, size.height * 0.86f)
        turn = Turn(forward, grab)
        finger.snapTo(if (forward) grab - Offset(1f, 1f) else gone)
        finger.animateTo(if (forward) gone else grab, tween(DURATION, easing = FastOutSlowInEasing))
        current = target
        turn = null
    }

    companion object { const val DURATION = 460 }
}

/**
 * Page Curl, as iOS's: the page rolls up from wherever it's taken (a corner
 * or anywhere along its outer edge) and follows the finger's path, its back
 * a translucent sheet with the words showing through backwards, over the
 * next page, which is already there underneath. Start on the right half to
 * turn forward, on the left half to turn back. Taps are left to the pages
 * (the reader turns on edge taps with [PageCurlState.turn]).
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
            var start = Offset.Zero
            var moved = Offset.Zero
            detectDragGestures(
                onDragStart = { at ->
                    start = at
                    moved = Offset.Zero
                    tracker.resetTracking()
                    if (state.turn != null) return@detectDragGestures
                    // The side the finger starts on decides the way, as on iOS, so a little jitter never turns back.
                    val forward = at.x > width / 2
                    val target = state.current + if (forward) 1 else -1
                    if (target !in 0 until count) return@detectDragGestures
                    // Near a corner, that corner is held; otherwise the edge at the finger's height.
                    val corner = height * CORNER_SHARE
                    val y = when {
                        at.y < corner -> 0f
                        at.y > height - corner -> height
                        else -> at.y
                    }
                    val grab = Offset(width, y)
                    // The finger first, so the first frame of the turn never shows where the last one ended.
                    scope.launch {
                        state.finger.snapTo(if (forward) grab - Offset(0.5f, 0f) else Offset(-width, grab.y))
                        state.turn = PageCurlState.Turn(forward, grab)
                    }
                },
                onDrag = { change, amount ->
                    val active = state.turn ?: return@detectDragGestures
                    change.consume()
                    moved += amount
                    tracker.addPosition(change.uptimeMillis, change.position)
                    // Forward: the held point moves with the finger. Back: the page comes in from
                    // the left, reaching flat as the finger reaches the right edge.
                    val target = if (active.forward) {
                        active.grab + moved
                    } else {
                        val reach = (width - start.x).coerceAtLeast(width * 0.25f)
                        Offset(-width + 2f * width * (moved.x / reach), active.grab.y + moved.y)
                    }
                    scope.launch { state.finger.snapTo(Offset(target.x.coerceIn(-width, width), target.y.coerceIn(-height * 0.25f, height * 1.25f))) }
                },
                onDragEnd = {
                    val active = state.turn ?: return@detectDragGestures
                    val velocity = tracker.calculateVelocity()
                    val position = state.finger.value
                    val completes = if (active.forward) position.x < width * 0.5f || velocity.x < -800f else position.x > -width * 0.2f || velocity.x > 800f
                    val gone = Offset(-width, active.grab.y + (position.y - active.grab.y) * 0.5f)
                    val end = if (active.forward == completes) gone else active.grab
                    // The rest of the way at the speed the finger left it, never slower than a quick turn.
                    val remaining = (end - position).getDistance() / width
                    val millis = (remaining * 300f).toInt().coerceIn(140, 340)
                    scope.launch {
                        state.finger.animateTo(end, tween(millis, easing = FastOutSlowInEasing), initialVelocity = Offset(velocity.x, velocity.y))
                        if (completes) state.snapTo(state.current + if (active.forward) 1 else -1) else state.turn = null
                    }
                },
                onDragCancel = {
                    val active = state.turn ?: return@detectDragGestures
                    scope.launch {
                        state.finger.animateTo(if (active.forward) active.grab else Offset(-width, active.grab.y), tween(200))
                        state.turn = null
                    }
                },
            )
        }
        Box(Modifier.fillMaxSize().then(drag)) {
            if (turn == null) {
                key(state.current) { content(state.current) }
            } else {
                // Beneath: the next page, already there (forward), or the page being covered (back).
                val under = if (turn.forward) state.current + 1 else state.current
                val turning = if (turn.forward) state.current else state.current - 1
                key(under) { content(under) }
                key(turning) { CurlingPage(state, turn.grab, backColor) { content(turning) } }
            }
        }
    }
}

private const val CORNER_SHARE = 0.14f

/**
 * One page rolled over a cylinder. The page is drawn in strips parallel to
 * the roll's axis: flat before it, wrapping around it (the front, then the
 * back), then lying back over the page, mirrored and translucent.
 */
@Composable
private fun CurlingPage(state: PageCurlState, grab: Offset, backColor: Color, content: @Composable () -> Unit) {
    val layer = rememberGraphicsLayer()
    Box(
        Modifier
            .fillMaxSize()
            .drawWithContent {
                layer.record { this@drawWithContent.drawContent() }
                val curl = CurlGeometry.of(grab, state.finger.value, size.width, maxRadius = size.width * 0.11f)
                if (curl == null) {
                    drawLayer(layer)
                    return@drawWithContent
                }
                val rect = listOf(Offset(0f, 0f), Offset(size.width, 0f), Offset(size.width, size.height), Offset(0f, size.height))
                val u = curl.direction
                val axis = curl.axis
                fun side(p: Offset) = (p.x - axis.x) * u.x + (p.y - axis.y) * u.y
                fun band(from: Float, to: Float) = clipPolygon(clipPolygon(rect) { side(it) - to }) { from - side(it) }
                val r = curl.radius
                val shadow = 26f * density

                // The page still lying flat.
                clipPolygon(rect) { side(it) }.takeIf { it.size >= 3 }?.let { clipPath(it.toPath()) { drawLayer(layer) } }

                // The roll's shadow on the page underneath.
                clipPolygon(rect) { -side(it) }.takeIf { it.size >= 3 }?.let { lifted ->
                    clipPath(lifted.toPath()) {
                        drawRect(
                            Brush.linearGradient(
                                0f to Color.Black.copy(alpha = 0.30f), 1f to Color.Transparent,
                                start = axis + u * r, end = axis + u * (r + shadow),
                            ),
                        )
                    }
                }

                fun strip(from: Float, to: Float, mapFrom: Float, mapTo: Float, draw: DrawScope.() -> Unit) {
                    val polygon = band(from, to + 0.75f)
                    if (polygon.size < 3) return
                    val b = (mapTo - mapFrom) / (to - from)
                    val k = b - 1f
                    // d' = mapFrom + b(d - from), as a transform: p' = p + u·δ(p), δ = c + k·(p·u).
                    val c = mapFrom - b * from - k * (u.x * axis.x + u.y * axis.y)
                    val matrix = Matrix().apply {
                        values[Matrix.ScaleX] = 1 + k * u.x * u.x
                        values[Matrix.SkewY] = k * u.x * u.y
                        values[Matrix.SkewX] = k * u.x * u.y
                        values[Matrix.ScaleY] = 1 + k * u.y * u.y
                        values[Matrix.TranslateX] = u.x * c
                        values[Matrix.TranslateY] = u.y * c
                    }
                    withTransform({ transform(matrix) }) { clipPath(polygon.toPath()) { draw() } }
                }

                val half = Math.PI.toFloat() * r
                if (r >= 0.5f) {
                    // The front, wrapping up and away.
                    for (i in 0 until STRIPS) {
                        val a0 = i.toFloat() / STRIPS * (Math.PI.toFloat() / 2f)
                        val a1 = (i + 1).toFloat() / STRIPS * (Math.PI.toFloat() / 2f)
                        strip(a0 * r, a1 * r, r * sin(a0), r * sin(a1)) {
                            drawLayer(layer)
                            drawRect(Color.Black.copy(alpha = 0.20f * (1f - cos((a0 + a1) / 2f))))
                        }
                    }
                }
                // The back, lying over the page: mirrored, the words faint through it.
                strip(half, half + size.width * 3f, 0f, -size.width * 3f) {
                    drawLayer(layer)
                    drawRect(backColor.copy(alpha = BACK_ALPHA))
                }
                // A soft shade on the back near the roll.
                strip(half, half + shadow * 1.4f, 0f, -shadow * 1.4f) {
                    drawRect(
                        Brush.linearGradient(
                            0f to Color.Black.copy(alpha = 0.12f), 1f to Color.Transparent,
                            start = axis + u * half, end = axis + u * (half + shadow * 1.4f),
                        ),
                    )
                }
                if (r >= 0.5f) {
                    // The back of the roll, over its front.
                    for (i in 0 until STRIPS) {
                        val a0 = Math.PI.toFloat() / 2f + i.toFloat() / STRIPS * (Math.PI.toFloat() / 2f)
                        val a1 = Math.PI.toFloat() / 2f + (i + 1).toFloat() / STRIPS * (Math.PI.toFloat() / 2f)
                        strip(a0 * r, a1 * r, r * sin(a0), r * sin(a1)) {
                            drawLayer(layer)
                            drawRect(backColor.copy(alpha = BACK_ALPHA))
                            drawRect(Color.Black.copy(alpha = 0.10f * sin((a0 + a1) / 2f) + 0.04f))
                        }
                    }
                }
            },
    ) { content() }
}

/** How opaque the page's back is: enough to read as paper, with the words showing through backwards. */
private const val BACK_ALPHA = 0.80f
private const val STRIPS = 12

/**
 * Where the roll is: the cylinder's axis (a point on it), the direction
 * from the axis into the lifted part, and its radius. The held point lies
 * on the part folded back flat, and lands under the finger. The finger is
 * kept within reach of the spine, so the page never tears from it.
 */
internal data class CurlGeometry(val axis: Offset, val direction: Offset, val radius: Float) {
    companion object {
        fun of(grab: Offset, finger: Offset, width: Float, maxRadius: Float): CurlGeometry? {
            val spine = Offset(0f, grab.y)
            val reach = (grab - spine).getDistance()
            var f = finger
            val fromSpine = f - spine
            val distance = fromSpine.getDistance()
            if (distance > reach && distance > 0f) f = spine + fromSpine * (reach / distance)
            val n = grab - f
            val length = hypot(n.x, n.y)
            if (length < 0.5f) return null
            val u = Offset(n.x / length, n.y / length)
            // The roll grows with the turn: a fold at first, then a curl.
            val radius = (length / Math.PI.toFloat()).coerceAtMost(maxRadius).coerceAtMost(width * 0.5f)
            // Axis midway, less a quarter turn: the held point (on the flat back) lands on the finger.
            val middle = (grab + f) / 2f
            val axis = middle - u * (Math.PI.toFloat() * radius / 2f)
            return CurlGeometry(axis, u, radius)
        }
    }
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
