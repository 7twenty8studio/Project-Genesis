package com.genesis.app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RadialGradient
import android.graphics.Shader
import android.util.Log
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.core.content.edit
import com.genesis.app.reader.backdrop.drawScene
import com.genesis.app.reader.backdrop.drawSeasonStill
import com.genesis.app.reader.backdrop.sceneArt
import com.genesis.core.domain.share.VerseImageStyle
import com.genesis.core.domain.theme.ForestWide
import com.genesis.core.domain.theme.ReaderTheme
import com.genesis.core.domain.theme.SceneSize
import com.genesis.core.domain.theme.ThemeScene
import com.genesis.core.domain.widgets.WidgetArtShape
import com.genesis.core.domain.widgets.WidgetArtStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The verse widget's look chosen in Versely (Settings › Widget Styles), as
 * WidgetStylePreference on iOS. Widgets whose Background is "Chosen in
 * Versely" (the default) follow it; one widget can pick its own when it's
 * placed or reconfigured.
 */
object WidgetStylePreference {
    private val _style = MutableStateFlow(WidgetArtStyle.CLASSIC)
    val style: StateFlow<WidgetArtStyle> = _style.asStateFlow()

    private fun defaults(context: Context) = context.applicationContext.getSharedPreferences("widgets", Context.MODE_PRIVATE)

    fun current(context: Context): WidgetArtStyle =
        (WidgetArtStyle.of(defaults(context).getString(WidgetArtStyle.PREFERENCE_KEY, null)) ?: WidgetArtStyle.CLASSIC).also { _style.value = it }

    suspend fun set(context: Context, style: WidgetArtStyle) {
        defaults(context).edit { putString(WidgetArtStyle.PREFERENCE_KEY, style.rawValue) }
        _style.value = style
        VerselyWidgets.refresh(context)
    }
}

/**
 * The verse widget's painted backgrounds (paper, the seasons, Night and the
 * scenes), drawn by the app into its files, as WidgetArtWriter on iOS: once,
 * a moment after launch, one picture at a time, and again when `VERSION`
 * changes or a file is missing. Pictures only: the widget draws the verse
 * over them, verbatim.
 */
object WidgetArt {
    /** Bump to draw the pictures again after changing them. */
    private const val VERSION = 1
    private const val VERSION_KEY = "widgetArt.version"
    private const val TAG = "WidgetArt"
    private val drawing = Mutex()

    internal fun folder(context: Context) = File(context.applicationContext.filesDir, "WidgetArt")

    /** A painted picture, or the person's photo framed for the shape. */
    fun file(context: Context, style: WidgetArtStyle, shape: WidgetArtShape): File =
        File(folder(context), "${style.rawValue}-${shape.rawValue}.jpg")

