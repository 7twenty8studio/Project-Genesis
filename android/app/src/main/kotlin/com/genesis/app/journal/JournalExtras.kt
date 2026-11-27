package com.genesis.app.journal

import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.reader.PremiumTag
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.journal.JournalTemplate

/** A template as text in the app's language: plain for a prayer, Markdown for sermon notes. */
internal fun JournalTemplate.text(context: Context): String =
    text(words.parts.map { (heading, prompt) -> JournalTemplate.Part(context.getString(heading), context.getString(prompt)) })

/**
 * The editor's Premium extras, as JournalExtrasMenu on iOS: start from a
 * template, or export as a PDF. Without Premium the same menu shows them,
 * marked Premium, and they can't be chosen.
 */
@Composable
internal fun JournalExtrasMenu(sermon: Boolean, onTemplate: (String) -> Unit, onExport: () -> Unit) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val unlocked = Entitlements.isPremium
    var open by remember { mutableStateOf(false) }
    var templates by remember { mutableStateOf(false) }
    val more = stringResource(R.string.more)
    Box {
        TextButton(onClick = { open = true }, modifier = Modifier.semantics { contentDescription = more }) {
            Text("⋯", style = MaterialTheme.typography.titleLarge, color = colors.accent)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false; templates = false }) {
            if (!unlocked) {
                Row(Modifier.size(width = 200.dp, height = 36.dp), verticalAlignment = Alignment.CenterVertically) {
                    Spacer(Modifier.size(16.dp))
                    PremiumTag()
                }
            }
            if (templates) {
                JournalTemplate.templates(sermon).forEach { template ->
                    DropdownMenuItem(
                        text = { Text(stringResource(template.words.title)) },
                        enabled = unlocked,
                        onClick = {
                            open = false
                            templates = false
                            onTemplate(template.text(context))
                        },
                    )
                }
            } else {
                DropdownMenuItem(text = { Text(stringResource(R.string.templates) + "  ›") }, enabled = unlocked, onClick = { templates = true })
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(stringResource(R.string.export_pdf)) },
                    enabled = unlocked,
                    onClick = {
                        open = false
                        onExport()
                    },
                )
            }
        }
    }
}
