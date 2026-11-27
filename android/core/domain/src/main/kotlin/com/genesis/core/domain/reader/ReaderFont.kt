package com.genesis.core.domain.reader

/**
 * The reader's typefaces, with the ids, order and Premium rules of
 * ReaderFont.swift, so a choice means the same on both phones. Apple's own
 * faces aren't on Android: New York becomes the system serif (Noto Serif),
 * SF Pro the system sans (Roboto), and Georgia and Baskerville, which have
 * no free equivalent, read as the system serif and aren't offered.
 */
enum class ReaderFont(val id: String, val isPremium: Boolean = false, val faces: Faces? = null) {
    NEW_YORK("newYork"),
    SF_PRO("sfPro"),
    GEORGIA("georgia"),
    BASKERVILLE("baskerville"),
    ATKINSON_HYPERLEGIBLE("atkinsonHyperlegible", faces = Faces("AtkinsonHyperlegible-Regular", "AtkinsonHyperlegible-Bold", "AtkinsonHyperlegible-Italic")),
    LITERATA("literata", faces = Faces("Literata-Regular", "Literata-SemiBold", "Literata-Italic")),
    EB_GARAMOND("ebGaramond", faces = Faces("EBGaramond-Regular", "EBGaramond-SemiBold", "EBGaramond-Italic")),
    CRIMSON_PRO("crimsonPro", isPremium = true, faces = Faces("CrimsonPro-Regular", "CrimsonPro-SemiBold", "CrimsonPro-Italic")),
    SOURCE_SERIF("sourceSerif", isPremium = true, faces = Faces("SourceSerif4-Regular", "SourceSerif4-SemiBold", "SourceSerif4-Italic")),
    SPECTRAL("spectral", isPremium = true, faces = Faces("Spectral-Regular", "Spectral-SemiBold", "Spectral-Italic"));

    /** A bundled face's files (Genesis/Resources/Fonts/<name>.ttf): regular, bold and italic. */
    data class Faces(val regular: String, val bold: String, val italic: String)

    /** Offered in Android's font list: every face but Apple's own Georgia and Baskerville. */
    val isOffered: Boolean get() = this != GEORGIA && this != BASKERVILLE

    /** True for the system sans; every other face is a serif. */
    val isSans: Boolean get() = this == SF_PRO

    /** Without Premium the reader falls back to the default face, keeping the choice. */
    fun available(premium: Boolean): ReaderFont = if (isPremium && !premium) NEW_YORK else this

    companion object {
        fun withId(id: String?): ReaderFont? = entries.firstOrNull { it.id == id }
        val offered: List<ReaderFont> get() = entries.filter { it.isOffered }
    }
}
