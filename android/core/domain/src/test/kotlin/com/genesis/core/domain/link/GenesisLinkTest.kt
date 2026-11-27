package com.genesis.core.domain.link

import com.genesis.core.domain.bible.VerseId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class GenesisLinkTest {
    @Test
    fun readsAVerse() {
        assertEquals(GenesisLink.Read(VerseId(43, 3, 16)), GenesisLink.parse("versely://read/43003016"))
        assertEquals("versely://read/43003016", GenesisLink.read(VerseId(43, 3, 16)))
    }

    @Test
    fun readWithoutAVerseContinues() {
        assertEquals(GenesisLink.ContinueReading, GenesisLink.parse("versely://read"))
        assertEquals(GenesisLink.Home, GenesisLink.parse("versely://home"))
    }

    @Test
    fun refusesOtherLinks() {
        assertNull(GenesisLink.parse("https://read/43003016"))
        assertNull(GenesisLink.parse("versely://read/43099001"))
        assertNull(GenesisLink.parse("versely://read/abc"))
        assertNull(GenesisLink.parse("versely://unknown"))
    }
}
