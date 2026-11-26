package com.genesis.app.reader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.ChapterId

/** Books by testament, names in the Bible's language; a book opens its chapters. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
internal fun BookPicker(language: String, current: ChapterId, onPick: (ChapterId) -> Unit, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    var openBook by rememberSaveable { mutableStateOf(current.book) }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = colors.background) {
        Text(
            stringResource(R.string.choose_book_and_chapter),
            style = MaterialTheme.typography.titleMedium,
            color = colors.text,
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp).semantics { heading() },
        )
        LazyColumn(Modifier.fillMaxWidth()) {
            for ((title, books) in listOf(
                R.string.old_testament to BibleBooks.oldTestament,
                R.string.new_testament to BibleBooks.newTestament,
            )) {
                item(key = title) {
                    Text(
                        stringResource(title),
                        style = MaterialTheme.typography.labelLarge,
                        color = colors.secondaryText,
                        modifier = Modifier.padding(start = 24.dp, top = 16.dp, bottom = 4.dp).semantics { heading() },
                    )
                }
                items(books, key = { it.id }) { book ->
                    Text(
                        book.name(language),
                        style = MaterialTheme.typography.bodyLarge,
                        color = if (book.id == current.book) colors.accent else colors.text,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { openBook = if (openBook == book.id) 0 else book.id }
                            .padding(horizontal = 24.dp, vertical = 12.dp),
                    )
                    if (openBook == book.id) {
                        FlowRow(
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            for (chapter in 1..book.chapterCount) {
                                val here = book.id == current.book && chapter == current.chapter
                                Surface(
                                    shape = RoundedCornerShape(10.dp),
                                    color = if (here) colors.accent else colors.surface,
                                    modifier = Modifier.size(48.dp).clickable { onPick(ChapterId(book.id, chapter)) },
                                ) {
                                    Box(contentAlignment = Alignment.Center) {
                                        Text(chapter.toString(), color = if (here) colors.background else colors.text)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
