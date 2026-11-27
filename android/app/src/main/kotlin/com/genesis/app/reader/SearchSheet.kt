package com.genesis.app.reader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.core.bible.Verse
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.ReaderColors
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.search.SearchHighlighter

/**
 * Instant search over the Bible being read, as SearchContent on iOS: a typed
 * reference ("Go to John 3:16"), book names, then verses with the matching
 * words marked. Verses are shown verbatim; a tap opens the reader there.
 * Premium's filters (one testament or book, order) and topics come later.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SearchSheet(
    search: SearchUiState,
    scripture: TextStyle,
    onText: (String) -> Unit,
    onOpen: (VerseId) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.background,
    ) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.94f).imePadding()) {
            Row(Modifier.padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(
                    value = search.text,
                    onValueChange = onText,
                    placeholder = { Text(stringResource(R.string.search)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = colors.text,
                        unfocusedTextColor = colors.text,
                        focusedBorderColor = colors.accent,
                        unfocusedBorderColor = colors.separator,
                        cursorColor = colors.accent,
                    ),
                    modifier = Modifier.weight(1f).focusRequester(focus),
                )
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold)
                }
            }
            LazyColumn(Modifier.fillMaxWidth(), contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp)) {
                val results = search.results
                if (search.text.isBlank()) {
                    item { SectionTitle(stringResource(R.string.search_try)) }
                    items(examples) { example ->
                        val text = stringResource(example)
                        Row_(text, colors) { onText(text) }
                    }
                    return@LazyColumn
                }
                results.reference?.let { reference ->
                    item {
                        Text(
                            stringResource(R.string.go_to, reference.description(search.language)),
                            style = MaterialTheme.typography.titleMedium,
                            color = colors.accent,
                            modifier = Modifier.fillMaxWidth().clickable { onOpen(reference.firstVerse) }.padding(horizontal = 20.dp, vertical = 14.dp),
                        )
                    }
                }
                if (results.bookSuggestions.isNotEmpty()) {
                    item { SectionTitle(stringResource(R.string.books)) }
                    items(results.bookSuggestions) { book ->
                        Row_(book.name(search.language), colors) { onOpen(ChapterId(book.id, 1).firstVerse) }
                    }
                }
                if (results.verses.isNotEmpty()) {
                    item {
                        val total = results.totalMatches
                        val shown = results.verses.size
                        SectionTitle(
                            if (shown < total) stringResource(R.string.verses_showing, total, shown)
                            else if (total == 1) stringResource(R.string.one_verse) else stringResource(R.string.verse_count, total),
                        )
                    }
                    items(results.verses, key = { it.id.rawValue }) { verse ->
                        VerseResult(verse, results.terms, search.language, scripture, colors) { onOpen(verse.id) }
                    }
                } else if (results.text.isNotEmpty() && results.isEmpty) {
                    item {
                        Text(
                            stringResource(R.string.no_verses_found, search.translationAbbreviation),
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.secondaryText,
                            modifier = Modifier.padding(20.dp),
                        )
                    }
                }
            }
        }
    }
}

private val examples = listOf(
    R.string.search_example_john,
    R.string.search_example_psalm,
    R.string.search_example_forgiveness,
    R.string.search_example_love,
    R.string.search_example_shepherd,
    R.string.search_example_romans,
)

@Composable
private fun SectionTitle(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = LocalReaderColors.current.secondaryText,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 6.dp).semantics { heading() },
    )
}

@Composable
private fun Row_(text: String, colors: ReaderColors, onClick: () -> Unit) {
    Column {
        Text(
            text,
            style = MaterialTheme.typography.bodyLarge,
            color = colors.text,
            modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 12.dp),
        )
        HorizontalDivider(Modifier.padding(start = 20.dp), color = colors.separator)
    }
}

@Composable
private fun VerseResult(verse: Verse, terms: List<String>, language: String, scripture: TextStyle, colors: ReaderColors, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 12.dp)) {
        Text(
            ReferenceParser.describe(verse.id.rawValue, language = language),
            style = MaterialTheme.typography.labelLarge,
            color = colors.accent,
        )
        Text(
            marked(verse.plainText, terms, colors),
            style = scripture.copy(fontSize = 17.sp, lineHeight = 24.sp),
            color = colors.text,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
    HorizontalDivider(Modifier.padding(start = 20.dp), color = colors.separator)
}

/** The verse verbatim, its matching words in semibold on a light tint. */
private fun marked(text: String, terms: List<String>, colors: ReaderColors): AnnotatedString = buildAnnotatedString {
    append(text)
    for (range in SearchHighlighter.matchRanges(text, terms)) {
        addStyle(SpanStyle(fontWeight = FontWeight.SemiBold, background = colors.accent.copy(alpha = 0.16f)), range.first, range.last + 1)
    }
}
