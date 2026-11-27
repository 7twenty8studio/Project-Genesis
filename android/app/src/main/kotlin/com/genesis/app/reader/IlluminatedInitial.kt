package com.genesis.app.reader

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.genesis.core.design.LocalReaderColors

/**
 * The illuminated first letter (Premium, `InitialStyle.ILLUMINATED`), as
 * ChapterTextBuilder.illuminatedInitial on iOS: the opening letter inside a
 * square frame with a fine double border, corner flourishes and a soft fill
 * in the theme's tones, about two lines tall. It's a picture placed just
 * before verse 1; the verse's own letters follow unchanged but hidden, so
 * the text stays verbatim. The placeholder is one line tall, so every line
 * keeps its height; the picture rises above it into the room kept before
 * the first paragraph (`LargeInitial.ROOM`).
 */
internal object IlluminatedInitial {
    /** The picture's side, in ems of the body text. */
    const val SIDE = 2.3f
    /** The gap after it, in ems. */
    const val GAP = 0.25f
    private const val PREFIX = "illuminated:"
    /** Compose's own tag for inline content in an AnnotatedString. */
    private const val INLINE_TAG = "androidx.compose.foundation.text.inlineContent"

    /** The picture before verse 1, standing for `letters` (the verse's own, which follow hidden). */
    fun AnnotatedString.Builder.appendOrnament(letters: String) = appendInlineContent(PREFIX + letters, "￼")

    /** The verse's own first letters, kept but not shown (the picture shows them). */
    val hidden = SpanStyle(color = androidx.compose.ui.graphics.Color.Transparent, fontSize = 0.01.em)

    private val placeholder = Placeholder((SIDE + GAP).em, 1.em, PlaceholderVerticalAlign.TextBottom)

    /** The placeholders in a text, for measuring it as it will be drawn (pagination). */
    fun placeholders(text: AnnotatedString): List<AnnotatedString.Range<Placeholder>> =
        text.getStringAnnotations(INLINE_TAG, 0, text.length)
            .filter { it.item.startsWith(PREFIX) }
            .map { AnnotatedString.Range(placeholder, it.start, it.end) }

    /** The pictures a text holds, for its Text's `inlineContent`. */
    fun content(text: AnnotatedString, style: TextStyle): Map<String, InlineTextContent> =
        text.getStringAnnotations(INLINE_TAG, 0, text.length)
            .filter { it.item.startsWith(PREFIX) }
            .associate { it.item to InlineTextContent(placeholder) { _ -> Ornament(it.item.removePrefix(PREFIX), style) } }
}

@Composable
private fun Ornament(initial: String, style: TextStyle) {
    val colors = LocalReaderColors.current
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val body = if (style.fontSize.isSp) style.fontSize else 18.sp
    val sideDp = with(density) { (body.toPx() * IlluminatedInitial.SIDE).toDp() }
    val gapDp = with(density) { (body.toPx() * IlluminatedInitial.GAP).toDp() }
    val accent = colors.accent
    val surface = colors.surface
    val dark = colors.isDark
    // Its foot on the line's foot, rising above it; drawn past the placeholder's bounds.
    Box(Modifier.wrapContentSize(Alignment.BottomStart, unbounded = true).requiredSize(sideDp + gapDp, sideDp)) {
        Canvas(Modifier.requiredSize(sideDp + gapDp, sideDp)) {
            val side = size.height
            val unit = side * 0.09f
            val outer = Rect(0f, 0f, side, side).deflate(unit * 0.45f)
            val inner = outer.deflate(unit * 0.55f)

            // Soft fill: the page's surface, warmed with the accent towards the lower corner.
            drawRect(surface, outer.topLeft, outer.size)
            val tint = if (dark) 0.22f else 0.16f
            clipRect(outer.left, outer.top, outer.right, outer.bottom) {
                drawRect(Brush.linearGradient(listOf(accent.copy(alpha = tint * 0.35f), accent.copy(alpha = tint)), outer.topLeft, outer.bottomRight), outer.topLeft, outer.size)
            }

            // A fine double border.
            drawRect(accent, outer.topLeft, outer.size, style = Stroke(maxOf(1f, side * 0.025f)))
            drawRect(accent.copy(alpha = 0.75f), inner.topLeft, inner.size, style = Stroke(maxOf(0.5f, side * 0.012f)))

            // Corner flourishes: a diamond on each outer corner, a curl with a dot inside each inner one.
            val corners = listOf(
                Triple(outer.topLeft, inner.topLeft, 1f to 1f),
                Triple(outer.topRight, inner.topRight, -1f to 1f),
                Triple(outer.bottomLeft, inner.bottomLeft, 1f to -1f),
                Triple(outer.bottomRight, inner.bottomRight, -1f to -1f),
            )
            for ((o, i, d) in corners) {
                val (dx, dy) = d
                val r = unit * 0.42f
                drawPath(Path().apply {
                    moveTo(o.x, o.y - r); lineTo(o.x + r, o.y); lineTo(o.x, o.y + r); lineTo(o.x - r, o.y); close()
                }, accent)
                drawPath(
                    Path().apply {
                        moveTo(i.x + dx * unit * 1.9f, i.y + dy * unit * 0.4f)
                        quadraticTo(i.x + dx * unit * 0.45f, i.y + dy * unit * 0.45f, i.x + dx * unit * 0.4f, i.y + dy * unit * 1.9f)
                    },
                    accent,
                    style = Stroke(maxOf(0.5f, side * 0.014f), cap = StrokeCap.Round),
                )
                drawCircle(accent, unit * 0.2f, Offset(i.x + dx * unit * 1.05f, i.y + dy * unit * 1.05f))
            }

            // The letter (any opening quotation mark smaller before it), centred in the frame.
            fun lettering(size: Float) = buildAnnotatedString {
                val prefix = initial.dropLast(1)
                if (prefix.isNotEmpty()) withStyle(SpanStyle(fontSize = (size * 0.5f).toSp())) { append(prefix) }
                withStyle(SpanStyle(fontSize = size.toSp(), fontWeight = FontWeight.SemiBold)) { append(initial.takeLast(1)) }
            }
            val letterStyle = style.copy(color = accent, lineHeight = androidx.compose.ui.unit.TextUnit.Unspecified)
            var letterSize = side * 0.6f
            var layout = measurer.measure(lettering(letterSize), letterStyle, constraints = Constraints())
            if (layout.size.width > side * 0.7f) {
                letterSize *= side * 0.7f / layout.size.width
                layout = measurer.measure(lettering(letterSize), letterStyle, constraints = Constraints())
            }
            // The capital's height (about 0.7 of the size) centred in the frame.
            val top = outer.center.y + letterSize * 0.35f - layout.firstBaseline
            drawText(layout, topLeft = Offset(outer.center.x - layout.size.width / 2f, top))
        }
    }
}
