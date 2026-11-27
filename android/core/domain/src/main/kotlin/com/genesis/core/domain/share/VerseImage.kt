package com.genesis.core.domain.share

import com.genesis.core.domain.theme.ReaderTheme
import com.genesis.core.domain.theme.Season

/** What goes on a verse image: verbatim Scripture from the database and its reference (VerseCard on iOS). */
data class VerseCard(val text: String, val reference: String, val translation: String)

/** A verse image's background, as VerseImageStyle on iOS. */
enum class VerseImageStyle(val rawValue: String) {
    PAPER("paper"), AUTUMN("autumn"), WINTER("winter"), SPRING("spring"), SUMMER("summer"), NIGHT("night"), PHOTO("photo");

    /** The theme whose paper and colours it uses. */
    fun theme(reading: ReaderTheme): ReaderTheme = when (this) {
        PAPER -> if (reading.isDark || reading.isScene) ReaderTheme.PAPER else reading
        AUTUMN -> ReaderTheme.AUTUMN
        WINTER -> ReaderTheme.WINTER
        SPRING -> ReaderTheme.SPRING
        SUMMER -> ReaderTheme.SUMMER
        NIGHT, PHOTO -> ReaderTheme.MIDNIGHT
    }

    val season: Season?
        get() = when (this) {
            AUTUMN -> Season.AUTUMN
            WINTER -> Season.WINTER
            SPRING -> Season.SPRING
            SUMMER -> Season.SUMMER
            else -> null
        }
}

/** The words' colour; Automatic follows the background's own text colour. */
enum class VerseImageInk(val rawValue: String, val hex: Long?) {
    AUTOMATIC("automatic", null),
    INK("ink", 0x2B2A27),
    WHITE("white", 0xFFFFFF),
    CREAM("cream", 0xF4ECD8),
    GOLD("gold", 0xC9A96E),
    NAVY("navy", 0x1F2A44),
}

/** A verse image's shape in pixels, and the room kept clear around the words. */
enum class VerseImageShape(val rawValue: String, val width: Int, val height: Int) {
    SQUARE("square", 1080, 1080),
    STORY("story", 1080, 1920),
    /** A tall phone screen (19.5:9), so it fills any recent phone's lock screen without stretching. */
    LOCK_SCREEN("lockScreen", 1290, 2796),
    ;

    /** On the lock screen: the date and clock above, the shortcuts below. */
    val textTop: Float get() = when (this) {
        SQUARE -> 100f
        STORY -> 260f
        LOCK_SCREEN -> height * 0.37f
    }

    val textBottom: Float get() = when (this) {
        SQUARE -> 100f
        STORY -> 260f
        LOCK_SCREEN -> height * 0.16f
    }

    val sidePadding: Float get() = if (this == LOCK_SCREEN) 120f else 96f
}

object VerseImageText {
    /** Larger for short verses, smaller for long passages, times the chosen size (0.7–1.4). */
    fun size(characters: Int, shape: VerseImageShape, scale: Double): Float {
        val base = when (shape) {
            VerseImageShape.SQUARE -> 58f
            VerseImageShape.STORY -> 64f
            VerseImageShape.LOCK_SCREEN -> 66f
        }
        val fitted = when {
            characters < 120 -> base * 1.2f
            characters < 260 -> base
            characters < 450 -> base * 0.8f
            else -> base * 0.66f
        }
        return fitted * scale.coerceIn(0.7, 1.4).toFloat()
    }
}
