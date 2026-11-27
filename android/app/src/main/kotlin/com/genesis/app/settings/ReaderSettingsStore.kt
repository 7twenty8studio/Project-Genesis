package com.genesis.app.settings

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import com.genesis.app.BuildConfig
import androidx.core.content.edit
import com.genesis.core.domain.reader.ReaderPreferences
import com.genesis.core.domain.study.HighlightColor
import com.genesis.core.domain.study.RecentHighlightColors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The reader's settings on this device, as iOS keeps them in UserDefaults
 * ("reader.preferences.v1", JSON). One store for the app process.
 */
class ReaderSettingsStore(context: Context) {
    private val prefs = context.getSharedPreferences("reader", Context.MODE_PRIVATE)
    private val _preferences = MutableStateFlow(ReaderPreferences.decoded(prefs.getString(KEY, null)))
    val preferences: StateFlow<ReaderPreferences> = _preferences.asStateFlow()

    private val _recentColors = MutableStateFlow(
        prefs.getString(RECENT_COLORS, null).orEmpty().split(',').filter { it.isNotEmpty() }.map(HighlightColor::withId),
    )

    /** The highlight colours used most recently, first in the selection bar. */
    val recentColors: StateFlow<List<HighlightColor>> = _recentColors.asStateFlow()

    fun used(color: HighlightColor) {
        val next = RecentHighlightColors.after(color, _recentColors.value)
        _recentColors.value = next
        prefs.edit { putString(RECENT_COLORS, next.joinToString(",") { it.id }) }
    }

    /** The Bible being read ("library.currentTranslation" on iOS), or null before setup. */
    var currentBible: String?
        get() = prefs.getString(CURRENT_BIBLE, null)
        set(value) = prefs.edit { putString(CURRENT_BIBLE, value) }

    private val _onboardingComplete = MutableStateFlow(prefs.getBoolean(ONBOARDING, false))

    /** True once first-launch setup is done ("onboarding.complete" on iOS). */
    val onboardingComplete: StateFlow<Boolean> = _onboardingComplete.asStateFlow()

    fun completeOnboarding() {
        _onboardingComplete.value = true
        prefs.edit { putBoolean(ONBOARDING, true) }
    }

    fun update(change: (ReaderPreferences) -> ReaderPreferences) {
        val next = change(_preferences.value).clamped()
        _preferences.value = next
        prefs.edit { putString(KEY, next.encoded()) }
    }

    private companion object {
        const val KEY = "reader.preferences.v1"
        const val RECENT_COLORS = "highlights.recentColors"
        const val CURRENT_BIBLE = "library.currentTranslation"
        const val ONBOARDING = "onboarding.complete"
    }
}

/** The highlight colours used most recently, for the selection bar. */
val LocalRecentColors = staticCompositionLocalOf<androidx.compose.runtime.State<List<HighlightColor>>> {
    androidx.compose.runtime.mutableStateOf(emptyList())
}

/**
 * The reader's settings for the screens below the activity, as they apply
 * now: night reading's theme in place of the day theme while it's night,
 * and the text size fixed when it doesn't follow the phone's font size.
 */
val LocalReaderPreferences = staticCompositionLocalOf { ReaderPreferences() }

/** The settings as the person chose them (the Aa sheet shows and changes these). */
val LocalChosenReaderPreferences = staticCompositionLocalOf { ReaderPreferences() }

/**
 * The settings as they apply now: night reading's theme (ReaderSettings.effectiveTheme
 * on iOS), and the size held still against the phone's font scale when it isn't followed.
 */
@androidx.compose.runtime.Composable
fun rememberEffectivePreferences(chosen: ReaderPreferences): ReaderPreferences {
    val systemIsDark = androidx.compose.foundation.isSystemInDarkTheme()
    val fontScale = androidx.compose.ui.platform.LocalDensity.current.fontScale
    // Moved on at each edge of the night window, so the theme switches on time.
    var clock by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf(java.time.ZonedDateTime.now()) }
    androidx.compose.runtime.LaunchedEffect(chosen.nightReading, clock) {
        val next = com.genesis.core.domain.reader.NightReading.nextChange(clock, chosen.nightReading) ?: return@LaunchedEffect
        kotlinx.coroutines.delay(java.time.Duration.between(java.time.ZonedDateTime.now(), next).toMillis().coerceAtLeast(1_000) + 500)
        clock = java.time.ZonedDateTime.now()
    }
    val theme = com.genesis.core.domain.reader.NightReading.theme(chosen.nightReading, chosen.theme, clock.toLocalDateTime(), systemIsDark, Entitlements.isPremium)
    return chosen.copy(
        theme = theme,
        fontSize = if (chosen.followsDynamicType) chosen.fontSize else chosen.fontSize / fontScale,
    )
}

