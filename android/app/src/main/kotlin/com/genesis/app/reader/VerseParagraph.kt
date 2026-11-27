package com.genesis.app.reader

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.dp
import com.genesis.core.bible.Verse
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.VerseId

/** One paragraph or poetry block of the scrolling reader. */
@Composable
internal fun VerseParagraph(verses: List<Verse>, style: TextStyle, marks: VerseMarks, onVerseTap: (VerseId) -> Unit, onNoteTap: (String) -> Unit = {}, onTap: ((VerseId?, Float) -> Unit)? = null) {
    val colors = LocalReaderColors.current
    val poetry = verses.firstOrNull()?.isPoetry == true
    VerseText(
        buildAnnotatedString { appendVerses(verses, colors, marks) },
        style = style,
        color = colors.text,
        onVerseTap = onVerseTap,
        onNoteTap = onNoteTap,
        onTap = onTap,
        modifier = Modifier.padding(bottom = 12.dp, start = if (poetry) 16.dp else 0.dp),
    )
}
