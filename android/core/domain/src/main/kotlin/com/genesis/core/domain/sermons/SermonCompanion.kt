package com.genesis.core.domain.sermons

import com.genesis.core.domain.prayer.PrayerPassage
import java.text.Normalizer
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

/**
 * Notes from a sermon, as Sermon on iOS (synced as sermons): who preached,
 * where, when, the passages (verse ids only, never the text) and the notes
 * as Markdown. Free for everyone, with no limits. `sourceSermonId` and
 * `handoutsJson` come from the iPhone (church sermons) and are kept as they are.
 */
data class Sermon(
    val id: String,
    val title: String = "",
    val preacher: String = "",
    val church: String = "",
    val preachedAt: Long,
    val series: String? = null,
    val body: String = "",
    val passages: List<PrayerPassage> = emptyList(),
    val isFavourite: Boolean = false,
    val sourceSermonId: String? = null,
    val handoutsJson: String? = null,
    val createdAt: Long,
    val updatedAt: Long,
) {
    val hasContent: Boolean
        get() = listOf(title, preacher, body).any { it.isNotBlank() } || passages.isNotEmpty()

    /** The title, else the notes' first line; null for "Sermon Notes". */
    val displayTitle: String?
        get() = title.trim().ifEmpty { null }
            ?: SermonMarkdown.plainText(body).split("\n").firstOrNull { it.isNotBlank() }?.trim()

    val churchName: String get() = church.trim()

    companion object {
        /** The most passages one sermon keeps. */
        const val MAXIMUM_PASSAGES = 30
    }
}

/** Search across the title, preacher, church, series and notes (case and accents aside). */
object SermonSearch {
    fun matches(sermon: Sermon, query: String): Boolean {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return true
        val key = SermonGrouping.fold(trimmed)
        return listOf(sermon.title, sermon.preacher, sermon.church, sermon.series.orEmpty(), SermonMarkdown.plainText(sermon.body))
            .any { SermonGrouping.fold(it).contains(key) }
    }
}

/** The list's sections: by date (this week, then by month) or by church. */
object SermonGrouping {
    enum class Mode { DATE, CHURCH }

    sealed interface Kind {
        data object ThisWeek : Kind
        data class Month(val month: YearMonth) : Kind
        data class Church(val name: String) : Kind
        data object NoChurch : Kind
    }

    data class Section(val kind: Kind, val sermons: List<Sermon>)

    private val newestFirst = compareByDescending<Sermon> { it.preachedAt }.thenBy { it.id }

    /** Sermons with content that match the search and the favourites filter, newest first. */
    fun visible(sermons: List<Sermon>, query: String, favouritesOnly: Boolean): List<Sermon> =
        sermons.filter { it.hasContent && (!favouritesOnly || it.isFavourite) && SermonSearch.matches(it, query) }.sortedWith(newestFirst)

    fun sections(sermons: List<Sermon>, mode: Mode, today: LocalDate = LocalDate.now(), zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): List<Section> =
        when (mode) {
            Mode.DATE -> byDate(sermons, today, zone, locale)
            Mode.CHURCH -> byChurch(sermons)
        }

    /** "This Week" first (and anything dated later), then each earlier month, newest first. */
    fun byDate(sermons: List<Sermon>, today: LocalDate, zone: ZoneId, locale: Locale = Locale.getDefault()): List<Section> {
        val weekStart = today.with(TemporalAdjusters.previousOrSame(WeekFields.of(locale).firstDayOfWeek))
        val grouped = sermons.groupBy { sermon ->
            val day = Instant.ofEpochMilli(sermon.preachedAt).atZone(zone).toLocalDate()
            if (!day.isBefore(weekStart)) Kind.ThisWeek else Kind.Month(YearMonth.from(day))
        }
        return grouped.map { (kind, members) -> Section(kind, members.sortedWith(newestFirst)) }
            .sortedWith(compareBy<Section> { if (it.kind == Kind.ThisWeek) 0 else 1 }.thenByDescending { (it.kind as? Kind.Month)?.month })
    }

    /** One section per church (spelling and case aside), A to Z, then sermons with no church. */
    fun byChurch(sermons: List<Sermon>): List<Section> =
        sermons.groupBy { churchKey(it.church) }.map { (key, members) ->
            val sorted = members.sortedWith(newestFirst)
            Section(if (key.isEmpty()) Kind.NoChurch else Kind.Church(sorted.first().churchName), sorted)
        }.sortedWith(compareBy<Section> { it.kind == Kind.NoChurch }.thenBy { fold((it.kind as? Kind.Church)?.name.orEmpty()) })

    /** Churches written before, most recent first, matching what's typed (and not just repeating it). */
    fun churchSuggestions(sermons: List<Sermon>, typed: String, limit: Int = 4): List<String> {
        val typedKey = churchKey(typed)
        val seen = mutableSetOf<String>()
        val result = mutableListOf<String>()
        for (sermon in sermons.sortedWith(newestFirst)) {
            val key = churchKey(sermon.church)
            if (key.isEmpty() || key == typedKey || !seen.add(key)) continue
            if (typedKey.isEmpty() || key.contains(typedKey)) result += sermon.churchName
            if (result.size == limit) break
        }
        return result
    }

    /** Case, accents and spacing don't matter. */
    fun churchKey(name: String): String = fold(name).split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")

    internal fun fold(text: String): String =
        Normalizer.normalize(text.lowercase(), Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
}

/** The small "Sermon Notes" card on Home: Sunday mornings only (5 to 2). */
object SermonSunday {
    fun isSundayMorning(day: DayOfWeek, hour: Int): Boolean = day == DayOfWeek.SUNDAY && hour in 5 until 14
}
