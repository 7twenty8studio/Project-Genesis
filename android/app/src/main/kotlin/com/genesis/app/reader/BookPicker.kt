package com.genesis.app.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.BibleBook
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.Testament

/**
 * Book and chapter navigation, as ChapterPickerView.swift: "Books" with a
 * Find a Book field, Old and New Testament, each book with its chapter count
 * (a bookmark on the one being read); a book opens its grid of chapters, the
 * current one filled. One-chapter books open at once. Names follow the Bible
 * being read.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BookPicker(language: String, current: ChapterId, onPick: (ChapterId) -> Unit, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    var testament by rememberSaveable { mutableStateOf(BibleBooks.withNumber(current.book).testament) }
    var filter by rememberSaveable { mutableStateOf("") }
    var openBook by rememberSaveable { mutableIntStateOf(0) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.background,
        dragHandle = null,
    ) {
        Column(Modifier.fillMaxHeight(0.94f)) {
            val book = BibleBooks.all.firstOrNull { it.id == openBook }
            // The bar: Close (or back to the books) and the title.
            Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 8.dp)) {
                TextButton(onClick = { if (book != null) openBook = 0 else onDismiss() }, modifier = Modifier.align(Alignment.CenterStart)) {
                    Text(if (book != null) "‹ " + stringResource(R.string.books) else stringResource(R.string.close), color = colors.accent)
                }
                Text(
                    book?.name(language) ?: stringResource(R.string.books),
                    style = MaterialTheme.typography.titleMedium,
                    color = colors.text,
                    modifier = Modifier.align(Alignment.Center).semantics { heading() },
                )
            }
            if (book != null) {
                ChapterGrid(book, current, onPick)
            } else {
                OutlinedTextField(
                    value = filter,
                    onValueChange = { filter = it },
                    placeholder = { Text(stringResource(R.string.find_a_book)) },
                    singleLine = true,
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = colors.accent,
                        unfocusedBorderColor = colors.separator,
                        focusedTextColor = colors.text,
                        unfocusedTextColor = colors.text,
                        cursorColor = colors.accent,
                    ),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                )
                if (filter.isEmpty()) {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
                        Testament.entries.forEachIndexed { index, choice ->
                            SegmentedButton(
                                selected = testament == choice,
                                onClick = { testament = choice },
                                shape = SegmentedButtonDefaults.itemShape(index, Testament.entries.size),
                                colors = SegmentedButtonDefaults.colors(activeContainerColor = colors.surface, activeContentColor = colors.text, inactiveContainerColor = colors.background, inactiveContentColor = colors.text),
                            ) { Text(stringResource(if (choice == Testament.OLD) R.string.old_testament else R.string.new_testament)) }
                        }
                    }
                } else Spacer(Modifier.size(10.dp))
                val books = books(filter, testament, language)
                LazyColumn(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .background(colors.surface, RoundedCornerShape(12.dp)),
                ) {
                    items(books, key = { it.id }) { item ->
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .clickable(role = Role.Button) {
                                    if (item.chapterCount == 1) onPick(ChapterId(item.id, 1)) else openBook = item.id
                                }
                                .padding(horizontal = 16.dp, vertical = 13.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(item.name(language), style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                            if (item.id == current.book) {
                                val reading = stringResource(R.string.currently_reading)
                                Box(Modifier.padding(end = 10.dp).semantics { contentDescription = reading }) { BookmarkIcon(colors.accent, filled = true) }
                            }
                            Text("${item.chapterCount}", style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                        }
                        if (item != books.last()) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator.copy(alpha = 0.6f))
                    }
                }
            }
        }
    }
}

/** The books for the testament, or those matching what's typed (in any of the app's languages). */
private fun books(filter: String, testament: Testament, language: String): List<BibleBook> {
    val typed = filter.trim()
    if (typed.isEmpty()) return if (testament == Testament.OLD) BibleBooks.oldTestament else BibleBooks.newTestament
    val matches = ReferenceParser.booksMatching(typed)
    return matches.ifEmpty {
        BibleBooks.all.filter { it.name(language).contains(typed, ignoreCase = true) || it.name("en").contains(typed, ignoreCase = true) }
    }
}

@Composable
private fun ChapterGrid(book: BibleBook, current: ChapterId, onPick: (ChapterId) -> Unit) {
    val colors = LocalReaderColors.current
    LazyVerticalGrid(
        columns = GridCells.Adaptive(56.dp),
        contentPadding = PaddingValues(20.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        items((1..book.chapterCount).toList()) { number ->
            val here = current == ChapterId(book.id, number)
            val label = stringResource(R.string.chapter_number, number)
            Text(
                "$number",
                fontSize = 17.sp,
                textAlign = TextAlign.Center,
                color = if (here) colors.background else colors.text,
                modifier = Modifier
                    .heightIn(min = 50.dp)
                    .background(if (here) colors.accent else colors.surface, RoundedCornerShape(12.dp))
                    .clickable(role = Role.Button) { onPick(ChapterId(book.id, number)) }
                    .semantics { contentDescription = label }
                    .padding(vertical = 14.dp),
            )
        }
    }
}
