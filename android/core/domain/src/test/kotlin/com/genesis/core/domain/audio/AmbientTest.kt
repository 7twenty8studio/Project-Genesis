package com.genesis.core.domain.audio

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AmbientTest {
    @Test fun savedMixRoundTrips() {
        val mix = mapOf(AmbientSound.WIND to 0.3f, AmbientSound.RAIN to 0.8f)
        assertEquals("rain=0.8,wind=0.3", AmbientRules.encode(mix))
        assertEquals(mix, AmbientRules.decode(AmbientRules.encode(mix)))
    }

    @Test fun decodeIgnoresJunk() {
        assertEquals(mapOf(AmbientSound.PAD to 1f), AmbientRules.decode("pad=3,thunder=0.5,rain,=,wind=x"))
        assertEquals(emptyMap(), AmbientRules.decode(null))
    }

    @Test fun toggleAndMatch() {
        val one = AmbientRules.toggle(emptyMap(), AmbientSound.RAIN)
        assertEquals("quiet-rain", AmbientMix.matching(one)?.id)
        assertNull(AmbientMix.matching(AmbientRules.toggle(one, AmbientSound.WIND)))
        assertEquals(emptyMap(), AmbientRules.toggle(one, AmbientSound.RAIN))
    }

    @Test fun ducking() {
        assertEquals(0.36f, AmbientRules.effective(0.8f, true), 0.0001f)
        assertEquals(0.8f, AmbientRules.effective(0.8f, false))
    }
}
