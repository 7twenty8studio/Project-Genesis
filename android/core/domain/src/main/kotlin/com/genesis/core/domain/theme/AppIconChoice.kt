package com.genesis.core.domain.theme

import java.time.LocalDate

/**
 * Settings › App Icon (AppIconChoice on iOS): the standard icon, Night, the
 * four seasons, or Seasons to change with the calendar. The standard icon is
 * free; the rest come with Premium (`.premiumThemes`).
 */
enum class AppIconChoice(val rawValue: String) {
    STANDARD("standard"), NIGHT("night"), AUTUMN("autumn"), WINTER("winter"), SPRING("spring"), SUMMER("summer"), SEASONS("seasons");

    val isPremium: Boolean get() = this != STANDARD

    /** The icon shown on a date (Seasons follows the calendar and where the person lives). */
    fun icon(date: LocalDate = LocalDate.now(), region: String? = java.util.Locale.getDefault().country): AppIconChoice = when (this) {
        SEASONS -> when (Season.current(date, region)) {
            Season.AUTUMN -> AUTUMN
            Season.WINTER -> WINTER
            Season.SPRING -> SPRING
            Season.SUMMER -> SUMMER
        }
        else -> this
    }

    /** What's shown without Premium: the standard icon. */
    fun shown(premium: Boolean): AppIconChoice = if (isPremium && !premium) STANDARD else this

    companion object {
        fun of(raw: String?): AppIconChoice = entries.firstOrNull { it.rawValue == raw } ?: STANDARD
    }
}