/**
 * Whether this person has Premium, as EntitlementService on iOS. Today that's
 * a grant the owner gave (public.premium_grants, from Studio OS), checked on
 * launch, return and sign-in, with a saved end date that ends it offline
 * too; debug builds also have Settings › Developer › Test as Premium. Play
 * Billing subscriptions join here when the Play account is ready.
 */
object Entitlements {
    var isPremium: Boolean by mutableStateOf(false)
        private set

    private const val TEST_KEY = "premium.testAsPremium"
    private const val GRANT_KEY = "premium.grant"
    private const val GRANT_ENDS_KEY = "premium.grantEnds"
    private const val PLAY_KEY = "premium.play"
    /** Settings › Developer › Test as Premium (debug builds). */
    var isTestingPremium: Boolean by mutableStateOf(false)
        private set
    private var testing: Boolean
        get() = isTestingPremium
        set(value) { isTestingPremium = value }
    private var grant = com.genesis.core.domain.premium.PremiumGrant.NONE

    /** A Google Play subscription this phone's Google account has (PlayBilling). */
    var hasPlaySubscription: Boolean by mutableStateOf(false)
        private set
    private var appContext: Context? = null

    /** Whether Premium came from the owner's grant (and its end), for the Premium screen. */
    val grantEndsAt: java.time.Instant? get() = grant.endsAt.takeIf { grant.isActive() }
    val hasGrant: Boolean get() = grant.isActive()

    private fun prefs(context: Context) = context.getSharedPreferences("premium", Context.MODE_PRIVATE)

    fun load(context: Context) {
        appContext = context.applicationContext
        val prefs = prefs(context)
        hasPlaySubscription = prefs.getBoolean(PLAY_KEY, false)
        testing = BuildConfig.DEBUG && prefs.getBoolean(TEST_KEY, false)
        val ends = prefs.getLong(GRANT_ENDS_KEY, 0L).takeIf { it > 0 }?.let(java.time.Instant::ofEpochMilli)
        grant = com.genesis.core.domain.premium.PremiumGrant(prefs.getBoolean(GRANT_KEY, false), ends)
        recompute()
    }

    fun setTestingPremium(context: Context, on: Boolean) {
        if (!BuildConfig.DEBUG) return
        prefs(context).edit { putBoolean(TEST_KEY, on) }
        testing = on
        recompute()
    }

    /** Asks the server for this account's grant; offline, keeps what was known unless its end date passed. */
    suspend fun refreshGrant(app: com.genesis.app.VerselyApplication) {
        val client = app.account.client
        val signedIn = app.account.state.value.user != null
        val next = if (client == null || !signedIn) {
            com.genesis.core.domain.premium.PremiumGrant.NONE
        } else {
            runCatching {
                val token = app.account.accessToken()
                val text = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                    client.select("premium_grants", listOf("select" to "expires_at"), token)
                }
                val rows = kotlinx.serialization.json.Json.parseToJsonElement(text.ifEmpty { "[]" }) as kotlinx.serialization.json.JsonArray
                val row = rows.firstOrNull() as? kotlinx.serialization.json.JsonObject
                val ends = (row?.get("expires_at") as? kotlinx.serialization.json.JsonPrimitive)?.takeIf { it.isString }?.content
                com.genesis.core.domain.premium.PremiumGrant.from(row != null, ends)
            }.getOrElse { if (grant.isActive()) grant else com.genesis.core.domain.premium.PremiumGrant.NONE }
        }
        grant = if (next.isActive()) next else com.genesis.core.domain.premium.PremiumGrant.NONE
        prefs(app).edit {
            putBoolean(GRANT_KEY, grant.active)
            grant.endsAt?.let { putLong(GRANT_ENDS_KEY, it.toEpochMilli()) } ?: remove(GRANT_ENDS_KEY)
        }
        recompute()
        AppIcons.apply(app)
    }

    /** Google Play answered: kept for the next launch, when Play may not have answered yet. */
    fun setPlaySubscription(active: Boolean) {
        hasPlaySubscription = active
        appContext?.let { prefs(it).edit { putBoolean(PLAY_KEY, active) } }
        recompute()
        appContext?.let { AppIcons.apply(it) }
    }

    private fun recompute() {
        isPremium = testing || grant.isActive() || hasPlaySubscription
    }
}
