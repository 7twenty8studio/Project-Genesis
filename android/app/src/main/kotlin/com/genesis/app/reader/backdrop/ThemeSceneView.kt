package com.genesis.app.reader.backdrop

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import com.genesis.app.R
import com.genesis.core.domain.theme.ForestMist
import com.genesis.core.domain.theme.ForestSway
import com.genesis.core.domain.theme.ForestWide
import com.genesis.core.domain.theme.HearthGlow
import com.genesis.core.domain.theme.HearthSparks
import com.genesis.core.domain.theme.OceanSwells
import com.genesis.core.domain.theme.SceneRect
import com.genesis.core.domain.theme.SceneShade
import com.genesis.core.domain.theme.SceneSize
import com.genesis.core.domain.theme.ThemeScene
import kotlin.math.roundToInt

/**
 * The scene behind the words in Forest, Ocean and Hearth, as ThemeSceneView
 * on iOS: the illustration (Forest's boughs swaying in bands over still
 * trunks), its moving layer (mist, swells, or the hearth's glow), the soft
 * shade where the text sits, and Hearth's embers. Under the text, no taps,
 * hidden from TalkBack. Moves at 30 fps only with Gentle Motion on, Remove
 * Animations off, outside Battery Saver and while the app is in front;
 * otherwise the composed still (ThemeScene.STILL_TIME).
 */
@Composable
fun ThemeSceneView(scene: ThemeScene, animates: Boolean, modifier: Modifier = Modifier, backdrop: SceneBackdrop? = null) {
    val running = animates && !rememberReduceMotion() && !rememberPowerSave() && rememberResumed()
    val clockState = rememberMotionTime(running) { 1.0 / 30 }
    val clock by clockState
    BoxWithConstraints(
        modifier.fillMaxSize().clipToBounds().background(Color(0xFF000000 or scene.fillHex.toLong())).clearAndSetSemantics { }
            .then(if (backdrop != null) Modifier.onGloballyPositioned { backdrop.origin = it.positionInWindow() } else Modifier),
    ) {
        val size = SceneSize(maxWidth.value.toDouble(), maxHeight.value.toDouble())
        // Only the pictures this area uses (the Forest's tall or wide set), since each is large.
        val art = rememberSceneArt(scene, ForestWide.uses(size))
        if (backdrop != null) {
            SideEffect {
                backdrop.scene = scene
                backdrop.art = art
                backdrop.size = size
                backdrop.clock = clockState
                backdrop.running = running
            }
            DisposableEffect(backdrop) { onDispose { backdrop.scene = null } }
        }
        Canvas(Modifier.fillMaxSize()) {
            drawScene(scene, art, size, if (running) ThemeScene.STILL_TIME + clock else ThemeScene.STILL_TIME)
        }
    }
}

/** The scene at one moment, laid out for `size` (in dp), into any DrawScope (the widget's painted backgrounds too). */
internal fun DrawScope.drawScene(scene: ThemeScene, art: SceneArt, size: SceneSize, time: Double = ThemeScene.STILL_TIME) {
    drawRect(Color(0xFF000000 or scene.fillHex.toLong()))
    when (scene) {
        ThemeScene.FOREST -> {
            drawForest(art, size, time)
            drawMist(size, time)
        }
        ThemeScene.OCEAN -> {
            drawOcean(art, size)
            drawSwell(art.swell, false, size, time)
            drawSwell(art.nearSwell, true, size, time)
        }
        ThemeScene.HEARTH -> drawHearthGlow(time)
    }
    drawShade(scene.shade)
    if (scene == ThemeScene.HEARTH) drawEmbers(time)
}

/** The scene's pictures outside Compose (for drawing into a bitmap). */
internal fun sceneArt(resources: android.content.res.Resources, scene: ThemeScene, wide: Boolean): SceneArt {
    fun load(id: Int) = android.graphics.BitmapFactory.decodeResource(resources, id).asImageBitmap()
    return when {
        scene == ThemeScene.FOREST && wide -> SceneArt(
            wide = load(R.drawable.theme_scene_forestwide), wideCanopy = load(R.drawable.theme_scene_forestwide_canopy),
            wideTrunks = load(R.drawable.theme_scene_forestwide_trunks), wideFront = load(R.drawable.theme_scene_forestwide_front),
        )
        scene == ThemeScene.FOREST -> SceneArt(
            forest = load(R.drawable.theme_scene_forest), canopy = load(R.drawable.theme_scene_forest_canopy),
            trunks = load(R.drawable.theme_scene_forest_trunks), front = load(R.drawable.theme_scene_forest_front),
        )
        scene == ThemeScene.OCEAN -> SceneArt(
            ocean = load(R.drawable.theme_scene_ocean), swell = load(R.drawable.theme_scene_ocean_swell), nearSwell = load(R.drawable.theme_scene_ocean_near_swell),
        )
        else -> SceneArt()
    }
}

