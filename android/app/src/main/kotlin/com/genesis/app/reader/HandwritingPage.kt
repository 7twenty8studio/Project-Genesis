package com.genesis.app.reader

import android.content.Context
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.input.pointer.PointerType
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.motionEventSpy
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.study.InkCapture
import com.genesis.core.domain.study.InkEraser
import com.genesis.core.domain.study.InkPage
import com.genesis.core.domain.study.InkPoint
import com.genesis.core.domain.study.InkSpline
import com.genesis.core.domain.study.InkStroke
import com.genesis.core.domain.study.InkType
import kotlinx.coroutines.launch

/** The look of the page behind the ink, as PaperStyle on iOS (same setting name). */
private enum class Paper { LINED, PLAIN }

private enum class Tool { PEN, PENCIL, MARKER, ERASER }

/** Ink colours: the pen's, and the marker's (translucent, as PencilKit's). */
private val PEN_COLORS = listOf(0x1C1C1EFFL, 0x2F5DA8FFL, 0xB23A3AFFL, 0x3E7D4FFFL, 0x8A5A2BFFL)
private val MARKER_COLORS = listOf(0xFFD60A80L, 0x7FD1AE80L, 0xFF9EB580L, 0x8EC5FF80L)
private val WIDTHS = listOf(2.0, 4.0, 8.0)

/**
 * A note's handwritten page, as HandwritingPage on iOS, in Versely Ink so
 * the same page opens on an iPhone (docs/HANDWRITING_FORMAT.md): a 768-point
 * page scaled to the width, growing downwards as the writing does. A pen
 * (S Pen or any stylus, with its pressure) or a finger writes; two fingers
 * scroll. With "Only Draw with a Pen" one finger scrolls instead. A pen's
 * eraser end or its side button erases whole strokes, as the eraser does.
 */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
