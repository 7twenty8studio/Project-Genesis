package com.genesis.app.reader

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId

/**
 * Related passages for a verse, as CrossReferencesView on iOS: the verse,
 * then the strongest links first, each with its first verses verbatim from
 * the Bible being read, and OpenBible.info's credit. A tap opens the reader there.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CrossReferencesSheet(
    crossReferences: CrossReferencesUiState,
    scripture: TextStyle,
    onOpen: (VerseId) -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val verseStyle = scripture.copy(fontSize = 17.sp, lineHeight = 24.sp)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = colors.background,
    ) {
        Column(Modifier.fillMaxWidth().fillMaxHeight(0.94f)) {
            Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.cross_references),
                    style = MaterialTheme.typography.titleLarge,
                    color = colors.text,
                    modifier = Modifier.weight(1f).semantics { heading() },
                )
                TextButton(onClick = onDismiss) {
                    Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold)
                }
            }
            LazyColumn(Modifier.fillMaxWidth(), contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp)) {
                        Text(
                            ReferenceParser.describe(crossReferences.verse.rawValue, language = crossReferences.language),
                            style = MaterialTheme.typography.labelLarge,
                            fontWeight = FontWeight.SemiBold,
                            color = colors.accent,
                        )
                        Text(crossReferences.sourceText, style = verseStyle, color = colors.text, modifier = Modifier.padding(top = 4.dp))
                    }
                }
                item {
                    Text(
                        stringResource(R.string.related_passages),
                        style = MaterialTheme.typography.labelLarge,
                        color = colors.secondaryText,
                        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 16.dp, bottom = 6.dp).semantics { heading() },
                    )
                    HorizontalDivider(color = colors.separator)
                }
                if (!crossReferences.loading && crossReferences.items.isEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.no_cross_references),
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.secondaryText,
                            modifier = Modifier.padding(20.dp),
                        )
                    }
                }
                items(crossReferences.items, key = { it.reference.target.rawValue * 31 + it.reference.targetEnd.rawValue }) { item ->
                    Column(Modifier.fillMaxWidth().clickable { onOpen(item.reference.target) }.padding(horizontal = 20.dp, vertical = 12.dp)) {
                        Text(item.title, style = MaterialTheme.typography.labelLarge, color = colors.accent)
                        Text(item.text, style = verseStyle, color = colors.text, maxLines = 4, modifier = Modifier.padding(top = 4.dp))
                    }
                    HorizontalDivider(Modifier.padding(start = 20.dp), color = colors.separator)
                }
                if (!crossReferences.loading) {
                    item {
                        Text(
                            stringResource(R.string.cross_references_attribution),
                            style = MaterialTheme.typography.bodySmall,
                            color = colors.secondaryText,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                        )
                    }
                }
            }
        }
    }
}
