package com.genesis.app.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import com.genesis.app.R
import com.genesis.core.domain.widgets.WidgetArtShape
import com.genesis.core.domain.widgets.WidgetArtStyle
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The keepsake verse widgets' pictures, as KeepsakeWidgets.swift on iOS:
 * linen behind everything, a cream text card (paper, ruled lines, a film
 * frame, a paperclip) and a picture card (the bundled pictures or the
 * person's photo, an instant print, a film frame, the pocket stamped with
 * the date, the calendar pad with the date written on it). Drawn by the app
 * at the widget's size, with no Scripture in them: the widget writes the
 * verse over the text card, verbatim.
 */
internal object Keepsakes {
    const val SAGE = 0xFF80825BL
    const val BODY = 0xFF5D5B55L
    const val INK = 0xFF3D3B36L
    const val TERRACOTTA = 0xFFC17C62L
    const val FADED_RED = 0xFFD48670L
    private const val CARD = 0xFFF7F2E9.toInt()
    private const val LINEN = 0xFFEEE8DE.toInt()
    private const val RULE_RED = 0xFFE2A59A.toInt()
    private const val RULE_BLUE = 0xFFC9DCEB.toInt()
    private const val AMBER = 0xFFD8A56D.toInt()

    /** Pixels per dp in the pictures. */
    private const val SCALE = 2.5f

    private fun image(context: Context, id: Int): Bitmap? = runCatching { BitmapFactory.decodeResource(context.resources, id) }.getOrNull()

    private fun bitmap(wDp: Float, hDp: Float): Pair<Bitmap, Canvas> {
        val bitmap = Bitmap.createBitmap((wDp * SCALE).roundToInt().coerceAtLeast(1), (hDp * SCALE).roundToInt().coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        return bitmap to Canvas(bitmap).apply { scale(SCALE, SCALE) }
    }

    private fun rounded(wDp: Float, hDp: Float, radius: Float) = Path().apply { addRoundRect(RectF(0f, 0f, wDp, hDp), radius, radius, Path.Direction.CW) }

    /** A picture filling a rectangle (cropped, centred, or anchored at the bottom). */
    private fun Canvas.fill(image: Bitmap, frame: RectF, bottom: Boolean = false) {
        val scale = max(frame.width() / image.width, frame.height() / image.height)
        val w = frame.width() / scale
        val h = frame.height() / scale
        val x = (image.width - w) / 2
        val y = if (bottom) image.height - h else (image.height - h) / 2
        drawBitmap(image, Rect(x.roundToInt(), y.roundToInt(), (x + w).roundToInt(), (y + h).roundToInt()), frame, Paint(Paint.FILTER_BITMAP_FLAG))
    }

    /** A picture shown whole (fitted, centred); returns where it went. */
    private fun Canvas.fit(image: Bitmap, frame: RectF): RectF {
        val scale = min(frame.width() / image.width, frame.height() / image.height)
        val w = image.width * scale
        val h = image.height * scale
        val target = RectF(frame.centerX() - w / 2, frame.centerY() - h / 2, frame.centerX() + w / 2, frame.centerY() + h / 2)
        drawBitmap(image, null, target, Paint(Paint.FILTER_BITMAP_FLAG))
        return target
    }

    private fun Canvas.paper(context: Context, wDp: Float, hDp: Float, lighten: Float, fallback: Int = CARD) {
        val paper = image(context, R.drawable.keepsake_paper)
        if (paper != null) {
            fill(paper, RectF(0f, 0f, wDp, hDp))
            drawRect(0f, 0f, wDp, hDp, Paint().apply { color = Color.WHITE; alpha = (lighten * 255).toInt() })
        } else {
            drawColor(fallback)
        }
    }

    private fun text(size: Float, color: Int, italic: Boolean = false, bold: Boolean = false, align: Paint.Align = Paint.Align.LEFT) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textSize = size
        this.color = color
        textAlign = align
        typeface = Typeface.create(Typeface.SERIF, when {
            italic -> Typeface.ITALIC
            bold -> Typeface.BOLD
            else -> Typeface.NORMAL
        })
    }

    /** The linen behind the cards. */
    fun linen(context: Context): Bitmap? = image(context, R.drawable.keepsake_linen)

