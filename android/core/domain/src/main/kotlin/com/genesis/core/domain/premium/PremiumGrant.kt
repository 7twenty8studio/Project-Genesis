package com.genesis.core.domain.premium

import java.time.Instant
import java.time.OffsetDateTime

/**
 * A Premium grant (public.premium_grants, added by the owner in Studio OS),
 * as EntitlementService.refreshGrant on iOS: a row with no end date is
 * permanent; one with an end date lasts until then, and a saved end date
 * ends it offline too.
 */
data class PremiumGrant(val active: Boolean, val endsAt: Instant?) {
    /** Still Premium at [now]: active, and its end date (if any) not yet passed. */
    fun isActive(now: Instant = Instant.now()): Boolean = active && (endsAt == null || endsAt > now)

    companion object {
        val NONE = PremiumGrant(false, null)

        /** The grant a row gives: [hasRow] false means no grant; [expiresAt] is Postgres's timestamptz text. */
        fun from(hasRow: Boolean, expiresAt: String?, now: Instant = Instant.now()): PremiumGrant {
            if (!hasRow) return NONE
            val end = expiresAt?.let(::parse)
            if (expiresAt != null && end == null) return NONE
            return PremiumGrant(end == null || end > now, end)
        }

        fun parse(text: String): Instant? =
            runCatching { OffsetDateTime.parse(text.replace(' ', 'T').let { if (Regex("[+-]\\d{2}$").containsMatchIn(it)) "$it:00" else it }).toInstant() }.getOrNull()
                ?: runCatching { Instant.parse(text) }.getOrNull()
    }
}
