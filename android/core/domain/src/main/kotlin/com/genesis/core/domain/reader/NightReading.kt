package com.genesis.core.domain.reader

import com.genesis.core.domain.theme.ReaderTheme
import java.time.LocalDateTime
import java.time.ZonedDateTime

/** The theme the reader switches to at night ("At night, switch to"), as NightTheme.swift. */
enum class NightTheme(val id: String, val isPremium: Boolean) {
    OFF("off", false),
    NIGHT("night", false),
    /** Premium; without it the reader uses Night, keeping this choice. */
    STARLIGHT("starlight", true);

    /** The reader theme to use, null for Off. Starlight falls back to Night without Premium. */
    fun theme(premium: Boolean): ReaderTheme? = when (this) {
        OFF -> null
        NIGHT -> ReaderTheme.NIGHT
        STARLIGHT -> if (premium) ReaderTheme.STARLIGHT else ReaderTheme.NIGHT
    }
}

/** When night reading switches: with Dark Mode, or between two hours the person sets. */
enum class NightReadingTiming(val id: String) {
    DARK_MODE("darkMode"),
    HOURS("hours"),
}

/** Night reading: which theme, and when (with Dark Mode by default, or 8 pm to 6 am). */
data class NightReadingSchedule(
    val theme: NightTheme = NightTheme.OFF,
    val timing: NightReadingTiming = NightReadingTiming.DARK_MODE,
    /** The hour (0–23) night reading starts. */
    val startHour: Int = 20,
    /** The hour (0–23) it ends. The same as startHour means never. */
    val endHour: Int = 6,
)

/** Decides the reader's theme for night reading, as NightReading.swift. Pure. */
object NightReading {
    /** Whether the hour falls inside the night window; it may cross midnight; start == end is never night. */
    fun isNight(hour: Int, startHour: Int, endHour: Int): Boolean {
        if (startHour == endHour) return false
        return if (startHour < endHour) hour in startHour until endHour else hour >= startHour || hour < endHour
    }

    /** The night theme while Dark Mode is on (or inside the window), the day theme otherwise. */
    fun theme(schedule: NightReadingSchedule, dayTheme: ReaderTheme, now: LocalDateTime, systemIsDark: Boolean, premium: Boolean): ReaderTheme {
        val night = schedule.theme.theme(premium) ?: return dayTheme
        val nightNow = when (schedule.timing) {
            NightReadingTiming.DARK_MODE -> systemIsDark
            NightReadingTiming.HOURS -> isNight(now.hour, schedule.startHour, schedule.endHour)
        }
        return if (nightNow) night else dayTheme
    }

    /** When the window next opens or closes after `now`; null when off or following Dark Mode. */
    fun nextChange(now: ZonedDateTime, schedule: NightReadingSchedule): ZonedDateTime? {
        if (schedule.theme == NightTheme.OFF || schedule.timing != NightReadingTiming.HOURS || schedule.startHour == schedule.endHour) return null
        return listOf(schedule.startHour, schedule.endHour).map { hour ->
            val today = now.withHour(hour).withMinute(0).withSecond(0).withNano(0)
            if (today.isAfter(now)) today else today.plusDays(1)
        }.minOrNull()
    }
}
