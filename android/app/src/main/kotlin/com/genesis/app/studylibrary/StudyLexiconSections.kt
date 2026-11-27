package com.genesis.app.studylibrary

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.original.FooterText
import com.genesis.app.original.Section
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.studyresources.StudyLexiconEntry
import com.genesis.core.domain.studyresources.StudyResourceKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Brown-Driver-Briggs and Liddell-Scott-Jones on a lexicon entry, from an
 * installed lexicon pack (Premium, like word study), as on iOS. Nothing
 * shows when no pack is installed or it has no entry for the word.
 */
@Composable
internal fun StudyLexiconSections(strongs: String) {
    if (!Entitlements.isPremium) return
    val colors = LocalReaderColors.current
    val library = (LocalContext.current.applicationContext as VerselyApplication).studyResources
    val installed by library.installed.collectAsStateWithLifecycle()
    val packs = library.installedResources(StudyResourceKind.LEXICON, installed)
    val entries by produceState<List<Pair<String, StudyLexiconEntry>>>(emptyList(), strongs, packs.map { it.id }) {
        value = withContext(Dispatchers.IO) {
            packs.flatMap { pack ->
                runCatching { library.repository(pack.id)?.lexicon(strongs).orEmpty() }.getOrDefault(emptyList()).map { pack.attribution.ifEmpty { pack.name } to it }
            }
        }
    }
    for ((credit, entry) in entries) {
        val title = if (entry.source == "lsj") R.string.lexicon_lsj else R.string.lexicon_bdb
        Section(stringResource(title), footer = { FooterText(credit) }) {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                val heading = listOf(entry.lemma, entry.transliteration).filter { it.isNotEmpty() }.joinToString(" · ")
                if (heading.isNotEmpty()) Text(heading, style = MaterialTheme.typography.bodyMedium.copy(fontStyle = FontStyle.Italic), color = colors.secondaryText)
                if (entry.gloss.isNotEmpty()) Text(entry.gloss, style = MaterialTheme.typography.titleSmall, color = colors.accent)
                if (entry.definition.isNotEmpty()) StudyText(entry.definition) {}
            }
        }
    }
}
