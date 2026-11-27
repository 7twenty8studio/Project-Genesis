package com.genesis.app.share

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.Shader
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.service.wallpaper.WallpaperService
import android.view.SurfaceHolder
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.core.content.edit
import com.genesis.app.reader.backdrop.drawSeasonMoment
import com.genesis.core.domain.theme.Season
import com.genesis.core.domain.theme.SeasonMotion
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The live wallpaper (Premium, as LiveWallpaperMaker's Live Photo on iOS):
 * the Lock Screen verse image, its words verbatim, with the season drifting
 * over it, kept to the sides clear of the verse and the clock. Android's own
 * picker sets it on the lock screen, the home screen or both.
 */
object LiveWallpaper {
    private fun file(context: Context) = File(context.filesDir, "LiveWallpaper/verse.png")
    private fun defaults(context: Context) = context.getSharedPreferences("liveWallpaper", Context.MODE_PRIVATE)

    /** Keeps the image and its season, then opens Android's live wallpaper preview. */
    suspend fun set(context: Context, image: Bitmap, season: Season) {
        withContext(Dispatchers.IO) {
            val target = file(context)
            target.parentFile?.mkdirs()
            target.outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            defaults(context).edit { putString("season", season.name) }
        }
        val component = ComponentName(context, VerseWallpaperService::class.java)
        val intent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER)
            .putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }.onFailure {
            // Should the preview be missing, Android's wallpaper chooser still lists Versely.
            runCatching { context.startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    internal fun image(context: Context): Bitmap? = file(context).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }

    internal fun season(context: Context): Season? = defaults(context).getString("season", null)?.let { name -> Season.entries.firstOrNull { it.name == name } }
}

/** Draws the live wallpaper: the image filling the screen, the season over its sides, 30 fps while it's seen. */
class VerseWallpaperService : WallpaperService() {
    override fun onCreateEngine(): Engine = VerseEngine()

    private inner class VerseEngine : Engine() {
        private val handler = Handler(Looper.getMainLooper())
        private var image: Bitmap? = null
        private var season: Season? = null
        private var visible = false
        private var started = 0L
        private val frame = Runnable { draw() }

        override fun onCreate(surfaceHolder: SurfaceHolder) {
            super.onCreate(surfaceHolder)
            load()
        }

        private fun load() {
            image = LiveWallpaper.image(this@VerseWallpaperService)
            season = LiveWallpaper.season(this@VerseWallpaperService)
        }

        override fun onVisibilityChanged(visible: Boolean) {
            this.visible = visible
            if (visible) {
                // A newer verse may have been set since.
                load()
                if (started == 0L) started = System.nanoTime()
                draw()
            } else {
                handler.removeCallbacks(frame)
            }
        }

        override fun onSurfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            super.onSurfaceChanged(holder, format, width, height)
            draw()
        }

        override fun onSurfaceDestroyed(holder: SurfaceHolder) {
            visible = false
            handler.removeCallbacks(frame)
            super.onSurfaceDestroyed(holder)
        }

        override fun onDestroy() {
            handler.removeCallbacks(frame)
            super.onDestroy()
        }

        /** Remove Animations or Battery Saver: the painted still moment, no motion. */
        private fun still(): Boolean {
            val power = getSystemService(PowerManager::class.java)
            val scale = runCatching { Settings.Global.getFloat(contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE) }.getOrDefault(1f)
            return scale == 0f || power?.isPowerSaveMode == true
        }

        private fun draw() {
            val holder = surfaceHolder
            val canvas = runCatching { holder.lockHardwareCanvas() }.getOrNull() ?: return
            val still = still()
            try {
                val width = canvas.width
                val height = canvas.height
                canvas.drawColor(0xFFF6EFE4.toInt())
                image?.let { canvas.drawBitmap(it, cover(it, width, height), Rect(0, 0, width, height), Paint(Paint.FILTER_BITMAP_FLAG)) }
                season?.let { season ->
                    val t = if (still) SeasonMotion.PAINTED_MOMENT else (System.nanoTime() - started) / 1e9 + 3.0
                    val layer = canvas.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
                    CanvasDrawScope().draw(Density(resources.displayMetrics.density), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(canvas), Size(width.toFloat(), height.toFloat())) {
                        drawSeasonMoment(season, t, 1f)
                    }
                    // Kept to the sides, as on the image itself.
                    canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), Paint().apply {
                        xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
                        shader = LinearGradient(
                            0f, 0f, width.toFloat(), 0f,
                            intArrayOf(0xEB000000.toInt(), 0x1F000000, 0x1F000000, 0xEB000000.toInt()),
                            floatArrayOf(0f, 0.24f, 0.76f, 1f),
                            Shader.TileMode.CLAMP,
                        )
                    })
                    canvas.restoreToCount(layer)
                }
            } finally {
                holder.unlockCanvasAndPost(canvas)
            }
            handler.removeCallbacks(frame)
            if (visible && season != null && !still) handler.postDelayed(frame, 1000L / 30)
        }

        /** The part of the image that fills the screen (centred, cropped). */
        private fun cover(image: Bitmap, width: Int, height: Int): Rect {
            val scale = max(width.toFloat() / image.width, height.toFloat() / image.height)
            val w = min(image.width, (width / scale).roundToInt())
            val h = min(image.height, (height / scale).roundToInt())
            val x = (image.width - w) / 2
            val y = (image.height - h) / 2
            return Rect(x, y, x + w, y + h)
        }
    }
}