/** The scene's pictures, decoded once while it's shown. */
internal class SceneArt(
    val forest: ImageBitmap? = null, val canopy: ImageBitmap? = null, val trunks: ImageBitmap? = null, val front: ImageBitmap? = null,
    val wide: ImageBitmap? = null, val wideCanopy: ImageBitmap? = null, val wideTrunks: ImageBitmap? = null, val wideFront: ImageBitmap? = null,
    val ocean: ImageBitmap? = null, val swell: ImageBitmap? = null, val nearSwell: ImageBitmap? = null,
)

@Composable
private fun rememberSceneArt(scene: ThemeScene, wide: Boolean): SceneArt = when {
    scene == ThemeScene.FOREST && wide -> SceneArt(
        wide = ImageBitmap.imageResource(R.drawable.theme_scene_forestwide),
        wideCanopy = ImageBitmap.imageResource(R.drawable.theme_scene_forestwide_canopy),
        wideTrunks = ImageBitmap.imageResource(R.drawable.theme_scene_forestwide_trunks),
        wideFront = ImageBitmap.imageResource(R.drawable.theme_scene_forestwide_front),
    )
    scene == ThemeScene.FOREST -> SceneArt(
        forest = ImageBitmap.imageResource(R.drawable.theme_scene_forest),
        canopy = ImageBitmap.imageResource(R.drawable.theme_scene_forest_canopy),
        trunks = ImageBitmap.imageResource(R.drawable.theme_scene_forest_trunks),
        front = ImageBitmap.imageResource(R.drawable.theme_scene_forest_front),
    )
    scene == ThemeScene.OCEAN -> SceneArt(
        ocean = ImageBitmap.imageResource(R.drawable.theme_scene_ocean),
        swell = ImageBitmap.imageResource(R.drawable.theme_scene_ocean_swell),
        nearSwell = ImageBitmap.imageResource(R.drawable.theme_scene_ocean_near_swell),
    )
    else -> remember { SceneArt() }
}

private fun hex(value: Int) = Color(0xFF000000 or value.toLong())

private fun DrawScope.px(rect: SceneRect) = Rect((rect.x * density).toFloat(), (rect.y * density).toFloat(), (rect.maxX * density).toFloat(), (rect.maxY * density).toFloat())

/** One picture drawn into a frame (in dp), mirrored about its middle where it repeats. */
private fun DrawScope.drawArt(image: ImageBitmap, frame: SceneRect, mirrored: Boolean = false, dx: Double = 0.0) {
    val r = px(frame.offsetBy(dx))
    val draw: DrawScope.() -> Unit = {
        drawImage(
            image,
            dstOffset = IntOffset(r.left.roundToInt(), r.top.roundToInt()),
            dstSize = IntSize(r.width.roundToInt().coerceAtLeast(1), r.height.roundToInt().coerceAtLeast(1)),
            filterQuality = FilterQuality.High,
        )
    }
    val pivot = (frame.midX * density).toFloat()
    if (mirrored) withTransform({ scale(-1f, 1f, Offset(pivot, 0f)) }, draw) else draw()
}

/** Draws into an offscreen layer, so blend modes there touch only what's drawn in it. */
private inline fun DrawScope.inLayer(block: DrawScope.() -> Unit) {
    drawIntoCanvas { it.saveLayer(Rect(0f, 0f, size.width, size.height), Paint()) }
    block()
    drawIntoCanvas { it.restore() }
}

// MARK: Forest

private fun DrawScope.drawForest(art: SceneArt, size: SceneSize, time: Double) {
    if (ForestWide.uses(size)) {
        val (left, right) = ForestWide.copies(size)
        val (from, to) = ForestWide.blend(size)
        val layers = listOfNotNull(art.wide, art.wideCanopy, art.wideTrunks, art.wideFront)
        if (layers.size < 4) return
        drawForestCopy(layers, ForestWide.CANOPY, left, false, time)
        // The right copy fades in across the clearing in the middle.
        inLayer {
            drawForestCopy(layers, ForestWide.CANOPY, right, false, time)
            drawRect(
                Brush.horizontalGradient(
                    0f to Color.Transparent,
                    (from / size.width).toFloat() to Color.Transparent,
                    (to / size.width).toFloat().coerceAtLeast((from / size.width).toFloat() + 0.0001f) to Color.Black,
                    1f to Color.Black,
                ),
                blendMode = BlendMode.DstIn,
            )
        }
    } else {
        val layers = listOfNotNull(art.forest, art.canopy, art.trunks, art.front)
        if (layers.size < 4) return
        for (tile in ThemeScene.FOREST.tiles(size)) drawForestCopy(layers, ForestSway.CANOPY, tile.frame, tile.mirrored, time)
    }
}

