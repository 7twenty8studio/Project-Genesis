package com.genesis.app.reader.backdrop

import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.translate
import com.genesis.core.domain.theme.SceneSize
import com.genesis.core.domain.theme.ThemeScene

/**
 * The scene behind clear pages, shared with the pages, as setLiveScene on
 * iOS: Page Curl needs opaque pages, so while a page turns each one paints
 * the very scene behind it (same moment, same place on screen) under its
 * words. Nothing shows through the turning page, and nothing pauses.
 */
@Stable
class SceneBackdrop {
    internal var scene by mutableStateOf<ThemeScene?>(null)
    internal var art by mutableStateOf<SceneArt?>(null)
    internal var size by mutableStateOf(SceneSize(0.0, 0.0))
    internal var clock by mutableStateOf<State<Double>?>(null)
    internal var running by mutableStateOf(false)
    /** Where the scene's top left corner is in the window. */
    internal var origin by mutableStateOf(Offset.Zero)

    val isReady: Boolean get() = scene != null && art != null && size.width > 0

    /** Paints the scene into a page whose top left corner is at `at` in the window. */
    fun DrawScope.paint(at: Offset) {
        val scene = scene ?: return
        val art = art ?: return
        val time = if (running) ThemeScene.STILL_TIME + (clock?.value ?: 0.0) else ThemeScene.STILL_TIME
        translate(origin.x - at.x, origin.y - at.y) { drawScene(scene, art, this@SceneBackdrop.size, time) }
    }
}
