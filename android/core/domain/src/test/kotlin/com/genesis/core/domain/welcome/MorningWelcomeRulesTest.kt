package com.genesis.core.domain.welcome

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MorningWelcomeRulesTest {
    @Test fun showsOncePerDayForPremium() {
        assertTrue(MorningWelcomeRules.shouldShow(true, true, true, "2026-11-26", "2026-11-27"))
        assertTrue(MorningWelcomeRules.shouldShow(true, true, true, null, "2026-11-27"))
        assertFalse(MorningWelcomeRules.shouldShow(true, true, true, "2026-11-27", "2026-11-27"))
        assertFalse(MorningWelcomeRules.shouldShow(true, true, false, null, "2026-11-27"))
        assertFalse(MorningWelcomeRules.shouldShow(true, false, true, null, "2026-11-27"))
        assertFalse(MorningWelcomeRules.shouldShow(false, true, true, null, "2026-11-27"))
    }

    @Test fun dayKeyIsPadded() = assertEquals("2026-01-05", MorningWelcomeRules.dayKey(LocalDate.of(2026, 1, 5)))

    @Test fun firstName() {
        assertEquals("Jeovanni", MorningWelcomeRules.firstName("  Jeovanni Santos "))
        assertNull(MorningWelcomeRules.firstName("   "))
        assertNull(MorningWelcomeRules.firstName(null))
    }
}
