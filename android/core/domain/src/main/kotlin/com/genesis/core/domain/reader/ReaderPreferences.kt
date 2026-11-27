package com.genesis.core.domain.reader

import com.genesis.core.domain.theme.ReaderTheme
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Page by page (the default, as on iOS) or one long scroll. */
enum class ReadingMode(val id: String) {
    PAGE("page"),
    SCROLL("scroll"),
}

/** How a page turns: sliding across, or curling like paper (the default, as iOS). */
enum class PageTurnStyle(val id: String) {
    SLIDE("slide"),
    CURL("curl"),
}

/** Verses run on in paragraphs, or each verse on its own line. */
enum class TextLayout(val id: String) {
    PARAGRAPHS("paragraphs"),
    VERSE_PER_LINE("versePerLine"),
}

/** The page's side margins, in points as iOS. */
enum class ReaderMargins(val id: String, val points: Int) {
    NARROW("narrow", 18),
    REGULAR("regular", 28),
    WIDE("wide", 44),
}

/** The large first letter: plain, or an illuminated manuscript initial (Premium). */
enum class InitialStyle(val id: String, val isPremium: Boolean) {
    PLAIN("plain", false),
    ILLUMINATED("illuminated", true),
}

/**
 * How the reader looks, as ReaderPreferences in ReaderSettings.swift, with
 * the same defaults and ranges. Saved as JSON; anything missing or unknown
 * keeps its default, as iOS decodes them.
 */
