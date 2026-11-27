package com.genesis.app.insights

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import com.genesis.app.R
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.insights.ReadingStats
import com.genesis.core.domain.insights.YearInReview
import com.genesis.core.domain.reader.ReaderFont
import com.genesis.core.domain.theme.ReaderTheme
import java.text.NumberFormat
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * The shareable Year in Review cards at 1080 × 1350, as YearSummaryCard and
 * YearShareCards.swift: the summary for everyone; with Reading insights
 * (Premium) also a dot for every day of the year and a shelf of the 66 books.
 */
internal object YearCards {
    const val WIDTH = 1080
    const val HEIGHT = 1350
    private const val PAD = 100f

    /** The page the cards are printed on: a dark theme as it is, a light one on its paper, else cream. */
    fun theme(current: ReaderTheme): ReaderTheme =
        if (current.isDark || current in setOf(ReaderTheme.PAPER, ReaderTheme.CREAM, ReaderTheme.SEPIA, ReaderTheme.PARCHMENT)) current else ReaderTheme.CREAM

    fun summary(context: Context, review: YearInReview, theme: ReaderTheme, font: ReaderFont, language: String): Bitmap = card(theme) { canvas, p ->
        var y = PAD
        y = text(canvas, context.getString(R.string.year_card_title), sans(28f, true, p.accent, spacing = 0.1f), PAD, y) + 8
        y = text(canvas, review.year.toString(), face(context, font, 150f, true, p.text), PAD, y) + 46
        val rows = buildList {
            add(number(review.daysRead) to context.getString(R.string.year_card_days))
            add(number(review.chaptersRead) to context.getString(R.string.year_card_chapters))
            add(number(review.longestStreak) to context.getString(R.string.year_card_streak))
            add(number(review.highlights) to context.getString(R.string.year_card_highlighted))
            if (review.prayersAnswered > 0) add(number(review.prayersAnswered) to context.getString(R.string.year_card_answered))
        }
        for ((value, label) in rows) {
            val valuePaint = face(context, font, 84f, true, p.text)
            val baseline = y - valuePaint.fontMetrics.ascent
            canvas.drawText(value, PAD, baseline, valuePaint)
            canvas.drawText(label, PAD + valuePaint.measureText(value) + 22, baseline, sans(36f, false, p.secondaryText))
            y = baseline + valuePaint.fontMetrics.descent + 30
        }
        review.topBook?.let { book ->
            val paint = face(context, font, 40f, false, p.secondaryText)
            canvas.drawText(context.getString(R.string.year_most_read, BibleBooks.withNumber(book).name(language)), PAD, HEIGHT - PAD, paint)
        }
    }

    fun days(context: Context, review: YearInReview, readingDays: Set<LocalDate>, theme: ReaderTheme, font: ReaderFont): Bitmap = page(context, review.year, theme, font) { canvas, p, top ->
        var y = big(context, canvas, number(review.daysRead), context.getString(R.string.year_card_days), font, p, top) + 56
        val first: DayOfWeek = WeekFields.of(Locale.getDefault()).firstDayOfWeek
        val weeks = YearInReview.readingWeeks(review.year, readingDays, first)
        val dot = 12f
        val gap = 4.2f
        val read = fill(p.accent)
        val unread = fill(withAlpha(p.separator, 0.7f))
        weeks.forEachIndexed { week, days ->
            days.forEachIndexed { weekday, wasRead ->
                if (wasRead != null) {
                    val cx = PAD + week * (dot + gap) + dot / 2
                    val cy = y + weekday * (dot + gap) + dot / 2
                    canvas.drawCircle(cx, cy, dot / 2, if (wasRead) read else unread)
                }
            }
        }
        y += 7 * (dot + gap) + 56
        figures(context, canvas, y, p, buildList {
            add(number(review.longestStreak) to context.getString(R.string.year_card_streak))
            if (review.minutesRead > 0) add(duration(context, review.minutesRead * 60L) to context.getString(R.string.year_time_reading))
        })
    }

    fun books(context: Context, review: YearInReview, chapters: Set<Int>, theme: ReaderTheme, font: ReaderFont, language: String): Bitmap = page(context, review.year, theme, font) { canvas, p, top ->
        var y = big(context, canvas, number(review.chaptersRead), context.getString(R.string.year_card_chapters), font, p, top) + 56
        val shares = YearInReview.bookShares(chapters)
        val track = fill(withAlpha(p.separator, 0.6f))
        val filled = fill(p.accent)
        for (row in 0 until 3) {
            for (column in 0 until 22) {
                val share = shares.getOrNull(row * 22 + column) ?: continue
                val x = PAD + column * 40f
                canvas.drawRoundRect(RectF(x, y, x + 32, y + 74), 5f, 5f, track)
                if (share > 0) canvas.drawRoundRect(RectF(x, y + 74 - (74 * share).toFloat(), x + 32, y + 74), 5f, 5f, filled)
            }
            y += 74 + 14
        }
        y += 42
        y = figures(context, canvas, y, p, listOf(
            number(review.booksOpened) to context.getString(R.string.year_card_books_opened),
            number(review.booksFinished) to context.getString(R.string.year_card_books_finished),
        )) + 56
        review.topBook?.let { book ->
            val paint = face(context, font, 40f, false, p.secondaryText)
            canvas.drawText(context.getString(R.string.year_most_read, BibleBooks.withNumber(book).name(language)), PAD, y - paint.fontMetrics.ascent, paint)
        }
    }

