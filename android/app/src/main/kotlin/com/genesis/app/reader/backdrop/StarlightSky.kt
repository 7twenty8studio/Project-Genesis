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
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import com.genesis.core.domain.theme.NightSky
import com.genesis.core.domain.theme.SkyPoint
import com.genesis.core.domain.theme.SkyRect
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/** Where the words are, as insets from the backdrop's edges (dp). */
data class TextInsets(val left: Dp, val top: Dp, val right: Dp, val bottom: Dp)

/**
 * Starlight's clear night sky, as StarlightSkyView on iOS: twenty stars in
 * three colours that twinkle with a quick brightening and a slow fade, a
 * glint on the brightest, a faint Milky Way along the edges, and a shooting
 * star every 3–8 seconds in the band above the running head. It lies over
 * the page but keeps out of the words (margins and band only; the haze thins
 * before the text), takes no taps and is hidden from TalkBack. 20 frames a
 * second, 60 while a star shoots; held still in Battery Saver; with Remove
 * Animations the stars only fade gently and none shoot.
 */
@Composable
fun StarlightSky(textInsets: TextInsets?, skyBand: Dp, modifier: Modifier = Modifier) {
    val reduce = rememberReduceMotion()
    val running = !rememberPowerSave() && rememberResumed()
    val shooting = skyBand.value > 0 && !reduce
    val time by rememberMotionTime(running) { t ->
        when {
            reduce -> 1.0 / 10
            shooting && (NightSky.activeStreaks(t).isNotEmpty() || NightSky.activeStreaks(t + 1.0 / 20).isNotEmpty()) -> 1.0 / 60
            else -> 1.0 / 20
        }
    }
    Box(modifier.fillMaxSize().clearAndSetSemantics { }) {
        // The haze never moves: its own layer, drawn once per size.
        Canvas(Modifier.fillMaxSize()) { drawMilkyWay(text(textInsets)) }
        Canvas(Modifier.fillMaxSize()) {
            val t = time
            drawStars(t, text(textInsets), skyBand.value.toDouble(), reduce)
            if (shooting) drawShootingStars(t, skyBand.value.toDouble())
        }
    }
}

private val tints = listOf(Color(0xFFCDDAFF), Color(0xFFF4F1E8), Color(0xFFFFE4BA))
private val streakColor = Color(0xFFFAF2D2)
private val headColor = Color(0xFFFFF8E0)
private val hazeColors = listOf(Color(0xFF96AAD7), Color(0xFFBEB4D2))
private val dustColor = Color(0xFFDCE2F0)

/** The text's rectangle in dp. */
private fun DrawScope.text(insets: TextInsets?): SkyRect? {
    insets ?: return null
    val w = size.width / density
    val h = size.height / density
    return SkyRect(insets.left.value.toDouble(), insets.top.value.toDouble(), (w - insets.right.value).toDouble(), (h - insets.bottom.value).toDouble())
}

private fun DrawScope.px(point: SkyPoint) = Offset((point.x * density).toFloat(), (point.y * density).toFloat())

private fun DrawScope.glow(center: Offset, radius: Float, color: Color, alpha: Float) {
    if (radius <= 0f || alpha <= 0f) return
    drawCircle(Brush.radialGradient(listOf(color.copy(alpha = alpha.coerceIn(0f, 1f)), color.copy(alpha = 0f)), center, radius), radius, center)
}

private fun DrawScope.drawStars(time: Double, text: SkyRect?, band: Double, reduce: Boolean) {
    val w = (size.width / density).toDouble()
    val h = (size.height / density).toDouble()
    val fadeIn = min(1.0, time / 1.5)
    for (star in NightSky.stars) {
        val point = NightSky.position(star, w, h, text, band) ?: continue
        val center = px(point)
        val brightness = NightSky.brightness(time, star.period, star.offset, reduce)
        val flicker = if (!reduce && brightness > 0.6) 0.08 * sin(time * 37 + star.offset * 11) else 0.0
        val core = if (reduce) star.core else star.core * (1 + 0.4 * max(0.0, brightness - 0.3) / 0.7)
        val tint = tints[star.tint]
        val glowRadius = (core * (if (star.isMajor) 7 else 5) * density).toFloat()
        glow(center, glowRadius, tint, ((0.35 + flicker) * brightness * fadeIn).toFloat())
        drawCircle(tint.copy(alpha = (min(1.0, brightness + 0.1 + flicker) * fadeIn).toFloat().coerceIn(0f, 1f)), (core * density).toFloat(), center)
        if (!reduce && star.isMajor && brightness > 0.7) {
            val k = (brightness - 0.7) / 0.3
            val length = (core * 6 * k * density).toFloat()
            val color = tint.copy(alpha = (0.75 * k * fadeIn).toFloat().coerceIn(0f, 1f))
            val stroke = 0.7f * density
            drawLine(color, center - Offset(length, 0f), center + Offset(length, 0f), stroke, StrokeCap.Round)
            drawLine(color, center - Offset(0f, length), center + Offset(0f, length), stroke, StrokeCap.Round)
        }
    }
}

private fun DrawScope.drawShootingStars(time: Double, band: Double) {
    val w = (size.width / density).toDouble()
    for (streak in NightSky.activeStreaks(time)) {
        val (from, travel) = streak.path(w, band)
        val elapsed = time - streak.start
        val progress = elapsed / streak.duration
        val eased = NightSky.easeOut(progress)
        val head = SkyPoint(from.x + travel.x * eased, from.y + travel.y * eased)
        val alpha = minOf(1.0, elapsed / 0.1, (1 - progress) * streak.duration / 0.28).toFloat().coerceIn(0f, 1f)
        val distance = hypot(travel.x, travel.y)
        if (distance <= 0) continue
        val tail = min(streak.tail, distance * eased)
        val end = SkyPoint(head.x - travel.x / distance * tail, head.y - travel.y / distance * tail)
        val h = px(head)
        val e = px(end)
        drawLine(
            Brush.linearGradient(listOf(streakColor.copy(alpha = 0.95f * alpha), streakColor.copy(alpha = 0f)), h, e),
            h, e, 1.5f * density, StrokeCap.Round,
        )
        glow(h, 5 * density, headColor, 0.6f * alpha)
        drawCircle(headColor.copy(alpha = alpha), 1.4f * density, h)
    }
}

/** A faint band of haze and star dust from the top-left corner down the right-hand side, thinning before the text. */
private fun DrawScope.drawMilkyWay(text: SkyRect?) {
    val w = (size.width / density).toDouble()
    val h = (size.height / density).toDouble()
    for (i in 0 until 90) {
        val point = NightSky.hazeSpot(i, 40, 30.0, w, h)
        val fade = text?.let { NightSky.hazeFade(point, it) } ?: 1.0
        if (fade <= 0) continue
        val radius = ((12 + 18 * NightSky.unit(i, 43)) * density).toFloat()
        glow(px(point), radius, hazeColors[if (NightSky.unit(i, 44) < 0.5) 0 else 1], (0.06 * fade).toFloat())
    }
    for (i in 0 until 200) {
        val point = NightSky.hazeSpot(i, 50, 24.0, w, h)
        val fade = text?.let { NightSky.hazeFade(point, it) } ?: 1.0
        if (fade <= 0) continue
        val radius = ((0.35 + 0.35 * NightSky.unit(i, 53)) * density).toFloat()
        drawCircle(dustColor.copy(alpha = ((0.15 + 0.25 * NightSky.unit(i, 54)) * fade).toFloat()), radius, px(point))
    }
}
