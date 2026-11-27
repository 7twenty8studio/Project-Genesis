package com.genesis.app.reader

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import com.genesis.core.domain.bible.VerseId

/**
 * Scripture text that knows which verse a tap lands on (the verse id each
 * verse carries as an annotation), as ReaderTap on iOS: a tap on a verse
 * selects it, and a long press does too; a tap on a note's mark opens it.
 */
@Composable
internal fun VerseText(
    text: AnnotatedString,
    style: TextStyle,
    color: Color,
    onVerseTap: (VerseId) -> Unit,
    modifier: Modifier = Modifier,
    onNoteTap: (String) -> Unit = {},
    /** Every other tap, with the verse under it (if any) and its x here; the reader decides (ReaderTap). */
    onTap: ((VerseId?, Float) -> Unit)? = null,
) {
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    fun offsetAt(position: androidx.compose.ui.geometry.Offset): Int? {
        val result = layout ?: return null
        val line = result.getLineForVerticalPosition(position.y)
        if (position.x < result.getLineLeft(line) - 8 || position.x > result.getLineRight(line) + 8) return null
        return result.getOffsetForPosition(position)
    }
    fun verseAt(position: androidx.compose.ui.geometry.Offset): VerseId? {
        val offset = offsetAt(position) ?: return null
        return text.getStringAnnotations(VERSE_TAG, offset, offset + 1).firstOrNull()?.item?.toIntOrNull()?.let(::VerseId)
    }
    /** A note's mark is small, so a tap just beside it counts too. */
    fun noteAt(position: androidx.compose.ui.geometry.Offset): String? {
        val offset = offsetAt(position) ?: return null
        return text.getStringAnnotations(NOTE_TAG, (offset - 1).coerceAtLeast(0), offset + 1).firstOrNull()?.item
    }
    Text(
        text,
        style = style,
        color = color,
        onTextLayout = { layout = it },
        modifier = modifier.pointerInput(text) {
            detectTapGestures(
                onTap = { position ->
                    val note = noteAt(position)
                    when {
                        note != null -> onNoteTap(note)
                        onTap != null -> onTap(verseAt(position), position.x)
                        else -> verseAt(position)?.let(onVerseTap)
                    }
                },
                onLongPress = { position -> verseAt(position)?.let(onVerseTap) },
            )
        },
    )
}
