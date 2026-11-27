package com.genesis.core.domain.reader

import com.genesis.core.domain.theme.ReaderTheme
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * How the reader looks, as ReaderPreferences in ReaderSettings.swift: theme,
 * typeface, text size and line spacing, with the same defaults and ranges.
 * More of iOS's settings (paragraph spacing, page turns, first letter…)
 * join as their features arrive.
 */
data class ReaderPreferences(
    val theme: ReaderTheme = ReaderTheme.AUTOMATIC,
    val font: ReaderFont = ReaderFont.NEW_YORK,
    val fontSize: Double = 19.0,
    val lineSpacing: Double = 1.45,
) {
    /** The same settings with every number inside its range. */
    fun clamped(): ReaderPreferences = copy(
        fontSize = fontSize.coerceIn(FONT_SIZE_RANGE),
        lineSpacing = lineSpacing.coerceIn(LINE_SPACING_RANGE),
    )

    /** One step smaller or larger, as the reader's A buttons. */
    fun smaller() = copy(fontSize = (fontSize - 1).coerceIn(FONT_SIZE_RANGE))
    fun larger() = copy(fontSize = (fontSize + 1).coerceIn(FONT_SIZE_RANGE))

    fun encoded(): String = json.encodeToString(Stored.serializer(), Stored(theme.name, font.id, fontSize, lineSpacing))

    @Serializable
    private data class Stored(
        val theme: String? = null,
        val font: String? = null,
        val fontSize: Double? = null,
        val lineSpacing: Double? = null,
    )

    companion object {
        val FONT_SIZE_RANGE = 13.0..36.0
        val LINE_SPACING_RANGE = 1.1..2.1

        private val json = Json { ignoreUnknownKeys = true }

        /** Saved settings, keeping the default for anything missing or unknown, as iOS decodes them. */
        fun decoded(text: String?): ReaderPreferences {
            val defaults = ReaderPreferences()
            val stored = text?.let { runCatching { json.decodeFromString(Stored.serializer(), it) }.getOrNull() } ?: return defaults
            return ReaderPreferences(
                theme = ReaderTheme.entries.firstOrNull { it.name == stored.theme } ?: defaults.theme,
                font = ReaderFont.withId(stored.font) ?: defaults.font,
                fontSize = stored.fontSize ?: defaults.fontSize,
                lineSpacing = stored.lineSpacing ?: defaults.lineSpacing,
            ).clamped()
        }
    }
}
