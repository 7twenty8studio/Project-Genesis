package com.genesis.core.domain.prayer

import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId

/**
 * "Your prayer life", as PrayerStatistics on iOS: counts, answered share,
 * categories and how long answers took. Prayers left empty don't count.
 */
data class PrayerStatistics(
    val total: Int,
    val answered: Int,
    val active: Int,
    /** Most prayed-for first (ties in category order); categories with none are left out. */
    val byCategory: List<Pair<PrayerCategory, Int>>,
    /** Mean days from asking to the answer, over answered prayers with a date. */
    val averageDaysToAnswer: Double?,
) {
    /** Answered, as a whole percentage of all requests (0 with none). */
    val answeredPercent: Int get() = if (total == 0) 0 else Math.round(answered.toDouble() / total * 100).toInt()

    /** The average wait in whole days (0 means within a day). */
    val averageAnswerDays: Int? get() = averageDaysToAnswer?.let { kotlin.math.floor(it).toInt() }

    companion object {
        fun of(prayers: List<Prayer>): PrayerStatistics {
            val counted = prayers.filter { it.hasContent }
            val answered = counted.count { it.isAnswered }
            val counts = counted.groupingBy { it.category }.eachCount()
            val byCategory = PrayerCategory.entries.mapNotNull { category -> counts[category]?.let { category to it } }
                .sortedByDescending { it.second }
            val waits = counted.mapNotNull { prayer ->
                val at = prayer.answeredAt?.takeIf { prayer.isAnswered } ?: return@mapNotNull null
                maxOf(0L, at - prayer.createdAt) / 86_400_000.0
            }
            return PrayerStatistics(
                total = counted.size,
                answered = answered,
                active = counted.size - answered,
                byCategory = byCategory,
                averageDaysToAnswer = if (waits.isEmpty()) null else waits.average(),
            )
        }
    }
}

/**
 * The journal as a story, as PrayerTimeline on iOS: each prayer where it was
 * asked and, once answered, where the answer came. Months newest first.
 */
object PrayerTimeline {
    enum class Kind { ASKED, ANSWERED }

    data class Entry(val prayer: Prayer, val kind: Kind, val date: Long)

    data class Month(val month: YearMonth, val entries: List<Entry>)

    fun months(prayers: List<Prayer>, zone: ZoneId): List<Month> {
        val entries = prayers.filter { it.hasContent }.flatMap { prayer ->
            listOfNotNull(
                Entry(prayer, Kind.ASKED, prayer.createdAt),
                prayer.answeredAt?.takeIf { prayer.isAnswered }?.let { Entry(prayer, Kind.ANSWERED, it) },
            )
        }
        return entries.groupBy { YearMonth.from(Instant.ofEpochMilli(it.date).atZone(zone)) }
            .map { (month, items) ->
                // Newest first; an answer before its asking at the same instant.
                Month(month, items.sortedWith(compareByDescending<Entry> { it.date }.thenBy { if (it.kind == Kind.ANSWERED) 0 else 1 }))
            }
            .sortedByDescending { it.month }
    }
}

/**
 * Days in a row with prayer, as PrayerStreak on iOS: adding a request,
 * marking one prayed or answered, or "I prayed today". A missed day just
 * starts again; today or through yesterday counts, as the reading streak.
 */
object PrayerStreak {
    /** Days kept in the "I prayed today" log; older ones aren't needed. */
    const val KEPT_DAYS = 400L

    fun days(log: Set<LocalDate>, prayers: List<Prayer>, zone: ZoneId): Set<LocalDate> = buildSet {
        addAll(log)
        fun day(millis: Long) = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()
        for (prayer in prayers) {
            if (!prayer.hasContent) continue
            add(day(prayer.createdAt))
            prayer.answeredAt?.let { add(day(it)) }
            prayer.lastPrayedAt?.let { add(day(it)) }
        }
    }

    fun length(days: Set<LocalDate>, today: LocalDate): Int {
        var day = if (today in days) today else today.minusDays(1)
        var count = 0
        while (day in days) {
            count++
            day = day.minusDays(1)
        }
        return count
    }

    /** "yyyy-MM-dd" days separated by commas, as iOS keeps the log. */
    fun decodeLog(raw: String): Set<LocalDate> =
        raw.split(',').mapNotNull { runCatching { LocalDate.parse(it.trim()) }.getOrNull() }.toSet()

    /** The log with `today` added, keeping only recent days. */
    fun recording(today: LocalDate, raw: String): String {
        val oldest = today.minusDays(KEPT_DAYS)
        return (decodeLog(raw) + today).filter { it >= oldest }.sorted().joinToString(",")
    }
}
