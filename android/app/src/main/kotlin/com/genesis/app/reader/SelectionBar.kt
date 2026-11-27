package com.genesis.app.reader

import android.content.ClipData
import android.content.Intent
import android.widget.Toast
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.ClipEntry
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.study.HighlightColor
import kotlinx.coroutines.launch

/**
 * The bar that replaces the chapter buttons while verses are selected, as
 * SelectionActionBar on iOS: the reference and ×, then the colours (the
 * three most recent first), Note, Related (cross references), Bookmark, Remove when a selected verse is
 * highlighted, Copy and Share.
 */
@Composable
internal fun SelectionBar(
    reference: String,
    shareText: String,
    colorsInOrder: List<HighlightColor>,
    anyHighlighted: Boolean,
    isBookmarked: Boolean,
    onHighlight: (HighlightColor) -> Unit,
    onRemoveHighlight: () -> Unit,
    onBookmark: () -> Unit,
    onNote: () -> Unit,
    onCrossReferences: () -> Unit,
    onMemorise: () -> Unit,
    onWordStudy: () -> Unit,
    onStudy: () -> Unit,
    onDone: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val copied = stringResource(R.string.copied)

    Column(Modifier.fillMaxWidth().background(colors.surface).navigationBarsPadding()) {
        HorizontalDivider(color = colors.separator)
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 4.dp, top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(reference, style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.weight(1f))
            val done = stringResource(R.string.done_selecting)
            TextButton(onClick = onDone, modifier = Modifier.semantics { contentDescription = done }) {
                Text("✕", color = colors.secondaryText, fontSize = 18.sp)
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            for (color in colorsInOrder) {
                val label = stringResource(R.string.highlight_color, stringResource(color.title))
                Spacer(
                    Modifier
                        .size(30.dp)
                        .background(Color(0xFF000000 or color.hex.toLong()), CircleShape)
                        .border(1.dp, colors.separator, CircleShape)
                        .clickable(onClickLabel = label) { onHighlight(color) }
                        .semantics {
                            contentDescription = label
                            role = Role.Button
                        },
                )
            }
        }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 4.dp)) {
            Action(R.string.note, onNote)
            Action(R.string.related, onCrossReferences)
            Action(R.string.word_study, onWordStudy)
            Action(R.string.study_action, onStudy)
            // Memorize is Premium; without it the action isn't offered here.
            if (com.genesis.app.settings.Entitlements.isPremium) {
                val added = stringResource(R.string.memorise_added)
                Action(R.string.memorise) {
                    onMemorise()
                    android.widget.Toast.makeText(context, added, android.widget.Toast.LENGTH_SHORT).show()
                }
            }
            Action(if (isBookmarked) R.string.remove_bookmark else R.string.bookmark, onBookmark)
            if (anyHighlighted) Action(R.string.remove_highlight, onRemoveHighlight)
            Action(R.string.copy) {
                scope.launch { clipboard.setClipEntry(ClipEntry(ClipData.newPlainText(reference, shareText))) }
                Toast.makeText(context, copied, Toast.LENGTH_SHORT).show()
                onDone()
            }
            Action(R.string.share) {
                val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, shareText)
                context.startActivity(Intent.createChooser(send, null))
                onDone()
            }
            Spacer(Modifier.width(4.dp))
        }
    }
}

@Composable
private fun Action(@StringRes title: Int, onClick: () -> Unit) {
    TextButton(onClick = onClick) {
        Text(stringResource(title), color = LocalReaderColors.current.accent)
    }
}

@get:StringRes
internal val HighlightColor.title: Int
    get() = when (this) {
        HighlightColor.YELLOW -> R.string.color_yellow
        HighlightColor.BLUE -> R.string.color_blue
        HighlightColor.GREEN -> R.string.color_green
        HighlightColor.PURPLE -> R.string.color_purple
        HighlightColor.PINK -> R.string.color_pink
        HighlightColor.ORANGE -> R.string.color_orange
    }