@Composable
internal fun HandwritingPage(page: InkPage, onChange: (InkPage) -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val colors = LocalReaderColors.current
    val prefs = remember { context.getSharedPreferences("handwriting", Context.MODE_PRIVATE) }
    var paper by remember { mutableStateOf(if (prefs.getString("paper", "lined") == "plain") Paper.PLAIN else Paper.LINED) }
    var penOnly by remember { mutableStateOf(prefs.getBoolean("penOnly", false)) }
    var tool by remember { mutableStateOf(Tool.PEN) }
    var penColor by remember { mutableStateOf(PEN_COLORS[0]) }
    var markerColor by remember { mutableStateOf(MARKER_COLORS[0]) }
    var width by remember { mutableStateOf(WIDTHS[1]) }
    var confirmClear by remember { mutableStateOf(false) }
    var paperMenu by remember { mutableStateOf(false) }
    val undo = remember { mutableStateListOf<InkPage>() }
    val redo = remember { mutableStateListOf<InkPage>() }
    val current by rememberUpdatedState(page)
    val change by rememberUpdatedState(onChange)

    fun commit(next: InkPage) {
        if (next == current) return
        undo += current
        if (undo.size > 50) undo.removeAt(0)
        redo.clear()
        change(next)
    }

    val dark = colors.background.luminance() < 0.5f
    Column(modifier) {
        // Tools: pen, pencil, marker, eraser; colours; width; undo, redo; paper and clear.
        Row(
            Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            ToolChip(stringResource(R.string.ink_pen), tool == Tool.PEN) { tool = Tool.PEN }
            ToolChip(stringResource(R.string.ink_pencil), tool == Tool.PENCIL) { tool = Tool.PENCIL }
            ToolChip(stringResource(R.string.ink_marker), tool == Tool.MARKER) { tool = Tool.MARKER }
            ToolChip(stringResource(R.string.ink_eraser), tool == Tool.ERASER) { tool = Tool.ERASER }
            val swatches = if (tool == Tool.MARKER) MARKER_COLORS else PEN_COLORS
            val chosen = if (tool == Tool.MARKER) markerColor else penColor
            if (tool != Tool.ERASER) {
                swatches.forEach { color ->
                    val shown = inkColor(color, dark)
                    Box(
                        Modifier.size(26.dp).clip(CircleShape).background(shown.copy(alpha = 1f))
                            .border(if (color == chosen) 2.dp else 1.dp, if (color == chosen) colors.accent else colors.separator, CircleShape)
                            .clickable { if (tool == Tool.MARKER) markerColor = color else penColor = color }
                            .semantics { selected = color == chosen; contentDescription = "#" + com.genesis.core.domain.study.InkFormat.hex(color).take(6) },
                    )
                }
                WIDTHS.forEach { w ->
                    Box(
                        Modifier.size(30.dp).clip(CircleShape).clickable { width = w }
                            .border(if (w == width) 2.dp else 0.dp, if (w == width) colors.accent else Color.Transparent, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) { Box(Modifier.size((3 + w * 1.4).dp).clip(CircleShape).background(colors.text)) }
                }
            }
            TextButton(onClick = { undo.removeLastOrNull()?.let { redo += current; change(it) } }, enabled = undo.isNotEmpty()) {
                Text(stringResource(R.string.undo), color = if (undo.isNotEmpty()) colors.accent else colors.secondaryText)
            }
            TextButton(onClick = { redo.removeLastOrNull()?.let { undo += current; change(it) } }, enabled = redo.isNotEmpty()) {
                Text(stringResource(R.string.redo), color = if (redo.isNotEmpty()) colors.accent else colors.secondaryText)
            }
            Box {
                TextButton(onClick = { paperMenu = true }) { Text("⋯", color = colors.accent, fontWeight = FontWeight.Bold) }
                DropdownMenu(expanded = paperMenu, onDismissRequest = { paperMenu = false }) {
                    DropdownMenuItem(text = { Text((if (paper == Paper.LINED) "✓  " else "     ") + stringResource(R.string.lined_paper)) }, onClick = {
                        paperMenu = false; paper = Paper.LINED; prefs.edit().putString("paper", "lined").apply()
                    })
                    DropdownMenuItem(text = { Text((if (paper == Paper.PLAIN) "✓  " else "     ") + stringResource(R.string.plain_paper)) }, onClick = {
                        paperMenu = false; paper = Paper.PLAIN; prefs.edit().putString("paper", "plain").apply()
                    })
                    DropdownMenuItem(text = { Text((if (penOnly) "✓  " else "     ") + stringResource(R.string.only_draw_with_pen)) }, onClick = {
                        paperMenu = false; penOnly = !penOnly; prefs.edit().putBoolean("penOnly", penOnly).apply()
                    })
                    DropdownMenuItem(text = { Text(stringResource(R.string.clear_page), color = MaterialTheme.colorScheme.error) }, enabled = !page.isEmpty, onClick = {
                        paperMenu = false; confirmClear = true
                    })
                }
            }
        }

        BoxWithConstraints(
            Modifier.fillMaxWidth().height(460.dp).clip(RoundedCornerShape(12.dp)).background(colors.background)
                .border(1.dp, colors.separator, RoundedCornerShape(12.dp)),
        ) {
            val density = LocalDensity.current
            val viewWidth = with(density) { maxWidth.toPx() }
            val viewHeight = with(density) { maxHeight.toPx() }
            val scale = (viewWidth / page.width).toFloat()
            val contentHeight = maxOf(viewHeight, ((page.bottom + InkPage.OVERSCROLL) * scale).toFloat())
            val scroll = rememberScrollState()
            val scope = rememberCoroutineScope()
            val live = remember { mutableStateListOf<InkPoint>() }
            val lineColor = colors.separator
            val penOnlyNow by rememberUpdatedState(penOnly)
            val toolNow by rememberUpdatedState(tool)
            val colorNow by rememberUpdatedState(if (tool == Tool.MARKER) markerColor else penColor)
            val widthNow by rememberUpdatedState(width)
            val scaleNow by rememberUpdatedState(scale)
            // The stylus's tilt, which Compose's pointer events don't carry: read from the raw events.
            val tiltNow = remember { doubleArrayOf(0.0) }

            Box(
                Modifier.fillMaxWidth().verticalScroll(scroll, enabled = false).height(with(density) { contentHeight.toDp() })
                    .motionEventSpy { event ->
                        tiltNow[0] = if (event.getToolType(0) == android.view.MotionEvent.TOOL_TYPE_STYLUS) event.getAxisValue(android.view.MotionEvent.AXIS_TILT, 0).toDouble() else 0.0
                    }
                    .pointerInput(Unit) {
                        awaitEachGesture {
                            val down = awaitFirstDown(requireUnconsumed = false)
                            val pen = down.type == PointerType.Stylus || down.type == PointerType.Eraser
                            // One finger scrolls when only the pen draws.
                            var scrolling = !pen && penOnlyNow
                            var erasing = down.type == PointerType.Eraser || toolNow == Tool.ERASER
                            val pageScale = scaleNow.toDouble()
                            fun at(p: Offset, pressure: Float): InkPoint {
                                val ink = toolNow.ink
                                val size = InkCapture.size(ink, widthNow * (if (ink == InkType.MARKER) 3.0 else 1.0), if (pen) pressure.toDouble() else 0.5)
                                val (shaded, opacity) = if (pen) com.genesis.core.domain.study.InkTilt.shade(ink, size, tiltNow[0]) else size to 1.0
                                return InkPoint(p.x / pageScale, p.y / pageScale, shaded, opacity)
                            }
                            live.clear()
                            if (!scrolling && !erasing) live += at(down.position, down.pressure)
                            if (erasing) commit(InkEraser.erase(current, down.position.x / pageScale, down.position.y / pageScale, 10.0))
                            down.consume()
                            while (true) {
                                val event = awaitPointerEvent()
                                val pressed = event.changes.filter { it.pressed }
                                if (pressed.isEmpty()) break
                                if (event.buttons.isSecondaryPressed) erasing = true
                                if (pressed.size > 1 && !scrolling) {
                                    // Two fingers: scroll, and the stroke just begun is dropped.
                                    scrolling = true
                                    live.clear()
                                }
                                if (scrolling) {
                                    val dy = pressed.map { it.position.y - it.previousPosition.y }.average().toFloat()
                                    scope.launch { scroll.scrollBy(-dy) }
                                } else if (erasing) {
                                    val p = pressed.first().position
                                    commit(InkEraser.erase(current, p.x / pageScale, p.y / pageScale, 10.0))
                                } else {
                                    pressed.first().let { live += at(it.position, it.pressure) }
                                }
                                event.changes.forEach { it.consume() }
                            }
                            if (!scrolling && !erasing && live.isNotEmpty()) {
                                InkCapture.stroke(toolNow.ink, colorNow, live.toList())?.let { commit(current.copy(strokes = current.strokes + it)) }
                            }
                            live.clear()
                        }
                    },
            ) {
                Canvas(Modifier.matchParentSize()) {
                    if (paper == Paper.LINED) {
                        val spacing = (InkPage.LINE_SPACING * scale).toFloat()
                        if (spacing >= 4f) {
                            var y = spacing
                            while (y < size.height) {
                                drawLine(lineColor, Offset(0f, y), Offset(size.width, y), 1f)
                                y += spacing
                            }
                        }
                    }
                    page.strokes.forEach { drawStroke(it, scale.toDouble(), dark) }
                    if (live.isNotEmpty()) {
                        val ink = toolNow.ink
                        drawStroke(InkStroke(ink, colorNow, InkSpline.pad(live.toList())), scale.toDouble(), dark)
                    }
                }
            }
        }
    }

    if (confirmClear) {
        AlertDialog(
            onDismissRequest = { confirmClear = false },
            title = { Text(stringResource(R.string.clear_this_page_question)) },
            text = { Text(stringResource(R.string.clear_page_message)) },
            confirmButton = {
                TextButton(onClick = { confirmClear = false; commit(InkPage(width = page.width)) }) {
                    Text(stringResource(R.string.clear_page), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmClear = false }) { Text(stringResource(R.string.cancel)) } },
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.secondaryText,
        )
    }
}

private val Tool.ink: InkType
    get() = when (this) {
        Tool.PENCIL -> InkType.PENCIL
        Tool.MARKER -> InkType.MARKER
        else -> InkType.PEN
    }

@Composable
private fun ToolChip(label: String, selected: Boolean, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Text(
        label,
        style = MaterialTheme.typography.labelLarge,
        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
        color = if (selected) colors.text else colors.secondaryText,
        modifier = Modifier.clip(RoundedCornerShape(50)).background(if (selected) colors.accent.copy(alpha = 0.16f) else Color.Transparent)
            .clickable(onClick = onClick).semantics { this.selected = selected }.padding(horizontal = 12.dp, vertical = 6.dp),
    )
}

/** The ink's colour on this paper: dark ink is shown light on dark paper, as PencilKit does. */
private fun inkColor(rgba: Long, dark: Boolean): Color {
    val r = ((rgba shr 24) and 0xFF) / 255f
    val g = ((rgba shr 16) and 0xFF) / 255f
    val b = ((rgba shr 8) and 0xFF) / 255f
    val a = (rgba and 0xFF) / 255f
    val color = Color(r, g, b, a)
    if (!dark) return color
    val lightness = 0.2126f * r + 0.7152f * g + 0.0722f * b
    if (lightness >= 0.45f) return color
    // Flip the lightness, keep the hue.
    val lift = 1f - 2f * lightness
    return Color((r + lift).coerceIn(0f, 1f), (g + lift).coerceIn(0f, 1f), (b + lift).coerceIn(0f, 1f), a)
}

private fun Color.luminance(): Float = 0.2126f * red + 0.7152f * green + 0.0722f * blue

/** A stroke along its curve, its width and opacity changing from point to point. */
private fun DrawScope.drawStroke(stroke: InkStroke, scale: Double, dark: Boolean) {
    val base = inkColor(stroke.color, dark)
    val kindAlpha = when (stroke.ink) {
        InkType.PENCIL, InkType.CRAYON -> 0.82f
        InkType.WATERCOLOR -> 0.6f
        else -> 1f
    }
    val points = InkSpline.sample(stroke.points, 1.5)
    if (points.size == 1) {
        val p = points[0]
        drawCircle(base.copy(alpha = base.alpha * kindAlpha * p.opacity.toFloat()), (p.size * scale / 2).toFloat(), Offset((p.x * scale).toFloat(), (p.y * scale).toFloat()))
        return
    }
    // Translucent inks are drawn as one layer, so their segments never darken where they meet.
    val layerAlpha = base.alpha * kindAlpha
    val opaque = base.copy(alpha = 1f)
    val cap = if (stroke.ink == InkType.MARKER) StrokeCap.Square else StrokeCap.Round
    val layered = layerAlpha < 0.999f
    if (layered) drawContext.canvas.saveLayer(androidx.compose.ui.geometry.Rect(Offset.Zero, size), androidx.compose.ui.graphics.Paint().apply { alpha = layerAlpha })
    for (i in 1 until points.size) {
        val a = points[i - 1]
        val b = points[i]
        drawLine(
            opaque.copy(alpha = ((a.opacity + b.opacity) / 2).toFloat().coerceIn(0f, 1f)),
            Offset((a.x * scale).toFloat(), (a.y * scale).toFloat()),
            Offset((b.x * scale).toFloat(), (b.y * scale).toFloat()),
            ((a.size + b.size) / 2 * scale).toFloat().coerceAtLeast(0.6f),
            cap,
        )
    }
    if (layered) drawContext.canvas.restore()
}
