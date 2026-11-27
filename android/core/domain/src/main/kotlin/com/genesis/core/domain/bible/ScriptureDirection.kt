package com.genesis.core.domain.bible

/**
 * Keeps a Latin-script verse left to right when it opens with a Hebrew
 * letter (Psalm 119 in the KJV: "א ALEPH. Blessed are…"), as
 * ScriptureDirection on iOS: an invisible left-to-right mark before each
 * line, only when the text mixes the two. The reader sets the paragraph's
 * direction instead, so its offsets stay the verse's own. Copies, shares,
 * games and search keep the plain text.
 */
object ScriptureDirection {
    const val MARK = '‎'

    fun display(text: String): String =
        if (!needsMark(text)) text else text.split('\n').joinToString("\n") { MARK + it }

    /** True when the text holds both a right-to-left letter and a Latin one. */
    fun needsMark(text: String): Boolean {
        var rightToLeft = false
        var latin = false
        for (char in text) {
            when (char.code) {
                in 0x0590..0x08FF, in 0xFB1D..0xFDFF, in 0xFE70..0xFEFF -> rightToLeft = true
                in 0x0041..0x005A, in 0x0061..0x007A, in 0x00C0..0x024F -> latin = true
            }
            if (rightToLeft && latin) return true
        }
        return false
    }

    /** Whether a Bible in this language reads right to left (none bundled today). */
    fun isRightToLeft(language: String): Boolean = language.substringBefore('-').lowercase() in setOf("he", "ar", "fa", "ur", "yi", "syr")
}
