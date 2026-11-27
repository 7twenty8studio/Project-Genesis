package com.genesis.core.domain.reader

import com.genesis.core.domain.theme.ReaderTheme
import kotlin.test.Test
import kotlin.test.assertEquals

class ReaderPreferencesTest {
    @Test fun defaultsMatchIOS() {
        val defaults = ReaderPreferences()
        assertEquals(ReadingMode.PAGE, defaults.readingMode)
        assertEquals(ReaderTheme.AUTOMATIC, defaults.theme)
        assertEquals(ReaderFont.NEW_YORK, defaults.font)
        assertEquals(19.0, defaults.fontSize)
        assertEquals(1.45, defaults.lineSpacing)
    }

    @Test fun roundTrips() {
        val chosen = ReaderPreferences(ReadingMode.SCROLL, ReaderTheme.SEPIA, ReaderFont.EB_GARAMOND, 22.0, 1.7)
        assertEquals(chosen, ReaderPreferences.decoded(chosen.encoded()))
    }

    @Test fun unknownOrMissingValuesKeepDefaults() {
        assertEquals(ReaderPreferences(), ReaderPreferences.decoded(null))
        assertEquals(ReaderPreferences(), ReaderPreferences.decoded("not json"))
        val partial = ReaderPreferences.decoded("""{"theme":"NOT_A_THEME","font":"comicSans","fontSize":24}""")
        assertEquals(ReaderPreferences(fontSize = 24.0), partial)
    }

    @Test fun numbersStayInRange() {
        assertEquals(36.0, ReaderPreferences.decoded("""{"fontSize":90}""").fontSize)
        assertEquals(13.0, ReaderPreferences(fontSize = 13.0).smaller().fontSize)
        assertEquals(36.0, ReaderPreferences(fontSize = 36.0).larger().fontSize)
        assertEquals(1.1, ReaderPreferences(lineSpacing = 0.5).clamped().lineSpacing)
    }

    @Test fun premiumFacesFallBackWithoutPremium() {
        assertEquals(ReaderFont.NEW_YORK, ReaderFont.SPECTRAL.available(premium = false))
        assertEquals(ReaderFont.SPECTRAL, ReaderFont.SPECTRAL.available(premium = true))
        assertEquals(ReaderFont.LITERATA, ReaderFont.LITERATA.available(premium = false))
        assertEquals(listOf("newYork", "sfPro", "atkinsonHyperlegible", "literata", "ebGaramond", "crimsonPro", "sourceSerif", "spectral"), ReaderFont.offered.map { it.id })
    }
}
