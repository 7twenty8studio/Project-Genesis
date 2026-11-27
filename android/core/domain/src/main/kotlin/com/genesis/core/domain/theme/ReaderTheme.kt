package com.genesis.core.domain.theme

import java.time.LocalDate

/** Resolved colours for one theme as 0xRRGGBB, usable by Compose and by widgets. */
data class ThemePalette(
    val background: Int,
    val surface: Int,
    val text: Int,
    val secondaryText: Int,
    val accent: Int,
    val separator: Int,
)

/**
 * The reading themes, with the same names, colours and Premium rules as
 * ReaderTheme.swift. Auto, Paper, Sepia, Slate, Contrast and Night stay free,
 * so a readable light, dark, night and high-contrast choice is always there.
 */
enum class ReaderTheme {
    AUTOMATIC, PAPER, CREAM, SEPIA, PARCHMENT, SLATE, HIGH_CONTRAST,
    NIGHT, MIDNIGHT, STARLIGHT, SAGE,
    SEASONS, AUTUMN, WINTER, SPRING, SUMMER,
    FOREST, OCEAN, HEARTH;

    val isDark: Boolean
        get() = this in setOf(SLATE, HIGH_CONTRAST, NIGHT, MIDNIGHT, STARLIGHT, FOREST, OCEAN, HEARTH)

    val isPremium: Boolean
        get() = this !in setOf(AUTOMATIC, PAPER, SEPIA, SLATE, HIGH_CONTRAST, NIGHT)

    /** The season a theme shows (Seasons resolved first), for its leaves, snow, blossom or sunlight. */
    val season: Season?
        get() = when (this) {
            AUTUMN -> Season.AUTUMN
            WINTER -> Season.WINTER
            SPRING -> Season.SPRING
            SUMMER -> Season.SUMMER
            else -> null
        }

    /** Forest, Ocean and Hearth: a picture behind the words. */
    val isScene: Boolean get() = this == FOREST || this == OCEAN || this == HEARTH

    /** Starlight's moving night sky. */
    val hasStars: Boolean get() = this == STARLIGHT

    /** Auto follows the system's dark mode; Seasons follows the time of year. */
    fun resolved(systemIsDark: Boolean, date: LocalDate = LocalDate.now(), region: String? = null): ReaderTheme = when (this) {
        AUTOMATIC -> if (systemIsDark) SLATE else PAPER
        SEASONS -> Season.current(date, region).theme
        else -> this
    }

    val palette: ThemePalette
        get() = when (this) {
            AUTOMATIC, PAPER -> ThemePalette(0xFBF8F1, 0xF3EEE3, 0x2B2A27, 0x7D776B, 0xA8844E, 0xE4DDCD)
            CREAM -> ThemePalette(0xF6EFDF, 0xEDE4CF, 0x2F2B24, 0x7E7564, 0xA07C44, 0xE0D5BD)
            SEPIA -> ThemePalette(0xEFE3CC, 0xE5D6BA, 0x44372A, 0x806D57, 0x94703C, 0xD9C8A8)
            PARCHMENT -> ThemePalette(0xE9DCC0, 0xDFD0B0, 0x3B3225, 0x76694F, 0x6F7042, 0xD2C19D)
            SLATE -> ThemePalette(0x1E2226, 0x272C31, 0xDAD5C8, 0x8D9196, 0xC9A96E, 0x353B41)
            HIGH_CONTRAST -> ThemePalette(0x000000, 0x141414, 0xFFFFFF, 0xC8C8C8, 0xF0CF86, 0x3A3A3A)
            // Night: warm, dim and easy on tired eyes (text about 10:1).
            NIGHT -> ThemePalette(0x1F1A16, 0x29231E, 0xD4C2A2, 0x9C8C78, 0xB89466, 0x3A322B)
            MIDNIGHT -> ThemePalette(0x161B26, 0x1E2432, 0xD6D9E0, 0x8A91A0, 0xB9A77C, 0x2C3342)
            STARLIGHT -> ThemePalette(0x111A2C, 0x18233A, 0xC9CFDB, 0x8E98AB, 0xB8A97F, 0x26324A)
            SAGE -> ThemePalette(0xEEF0E6, 0xE3E7D8, 0x2C3128, 0x6F7866, 0x6E7F5A, 0xD3D9C4)
            SEASONS -> Season.current().theme.palette
            AUTUMN -> ThemePalette(0xF3E8D6, 0xEADBC3, 0x36291F, 0x80695A, 0xA65F34, 0xDDCAAE)
            WINTER -> ThemePalette(0xEEF1F2, 0xE2E7EA, 0x262C33, 0x6E7782, 0x5D7A8E, 0xD3DADF)
            SPRING -> ThemePalette(0xF6EFEC, 0xEDE2DE, 0x2F2A2B, 0x7C7072, 0xA86F7E, 0xE3D5D1)
            SUMMER -> ThemePalette(0xF5EFE1, 0xEBE2CF, 0x2C2B25, 0x76725F, 0x4E8481, 0xDDD3BC)
            FOREST -> ThemePalette(0x192D27, 0x213A33, 0xF1EBDA, 0xB9C2B0, 0xA9BE9A, 0x2C463E)
            OCEAN -> ThemePalette(0x1B2632, 0x223040, 0xEAF0F5, 0xA3B2C0, 0x9DB5C7, 0x2E3D4D)
            HEARTH -> ThemePalette(0x211A17, 0x2B231F, 0xF2E6D4, 0xB7A28C, 0xD49A6A, 0x3A302A)
        }
}

/** A season of the year, for the seasonal themes. */
enum class Season(val theme: ReaderTheme) {
    AUTUMN(ReaderTheme.AUTUMN), WINTER(ReaderTheme.WINTER), SPRING(ReaderTheme.SPRING), SUMMER(ReaderTheme.SUMMER);

    companion object {
        /** Meteorological seasons, flipped for the southern hemisphere. */
        fun current(date: LocalDate = LocalDate.now(), region: String? = java.util.Locale.getDefault().country): Season {
            val northern = when (date.monthValue) {
                in 3..5 -> SPRING
                in 6..8 -> SUMMER
                in 9..11 -> AUTUMN
                else -> WINTER
            }
            if (region == null || region !in southernRegions) return northern
            return when (northern) {
                SPRING -> AUTUMN
                SUMMER -> WINTER
                AUTUMN -> SPRING
                WINTER -> SUMMER
            }
        }

        private val southernRegions = setOf(
            "AR", "AU", "BO", "BR", "BW", "CL", "FJ", "LS", "MG", "MU", "MZ", "NA", "NZ",
            "PE", "PG", "PY", "SZ", "UY", "ZA", "ZM", "ZW",
        )
    }
}
