package com.genesis.core.domain.home

import kotlin.math.ceil
import kotlin.math.floor

/**
 * Picks a font size that shows a whole verse in a box, as iOS's
 * minimumScaleFactor does for widgets (Glance can't shrink text itself).
 * An estimate from a serif's average glyph width and line height, with
 * room for words that don't fill a line; the verse is never cut short
 * unless even the smallest size can't hold it.
 */
object TextFit {
    data class Fit(val fontSizeSp: Int, val maxLines: Int)

    private const val GLYPH_WIDTH = 0.52 // of the font size, an average serif letter or space
    private const val LINE_HEIGHT = 1.36 // of the font size
    private const val WRAP_WASTE = 1.1 // lines end before the edge at a word break

    fun fit(characters: Int, widthDp: Double, heightDp: Double, largest: Int, smallest: Int): Fit {
        for (size in largest downTo smallest) {
            val lineHeight = size * LINE_HEIGHT
            val available = maxOf(1, floor(heightDp / lineHeight).toInt())
            val perLine = maxOf(1.0, floor(widthDp / (size * GLYPH_WIDTH)))
            val needed = ceil(characters * WRAP_WASTE / perLine).toInt()
            if (needed <= available) return Fit(size, available)
        }
        return Fit(smallest, maxOf(1, floor(heightDp / (smallest * LINE_HEIGHT)).toInt()))
    }
}
