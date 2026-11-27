package com.genesis.core.domain.reader

import com.genesis.core.domain.bible.VerseId

/**
 * What a single tap on the reader's text does, as ReaderTap.swift:
 * - in paged reading, a tap in the page's outer edge (the margin and a
 *   little more) turns the page, keeping any selection;
 * - while verses are selected, a tap adds or removes a verse (or clears
 *   the selection when it lands on no verse);
 * - a tap on a verse selects it;
 * - a tap anywhere else (the running head, the page number, blank space)
 *   shows or hides the reader controls.
 */
object ReaderTap {
    sealed interface Action {
        data class TurnPage(val forward: Boolean) : Action
        data class ToggleSelection(val verse: VerseId) : Action
        data object ClearSelection : Action
        data object ToggleControls : Action
    }

    /** The margin plus 10, at least 32 and never more than 15% of the page. */
    fun edgeWidth(margin: Float, pageWidth: Float): Float = minOf(maxOf(margin + 10f, 32f), pageWidth * 0.15f)

    fun action(
        x: Float,
        pageWidth: Float,
        leftMargin: Float,
        rightMargin: Float,
        verse: VerseId?,
        isSelecting: Boolean,
        turnsPages: Boolean,
        leftHanded: Boolean = false,
    ): Action {
        if (turnsPages && pageWidth > 0f) {
            if (x < edgeWidth(leftMargin, pageWidth)) return Action.TurnPage(forward = leftHanded)
            if (x > pageWidth - edgeWidth(rightMargin, pageWidth)) return Action.TurnPage(forward = !leftHanded)
        }
        if (isSelecting) return verse?.let { Action.ToggleSelection(it) } ?: Action.ClearSelection
        return verse?.let { Action.ToggleSelection(it) } ?: Action.ToggleControls
    }
}
