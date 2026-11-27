package com.genesis.app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.net.Uri
import android.provider.Settings
import android.util.Log
import android.widget.RemoteViews
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.domain.share.VerseImageStyle
import com.genesis.core.domain.theme.SeasonMotion
import com.genesis.core.domain.theme.ThemeScene
import com.genesis.core.domain.widgets.WidgetArtShape
import com.genesis.core.domain.widgets.WidgetArtStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The moving backgrounds of the verse widget on Android: the seasons and
 * the scenes (Forest, Ocean, Hearth) drift as a short loop of frames that
 * the launcher flips (a ViewFlipper), since Android widgets can't animate
 * the way iOS's clock-hand wheels do. Each frame is a moment of the
 * reader's own animation; the loop blends into its own start, so it never
 * jumps. Drawn once per style into the app's files, a little smaller than
 * the still (the launcher holds every frame in memory), and only for the
 * styles widgets use. Pictures only: the verse is drawn over them, still.
 * Nothing moves when the person turned Gentle Motion off or Android's
 * animations off.
 */
object WidgetFrames {
    const val COUNT = 10
    /** Seconds of the animation between frames (the flipper shows each for 0.22 s). */
    private const val STEP = 0.26
    /** Frames are drawn at this share of the still's size. */
    private const val SCALE = 0.55f
    private const val VERSION = 2
    private const val TAG = "WidgetFrames"
    private val drawing = Mutex()
    /** Styles whose frames failed to draw in this run of the app: not tried again until it restarts. */
    private val failed = mutableSetOf<String>()

    fun animates(style: WidgetArtStyle): Boolean = sceneOf(style) != null || seasonOf(style) != null

    private fun sceneOf(style: WidgetArtStyle) = ThemeScene.entries.firstOrNull { it.name == style.name }
    private fun seasonOf(style: WidgetArtStyle) = VerseImageStyle.entries.firstOrNull { it.rawValue == style.rawValue }?.season

    fun folder(context: Context) = File(WidgetArt.folder(context), "frames")

    private fun file(context: Context, style: WidgetArtStyle, shape: WidgetArtShape, index: Int) =
        File(folder(context), "v$VERSION-${style.rawValue}-${shape.rawValue}-$index.jpg")

    /** Whether widgets should move now (Gentle Motion on, Android's animations on). */
    fun allowed(context: Context): Boolean {
        val app = context.applicationContext as? VerselyApplication ?: return false
        if (!app.readerSettings.preferences.value.seasonalEffects) return false
        val scale = runCatching { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) }.getOrDefault(1f)
        return scale > 0f
    }

    /**
     * A style's frames for a shape, if they're drawn: links the launcher opens
     * itself (WidgetFrameProvider), since ten pictures sent inside the update
     * are more than Android lets a widget update carry.
     */
    fun load(context: Context, style: WidgetArtStyle, shape: WidgetArtShape): List<Uri>? {
        val files = (0 until COUNT).map { file(context, style, shape, it) }
        if (!files.all { it.exists() }) return null
        return files.map { Uri.parse("content://${context.packageName}.widgetframes/${it.name}") }
    }

    /** The launcher's flipper holding the frames, for AndroidRemoteViews. */
    fun flipper(context: Context, frames: List<Uri>): RemoteViews {
        val flipper = RemoteViews(context.packageName, R.layout.widget_flipper)
        flipper.removeAllViews(R.id.widget_flipper)
        for (frame in frames) {
            val view = RemoteViews(context.packageName, R.layout.widget_frame)
            view.setImageViewUri(R.id.widget_frame, frame)
            flipper.addView(R.id.widget_flipper, view)
        }
        return flipper
    }

    /** Draws a style's frames in the background when they're missing, then redraws the widgets. */
    fun drawLater(context: Context, style: WidgetArtStyle) {
        val app = context.applicationContext as? VerselyApplication ?: return
        app.scope.launch { if (draw(app, style)) VerselyWidgets.refresh(app) }
    }

    /** True when something was drawn. */
    suspend fun draw(context: Context, style: WidgetArtStyle): Boolean = drawing.withLock {
        if (!animates(style) || style.rawValue in failed) return@withLock false
        val missing = WidgetArtShape.entries.filter { shape -> (0 until COUNT).any { !file(context, style, shape, it).exists() } }
        if (missing.isEmpty()) return@withLock false
        withContext(Dispatchers.Default) {
            folder(context).mkdirs()
            // Frames of an older version go.
            folder(context).listFiles()?.filter { !it.name.startsWith("v$VERSION-") }?.forEach { it.delete() }
            val start = if (sceneOf(style) != null) ThemeScene.STILL_TIME else SeasonMotion.PAINTED_MOMENT
            for (shape in missing) {
                val width = (shape.width * SCALE).toInt()
                val height = (shape.height * SCALE).toInt()
                for (index in 0 until COUNT) {
                    runCatching {
                        // A loop that meets its own start: each frame is this moment, with the
                        // moment a whole loop earlier faded in over it more and more.
                        val now = WidgetArt.paint(context, style, width, height, start + index * STEP, SCALE)
                        val share = index.toFloat() / COUNT
                        if (share > 0f) {
                            val earlier = WidgetArt.paint(context, style, width, height, start + (index - COUNT) * STEP, SCALE)
                            Canvas(now).drawBitmap(earlier, 0f, 0f, Paint().apply { alpha = (share * 255).toInt() })
                            earlier.recycle()
                        }
                        val target = file(context, style, shape, index)
                        val temporary = File(target.path + ".part")
                        temporary.outputStream().use { now.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                        temporary.renameTo(target)
                        now.recycle()
                    }.onFailure { Log.e(TAG, "Couldn't draw ${style.rawValue} frame $index", it) }
                }
            }
        }
        // Only a complete loop is worth a refresh; otherwise the still stays and nothing loops.
        val complete = missing.all { shape -> (0 until COUNT).all { file(context, style, shape, it).exists() } }
        if (!complete) failed += style.rawValue
        complete
    }
}
