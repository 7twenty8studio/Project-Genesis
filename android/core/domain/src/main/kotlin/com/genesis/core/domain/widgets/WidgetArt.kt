package com.genesis.core.domain.widgets

/**
 * The verse widget's looks, as WidgetArtStyle on iOS (the same ids). Classic
 * is free; the painted papers, the seasons, Night and the scenes are
 * Premium, and show Classic with a Premium tag without it, never a locked
 * card. (The keepsakes join later.)
 */
enum class WidgetArtStyle(val rawValue: String) {
    CLASSIC("classic"),
    PAPER("paper"),
    /** A postcard: cream stock, a stamp and a postmark. */
    VINTAGE("vintage"),
    NIGHT("night"),
    SPRING("spring"),
    SUMMER("summer"),
    AUTUMN("autumn"),
    WINTER("winter"),
    FOREST("forest"),
    OCEAN("ocean"),
    HEARTH("hearth"),
    /** A photo the person chose in Versely (Settings › Widget Photo). */
    PHOTO("photo");

    val needsPremium: Boolean get() = this != CLASSIC

    val isScene: Boolean get() = this == FOREST || this == OCEAN || this == HEARTH

    /** Words go in light ink on these (dark art or a shaded photo). */
    val isDark: Boolean get() = this == NIGHT || this == PHOTO || isScene

    /** A picture the app paints for the widget. */
    val isPainted: Boolean get() = this != CLASSIC && this != PHOTO

    /** A picture behind the words (painted, or the person's photo). */
    val hasPicture: Boolean get() = this != CLASSIC

    /** What a widget shows: the style, or Classic without Premium (with a Premium tag). */
    fun shown(premium: Boolean): WidgetArtStyle = if (needsPremium && !premium) CLASSIC else this

    companion object {
        /** The order Widget Styles shows them in, as on iOS. */
        val galleryOrder: List<WidgetArtStyle> = listOf(CLASSIC, PAPER, VINTAGE, NIGHT, SPRING, SUMMER, AUTUMN, WINTER, FOREST, OCEAN, HEARTH, PHOTO)

        val painted: List<WidgetArtStyle> = entries.filter { it.isPainted }

        fun of(raw: String?): WidgetArtStyle? = entries.firstOrNull { it.rawValue == raw }

        /** The defaults key for the look chosen in Versely (WidgetStylePreference on iOS). */
        const val PREFERENCE_KEY = "widgets.verseStyle"
    }
}

/**
 * One widget's Background: "Chosen in Versely" (`APP`, the default, follows
 * Widget Styles) or a style of its own, as VerseWidgetIntent's background.
 */
object VerseWidgetBackground {
    const val APP = "app"

    /** The style a widget wears before Premium is considered. */
    fun resolve(own: String?, chosenInApp: WidgetArtStyle): WidgetArtStyle =
        if (own == null || own == APP) chosenInApp else WidgetArtStyle.of(own) ?: chosenInApp
}

/** The widget's three home screen shapes, each with its own picture so the art isn't stretched. */
enum class WidgetArtShape(val rawValue: String, val width: Int, val height: Int) {
    SMALL("small", 400, 400),
    MEDIUM("medium", 840, 400),
    LARGE("large", 840, 880);

    companion object {
        /** The shape for a widget of this size (dp), as the launcher gives it. */
        fun of(widthDp: Float, heightDp: Float): WidgetArtShape = when {
            widthDp < 250f -> SMALL
            heightDp >= 250f -> LARGE
            else -> MEDIUM
        }
    }
}
