package com.genesis.core.domain.moments

import com.genesis.core.domain.bible.ChapterId
import java.time.LocalDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ChapterMomentRuleTest {
    private val day = LocalDate.of(2026, 10, 6)

    @Test fun keys() {
        assertEquals("2026-10-06|chapter:43003", ChapterMomentRule.key(ChapterMomentRule.chapterSubject(ChapterId(43, 3)), day))
        assertEquals("2026-10-06|plan:abc:12", ChapterMomentRule.key(ChapterMomentRule.planDaySubject("abc", 12), day))
    }

    @Test fun oncePerDay() {
        val key = ChapterMomentRule.key("chapter:1001", day)
        assertTrue(ChapterMomentRule.shouldCelebrate(key, emptySet()))
        assertFalse(ChapterMomentRule.shouldCelebrate(key, setOf(key)))
    }

    @Test fun keepsOnlyToday() {
        val kept = ChapterMomentRule.pruned(setOf("2026-10-05|chapter:1001", "2026-10-06|chapter:1002"), day)
        assertEquals(setOf("2026-10-06|chapter:1002"), kept)
    }
}
