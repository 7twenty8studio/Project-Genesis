package com.genesis.app.reader

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import com.genesis.core.bible.Verse
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.ScriptureText

/**
 * Verses run on in one paragraph with small raised numbers, as in a printed
 * Bible. The text is exactly as stored: only its style changes. Each verse
 * keeps its id as an annotation, ready for taps, highlights and selection.
 */
@Composable
internal fun VerseParagraph(verses: List<Verse>) {
    val colors = LocalReaderColors.current
    val poetry = verses.firstOrNull()?.isPoetry == true
    val text = buildAnnotatedString {
        verses.forEachIndexed { index, verse ->
            if (index > 0) append(if (poetry) "\n" else " ")
            withStyle(SpanStyle(color = colors.accent, fontSize = 0.6.em, fontWeight = FontWeight.Medium, baselineShift = BaselineShift(0.35f))) {
                append(verse.number.toString())
            }
            append(" ")
            pushStringAnnotation(tag = "verse", annotation = verse.id.rawValue.toString())
            append(verse.text)
            pop()
        }
    }
    Text(
        text,
        style = ScriptureText,
        color = colors.text,
        modifier = Modifier.padding(bottom = 12.dp, start = if (poetry) 16.dp else 0.dp),
    )
}
