package com.genesis.core.domain.premium

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PremiumGrantTest {
    private val now = Instant.parse("2026-11-27T12:00:00Z")

    @Test fun permanentAndTimedGrants() {
        assertTrue(PremiumGrant.from(true, null, now).isActive(now))
        assertTrue(PremiumGrant.from(true, "2027-02-27T12:00:00+00:00", now).isActive(now))
        assertFalse(PremiumGrant.from(true, "2026-11-01T00:00:00Z", now).isActive(now))
        assertFalse(PremiumGrant.from(false, null, now).isActive(now))
    }

    @Test fun aSavedEndDateEndsItOffline() {
        val grant = PremiumGrant.from(true, "2026-12-01 00:00:00+00", now)
        assertEquals(Instant.parse("2026-12-01T00:00:00Z"), grant.endsAt)
        assertTrue(grant.isActive(now))
        assertFalse(grant.isActive(Instant.parse("2026-12-02T00:00:00Z")))
    }
}