    /** The text card's background at this size (the words go over it). */
    fun textCard(context: Context, style: WidgetArtStyle, wDp: Float, hDp: Float, small: Boolean): Bitmap {
        val (bitmap, canvas) = bitmap(wDp, hDp)
        val radius = if (small) 14f else 16f
        canvas.clipPath(rounded(wDp, hDp, radius))
        when (style) {
            WidgetArtStyle.FILM_STRIP -> canvas.filmFrame(wDp, hDp, "11A ▸", "12", null)
            WidgetArtStyle.TYPEWRITER -> canvas.paper(context, wDp, hDp, 0.55f, 0xFFFCFBF8.toInt())
            WidgetArtStyle.LIBRARY_CARD -> {
                canvas.paper(context, wDp, hDp, 0.4f, 0xFFFAF7F0.toInt())
                // Blue rules, a red rule under the heading, a red margin.
                val blue = Paint().apply { color = RULE_BLUE }
                var y = 50f
                while (y < hDp) {
                    canvas.drawRect(0f, y, wDp, y + 0.75f, blue)
                    y += 18f
                }
                canvas.drawRect(0f, 31f, wDp, 32f, Paint().apply { color = RULE_RED })
                canvas.drawRect(15f, 31f, 15.75f, hDp, Paint().apply { color = RULE_RED; alpha = 178 })
            }
            WidgetArtStyle.CALENDAR_PAGE -> canvas.paper(context, wDp, hDp, 0.3f)
            else -> canvas.drawColor(Color.argb(230, 0xF7, 0xF2, 0xE9))
        }
        if (style == WidgetArtStyle.TYPEWRITER) {
            // The gold paperclip over the top right corner.
            canvas.save()
            canvas.translate(wDp - 28f, -6f)
            canvas.rotate(8f, 7f, 20f)
            canvas.paperclip(14f, 40f)
            canvas.restore()
        }
        return bitmap
    }

    /** The picture card at this size. */
    fun pictureCard(context: Context, style: WidgetArtStyle, wDp: Float, hDp: Float, shape: WidgetArtShape, photo: Bitmap?, date: LocalDate, caption: String? = null): Bitmap {
        val (bitmap, canvas) = bitmap(wDp, hDp)
        val radius = if (shape == WidgetArtShape.SMALL) 14f else 16f
        val frame = RectF(0f, 0f, wDp, hDp)
        when (style) {
            WidgetArtStyle.INSTANT_PHOTO -> canvas.instantPrint(wDp, hDp, photo ?: image(context, R.drawable.keepsake_beach), caption)
            else -> {
                canvas.clipPath(rounded(wDp, hDp, radius))
                canvas.drawColor(CARD)
                when (style) {
                    WidgetArtStyle.PRESSED_FLOWERS -> image(context, R.drawable.keepsake_flowers)?.let { canvas.fill(it, frame) }
                    WidgetArtStyle.FILM_STRIP -> canvas.filmFrame(wDp, hDp, "12", "12A", photo ?: image(context, R.drawable.keepsake_meadow))
                    WidgetArtStyle.TYPEWRITER ->
                        // The machine itself in the large widget; baby's breath elsewhere.
                        if (shape == WidgetArtShape.LARGE) image(context, R.drawable.keepsake_typewriter)?.let { canvas.fill(it, frame, bottom = true) }
                        else image(context, R.drawable.keepsake_sprigs)?.let { canvas.fill(it, frame) }
                    WidgetArtStyle.LIBRARY_CARD -> {
                        canvas.paper(context, wDp, hDp, 0f)
                        val pocket = image(context, R.drawable.keepsake_pocket)
                        val shown = pocket?.let { canvas.fit(it, frame) } ?: frame
                        // The stamp on the pocket's front, below the card's tab.
                        canvas.rubberStamp(shown.centerX(), shown.top + shown.height() * 0.6f, date, if (shape == WidgetArtShape.SMALL) 13f else 15f)
                    }
                    else -> {
                        canvas.drawColor(LINEN)
                        val pad = image(context, R.drawable.keepsake_pad)
                        val shown = pad?.let { canvas.fit(it, frame) } ?: frame
                        canvas.calendarDate(shown.left + shown.width() * 0.48f, shown.top + shown.height() * 0.55f, date, if (shape == WidgetArtShape.SMALL) 0.85f else 1f)
                    }
                }
            }
        }
        return bitmap
    }

