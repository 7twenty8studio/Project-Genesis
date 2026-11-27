package com.genesis.app.journal

import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.LeadingMarginSpan
import android.text.style.RelativeSizeSpan
import android.text.style.StyleSpan
import androidx.core.content.FileProvider
import com.genesis.app.R
import com.genesis.core.domain.sermons.SermonMarkdown
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * Everything a journal PDF shows, gathered beforehand (verse text verbatim
 * from the Bible database), as JournalExport on iOS.
 */
data class JournalExport(
    val title: String,
    val subtitle: String,
    val entries: List<Entry>,
    val createdAt: Long = System.currentTimeMillis(),
) {
    data class Passage(
        /** "John 3:16", in the Bible's language. */
        val reference: String,
        /** The translation's abbreviation, e.g. "KJV". */
        val translation: String,
        /** Verbatim from the Bible database; never edited. */
        val text: String,
        /** The credit a licensed Bible asks for wherever its text goes; null for a public-domain Bible. */
        val credit: String? = null,
    )

    data class Entry(
        val title: String,
        /** Lines under the title: date, church and preacher, category. */
        val details: List<String> = emptyList(),
        val body: String = "",
        /** Sermon notes are Markdown; prayers plain text. */
        val isMarkdown: Boolean = false,
        /** How an answered prayer was answered. */
        val answer: String? = null,
        val passages: List<Passage> = emptyList(),
        /** Photos on the entry, drawn in (files on this device). */
        val photos: List<File> = emptyList(),
        /** Recordings and imported PDFs, listed by name, not included. */
        val listed: List<String> = emptyList(),
    )

    /** Verses for a passage from the Bible Premium tools use (never a YouVersion Bible's text). */
    data class Source(val verses: Map<com.genesis.core.domain.bible.VerseId, com.genesis.core.bible.Verse>, val abbreviation: String, val language: String, val credit: String?)
}

/**
 * Draws a `JournalExport` as a PDF, as JournalPDFRenderer on iOS: a title
 * page, each entry with its passages, and "Made with Versely" on every page.
 * Letter in the US and Canada, A4 elsewhere.
 */
object JournalPdf {
    private const val INK = 0xFF2B2420.toInt()
    private const val QUIET = 0xFF7A6E64.toInt()
    private const val ACCENT = 0xFF9A5B34.toInt()

    fun render(context: Context, export: JournalExport, file: File) {
        val region = Locale.getDefault().country
        val (width, height) = if (region == "US" || region == "CA") 612 to 792 else 595 to 842
        val writer = Writer(context, width, height)
        writer.titlePage(export)
        export.entries.forEachIndexed { index, entry -> writer.entry(entry, index == 0) }
        writer.finish(file)
    }