    fun duration(context: Context, seconds: Long): String {
        val (hours, minutes) = ReadingStats.hoursAndMinutes(seconds)
        return if (hours == 0) context.getString(R.string.duration_minutes, minutes) else context.getString(R.string.duration_hours_minutes, hours, minutes)
    }

    private data class Ink(val text: Int, val secondaryText: Int, val accent: Int, val separator: Int)

    private fun card(theme: ReaderTheme, draw: (Canvas, Ink) -> Unit): Bitmap {
        val palette = theme.palette
        val bitmap = Bitmap.createBitmap(WIDTH, HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(opaque(palette.background))
        draw(canvas, Ink(opaque(palette.text), opaque(palette.secondaryText), opaque(palette.accent), opaque(palette.separator)))
        return bitmap
    }

    /** The days and books cards: the title and the year across the top. */
    private fun page(context: Context, year: Int, theme: ReaderTheme, font: ReaderFont, draw: (Canvas, Ink, Float) -> Unit): Bitmap = card(theme) { canvas, p ->
        val title = sans(28f, true, p.accent, spacing = 0.1f)
        val baseline = PAD - title.fontMetrics.ascent
        canvas.drawText(context.getString(R.string.year_card_title), PAD, baseline, title)
        val yearPaint = face(context, font, 40f, true, p.secondaryText).apply { textAlign = Paint.Align.RIGHT }
        canvas.drawText(year.toString(), WIDTH - PAD, baseline, yearPaint)
        draw(canvas, p, baseline + title.fontMetrics.descent + 56)
    }

    private fun big(context: Context, canvas: Canvas, value: String, label: String, font: ReaderFont, p: Ink, top: Float): Float {
        val y = text(canvas, value, face(context, font, 150f, true, p.text), PAD, top) + 4
        return text(canvas, label, sans(40f, false, p.secondaryText), PAD, y)
    }

    private fun figures(context: Context, canvas: Canvas, top: Float, p: Ink, items: List<Pair<String, String>>): Float {
        var x = PAD
        var bottom = top
        for ((value, label) in items) {
            val valuePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD); textSize = 64f; color = p.text }
            val labelPaint = sans(30f, false, p.secondaryText)
            val y = text(canvas, value, valuePaint, x, top) + 6
            bottom = maxOf(bottom, text(canvas, label, labelPaint, x, y))
            x += maxOf(valuePaint.measureText(value), labelPaint.measureText(label)) + 60
        }
        return bottom
    }

    /** Draws a line from its top; the bottom it reached. */
    private fun text(canvas: Canvas, value: String, paint: TextPaint, x: Float, top: Float): Float {
        val layout = StaticLayout.Builder.obtain(value, 0, value.length, paint, (WIDTH - x - PAD).toInt().coerceAtLeast(1))
            .setAlignment(Layout.Alignment.ALIGN_NORMAL).setIncludePad(false).build()
        canvas.save()
        canvas.translate(x, top)
        layout.draw(canvas)
        canvas.restore()
        return top + layout.height
    }

    private fun face(context: Context, font: ReaderFont, size: Float, bold: Boolean, color: Int) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        val faces = font.faces
        typeface = if (faces == null) Typeface.create(if (font.isSans) Typeface.SANS_SERIF else Typeface.SERIF, if (bold) Typeface.BOLD else Typeface.NORMAL)
        else runCatching { Typeface.createFromAsset(context.assets, (if (bold) faces.bold else faces.regular) + ".ttf") }.getOrElse { Typeface.create(Typeface.SERIF, if (bold) Typeface.BOLD else Typeface.NORMAL) }
        textSize = size
        this.color = color
    }

    private fun sans(size: Float, bold: Boolean, color: Int, spacing: Float = 0f) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = Typeface.create(Typeface.SANS_SERIF, if (bold) Typeface.BOLD else Typeface.NORMAL)
        textSize = size
        letterSpacing = spacing
        this.color = color
    }

    private fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color }
    private fun number(value: Int): String = NumberFormat.getIntegerInstance().format(value)
    private fun opaque(rgb: Int): Int = 0xFF000000.toInt() or rgb
    private fun withAlpha(color: Int, alpha: Float): Int = ((alpha * 255).toInt() shl 24) or (color and 0x00FFFFFF)
}