    /** A white instant print, slightly turned, with a wide bottom border (the small widget's reference written on it). */
    private fun Canvas.instantPrint(wDp: Float, hDp: Float, photo: Bitmap?, caption: String?) {
        val side = min(wDp, hDp / 1.17f) * 0.92f
        val left = (wDp - side) / 2
        val top = (hDp - side * 1.17f) / 2
        save()
        rotate(-3f, wDp / 2, hDp / 2)
        val print = RectF(left, top, left + side, top + side * 1.17f)
        drawRect(RectF(print).apply { offset(0f, 2f) }, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(36, 0, 0, 0) })
        drawRect(print, Paint().apply { color = 0xFFFDFCF9.toInt() })
        val picture = RectF(left + 6f, top + 6f, left + side - 6f, top + side - 6f)
        drawRect(picture, Paint().apply { shader = LinearGradient(0f, picture.top, 0f, picture.bottom, 0xFFDCE6EC.toInt(), 0xFFF2E7D3.toInt(), Shader.TileMode.CLAMP) })
        photo?.let { fill(it, picture) }
        caption?.let {
            val paint = text(side * 0.09f, BODY.toInt(), italic = true, align = Paint.Align.CENTER)
            val baseline = picture.bottom + (print.bottom - picture.bottom) / 2 + paint.textSize / 3
            drawText(ellipsize(it, paint, side - 12f), print.centerX(), baseline, paint)
        }
        restore()
    }

    private fun ellipsize(text: String, paint: Paint, width: Float): String {
        if (paint.measureText(text) <= width) return text
        var end = text.length
        while (end > 1 && paint.measureText(text.substring(0, end) + "…") > width) end--
        return text.substring(0, end) + "…"
    }

    /** A pale film frame: sprocket holes along the top and bottom, amber edge numbers, a photo in the middle. */
    private fun Canvas.filmFrame(wDp: Float, hDp: Float, edgeMark: String, frameMark: String, photo: Bitmap?) {
        drawColor(0xFFF4EEE3.toInt())
        photo?.let { fill(it, RectF(4f, 18f, wDp - 4f, hDp - 18f)) }
        val hole = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0xFFE6DCCB.toInt() }
        val count = max(4, (wDp / 17f).toInt())
        val slot = wDp / count
        for (i in 0 until count) {
            val cx = slot * i + slot / 2
            for (y in listOf(4f, hDp - 12f)) drawRoundRect(RectF(cx - 3.5f, y, cx + 3.5f, y + 8f), 1.5f, 1.5f, hole)
        }
        val marks = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = 6.5f; color = AMBER; alpha = 204; typeface = Typeface.DEFAULT_BOLD }
        drawText(edgeMark, 6f, 8f, marks)
        marks.textAlign = Paint.Align.RIGHT
        drawText(frameMark, wDp - 6f, 8f, marks)
    }

    /** A faded red date stamp, slightly turned. */
    private fun Canvas.rubberStamp(cx: Float, cy: Float, date: LocalDate, size: Float) {
        val label = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(Locale.getDefault()).format(date)
        val paint = text(size, Color.argb(217, 0xD4, 0x86, 0x70), align = Paint.Align.CENTER)
        val width = paint.measureText(label) + 18f
        val height = size + 10f
        save()
        rotate(-9f, cx, cy)
        drawRoundRect(RectF(cx - width / 2, cy - height / 2, cx + width / 2, cy + height / 2), 4f, 4f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = 1.5f; color = Color.argb(191, 0xD4, 0x86, 0x70)
        })
        drawText(label, cx, cy + size / 3, paint)
        restore()
    }

    /** Month, day and weekday as printed on a calendar page. */
    private fun Canvas.calendarDate(cx: Float, cy: Float, date: LocalDate, scale: Float) {
        val locale = Locale.getDefault()
        val month = DateTimeFormatter.ofPattern("LLLL", locale).format(date).uppercase(locale)
        val weekday = DateTimeFormatter.ofPattern("EEEE", locale).format(date).uppercase(locale)
        val top = cy - 30f * scale
        drawText(month, cx, top + 9f * scale, text(10f * scale, SAGE.toInt(), italic = true, align = Paint.Align.CENTER))
        drawText(date.dayOfMonth.toString(), cx, top + 42f * scale, text(36f * scale, TERRACOTTA.toInt(), align = Paint.Align.CENTER))
        drawRect(cx - 20f * scale, top + 47f * scale, cx + 20f * scale, top + 47.75f * scale, Paint().apply { color = SAGE.toInt(); alpha = 89 })
        drawText(weekday, cx, top + 59f * scale, text(9f * scale, SAGE.toInt(), align = Paint.Align.CENTER))
    }

    /** A gold paperclip: one wire, three loops. */
    private fun Canvas.paperclip(w: Float, h: Float) {
        val path = Path().apply {
            moveTo(w * 0.15f, h * 0.75f)
            lineTo(w * 0.15f, w * 0.45f)
            arcTo(RectF(w * 0.15f, w * 0.1f, w * 0.85f, w * 0.8f), 180f, 180f)
            lineTo(w * 0.85f, h - w * 0.4f)
            arcTo(RectF(w * 0.25f, h - w * 0.7f, w * 0.85f, h - w * 0.1f), 0f, 180f)
            lineTo(w * 0.25f, h * 0.3f)
            arcTo(RectF(w * 0.25f, h * 0.3f - w * 0.2f, w * 0.65f, h * 0.3f + w * 0.2f), 180f, 180f)
            lineTo(w * 0.65f, h * 0.62f)
        }
        fun wire(color: Int, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = width; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND; this.color = color
        }
        drawPath(path, wire(Color.argb(38, 0, 0, 0), 1.8f))
        save()
        translate(-0.3f, -0.4f)
        drawPath(path, wire(Color.rgb(201, 168, 110), 1.4f))
        restore()
    }
}
