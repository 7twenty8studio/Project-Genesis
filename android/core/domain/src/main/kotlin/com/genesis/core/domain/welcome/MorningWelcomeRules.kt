package com.genesis.core.domain.welcome

import java.time.LocalDate

/**
 * The Premium morning welcome's rules, as MorningWelcome.swift: shown the
 * first time Versely opens each day for a Premium member who has it on.
 */
object MorningWelcomeRules {
    fun shouldShow(isEnabled: Boolean, isOn: Boolean, isPremium: Boolean, lastShownDay: String?, today: String): Boolean =
        isEnabled && isOn && isPremium && lastShownDay != today

    /** "2026-10-06" in the person's own calendar day. */
    fun dayKey(date: LocalDate): String = "%04d-%02d-%02d".format(date.year, date.monthValue, date.dayOfMonth)

    /** The first word of a name, trimmed ("Jeovanni Santos" → "Jeovanni"); null when empty. */
    fun firstName(name: String?): String? =
        name?.trim()?.split(Regex("\\s+"))?.firstOrNull()?.takeIf { it.isNotEmpty() }
}
