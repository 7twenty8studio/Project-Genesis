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
 * selects it, and a long press does too.
 */
@Composable
internal fun VerseText(
    text: AnnotatedString,
    style: TextStyle,
    color: Color,
    onVerseTap: (VerseId) -> Unit,
    modifier: Modifier = Modifier,
) {
    var layout by remember { mutableStateOf<TextLayoutResult?>(null) }
    fun verseAt(position: androidx.compose.ui.geometry.Offset): VerseId? {
        val result = layout ?: return null
        val line = result.getLineForVerticalPosition(position.y)
        if (position.x < result.getLineLeft(line) - 8 || position.x > result.getLineRight(line) + 8) return null
        val offset = result.getOffsetForPosition(position)
        return text.getStringAnnotations(VERSE_TAG, offset, offset + 1).firstOrNull()?.item?.toIntOrNull()?.let(::VerseId)
    }
    Text(
        text,
        style = style,
        color = color,
        onTextLayout = { layout = it },
        modifier = modifier.pointerInput(text) {
            detectTapGestures(
                onTap = { position -> verseAt(position)?.let(onVerseTap) },
                onLongPress = { position -> verseAt(position)?.let(onVerseTap) },
            )
        },
    )
}
