package com.genesis.core.domain.notifications

import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.link.GenesisLink
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime

/**
 * The kinds of notification Versely sends, each with its own switch in
 * Settings › Notifications, as ReminderKind on iOS (same raw values, so the
 * saved keys read the same). Memorize, Sunday sermon notes, the weekly
 * recap and the group kinds join as their features arrive on Android.
 */
enum class ReminderKind(val rawValue: String, val hasTime: Boolean, val isOnByDefault: Boolean, val defaultMinutes: Int) {
    VERSE_OF_THE_DAY("verseOfTheDay", true, false, 7 * 60),
    DAILY_READING("dailyReading", true, false, 20 * 60),
    READING_PLAN("readingPlan", true, false, 8 * 60),
    PRAYER("prayer", false, true, 0),
    PRAYER_ANNIVERSARY("prayerAnniversary", true, true, 9 * 60),
}

/** Which kinds are on (the master switch included) and their times, in minutes after midnight. */
data class NotificationSettings(val enabled: Set<ReminderKind>, val minutes: Map<ReminderKind, Int> = emptyMap()) {
    fun minutes(kind: ReminderKind): Int = minutes[kind] ?: kind.defaultMinutes
}

/** Everything the planner needs, as plain values. */
data class NotificationInput(
    val now: LocalDateTime,
    val settings: NotificationSettings,
    /** Each coming day's verse, verbatim from the person's Bible. */
    val dailyVerses: Map<LocalDate, VerseText> = emptyMap(),
    /** Days with reading. */
    val readingDays: Set<LocalDate> = emptySet(),
    /** The active plan's title, and each coming day's unfinished reading. */
    val planTitle: String? = null,
    val planReadings: Map<LocalDate, String> = emptyMap(),
    val answeredPrayers: List<AnsweredPrayer> = emptyList(),
) {
    data class VerseText(val reference: String, val text: String, val verse: VerseId)
    data class AnsweredPrayer(val title: String, val answeredOn: LocalDate)
}

/** What a notification says; the app puts it into words in the person's language. */
sealed interface ReminderMessage {
    data class VerseOfTheDay(val reference: String, val text: String) : ReminderMessage
    data class Streak(val days: Int) : ReminderMessage
    data object TwoDaysInARow : ReminderMessage
    data object WelcomeBack : ReminderMessage
    /** One of four gentle invitations, rotating by day. */
    data class Invitation(val index: Int) : ReminderMessage
    data class PlanReading(val planTitle: String, val reading: String) : ReminderMessage
    data class Anniversary(val years: Int, val title: String, val more: Int) : ReminderMessage
}

data class PlannedNotification(
    val id: String,
    val kind: ReminderKind,
    val fireAt: LocalDateTime,
    val message: ReminderMessage,
    /** Where a tap goes (a versely:// link). */
    val link: String,
)

/**
 * Decides which notifications to schedule for the next week, as
 * NotificationPlanner on iOS. Pure, so it's tested without the system.
 * The week is rebuilt whenever Versely opens or leaves the screen, a
 * reminder fires or the settings change, so reading today drops today's
 * nudge and ticking off a plan day drops its reminder. Kind, never guilt.
 */
object NotificationPlanner {
    const val ID_PREFIX = "versely.reminder."
    const val HORIZON_DAYS = 7
    const val INVITATIONS = 4

