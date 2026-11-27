package com.genesis.core.domain.reader

/**
 * Two pages side by side like an open book, as PageSpread.swift: only when
 * chosen, with a reading area at least 800 wide and clearly wider than tall
 * and never beside the open side panel.
 */
object PageSpread {
    const val MINIMUM_WIDTH = 800f

    const val MINIMUM_ASPECT = 1.15f

    fun shows(enabled: Boolean, width: Float, height: Float, sidePanelShown: Boolean = false): Boolean =
        enabled && !sidePanelShown && height > 0f && width >= MINIMUM_WIDTH && width / height >= MINIMUM_ASPECT
}
