package com.genesis.core.domain.bible

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class ScriptureDirectionTest {
    @Test fun marksMixedText() {
        val verse = "א ALEPH. Blessed are the undefiled in the way"
        assertTrue(ScriptureDirection.needsMark(verse))
        assertEquals("‎" + verse, ScriptureDirection.display(verse))
        assertEquals("‎א A\n‎b", ScriptureDirection.display("א A\nb"))
    }

    @Test fun leavesPlainTextAlone() {
        assertFalse(ScriptureDirection.needsMark("In the beginning God created"))
        assertFalse(ScriptureDirection.needsMark("בְּרֵאשִׁית בָּרָא"))
        assertEquals("Blessed", ScriptureDirection.display("Blessed"))
        assertTrue(ScriptureDirection.isRightToLeft("he"))
        assertFalse(ScriptureDirection.isRightToLeft("pt-PT"))
    }
}