    fun plan(input: NotificationInput): List<PlannedNotification> {
        val today = input.now.toLocalDate()
        val planned = mutableListOf<PlannedNotification>()
        for (offset in 0 until HORIZON_DAYS) {
            val day = today.plusDays(offset.toLong())
            for (kind in ReminderKind.entries) {
                if (!kind.hasTime || kind !in input.settings.enabled) continue
                val fire = day.atTime(LocalTime.MIN).plusMinutes(input.settings.minutes(kind).toLong())
                if (!fire.isAfter(input.now)) continue
                val id = ID_PREFIX + kind.rawValue + "." + day
                val message: ReminderMessage
                val link: String
                when (kind) {
                    ReminderKind.VERSE_OF_THE_DAY -> {
                        val verse = input.dailyVerses[day] ?: continue
                        message = ReminderMessage.VerseOfTheDay(verse.reference, verse.text)
                        link = GenesisLink.read(verse.verse)
                    }
                    ReminderKind.DAILY_READING -> {
                        if (day in input.readingDays) continue
                        message = readingMessage(offset, day, input)
                        link = GenesisLink.CONTINUE_READING
                    }
                    ReminderKind.READING_PLAN -> {
                        val title = input.planTitle ?: continue
                        val reading = input.planReadings[day] ?: continue
                        message = ReminderMessage.PlanReading(title, reading)
                        link = GenesisLink.PLANS
                    }
                    ReminderKind.PRAYER_ANNIVERSARY -> {
                        message = anniversary(day, input.answeredPrayers) ?: continue
                        link = GenesisLink.PRAYER
                    }
                    ReminderKind.PRAYER -> continue
                }
                planned += PlannedNotification(id, kind, fire, message, link)
            }
        }
        return planned.sortedBy { it.fireAt }
    }

    /** Today's can mention the streak or a return after a break; later days rotate gentle invitations. */
    fun readingMessage(dayOffset: Int, day: LocalDate, input: NotificationInput): ReminderMessage {
        if (dayOffset == 0) {
            val streak = streak(input.readingDays, day)
            if (streak >= 2) return ReminderMessage.Streak(streak)
            if (streak == 1) return ReminderMessage.TwoDaysInARow
            val last = input.readingDays.maxOrNull()
            if (last != null && java.time.temporal.ChronoUnit.DAYS.between(last, day) >= 3) return ReminderMessage.WelcomeBack
        }
        // iOS counts the day's place in the era (1 January of year 1 is day 1).
        val ordinality = day.toEpochDay() + 719_163
        return ReminderMessage.Invitation(Math.floorMod(ordinality, INVITATIONS.toLong()).toInt())
    }

    /** Consecutive days read, ending today or yesterday. */
    fun streak(readingDays: Set<LocalDate>, today: LocalDate): Int {
        var day = if (today in readingDays) today else today.minusDays(1)
        var count = 0
        while (day in readingDays) {
            count++
            day = day.minusDays(1)
        }
        return count
    }

    /**
     * Prayers answered on this day of the year, a year or more ago: the
     * oldest, with how many more. 29 February is remembered on the 28th in
     * other years.
     */
    fun anniversary(day: LocalDate, prayers: List<NotificationInput.AnsweredPrayer>): ReminderMessage.Anniversary? {
        val matches = prayers.mapNotNull { prayer ->
            val answered = prayer.answeredOn
            if (day.year <= answered.year) return@mapNotNull null
            val sameDay = answered.monthValue == day.monthValue && answered.dayOfMonth == day.dayOfMonth
            val leapDay = !day.isLeapYear && answered.monthValue == 2 && answered.dayOfMonth == 29 && day.monthValue == 2 && day.dayOfMonth == 28
            if (sameDay || leapDay) prayer to day.year - answered.year else null
        }.sortedBy { it.first.answeredOn }
        val (first, years) = matches.firstOrNull() ?: return null
        return ReminderMessage.Anniversary(years, first.title.take(80), matches.size - 1)
    }

    /** Whether a prayer's own reminder belongs on the schedule, and when it next rings. */
    fun prayerReminder(isAnswered: Boolean, reminderAt: LocalDateTime?, repeatsDaily: Boolean, now: LocalDateTime): LocalDateTime? {
        if (isAnswered || reminderAt == null) return null
        if (!repeatsDaily) return reminderAt.takeIf { it.isAfter(now) }
        val today = now.toLocalDate().atTime(reminderAt.toLocalTime())
        return if (today.isAfter(now)) today else today.plusDays(1)
    }
}
