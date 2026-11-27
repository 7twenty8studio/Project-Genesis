package com.genesis.app.journal

import android.content.Context
import com.genesis.app.R
import com.genesis.app.prayer.JournalBible
import com.genesis.app.prayer.title
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.prayer.Prayer
import com.genesis.core.domain.prayer.PrayerCategory
import com.genesis.core.domain.prayer.PrayerPassage
import com.genesis.core.domain.sermons.Sermon
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.FormatStyle

/**
 * Gathers a sermon, a prayer or a stretch of the prayer journal into a
 * `JournalExport`, as JournalExportBuilder on iOS: verse text verbatim from
 * the Bible Premium tools use, with its abbreviation.
 */
internal class JournalExportBuilder(private val context: Context, private val bible: JournalBible) {
    suspend fun export(sermon: Sermon): JournalExport {
        val title = sermon.displayTitle ?: context.getString(R.string.sermon_notes)
        val date = JournalPdf.date(sermon.preachedAt, FormatStyle.LONG)
        val subtitle = sermon.churchName.let { if (it.isEmpty()) date else "$it · $date" }
        return JournalExport(title, subtitle, listOf(entry(sermon)))
    }

    suspend fun export(prayer: Prayer): JournalExport =
        JournalExport(prayer.displayTitle ?: context.getString(R.string.prayer), context.getString(R.string.from_my_prayer_journal), listOf(entry(prayer)))

    /** The prayers asked between two days (inclusive), optionally one category, oldest first. */
    suspend fun exportJournal(prayers: List<Prayer>, from: LocalDate, through: LocalDate, category: PrayerCategory?): JournalExport {
        val zone = ZoneId.systemDefault()
        val start = minOf(from, through).atStartOfDay(zone).toInstant().toEpochMilli()
        val end = maxOf(from, through).plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        val chosen = prayers
            .filter { it.hasContent && it.createdAt >= start && it.createdAt < end && (category == null || it.category == category) }
            .sortedBy { it.createdAt }
        fun day(date: LocalDate) = JournalPdf.date(date.atStartOfDay(zone).toInstant().toEpochMilli(), FormatStyle.MEDIUM)
        val range = "${day(from)} – ${day(through)}"
        val subtitle = category?.let { "${context.getString(it.title)} · $range" } ?: range
        return JournalExport(context.getString(R.string.prayer_journal), subtitle, chosen.map { entry(it) })
    }

    private suspend fun entry(sermon: Sermon) = JournalExport.Entry(
        title = sermon.displayTitle ?: context.getString(R.string.sermon_notes),
        details = listOf(
            JournalPdf.date(sermon.preachedAt, FormatStyle.FULL),
            listOf(sermon.preacher, sermon.church).map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" · "),
            sermon.series.orEmpty(),
        ),
        body = sermon.body,
        isMarkdown = true,
        passages = passages(sermon.passages),
    )

    private suspend fun entry(prayer: Prayer): JournalExport.Entry {
        val answer = if (prayer.isAnswered) {
            listOfNotNull(prayer.answeredAt?.let { JournalPdf.date(it, FormatStyle.LONG) }, prayer.answerNote?.trim())
                .filter { it.isNotEmpty() }.joinToString(" — ")
        } else {
            null
        }
        return JournalExport.Entry(
            title = prayer.displayTitle ?: context.getString(R.string.prayer),
            details = listOf(JournalPdf.date(prayer.createdAt, FormatStyle.FULL), context.getString(prayer.category.title)),
            body = prayer.body,
            answer = answer,
            passages = passages(prayer.passages),
        )
    }

    /** Each passage verbatim; one missing from the Bible is left out. */
    private suspend fun passages(passages: List<PrayerPassage>): List<JournalExport.Passage> = passages.mapNotNull { passage ->
        val ids = (passage.start.verse..passage.end.verse).map { VerseId(passage.start.book, passage.start.chapter, it) }
        val source = bible.export(ids) ?: return@mapNotNull null
        val verses = ids.mapNotNull { source.verses[it] }.distinctBy { it.id }
        if (verses.isEmpty()) return@mapNotNull null
        JournalExport.Passage(
            reference = passage.reference(source.language),
            translation = source.abbreviation,
            text = verses.joinToString(" ") { it.plainText },
            credit = source.credit,
        )
    }
}
