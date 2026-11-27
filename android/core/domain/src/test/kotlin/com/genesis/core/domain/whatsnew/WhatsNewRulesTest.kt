package com.genesis.core.domain.whatsnew

import kotlin.test.Test
import kotlin.test.assertEquals

class WhatsNewRulesTest {
    private val catalog = listOf(WhatsNewRules.Entry("a"), WhatsNewRules.Entry("b", "community"), WhatsNewRules.Entry("c", "church_sermons"))

    @Test fun newestFirstUnseenAndSwitchedOn() {
        val pending = WhatsNewRules.pending(catalog, setOf("a")) { it == "church_sermons" }
        assertEquals(listOf("c"), pending.map { it.id })
    }

    @Test fun newInstallSkipsShipped() = assertEquals(setOf("a"), WhatsNewRules.shippedIds(catalog))
}
