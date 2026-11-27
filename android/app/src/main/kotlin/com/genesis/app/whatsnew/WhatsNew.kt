package com.genesis.app.whatsnew

import android.content.Context
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.edit
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.FeatureFlags
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.features.titleRes
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.features.OptionalFeature
import com.genesis.core.domain.whatsnew.WhatsNewRules

/** One line in the What's New screen. */
data class WhatsNewItem(val symbol: String, @StringRes val title: Int, @StringRes val detail: Int)

/** A one-time note, as WhatsNewAnnouncement on iOS (same ids, so a note is one note everywhere). */
data class WhatsNewAnnouncement(
    val id: String,
    @StringRes val title: Int,
    val items: List<WhatsNewItem>,
    val flag: String? = null,
    val feature: OptionalFeature? = null,
)

/**
 * Android's notes. Versely for Android launches with every feature, so only
 * notes behind a server switch are news; add each new feature here with a
 * new, never reused id (and `flag` when a switch turns it on).
 */
object WhatsNewCatalog {
    val all: List<WhatsNewAnnouncement> = listOf(
        WhatsNewAnnouncement(
            "community", R.string.wn_community_title,
            listOf(
                WhatsNewItem("🙏", R.string.wn_community_wall, R.string.wn_community_wall_detail),
                WhatsNewItem("💬", R.string.wn_community_reflections, R.string.wn_community_reflections_detail),
                WhatsNewItem("🛡", R.string.wn_community_safe, R.string.wn_community_safe_detail),
            ),
            flag = FeatureFlags.COMMUNITY, feature = OptionalFeature.TOGETHER,
        ),
        WhatsNewAnnouncement(
            "church-sermons", R.string.wn_church_title,
            listOf(
                WhatsNewItem("▦", R.string.wn_church_outline, R.string.wn_church_outline_detail),
                WhatsNewItem("📖", R.string.wn_church_passages, R.string.wn_church_passages_detail),
                WhatsNewItem("✎", R.string.wn_church_notes, R.string.wn_church_notes_detail),
            ),
            flag = FeatureFlags.CHURCH_SERMONS, feature = OptionalFeature.CHURCH_SERMONS,
        ),
        WhatsNewAnnouncement(
            "church-sermon-handouts", R.string.wn_handouts_title,
            listOf(
                WhatsNewItem("✏", R.string.wn_handouts, R.string.wn_handouts_detail),
                WhatsNewItem("✓", R.string.wn_handouts_check, R.string.wn_handouts_check_detail),
            ),
            flag = FeatureFlags.CHURCH_SERMONS, feature = OptionalFeature.CHURCH_SERMONS,
        ),
    )
}

/** Remembers the notes this phone has seen ("whatsNew.seen", as iOS). */
class WhatsNewService(context: Context, private val catalog: List<WhatsNewAnnouncement> = WhatsNewCatalog.all) {
    private val defaults = context.getSharedPreferences("whatsNew", Context.MODE_PRIVATE)
    private fun entries() = catalog.map { WhatsNewRules.Entry(it.id, it.flag) }

    val seen: Set<String> get() = defaults.getStringSet(SEEN, emptySet()).orEmpty()

    fun pending(flags: Map<String, Boolean>): List<WhatsNewAnnouncement> {
        val ids = WhatsNewRules.pending(entries(), seen) { flags[it] == true }.map { it.id }
        return ids.mapNotNull { id -> catalog.firstOrNull { it.id == id } }
    }

    fun markSeen(announcements: List<WhatsNewAnnouncement>) {
        defaults.edit { putStringSet(SEEN, seen + announcements.map { it.id }) }
    }

    fun markShippedFeaturesSeen() {
        defaults.edit { putStringSet(SEEN, seen + WhatsNewRules.shippedIds(entries())) }
    }

    private companion object { const val SEEN = "whatsNew.seen" }
}

/** The one-time What's New screen, as WhatsNewView.swift. */
@Composable
fun WhatsNewScreen(announcements: List<WhatsNewAnnouncement>, onDone: () -> Unit) {
    val colors = LocalReaderColors.current
    val app = LocalContext.current.applicationContext as VerselyApplication
    val enabled by app.features.enabled.collectAsStateWithLifecycle()
    androidx.activity.compose.BackHandler(onBack = onDone)
    Column(Modifier.fillMaxSize().background(colors.background).statusBarsPadding().navigationBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(24.dp).widthIn(max = 560.dp).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    stringResource(R.string.whats_new),
                    style = MaterialTheme.typography.headlineLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                    color = colors.text,
                    modifier = Modifier.semantics { heading() },
                )
                Text(stringResource(R.string.whats_new_subtitle), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
            }
            for (announcement in announcements) {
                Column(verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    Text(stringResource(announcement.title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
                    for (item in announcement.items) {
                        Row(Modifier.semantics(mergeDescendants = true) {}, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            Text(item.symbol, fontSize = 20.sp, color = colors.accent, modifier = Modifier.width(32.dp))
                            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                                Text(stringResource(item.title), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
                                Text(stringResource(item.detail), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                            }
                        }
                    }
                    val feature = announcement.feature
                    if (feature != null && feature !in enabled) {
                        // They hid this kind of feature; let them choose.
                        OutlinedButton(onClick = { app.features.set(feature, true) }) {
                            Text("＋ " + stringResource(R.string.whats_new_turn_on, stringResource(feature.titleRes)), color = colors.accent)
                        }
                    } else if (feature != null) {
                        Text(stringResource(R.string.whats_new_on), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                    }
                }
            }
        }
        Button(
            onClick = onDone,
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
            modifier = Modifier.padding(horizontal = 24.dp, vertical = 12.dp).widthIn(max = 560.dp).fillMaxWidth(),
        ) { Text(stringResource(R.string.continue_button), fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(vertical = 6.dp)) }
    }
}
