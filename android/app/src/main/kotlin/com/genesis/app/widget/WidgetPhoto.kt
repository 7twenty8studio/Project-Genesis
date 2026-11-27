package com.genesis.app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ImageDecoder
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.Shader
import android.net.Uri
import androidx.core.content.edit
import com.genesis.core.domain.widgets.PhotoFraming
import com.genesis.core.domain.widgets.WidgetArtShape
import com.genesis.core.domain.widgets.WidgetArtStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The person's widget photo (Settings › Widget Photo), as WidgetArtWriter's
 * photo on iOS: kept at most 2400 pixels on its long side, as a JPEG drawn
 * afresh so no metadata (no location) travels with it, and cut for each
 * widget shape as the person framed it. It stays on this phone.
 */
object WidgetPhoto {
    private const val LONG_SIDE = 2400

    /** Bumped whenever the photo or its framing changes, so screens show the new one. */
    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version.asStateFlow()

    private fun original(context: Context) = File(WidgetArt.folder(context), "photo.jpg")
    private fun defaults(context: Context) = context.applicationContext.getSharedPreferences("widgets", Context.MODE_PRIVATE)
    private fun framingKey(shape: WidgetArtShape) = "widgetPhoto.framing.${shape.rawValue}"

    fun exists(context: Context): Boolean = original(context).exists()

    /** The photo as kept (for the framing editor). */
    suspend fun photo(context: Context): Bitmap? = withContext(Dispatchers.IO) {
        original(context).takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
    }

    /** Keeps a chosen photo and frames it in the middle for every widget size. */
    suspend fun save(context: Context, uri: Uri): Boolean = withContext(Dispatchers.IO) {
        val decoded = runCatching {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val long = max(info.size.width, info.size.height)
                if (long > LONG_SIDE) {
                    val factor = LONG_SIDE.toDouble() / long
                    decoder.setTargetSize((info.size.width * factor).roundToInt(), (info.size.height * factor).roundToInt())
                }
            }
        }.getOrNull() ?: return@withContext false
        WidgetArt.folder(context).mkdirs()
        original(context).outputStream().use { decoded.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        defaults(context).edit { WidgetArtShape.entries.forEach { remove(framingKey(it)) } }
        writeFramed(context, decoded, emptyMap())
        decoded.recycle()
        true
    }

    /** The framing kept for one widget shape (the middle, if never moved). */
    fun framing(context: Context, shape: WidgetArtShape): PhotoFraming = PhotoFraming.decode(defaults(context).getString(framingKey(shape), null))

    /** Keeps each shape's framing and writes the photo cut to each shape. */
    suspend fun saveFramings(context: Context, framings: Map<WidgetArtShape, PhotoFraming>) = withContext(Dispatchers.IO) {
        val photo = photo(context) ?: return@withContext
        defaults(context).edit { framings.forEach { (shape, framing) -> putString(framingKey(shape), framing.encoded()) } }
        writeFramed(context, photo, framings)
        photo.recycle()
    }

    suspend fun remove(context: Context) = withContext(Dispatchers.IO) {
        original(context).delete()
        WidgetArtShape.entries.forEach { WidgetArt.file(context, WidgetArtStyle.PHOTO, it).delete() }
        defaults(context).edit { WidgetArtShape.entries.forEach { remove(framingKey(it)) } }
        _version.value++
        VerselyWidgets.refresh(context)
    }

    /** Each shape's cut at the widget's size, softly shaded so light words read on any photo. */
    private suspend fun writeFramed(context: Context, photo: Bitmap, framings: Map<WidgetArtShape, PhotoFraming>) {
        for (shape in WidgetArtShape.entries) {
            val framing = framings[shape] ?: framing(context, shape)
            val crop = framing.crop(photo.width.toDouble(), photo.height.toDouble(), shape.width.toDouble() / shape.height)
            val source = Rect(crop.x.roundToInt(), crop.y.roundToInt(), min(photo.width, (crop.x + crop.width).roundToInt()), min(photo.height, (crop.y + crop.height).roundToInt()))
            val framed = Bitmap.createBitmap(shape.width, shape.height, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(framed)
            canvas.drawBitmap(photo, source, Rect(0, 0, shape.width, shape.height), Paint(Paint.FILTER_BITMAP_FLAG))
            val shade = Paint().apply {
                shader = LinearGradient(0f, 0f, 0f, shape.height.toFloat(), 0x47000000, 0x80000000.toInt(), Shader.TileMode.CLAMP)
            }
            canvas.drawRect(0f, 0f, shape.width.toFloat(), shape.height.toFloat(), shade)
            WidgetArt.file(context, WidgetArtStyle.PHOTO, shape).outputStream().use { framed.compress(Bitmap.CompressFormat.JPEG, 85, it) }
            framed.recycle()
        }
        _version.value++
        VerselyWidgets.refresh(context)
    }
}