/** One copy of a forest picture with its boughs moved: canopy in moving bands, trunks still, boughs in front moving again. */
private fun DrawScope.drawForestCopy(layers: List<ImageBitmap>, share: Double, frame: SceneRect, mirrored: Boolean, time: Double) {
    val (image, canopy, trunks, front) = layers
    drawArt(image, frame, mirrored)
    val canopyFrame = SceneRect(frame.x, frame.y, frame.width, frame.height * share)
    if (canopyFrame.maxY <= 0) return
    val band = canopyFrame.height / ForestSway.BANDS
    fun bands(layer: ImageBitmap) {
        for (index in 0 until ForestSway.BANDS) {
            val top = canopyFrame.y + index * band
            if (top + band <= 0 || top * density >= this.size.height) continue
            val bandShare = (index + 0.5) / ForestSway.BANDS * ForestSway.CANOPY
            val shift = ForestSway.offset(bandShare, time)
            clipRect(((frame.x - 20) * density).toFloat(), (top * density).toFloat(), ((frame.maxX + 20) * density).toFloat(), ((top + band + 0.5) * density).toFloat()) {
                // Mirrored copies draw the shift turned round, so it moves the same way on screen.
                drawArt(layer, canopyFrame, mirrored, if (mirrored) -shift else shift)
            }
        }
    }
    bands(canopy)
    drawArt(trunks, canopyFrame, mirrored)
    bands(front)
}

private val mistColor = Color(0.87f, 0.92f, 0.86f)

private fun DrawScope.drawMist(size: SceneSize, time: Double) {
    for (layer in ForestMist.layers) for (puff in layer.puffs) {
        val state = ForestMist.state(puff, layer, time, size)
        val cx = (state.centerX * density).toFloat()
        val cy = (state.centerY * density).toFloat()
        val rx = (state.radiusX * density).toFloat()
        val ry = (state.radiusY * density).toFloat()
        if (rx <= 0f || ry <= 0f) continue
        val o = state.opacity.toFloat()
        // A circle stretched to the puff, so it's soft all round.
        withTransform({ scale(1f, ry / rx, Offset(cx, cy)) }) {
            drawCircle(
                Brush.radialGradient(
                    0f to mistColor.copy(alpha = o), 0.5f to mistColor.copy(alpha = o * 0.45f), 1f to mistColor.copy(alpha = 0f),
                    center = Offset(cx, cy), radius = rx,
                ),
                rx, Offset(cx, cy),
            )
        }
    }
}

// MARK: Ocean

/** The raised sky first, then the lowered picture faded in over it, so its water sits low. */
private fun DrawScope.drawOcean(art: SceneArt, size: SceneSize) {
    val image = art.ocean ?: return
    val sky = ThemeScene.oceanSky(size)
    val picture = ThemeScene.OCEAN.artFrame(size)
    for (tile in ThemeScene.tiles(sky, size.width)) drawArt(image, tile.frame, tile.mirrored)
    val fadeTop = (picture.y + picture.height * ThemeScene.SKY_FADE_START) * density
    val fadeBottom = (picture.y + picture.height * ThemeScene.SKY_FADE_END) * density
    inLayer {
        for (tile in ThemeScene.tiles(picture, size.width)) drawArt(image, tile.frame, tile.mirrored)
        // Rub out the lowered picture above the fade, and fade it in.
        drawRect(
            Brush.verticalGradient(
                0f to Color.Black,
                (fadeTop / fadeBottom).toFloat().coerceIn(0f, 0.999f) to Color.Black,
                1f to Color.Transparent,
                startY = 0f, endY = fadeBottom.toFloat(),
            ),
            size = androidx.compose.ui.geometry.Size(this.size.width, fadeBottom.toFloat()),
            blendMode = BlendMode.DstOut,
        )
    }
}