    /** The picture for a widget, if it's been drawn. */
    fun load(context: Context, style: WidgetArtStyle, shape: WidgetArtShape): Bitmap? =
        file(context, style, shape).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }

    /** Draws whatever is missing (or out of date), then redraws the widgets. Cheap when there's nothing to do. */
    suspend fun drawIfNeeded(context: Context, wait: Boolean = true) = drawing.withLock {
        val app = context.applicationContext
        val defaults = app.getSharedPreferences("widgets", Context.MODE_PRIVATE)
        val current = defaults.getInt(VERSION_KEY, 0) == VERSION
        val missing = WidgetArtStyle.painted.flatMap { style -> WidgetArtShape.entries.map { style to it } }
            .filter { (style, shape) -> !current || !file(app, style, shape).exists() }
        if (missing.isEmpty()) return@withLock
        // Let launch (or the screen just opened) finish first.
        if (wait) delay(2_000)
        withContext(Dispatchers.Default) {
            folder(app).mkdirs()
            for ((style, shape) in missing) {
                runCatching {
                    val bitmap = paint(app, style, shape.width, shape.height)
                    val target = file(app, style, shape)
                    val temporary = File(target.path + ".part")
                    temporary.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 84, it) }
                    temporary.renameTo(target)
                    bitmap.recycle()
                }.onFailure { Log.e(TAG, "Couldn't draw ${style.rawValue}-${shape.rawValue}", it) }
                // Give the screen its turn before the next picture.
                delay(120)
            }
        }
        if (missing.all { (style, shape) -> file(app, style, shape).exists() }) defaults.edit { putInt(VERSION_KEY, VERSION) }
        VerselyWidgets.refresh(app)
    }

    /**
     * One painted background at full size, as WidgetArtCanvas on iOS: the
     * theme's paper and, for a season, its still kept to the edges so the
     * words in the middle stay clear; or a scene as the reader shows it still.
     */
    fun paint(context: Context, style: WidgetArtStyle, width: Int, height: Int): Bitmap {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val scene = ThemeScene.entries.firstOrNull { it.name == style.name }
        if (scene != null) {
            // Laid out at the widget's size in dp (a 2.6× phone), drawn at full size.
            val density = 2.6f
            val size = SceneSize(width / density.toDouble(), height / density.toDouble())
            val art = sceneArt(context.resources, scene, ForestWide.uses(size))
            CanvasDrawScope().draw(Density(density), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(canvas), Size(width.toFloat(), height.toFloat())) {
                drawScene(scene, art, size)
            }
            return bitmap
        }
        if (style == WidgetArtStyle.VINTAGE) {
            paintVintage(canvas, width, height, stamp = width > 600)
            return bitmap
        }
        val imageStyle = VerseImageStyle.entries.firstOrNull { it.rawValue == style.rawValue } ?: VerseImageStyle.PAPER
        canvas.drawColor((0xFF000000 or imageStyle.theme(ReaderTheme.PAPER).palette.background.toLong()).toInt())
        imageStyle.season?.let { season ->
            val layer = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val layerCanvas = Canvas(layer)
            // Drawn at phone size and enlarged, as on verse images.
            val enlarge = 2.5f
            CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(layerCanvas), Size(width.toFloat(), height.toFloat())) {
                scale(enlarge, pivot = Offset.Zero) {
                    CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, drawContext.canvas, Size(width / enlarge, height / enlarge)) { drawSeasonStill(season) }
                }
            }
            // Kept to the edges: faint in the middle, where the words go.
            val mask = Paint().apply {
                xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
                shader = RadialGradient(
                    width / 2f, height / 2f, maxOf(width, height) * 0.62f,
                    intArrayOf(0x1A000000, 0x1A000000, 0xFF000000.toInt()),
                    floatArrayOf(0f, 0.45f, 1f),
                    Shader.TileMode.CLAMP,
                )
            }
            layerCanvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), mask)
            canvas.drawBitmap(layer, 0f, 0f, null)
            layer.recycle()
        }
        return bitmap
    }

    /**
     * Vintage, as VintageBackground on iOS: cream postcard stock with a fine
     * grain and, beside the words on the larger sizes, a blank stamp with
     * perforated edges, slightly turned, a round postmark over its corner and
     * wavy cancellation lines.
     */
    private fun paintVintage(canvas: Canvas, width: Int, height: Int, stamp: Boolean) {
        canvas.drawColor(0xFFF6F1E7.toInt())
        // One point of the iOS widget, in this picture's pixels.
        val pt = width / if (width > 600) 364f else 170f
        val grain = Paint(Paint.ANTI_ALIAS_FLAG)
        var seed = 0x5EEDL
        fun next(): Float {
            seed = seed * 6_364_136_223_846_793_005L + 1_442_695_040_888_963_407L
            return ((seed ushr 11).toDouble() / (1L shl 53).toDouble()).toFloat()
        }
        repeat((width / pt * height / pt / 28f).toInt()) {
            val r = (0.3f + next() * 0.5f) * pt
            val x = next() * width
            val y = next() * height
            grain.color = android.graphics.Color.argb(((0.04f + next() * 0.04f) * 255).toInt(), 102, 84, 61)
            canvas.drawCircle(x, y, r, grain)
        }
        if (!stamp) return
        canvas.save()
        // The stamp's 96-point box, 12 points in from the top right.
        canvas.translate(width - (96f + 12f) * pt, 12f * pt)
        canvas.scale(pt, pt)
        val ink = android.graphics.Color.rgb(107, 102, 97)
        fun inkPaint(alpha: Float, stroke: Float? = null) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ink
            this.alpha = (alpha * 255).toInt()
            if (stroke != null) { style = Paint.Style.STROKE; strokeWidth = stroke }
        }
        val stampRect = android.graphics.RectF(18f, 4f, 76f, 74f)
        canvas.save()
        canvas.rotate(4f, stampRect.centerX(), stampRect.centerY())
        canvas.drawRect(android.graphics.RectF(stampRect).apply { offset(1f, 1.5f) }, Paint().apply { color = 0x14000000 })
        canvas.drawRect(stampRect, Paint().apply { color = android.graphics.Color.rgb(252, 250, 242) })
        val hole = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFF6F1E7.toInt() }
        var hx = stampRect.left
        while (hx <= stampRect.right) {
            canvas.drawCircle(hx, stampRect.top, 2.2f, hole); canvas.drawCircle(hx, stampRect.bottom, 2.2f, hole); hx += 6f
        }
        var hy = stampRect.top
        while (hy <= stampRect.bottom) {
            canvas.drawCircle(stampRect.left, hy, 2.2f, hole); canvas.drawCircle(stampRect.right, hy, 2.2f, hole); hy += 6f
        }
        canvas.drawRect(android.graphics.RectF(stampRect).apply { inset(5f, 5f) }, inkPaint(0.25f, 0.6f))
        canvas.restore()
        // Postmark.
        val cx = stampRect.right - 4f
        val cy = stampRect.bottom - 6f
        for (radius in listOf(17f, 12.5f)) canvas.drawCircle(cx, cy, radius, inkPaint(0.55f, 1f))
        for (row in 0 until 3) {
            val rowY = cy - 5f + row * 5f
            canvas.drawLine(cx - 9f, rowY, cx + 9f, rowY, inkPaint(0.4f, 0.8f))
        }
        // Wavy cancellation lines to the left.
        for (row in 0 until 4) {
            val baseY = stampRect.bottom - 26f + row * 6f
            val wave = android.graphics.Path().apply { moveTo(0f, baseY) }
            var wx = 0f
            while (wx < stampRect.left + 14f) {
                wave.quadTo(wx + 4f, baseY + if ((wx / 8f).toInt() % 2 == 0) -2.5f else 2.5f, wx + 8f, baseY)
                wx += 8f
            }
            canvas.drawPath(wave, inkPaint(0.5f, 0.9f))
        }
        canvas.restore()
    }
}
