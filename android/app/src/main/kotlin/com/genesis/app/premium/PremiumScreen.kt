package com.genesis.app.premium

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlinx.coroutines.launch

/** Anywhere Premium is locked asks for the Premium screen here; AppShell shows it over everything. */
object Paywall {
    var isShown: Boolean by mutableStateOf(false)
        private set

    fun open() {
        if (!Entitlements.isPremium) isShown = true
    }

    /** Settings › Versely Premium: also when Premium is on (to manage it). */
    fun openAlways() {
        isShown = true
    }

    fun close() {
        isShown = false
    }
}

/** What Premium includes, as PremiumFeature on iOS (the study assistant isn't on Android). */
private enum class PremiumItem(val title: Int, val detail: Int) {
    MORNING_WELCOME(R.string.pf_morning_welcome, R.string.pf_morning_welcome_detail),
    WORD_STUDY(R.string.pf_word_study, R.string.pf_word_study_detail),
    THEMES(R.string.pf_themes, R.string.pf_themes_detail),
    HISTORICAL(R.string.pf_historical, R.string.pf_historical_detail),
    INSIGHTS(R.string.pf_insights, R.string.pf_insights_detail),
    SEARCH(R.string.pf_search, R.string.pf_search_detail),
    AMBIENT(R.string.ambient_sounds_lower, R.string.pf_ambient_detail),
    MEMORISE(R.string.memorise_title, R.string.memorise_premium_message),
    WIDGETS(R.string.pf_widgets, R.string.pf_widgets_detail_android),
    JOURNAL(R.string.pf_journal, R.string.pf_journal_detail_android),
    BIBLES(R.string.pf_bibles, R.string.pf_bibles_detail),
}

/**
 * The Versely Premium screen, as PremiumView on iOS: what it includes,
 * monthly or yearly (Google Play has no Family Sharing for subscriptions,
 * so Android offers the Individual plan), restore, and Google Play's terms.
 */
@Composable
fun PremiumScreen(onDone: () -> Unit, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val billing = app.billing
    val state by billing.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val uri = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    var yearly by rememberSaveable { mutableStateOf(true) }
    var message by remember { mutableStateOf<Int?>(null) }
    val catalog by app.bibles.catalog.collectAsStateWithLifecycle()
    val hasPremiumBibles = catalog.any { it.premium && !it.isYouVersion }
    LaunchedEffect(Unit) { billing.start() }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.versely_premium),
                style = MaterialTheme.typography.titleMedium,
                color = colors.secondaryText,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.close), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp).widthIn(max = 560.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("✦", color = colors.accent, style = MaterialTheme.typography.headlineMedium)
                Text(
                    stringResource(if (Entitlements.isPremium) R.string.premium_you_have else R.string.premium_go_deeper),
                    style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                    color = colors.text,
                    modifier = Modifier.semantics { heading() },
                )
                if (!Entitlements.isPremium) {
                    Text(stringResource(R.string.premium_free_always), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                }
            }

            if (Entitlements.isPremium) {
                ActiveCard(onManage = { uri.openUri(PlayBilling.manageURL(context.packageName)) })
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
                    PremiumItem.entries.filter { it != PremiumItem.BIBLES || hasPremiumBibles }.forEach { item ->
                        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                            Text("✓", color = colors.accent, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 2.dp))
                            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                Text(stringResource(item.title), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
                                Text(stringResource(item.detail), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                            }
                        }
                    }
                }

                if (!state.loaded) {
                    CircularProgressIndicator(color = colors.accent, modifier = Modifier.align(Alignment.CenterHorizontally))
                } else if (!state.isAvailable) {
                    Text(stringResource(R.string.premium_unavailable_android), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                } else {
                    val selected = state.plans.firstOrNull { it.yearly == yearly } ?: state.plans.first()
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        state.plans.sortedByDescending { it.yearly }.forEach { plan ->
                            val isSelected = plan == selected
                            Row(
                                Modifier.fillMaxWidth()
                                    .background(colors.surface, RoundedCornerShape(16.dp))
                                    .border(if (isSelected) 2.dp else 1.dp, if (isSelected) colors.accent else colors.separator, RoundedCornerShape(16.dp))
                                    .clickable { yearly = plan.yearly }
                                    .semantics { role = Role.RadioButton; this.selected = isSelected }
                                    .padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Column(Modifier.weight(1f)) {
                                    Text(stringResource(if (plan.yearly) R.string.plan_yearly else R.string.plan_monthly), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
                                    if (plan.yearly) Text(stringResource(R.string.best_value), style = MaterialTheme.typography.bodySmall, color = colors.accent)
                                }
                                Text(
                                    stringResource(if (plan.yearly) R.string.price_per_year else R.string.price_per_month, plan.price),
                                    style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, color = colors.text,
                                )
                            }
                        }
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                val activity = context.findActivity() ?: return@Button
                                message = null
                                scope.launch {
                                    message = when (billing.purchase(activity, selected.yearly)) {
                                        PlayBilling.Outcome.PURCHASED -> { onDone(); null }
                                        PlayBilling.Outcome.PENDING -> R.string.purchase_waiting
                                        PlayBilling.Outcome.CANCELLED -> null
                                        PlayBilling.Outcome.FAILED -> R.string.purchase_failed_android
                                    }
                                }
                            },
                            enabled = !state.isPurchasing,
                            colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                            modifier = Modifier.fillMaxWidth(),
                        ) {
                            if (state.isPurchasing) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                            else Text(selected.trialDays?.let { stringResource(R.string.try_free_days, it) } ?: stringResource(R.string.subscribe), fontWeight = FontWeight.SemiBold)
                        }
                        if (selected.trialDays != null) {
                            Text(
                                stringResource(if (selected.yearly) R.string.trial_terms_android_year else R.string.trial_terms_android_month, selected.price),
                                style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
            }
            message?.let { Text(stringResource(it), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth()) }

            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                TextButton(onClick = {
                    scope.launch { message = if (billing.refresh()) R.string.premium_restored else R.string.no_play_subscription }
                }) { Text(stringResource(R.string.restore_purchases), color = colors.accent) }
                Text(stringResource(R.string.play_terms), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                if (catalog.any { it.isYouVersion }) {
                    Text(stringResource(R.string.settings_youversion_free), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                }
                TextButton(onClick = { uri.openUri(PRIVACY_URL) }) { Text(stringResource(R.string.privacy_policy), color = colors.accent, style = MaterialTheme.typography.bodySmall) }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun ActiveCard(onManage: () -> Unit) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (Entitlements.hasPlaySubscription) {
            Text(stringResource(R.string.premium_play_active), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
            TextButton(onClick = onManage) { Text(stringResource(R.string.manage_subscription), color = colors.accent) }
        } else if (Entitlements.hasGrant) {
            val end = Entitlements.grantEndsAt?.atZone(ZoneId.systemDefault())?.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG))
            Text(
                end?.let { stringResource(R.string.premium_given_until, it) } ?: stringResource(R.string.premium_given),
                style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.SemiBold, color = colors.text,
            )
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

private const val PRIVACY_URL = "https://www.7twenty8studio.com/versely/privacy"
