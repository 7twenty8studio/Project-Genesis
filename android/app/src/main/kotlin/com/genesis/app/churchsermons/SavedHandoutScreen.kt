package com.genesis.app.churchsermons

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Header
import com.genesis.core.cloud.community.ChurchPassageBible
import com.genesis.core.cloud.community.SavedHandout
import com.genesis.core.cloud.community.SavedHandouts
import com.genesis.core.cloud.community.SermonAnswers
import com.genesis.core.cloud.community.SermonReference
import com.genesis.core.design.LocalReaderColors
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** Sermon Notes' list of the church handouts the person filled in (newest first). */
@Composable
internal fun SavedHandoutsSection(handoutsJson: String?, onOpen: (SavedHandout) -> Unit) {
    val colors = LocalReaderColors.current
    val handouts = remember(handoutsJson) { SavedHandouts.decode(handoutsJson) }
    if (handouts.isEmpty()) return
    Header(stringResource(R.string.your_handout))
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(colors.surface)) {
        handouts.reversed().forEach { handout ->
            val day = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(Instant.ofEpochMilli(handout.savedAt).atZone(ZoneId.systemDefault()))
            Row(Modifier.fillMaxWidth().clickable { onOpen(handout) }.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(handout.title.ifEmpty { stringResource(R.string.your_handout) }, color = colors.text)
                    Text(
                        stringResource(if (handout.hasKey) R.string.saved_on_with_key else R.string.saved_on, day),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.secondaryText,
                    )
                }
                Text("›", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
            }
        }
    }
    Footer(stringResource(R.string.saved_handouts_footer))
}

/**
 * The member's saved work on a church's handout, as SavedHandoutView on
 * iOS: the revision they filled in (it still opens after an unpublish) and
 * their answers, checkable only with the key saved for that revision.
 */
@Composable
internal fun SavedHandoutScreen(handout: SavedHandout, context: ChurchSermonContext?, onSave: (Map<Int, String>) -> Unit, onDone: () -> Unit) {
    val colors = LocalReaderColors.current
    BackHandler(onBack = onDone)
    val state = remember(handout.id) {
        HandoutState(handout.blanks, if (handout.hasKey) SermonAnswers.REVEALED else SermonAnswers.HIDDEN, handout.responses, save = onSave)
    }
    var passage by remember { mutableStateOf<SermonReference?>(null) }
    var passageBible by remember { mutableStateOf<String?>(null) }
    val shownBible = context?.let { ChurchPassageBible.shown(ChurchPassageBible.options(it.currentBible, passageBible, null) { id -> id in it.bibles }, passageBible) } ?: "KJV"
    Column(Modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.your_handout), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.weight(1f))
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Column(Modifier.widthIn(max = 680.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(handout.church.uppercase(), style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
                Text(
                    handout.title.ifEmpty { stringResource(R.string.sermon_untitled) },
                    style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                    color = colors.text,
                    modifier = Modifier.semantics { heading() },
                )
                val saved = DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).format(Instant.ofEpochMilli(handout.savedAt).atZone(ZoneId.systemDefault()))
                Text(stringResource(R.string.saved_on, saved), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                handout.blocks.forEach { block ->
                    OutlineBlock(block, state, context?.language ?: "en", shownBible) { if (context != null) passage = it }
                }
                Box { HandoutBar(state) }
            }
        }
    }
    val ctx = context
    passage?.let { reference ->
        if (ctx != null) ChurchPassageSheet(reference.copy(translation = null), ctx, passageBible, onChoose = { passageBible = it }, onDismiss = { passage = null })
    }
}