/** One swell layer, repeated (mirrored) across when the area is wider than one copy. */
private fun DrawScope.drawSwell(image: ImageBitmap?, near: Boolean, size: SceneSize, time: Double) {
    image ?: return
    val frame = OceanSwells.frame(near, size)
    val period = OceanSwells.period(size)
    val (dx, dy) = OceanSwells.offset(near, time)
    val pad = (frame.width - period) / 2
    val copies = ThemeScene.tiles(SceneRect(frame.x + pad, frame.y, period, frame.height), size.width)
    for (copy in copies) {
        drawArt(image, SceneRect(copy.frame.x - pad + dx, frame.y - dy, frame.width, frame.height), copy.mirrored)
    }
}

// MARK: Hearth

private val amber = Color(0.78f, 0.45f, 0.23f)
private val flame = Color(1f, 0.66f, 0.34f)

/** The fire is just below the screen: its glow rises from the whole foot, breathing, brighter patches wandering along it. */
private fun DrawScope.drawHearthGlow(time: Double) {
    val strength = HearthGlow.strength(time).toFloat()
    val top = size.height * (1 - HearthGlow.HEIGHT.toFloat())
    drawRect(
        Brush.verticalGradient(
            0f to amber.copy(alpha = 0f), 0.55f to amber.copy(alpha = 0.17f * strength), 1f to amber.copy(alpha = 0.5f * strength),
            startY = top, endY = size.height,
        ),
        topLeft = Offset(0f, top),
        size = androidx.compose.ui.geometry.Size(size.width, size.height - top),
    )
    for ((x, patch) in HearthGlow.patches(time)) {
        val center = Offset(size.width * x.toFloat(), size.height * 1.03f)
        val rx = size.width * 0.42f
        val ry = size.height * 0.16f
        withTransform({ scale(1f, ry / rx, center) }) {
            drawCircle(
                Brush.radialGradient(listOf(flame.copy(alpha = (0.32 * strength * patch).toFloat().coerceIn(0f, 1f)), flame.copy(alpha = 0f)), center, rx),
                rx, center, blendMode = BlendMode.Plus,
            )
        }
    }
}

private val emberGlow = Color(1f, 0.62f, 0.25f)
private val emberCore = Color(1f, 0.8f, 0.5f)

/** Sparks rising from all along the foot as high as the glow reaches, fading as they climb. */
private fun DrawScope.drawEmbers(time: Double) {
    val d = density
    val width = size.width / d
    val height = size.height / d
    val ceiling = height * (1 - HearthGlow.HEIGHT)
    HearthSparks.sparks.forEachIndexed { index, spark ->
        val state = HearthSparks.state(spark, index, time, width / 2.0, height + 4.0, width * HearthGlow.EMBER_WIDTH, ceiling) ?: return@forEachIndexed
        if (state.opacity <= 0.01) return@forEachIndexed
        val center = Offset((state.x * d).toFloat(), (state.y * d).toFloat())
        val radius = (state.radius * d).toFloat()
        val o = state.opacity.toFloat().coerceIn(0f, 1f)
        val glow = radius * 3.5f
        drawCircle(Brush.radialGradient(listOf(emberGlow.copy(alpha = o * 0.35f), Color.Transparent), center, glow), glow, center, blendMode = BlendMode.Plus)
        drawCircle(emberCore.copy(alpha = o), radius, center, blendMode = BlendMode.Plus)
    }
}

// MARK: Shade

/** The soft shade behind the words: an ellipse, strongest where the text is, its edge opacity beyond it. */
private fun DrawScope.drawShade(shade: SceneShade) {
    val color = hex(shade.hex)
    val center = Offset(size.width * shade.centerX.toFloat(), size.height * shade.centerY.toFloat())
    val rx = size.width * shade.radiusX.toFloat()
    val ry = size.height * shade.radiusY.toFloat()
    val stops = shade.stops.map { (at, opacity) -> at.toFloat() to color.copy(alpha = opacity.toFloat()) }.toTypedArray()
    val edge = shade.stops.last().second.toFloat()
    inLayer {
        if (edge > 0f) drawRect(color.copy(alpha = edge))
        withTransform({ scale(1f, ry / rx, center) }) {
            drawCircle(Brush.radialGradient(*stops, center = center, radius = rx), rx, center, blendMode = if (edge > 0f) BlendMode.Src else BlendMode.SrcOver)
        }
    }
}

/** Room (dp) kept free under the text on a page, so the last lines end above the swells and the glow. */
fun sceneFootRoom(scene: ThemeScene, widthDp: Float, heightDp: Float, footDp: Float): Float =
    scene.footRoom(SceneSize(widthDp.toDouble(), heightDp.toDouble()), footDp.toDouble()).toFloat()

