package com.genesis.app.share

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import com.genesis.app.reader.backdrop.drawSeasonStill
import com.genesis.core.domain.bible.ScriptureDirection
import com.genesis.core.domain.reader.ReaderFont
import com.genesis.core.domain.share.VerseCard
import com.genesis.core.domain.share.VerseImageInk
import com.genesis.core.domain.share.VerseImageShape
import com.genesis.core.domain.share.VerseImageStyle
import com.genesis.core.domain.share.VerseImageText
import com.genesis.core.domain.theme.ReaderTheme

/** How the words look on a verse image (VerseImageOptions on iOS). */
data class VerseImageOptions(
    val font: ReaderFont,
    val ink: VerseImageInk = VerseImageInk.AUTOMATIC,
    /** Scales the text (0.7–1.4). */
    val size: Double = 1.0,
    val centered: Boolean = false,
)

/**
 * Draws a verse image at full size, as VerseImageCanvas on iOS: the verse
 * verbatim in the chosen face on the theme's paper, a season's painted
 * still or one of the person's photos, its reference and Versely's name.
 */
object VerseImageRenderer {
    fun render(
        context: Context,
        card: VerseCard,
        style: VerseImageStyle,
        shape: VerseImageShape,
        options: VerseImageOptions,
        reading: ReaderTheme,
        photo: Bitmap?,
        /** False for the live wallpaper, which draws the season moving over the image itself. */
        seasonStill: Boolean = true,
    ): Bitmap {
        val width = shape.width
        val height = shape.height
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val theme = style.theme(reading)
        val palette = theme.palette

        // The background: the paper's colour, or the photo filling the image under a soft scrim.
        if (style == VerseImageStyle.PHOTO && photo != null) {
            canvas.drawBitmap(photo, centerCrop(photo, width, height), Rect(0, 0, width, height), Paint(Paint.FILTER_BITMAP_FLAG))
            val scrim = Paint().apply {
                shader = LinearGradient(0f, 0f, 0f, height.toFloat(), 0x40000000, 0x80000000.toInt(), Shader.TileMode.CLAMP)
            }
            canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), scrim)
        } else {
            canvas.drawColor(opaque(palette.background))
        }

        // A season's still, drawn at phone size and enlarged so leaves and snow keep their size.
        style.season?.takeIf { seasonStill }?.let { season ->
            val layer = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            val layerCanvas = Canvas(layer)
            val enlarge = 2.5f
            CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(layerCanvas), Size(width.toFloat(), height.toFloat())) {
                scale(enlarge, pivot = androidx.compose.ui.geometry.Offset.Zero) {
                    val phone = CanvasDrawScope()
                    phone.draw(Density(1f), LayoutDirection.Ltr, drawContext.canvas, Size(width / enlarge, height / enlarge)) { drawSeasonStill(season) }
                }
            }
            // On a wallpaper the leaves and snow keep to the sides, clear of the verse and the clock.
            if (shape == VerseImageShape.LOCK_SCREEN) {
                val mask = Paint().apply {
                    xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN)
                    shader = LinearGradient(
                        0f, 0f, width.toFloat(), 0f,
                        intArrayOf(0xFF000000.toInt(), 0x1F000000, 0x1F000000, 0xFF000000.toInt()),
                        floatArrayOf(0f, 0.24f, 0.76f, 1f),
                        Shader.TileMode.CLAMP,
                    )
                }
                layerCanvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), mask)
            }
            canvas.drawBitmap(layer, 0f, 0f, Paint().apply { alpha = 230 })
            layer.recycle()
        }

        drawWords(context, canvas, card, shape, options, theme)
        return bitmap
    }

    private fun drawWords(context: Context, canvas: Canvas, card: VerseCard, shape: VerseImageShape, options: VerseImageOptions, theme: ReaderTheme) {
        val palette = theme.palette
        val ink = options.ink.hex?.let { opaque(it.toInt()) } ?: opaque(palette.text)
        val face = typeface(context, options.font, bold = false)
        val bold = typeface(context, options.font, bold = true)
        val left = shape.sidePadding
        val right = shape.width - shape.sidePadding
        val textWidth = (right - left).toInt()
        val alignment = if (options.centered) Layout.Alignment.ALIGN_CENTER else Layout.Alignment.ALIGN_NORMAL
        val spacing = 44f

        // The opening quotation mark, faint.
        val quote = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = face; textSize = 160f; color = withAlpha(ink, 0.45f) }
        var top = shape.textTop
        val quoteX = if (options.centered) (shape.width - quote.measureText("“")) / 2 else left
        canvas.drawText("“", quoteX, top - quote.fontMetrics.ascent * 0.72f, quote)
        top += 70f + spacing

        // The reference, the Bible and Versely's name at the foot.
        val referencePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = bold; textSize = 40f; color = if (options.ink == VerseImageInk.AUTOMATIC) opaque(palette.accent) else ink }
        val translationPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create(Typeface.DEFAULT, 500, false); textSize = 26f; color = withAlpha(ink, 0.7f) }
        val namePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD); textSize = 26f; color = withAlpha(ink, 0.6f) }
        val referenceLayout = layout(card.reference, referencePaint, textWidth, alignment)
        val translationLayout = layout(card.translation, translationPaint, textWidth, alignment)
        val nameHeight = if (options.centered) namePaint.fontSpacing + spacing else 0f
        val footHeight = referenceLayout.height + 6f + translationLayout.height + nameHeight
        val bottom = shape.height - shape.textBottom
        val footTop = bottom - footHeight

        // The verse, verbatim, shrunk until it fits (as far as about a third of its size).
        val area = footTop - spacing - top
        val start = VerseImageText.size(card.text.length, shape, options.size)
        var size = start
        var verse: StaticLayout
        val text = ScriptureDirection.display(card.text)
        while (true) {
            val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = face; textSize = size; color = ink }
            verse = StaticLayout.Builder.obtain(text, 0, text.length, paint, textWidth)
                .setAlignment(alignment)
                .setLineSpacing(size * 0.32f, 1f)
                .setIncludePad(false)
                .build()
            if (verse.height <= area || size <= start * 0.35f) break
            size *= 0.94f
        }
        val verseTop = if (options.centered) top + maxOf(0f, (area - verse.height) / 2) else top
        canvas.save()
        canvas.clipRect(RectF(left, top, right, footTop - spacing + 1))
        canvas.translate(left, verseTop)
        verse.draw(canvas)
        canvas.restore()

        canvas.save()
        canvas.translate(left, footTop)
        referenceLayout.draw(canvas)
        canvas.translate(0f, referenceLayout.height + 6f)
        translationLayout.draw(canvas)
        canvas.restore()
        if (options.centered) {
            val x = (shape.width - namePaint.measureText(NAME)) / 2
            canvas.drawText(NAME, x, bottom - namePaint.descent(), namePaint)
        } else {
            canvas.drawText(NAME, right - namePaint.measureText(NAME), bottom - translationLayout.height + translationLayout.getLineBaseline(0).toFloat(), namePaint)
        }
    }

    private const val NAME = "Versely"

    private fun layout(text: String, paint: TextPaint, width: Int, alignment: Layout.Alignment): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, width).setAlignment(alignment).setIncludePad(false).build()

    private fun typeface(context: Context, font: ReaderFont, bold: Boolean): Typeface {
        val faces = font.faces ?: return Typeface.create(if (font.isSans) Typeface.SANS_SERIF else Typeface.SERIF, if (bold) Typeface.BOLD else Typeface.NORMAL)
        return runCatching { Typeface.createFromAsset(context.assets, (if (bold) faces.bold else faces.regular) + ".ttf") }
            .getOrElse { Typeface.create(Typeface.SERIF, if (bold) Typeface.BOLD else Typeface.NORMAL) }
    }

    private fun opaque(rgb: Int): Int = 0xFF000000.toInt() or rgb

    private fun withAlpha(color: Int, alpha: Float): Int = ((alpha * 255).toInt() shl 24) or (color and 0x00FFFFFF)

    /** The part of the photo that fills the image, cropped from its centre. */
    private fun centerCrop(photo: Bitmap, width: Int, height: Int): Rect {
        val scale = maxOf(width.toFloat() / photo.width, height.toFloat() / photo.height)
        val w = (width / scale).toInt()
        val h = (height / scale).toInt()
        val x = (photo.width - w) / 2
        val y = (photo.height - h) / 2
        return Rect(x, y, x + w, y + h)
    }
}
