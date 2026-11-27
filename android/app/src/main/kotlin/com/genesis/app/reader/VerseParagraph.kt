package com.genesis.app.reader

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.dp
import com.genesis.core.bible.Verse
import com.genesis.core.design.LocalReaderColors

/** One paragraph or poetry block of the scrolling reader. */
@Composable
internal fun VerseParagraph(verses: List<Verse>, style: TextStyle) {
    val colors = LocalReaderColors.current
    val poetry = verses.firstOrNull()?.isPoetry == true
    Text(
        buildAnnotatedString { appendVerses(verses, colors) },
        style = style,
        color = colors.text,
        modifier = Modifier.padding(bottom = 12.dp, start = if (poetry) 16.dp else 0.dp),
    )
}