    /** Writes the PDF in the app's cache and opens Android's share sheet for it. */
    suspend fun share(context: Context, export: JournalExport) {
        val file = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            val folder = File(context.cacheDir, "exports").apply { mkdirs() }
            folder.listFiles()?.forEach { it.delete() }
            File(folder, fileName(export.title)).also { render(context, export, it) }
        }
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
        val send = Intent(Intent.ACTION_SEND).apply {
            type = "application/pdf"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_TITLE, export.title)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, export.title).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** "Grace upon grace.pdf", safe as a file name. */
    fun fileName(title: String): String {
        val cleaned = title.replace(Regex("[/\\\\:?%*|\"<>\\p{Cntrl}]"), " ").split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")
        return cleaned.take(80).trim().ifEmpty { "Versely" } + ".pdf"
    }

    fun date(millis: Long, style: FormatStyle): String =
        DateTimeFormatter.ofLocalizedDate(style).withLocale(Locale.getDefault()).format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))

    private class Writer(private val context: Context, private val width: Int, private val height: Int) {
        private val document = PdfDocument()
        private val margin = 64f
        private val footerSpace = 40f
        private val contentWidth = (width - margin * 2).toInt()
        private val bottom get() = height - margin - footerSpace + 24f
        private var page: PdfDocument.Page? = null
        private var canvas: Canvas? = null
        private var y = margin
        private var number = 0
        private var empty = true

        private val serif = Typeface.SERIF

        private fun paint(size: Float, color: Int = INK, bold: Boolean = false, italic: Boolean = false) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            this.color = color
            typeface = Typeface.create(serif, when {
                bold && italic -> Typeface.BOLD_ITALIC
                bold -> Typeface.BOLD
                italic -> Typeface.ITALIC
                else -> Typeface.NORMAL
            })
            // Ligatures off, so the text copies out of the PDF exactly.
            fontFeatureSettings = "'liga' 0, 'clig' 0"
        }

        private fun beginPage() {
            page?.let { document.finishPage(it) }
            number += 1
            val next = document.startPage(PdfDocument.PageInfo.Builder(width, height, number).create())
            page = next
            canvas = next.canvas.also { it.drawColor(Color.WHITE) }
            y = margin
            empty = true
            footer()
        }

        private fun footer() {
            val c = canvas ?: return
            val baseline = height - margin / 2 - 6f
            val small = paint(8.5f, QUIET, italic = true).apply { textAlign = Paint.Align.CENTER }
            c.drawText(context.getString(R.string.made_with_versely), width / 2f, baseline, small)
            if (number > 1) {
                val right = paint(9f, QUIET).apply { textAlign = Paint.Align.RIGHT }
                c.drawText(number.toString(), width - margin, baseline, right)
            }
        }

        private fun ensureSpace(needed: Float) {
            if (bottom - y < needed && !empty) beginPage()
        }

        /** Text that flows across pages, line by line. */
        private fun text(content: CharSequence, paint: TextPaint, after: Float = 6f, alignment: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL, indent: Int = 0, spacing: Float = 1.25f) {
            if (content.isEmpty()) return
            val layout = StaticLayout.Builder.obtain(content, 0, content.length, paint, contentWidth - indent)
                .setAlignment(alignment)
                .setLineSpacing(0f, spacing)
                .setIncludePad(false)
                .build()
            var line = 0
            while (line < layout.lineCount) {
                if (page == null) beginPage()
                // As many lines as fit on this page.
                val top = layout.getLineTop(line)
                var last = line
                while (last + 1 < layout.lineCount && layout.getLineBottom(last + 1) - top <= bottom - y) last++
                val sliceHeight = layout.getLineBottom(last) - top
                if (sliceHeight > bottom - y && !empty) {
                    beginPage()
                    continue
                }
                val c = canvas!!
                c.save()
                c.translate(margin + indent, y - top)
                c.clipRect(0f, top.toFloat(), (contentWidth - indent).toFloat(), layout.getLineBottom(last).toFloat())
                layout.draw(c)
                c.restore()
                y += sliceHeight
                empty = false
                line = last + 1
                if (line < layout.lineCount) beginPage()
            }
            y += after
        }

        private fun rule(length: Float) {
            val c = canvas ?: return
            val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ACCENT; strokeWidth = 0.8f }
            c.drawLine(width / 2f - length / 2, y, width / 2f + length / 2, y, stroke)
        }

        private fun label(title: String) {
            ensureSpace(60f)
            y += 10f
            text(title.uppercase(Locale.getDefault()), paint(9.5f, ACCENT, bold = true).apply { letterSpacing = 0.08f }, after = 6f)
        }

        fun titlePage(export: JournalExport) {
            beginPage()
            y = margin + (bottom - margin) * 0.3f
            rule(60f)
            y += 28f
            text(export.title, paint(30f, bold = true), after = 10f, alignment = Layout.Alignment.ALIGN_CENTER, spacing = 1.1f)
            if (export.subtitle.isNotEmpty()) {
                text(export.subtitle, paint(14f, QUIET, italic = true), after = 10f, alignment = Layout.Alignment.ALIGN_CENTER)
            }
            y += 18f
            rule(60f)
            y += 18f
            text(date(export.createdAt, FormatStyle.LONG), paint(11f, QUIET), alignment = Layout.Alignment.ALIGN_CENTER)
        }

        fun entry(entry: JournalExport.Entry, first: Boolean) {
            if (first) {
                beginPage()
            } else {
                ensureSpace(180f)
                if (!empty) {
                    y += 20f
                    rule(40f)
                    y += 24f
                }
            }
            text(entry.title, paint(20f, bold = true), after = 6f, spacing = 1.1f)
            entry.details.filter { it.isNotBlank() }.forEach { text(it, paint(10.5f, QUIET), after = 2f) }
            y += 12f
            if (entry.body.isNotBlank()) {
                if (entry.isMarkdown) markdown(entry.body) else text(entry.body.trim(), paint(12f), after = 8f)
            }
            entry.answer?.takeIf { it.isNotBlank() }?.let {
                label(context.getString(R.string.answered))
                text(it, paint(12f, italic = true), after = 8f)
            }
            passages(entry.passages)
            attachments(entry)
        }

        private fun attachments(entry: JournalExport.Entry) {
            if (entry.photos.isEmpty() && entry.listed.isEmpty()) return
            label(context.getString(R.string.attachments))
            entry.photos.forEach { file ->
                val bitmap = runCatching { android.graphics.BitmapFactory.decodeFile(file.path) }.getOrNull() ?: return@forEach
                val scale = minOf(contentWidth.toFloat() / bitmap.width, 320f / bitmap.height, 1f)
                val w = bitmap.width * scale
                val h = bitmap.height * scale
                ensureSpace(h + 12f)
                if (page == null) beginPage()
                canvas!!.drawBitmap(bitmap, null, android.graphics.RectF(margin, y, margin + w, y + h), Paint(Paint.FILTER_BITMAP_FLAG))
                bitmap.recycle()
                y += h + 12f
                empty = false
            }
            entry.listed.forEach { text("• $it", paint(11f, QUIET), after = 3f, indent = 14) }
            y += 6f
        }

        private fun markdown(body: String) {
            SermonMarkdown.blocks(body).forEach { block ->
                val line = SpannableStringBuilder()
                SermonMarkdown.spans(block.text).forEach { span ->
                    val start = line.length
                    line.append(span.text)
                    val style = when {
                        span.bold && span.italic -> Typeface.BOLD_ITALIC
                        span.bold -> Typeface.BOLD
                        span.italic -> Typeface.ITALIC
                        else -> null
                    }
                    style?.let { line.setSpan(StyleSpan(it), start, line.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE) }
                }
                when (val kind = block.kind) {
                    SermonMarkdown.BlockKind.Heading -> {
                        line.setSpan(StyleSpan(Typeface.BOLD), 0, line.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        line.setSpan(RelativeSizeSpan(1.25f), 0, line.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        ensureSpace(50f)
                        y += 6f
                        text(line, paint(12f), after = 4f)
                    }
                    SermonMarkdown.BlockKind.Bullet -> text(hanging("•", line), paint(12f), after = 4f)
                    is SermonMarkdown.BlockKind.Numbered -> text(hanging("${kind.number}.", line), paint(12f), after = 4f)
                    SermonMarkdown.BlockKind.Quote -> {
                        line.setSpan(StyleSpan(Typeface.ITALIC), 0, line.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        text(line, paint(12f, QUIET), after = 6f, indent = 18)
                    }
                    SermonMarkdown.BlockKind.Paragraph -> text(line, paint(12f), after = 8f)
                }
            }
        }

        /** "• Item" with the item's later lines lined up under its first word. */
        private fun hanging(marker: String, line: SpannableStringBuilder): CharSequence {
            val prefix = "$marker  "
            val markerWidth = paint(12f).measureText(prefix).toInt()
            return SpannableStringBuilder(prefix).append(line).apply {
                setSpan(LeadingMarginSpan.Standard(14, 14 + markerWidth), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            }
        }

        private fun passages(passages: List<JournalExport.Passage>) {
            if (passages.isEmpty()) return
            label(context.getString(R.string.pdf_passages))
            passages.forEach { passage ->
                ensureSpace(60f)
                text("${passage.reference} · ${passage.translation}", paint(10.5f, ACCENT, bold = true), after = 3f, indent = 14)
                text(passage.text, paint(12f), after = 10f, indent = 14)
            }
            // Each licensed Bible's credit once, after its passages.
            passages.mapNotNull { it.credit }.distinct().forEach {
                ensureSpace(40f)
                text(it, paint(9f, QUIET), after = 8f, indent = 14)
            }
        }

        fun finish(file: File) {
            page?.let { document.finishPage(it) }
            page = null
            file.outputStream().use { document.writeTo(it) }
            document.close()
        }
    }
}
