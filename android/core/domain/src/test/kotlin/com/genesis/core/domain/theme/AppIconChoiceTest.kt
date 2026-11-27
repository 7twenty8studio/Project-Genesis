package com.genesis.core.domain.theme

import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals

class AppIconChoiceTest {
    @Test fun seasonsFollowTheCalendarAndHemisphere() {
        assertEquals(AppIconChoice.AUTUMN, AppIconChoice.SEASONS.icon(LocalDate.of(2026, 11, 27), "US"))
        assertEquals(AppIconChoice.SPRING, AppIconChoice.SEASONS.icon(LocalDate.of(2026, 11, 27), "BR"))
        assertEquals(AppIconChoice.NIGHT, AppIconChoice.NIGHT.icon(LocalDate.of(2026, 11, 27), "US"))
    }

    @Test fun premiumIconsNeedPremium() {
        assertEquals(AppIconChoice.STANDARD, AppIconChoice.NIGHT.shown(premium = false))
        assertEquals(AppIconChoice.NIGHT, AppIconChoice.NIGHT.shown(premium = true))
        assertEquals(AppIconChoice.STANDARD, AppIconChoice.of("unknown"))
    }
}
