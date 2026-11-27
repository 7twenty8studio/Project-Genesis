package com.genesis.core.domain.study

/** The highlight colours, with the ids and swatches of HighlightColor in ReaderTheme.swift. */
enum class HighlightColor(val id: String, val hex: Int) {
    YELLOW("yellow", 0xF2D98B),
    BLUE("blue", 0xA9C7E8),
    GREEN("green", 0xB9D8A8),
    PURPLE("purple", 0xCBB7E3),
    PINK("pink", 0xEDB8C8),
    ORANGE("orange", 0xF2C39B);

    /** The wash behind highlighted words: softer on dark themes, as on iOS. */
    fun alpha(onDarkTheme: Boolean): Float = if (onDarkTheme) 0.32f else 0.6f

    companion object {
        /** An unknown id (a colour added later on another phone) reads as yellow, as iOS does. */
        fun withId(id: String?): HighlightColor = entries.firstOrNull { it.id == id } ?: YELLOW
    }
}

/**
 * The colours offered first in the selection bar: the three used most
 * recently (RecentHighlightColors.swift), filled from the standard order.
 */
object RecentHighlightColors {
    const val COUNT = 3

    fun after(using: HighlightColor, recent: List<HighlightColor>): List<HighlightColor> =
        (listOf(using) + recent).distinct().take(COUNT)

    fun shown(recent: List<HighlightColor>): List<HighlightColor> =
        (recent + HighlightColor.entries).distinct().take(COUNT)
}