data class ReaderPreferences(
    val readingMode: ReadingMode = ReadingMode.PAGE,
    val theme: ReaderTheme = ReaderTheme.AUTOMATIC,
    val font: ReaderFont = ReaderFont.NEW_YORK,
    val fontSize: Double = 19.0,
    val lineSpacing: Double = 1.45,
    val paragraphSpacing: Double = 0.55,
    val margins: ReaderMargins = ReaderMargins.REGULAR,
    val pageTurn: PageTurnStyle = PageTurnStyle.CURL,
    val twoPageSpread: Boolean = true,
    val showsVerseNumbers: Boolean = true,
    val layout: TextLayout = TextLayout.PARAGRAPHS,
    val leftHanded: Boolean = false,
    /** Follow the phone's font size setting (Dynamic Type on iOS). */
    val followsDynamicType: Boolean = true,
    /** Gentle Motion / Seasonal Touches: the seasons' leaves and snow and the scenes' motion (on by default, as iOS). */
    val seasonalEffects: Boolean = true,
    val largeInitial: Boolean = true,
    val initialStyle: InitialStyle = InitialStyle.PLAIN,
    val pageTurnSound: Boolean = false,
    val pageTurnHaptic: Boolean = true,
    val pageTurnVolume: Double = 0.5,
    val pageTurnHapticStrength: Double = 0.9,
    val nightReading: NightReadingSchedule = NightReadingSchedule(),
) {
    /** The same settings with every number inside its range. */
    fun clamped(): ReaderPreferences = copy(
        fontSize = fontSize.coerceIn(FONT_SIZE_RANGE),
        lineSpacing = lineSpacing.coerceIn(LINE_SPACING_RANGE),
        paragraphSpacing = paragraphSpacing.coerceIn(PARAGRAPH_SPACING_RANGE),
        pageTurnVolume = pageTurnVolume.coerceIn(0.0, 1.0),
        pageTurnHapticStrength = pageTurnHapticStrength.coerceIn(HAPTIC_STRENGTH_RANGE),
    )

    /** One step smaller or larger, as the reader's A buttons. */
    fun smaller() = copy(fontSize = (fontSize - 1).coerceIn(FONT_SIZE_RANGE))
    fun larger() = copy(fontSize = (fontSize + 1).coerceIn(FONT_SIZE_RANGE))

    fun encoded(): String = json.encodeToString(
        Stored.serializer(),
        Stored(
            theme = theme.name, font = font.id, fontSize = fontSize, lineSpacing = lineSpacing, readingMode = readingMode.id,
            seasonalEffects = seasonalEffects, paragraphSpacing = paragraphSpacing, margins = margins.id, pageTurn = pageTurn.id,
            twoPageSpread = twoPageSpread, showsVerseNumbers = showsVerseNumbers, layout = layout.id, leftHanded = leftHanded,
            followsDynamicType = followsDynamicType, largeInitial = largeInitial, initialStyle = initialStyle.id,
            pageTurnSound = pageTurnSound, pageTurnHaptic = pageTurnHaptic, pageTurnVolume = pageTurnVolume,
            pageTurnHapticStrength = pageTurnHapticStrength,
            nightTheme = nightReading.theme.id, nightTiming = nightReading.timing.id,
            nightStart = nightReading.startHour, nightEnd = nightReading.endHour,
        ),
    )

    @Serializable
    private data class Stored(
        val theme: String? = null,
        val font: String? = null,
        val fontSize: Double? = null,
        val lineSpacing: Double? = null,
        val readingMode: String? = null,
        val seasonalEffects: Boolean? = null,
        val paragraphSpacing: Double? = null,
        val margins: String? = null,
        val pageTurn: String? = null,
        val twoPageSpread: Boolean? = null,
        val showsVerseNumbers: Boolean? = null,
        val layout: String? = null,
        val leftHanded: Boolean? = null,
        val followsDynamicType: Boolean? = null,
        val largeInitial: Boolean? = null,
        val initialStyle: String? = null,
        val pageTurnSound: Boolean? = null,
        val pageTurnHaptic: Boolean? = null,
        val pageTurnVolume: Double? = null,
        val pageTurnHapticStrength: Double? = null,
        val nightTheme: String? = null,
        val nightTiming: String? = null,
        val nightStart: Int? = null,
        val nightEnd: Int? = null,
    )

    companion object {
        val FONT_SIZE_RANGE = 13.0..36.0
        val LINE_SPACING_RANGE = 1.1..2.1
        val PARAGRAPH_SPACING_RANGE = 0.0..1.5
        val HAPTIC_STRENGTH_RANGE = 0.2..1.0

        private val json = Json { ignoreUnknownKeys = true }

        /** Saved settings, keeping the default for anything missing or unknown, as iOS decodes them. */
        fun decoded(text: String?): ReaderPreferences {
            val d = ReaderPreferences()
            val s = text?.let { runCatching { json.decodeFromString(Stored.serializer(), it) }.getOrNull() } ?: return d
            val nightTheme = NightTheme.entries.firstOrNull { it.id == s.nightTheme } ?: d.nightReading.theme
            return ReaderPreferences(
                readingMode = ReadingMode.entries.firstOrNull { it.id == s.readingMode } ?: d.readingMode,
                theme = ReaderTheme.entries.firstOrNull { it.name == s.theme } ?: d.theme,
                font = ReaderFont.withId(s.font) ?: d.font,
                fontSize = s.fontSize ?: d.fontSize,
                lineSpacing = s.lineSpacing ?: d.lineSpacing,
                paragraphSpacing = s.paragraphSpacing ?: d.paragraphSpacing,
                margins = ReaderMargins.entries.firstOrNull { it.id == s.margins } ?: d.margins,
                pageTurn = PageTurnStyle.entries.firstOrNull { it.id == s.pageTurn } ?: d.pageTurn,
                twoPageSpread = s.twoPageSpread ?: d.twoPageSpread,
                showsVerseNumbers = s.showsVerseNumbers ?: d.showsVerseNumbers,
                layout = TextLayout.entries.firstOrNull { it.id == s.layout } ?: d.layout,
                leftHanded = s.leftHanded ?: d.leftHanded,
                followsDynamicType = s.followsDynamicType ?: d.followsDynamicType,
                seasonalEffects = s.seasonalEffects ?: d.seasonalEffects,
                largeInitial = s.largeInitial ?: d.largeInitial,
                initialStyle = InitialStyle.entries.firstOrNull { it.id == s.initialStyle } ?: d.initialStyle,
                pageTurnSound = s.pageTurnSound ?: d.pageTurnSound,
                pageTurnHaptic = s.pageTurnHaptic ?: d.pageTurnHaptic,
                pageTurnVolume = s.pageTurnVolume ?: d.pageTurnVolume,
                pageTurnHapticStrength = s.pageTurnHapticStrength ?: d.pageTurnHapticStrength,
                nightReading = NightReadingSchedule(
                    theme = nightTheme,
                    timing = NightReadingTiming.entries.firstOrNull { it.id == s.nightTiming } ?: d.nightReading.timing,
                    startHour = s.nightStart?.coerceIn(0, 23) ?: d.nightReading.startHour,
                    endHour = s.nightEnd?.coerceIn(0, 23) ?: d.nightReading.endHour,
                ),
            ).clamped()
        }
    }
}
