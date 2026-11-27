package com.genesis.app.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontFamily
import androidx.glance.text.FontStyle
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import androidx.compose.ui.graphics.Color
import com.genesis.app.MainActivity
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.BundledBible
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.home.DailyVerse
import com.genesis.core.domain.home.TextFit
import com.genesis.core.domain.link.GenesisLink
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.LocalDateTime
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.glance.appwidget.state.getAppWidgetState
import androidx.glance.state.PreferencesGlanceStateDefinition
import androidx.glance.layout.fillMaxWidth
import com.genesis.app.settings.Entitlements
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.widgets.CategoryPassage
import com.genesis.core.domain.widgets.ReadingVersePicker
import com.genesis.core.domain.widgets.VerseCategories
import com.genesis.core.domain.widgets.VerseWidgetSchedule
import com.genesis.core.domain.widgets.VerseWidgetSource
import com.genesis.core.domain.widgets.WidgetVerses
import java.time.ZoneId
import java.util.Locale

/**
 * The Verse of the Day widget, free in Versely's Classic look at every size
 * (WidgetAccess on iOS): the day's verse verbatim from the Bible being read,
 * its reference, and a tap that opens the reader there. The brand's cream,
 * copper and walnut, walnut at night (WidgetPalette). Premium backgrounds,
 * Verse of the Day and Random Verse are free; the categories and From Your
 * Reading are Premium (VerseWidgetIntent on iOS), chosen when the widget is
 * placed or by reconfiguring it. Painted backgrounds come with scene themes.
 */
class VerseOfTheDayWidget : GlanceAppWidget() {
    // Exact, so LocalSize is the widget's real size and the verse can be fitted
    // to it (Responsive gives the size bucket, which is far smaller).
    override val sizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val source = VerseWidgetSource.of(
            runCatching { getAppWidgetState(context, PreferencesGlanceStateDefinition, id)[SOURCE] }.getOrNull(),
        )
        val day = load(context, source)
        // Its background: its own, or the one chosen in Versely; Classic (with a Premium tag) without Premium.
        val own = runCatching { getAppWidgetState(context, PreferencesGlanceStateDefinition, id)[BACKGROUND] }.getOrNull()
        val wanted = com.genesis.core.domain.widgets.VerseWidgetBackground.resolve(own, WidgetStylePreference.current(context))
        val style = wanted.shown(Entitlements.isPremium)
        val art = if (style.isPainted) withContext(Dispatchers.IO) {
            com.genesis.core.domain.widgets.WidgetArtShape.entries.associateWith { WidgetArt.load(context, style, it) }
        } else emptyMap()
        // A painted style whose pictures aren't drawn yet shows Classic until they are.
        val look = WidgetLook.of(if (art.values.any { it != null }) style else com.genesis.core.domain.widgets.WidgetArtStyle.CLASSIC, art, styleTag = wanted != style)
        provideContent { Content(day, look) }
    }

    /**
     * The widget's verse, read once per update, verbatim: from the person's
     * Bible, or the KJV where their Bible numbers a passage differently. A
     * Premium option without Premium shows the verse of the day with a
     * Premium tag (never a locked card); anything not found falls back to it.
     */
    private suspend fun load(context: Context, chosen: VerseWidgetSource): WidgetVerse? = withContext(Dispatchers.IO) {
        val app = context.applicationContext as VerselyApplication
        val bible = app.currentBible
        val zone = ZoneId.systemDefault()
        val now = LocalDateTime.now(zone)
        val locked = chosen.needsPremium && !Entitlements.isPremium
        val source = if (locked) VerseWidgetSource.VERSE_OF_THE_DAY else chosen
        val day = VerseWidgetSchedule.dayNumber(now.toLocalDate(), zone)
        runCatching {
            BibleRepository.open(context, bible).use { repository ->
                val translation = repository.translation
                fun passage(item: CategoryPassage): WidgetVerse? {
                    val own = WidgetVerses.usesOwnBible(item, translation.id)
                    val found = if (own) repository.verses(item.verseIds) else BibleRepository.open(context, com.genesis.core.bible.BundledBible.KJV).use { it.verses(item.verseIds) }
                    val verses = item.verseIds.mapNotNull { found[it] }
                    if (verses.size != item.verseIds.size) return null
                    val shown = if (own) translation else null
                    return WidgetVerse(
                        link = GenesisLink.read(item.start),
                        text = verses.joinToString(" ") { it.displayText },
                        citation = item.reference.description(shown?.language ?: "en") + " · " + (shown?.abbreviation ?: "KJV"),
                        title = source,
                        premiumTag = locked,
                    )
                }
                fun rotating(pool: List<CategoryPassage>) = VerseWidgetSchedule.index(now, pool.size, zone)?.let { passage(pool[it]) }
                val picked = when (source) {
                    VerseWidgetSource.VERSE_OF_THE_DAY -> null
                    VerseWidgetSource.RANDOM -> rotating(WidgetVerses.randomPool(day))
                    VerseWidgetSource.FROM_YOUR_READING -> {
                        val chapters = app.progress.recentChapters(7, now.toLocalDate())
                        ReadingVersePicker.pick(chapters, day, { key -> runCatching { repository.chapter(ChapterId(key / 1_000, key % 1_000)).verses }.getOrDefault(emptyList()) }, { it.plainText })?.let { verse ->
                            WidgetVerse(
                                link = GenesisLink.read(verse.id),
                                text = verse.displayText,
                                citation = ReferenceParser.describe(verse.id.rawValue, language = translation.language) + " · " + translation.abbreviation,
                                title = source,
                            )
                        }
                    }
                    else -> source.category?.let { rotating(VerseCategories.passages(it)) }
                }
                picked ?: run {
                    val verse = DailyVerse.verse(now.toLocalDate(), zone)
                    val text = repository.verses(listOf(verse))[verse]?.displayText ?: return@use null
                    WidgetVerse(
                        link = GenesisLink.read(verse),
                        text = text,
                        citation = ReferenceParser.describe(verse.rawValue, language = translation.language) + " · " + translation.abbreviation,
                        title = VerseWidgetSource.VERSE_OF_THE_DAY,
                        premiumTag = locked,
                    )
                }
            }
        }.onFailure { Log.e(TAG, "Couldn't read the widget's verse", it) }.getOrNull()
    }

    @Composable
    private fun Content(day: WidgetVerse?, look: WidgetLook) {
        val size = LocalSize.current
        val picture = look.art[com.genesis.core.domain.widgets.WidgetArtShape.of(size.width.value, size.height.value)]
        val small = size.width < MEDIUM.width
        val padding = if (small) 14.dp else 18.dp
        // The verse's box: the widget less its padding, the eyebrow and the citation.
        val fit = TextFit.fit(
            characters = day?.text?.length ?: 0,
            widthDp = (size.width - padding * 2).value.toDouble(),
            heightDp = (size.height - padding * 2 - (if (small) 6.dp else 10.dp) - 14.dp - 24.dp).value.toDouble(),
            largest = if (size.height >= LARGE.height) 20 else if (small) 15 else 17,
            smallest = 11,
        )
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(day?.link ?: "versely://read"))
            .setClass(androidx.glance.LocalContext.current, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(picture?.let { ImageProvider(it) } ?: ImageProvider(R.drawable.widget_background))
                .cornerRadius(20.dp)
                .padding(padding)
                .clickable(actionStartActivity(open)),
            verticalAlignment = Alignment.Top,
        ) {
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Eyebrow(androidx.glance.LocalContext.current.getString((day?.title ?: VerseWidgetSource.VERSE_OF_THE_DAY).titleRes), look.accent)
                if (day?.premiumTag == true || look.styleTag) {
                    Spacer(GlanceModifier.defaultWeight())
                    Text(
                        androidx.glance.LocalContext.current.getString(R.string.premium),
                        style = TextStyle(color = look.accent, fontWeight = FontWeight.Bold, fontSize = 9.sp),
                    )
                }
            }
            Spacer(GlanceModifier.height(if (small) 6.dp else 10.dp))
            Text(
                day?.text ?: "",
                maxLines = fit.maxLines,
                style = TextStyle(
                    color = look.text,
                    fontFamily = FontFamily.Serif,
                    fontSize = fit.fontSizeSp.sp,
                ),
                modifier = GlanceModifier.defaultWeight(),
            )
            if (day != null) {
                Spacer(GlanceModifier.height(6.dp))
                Text(
                    day.citation,
                    maxLines = 1,
                    style = TextStyle(color = look.secondary, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, fontSize = 12.sp),
                )
            }
        }
    }

    private data class WidgetVerse(
        val link: String,
        val text: String,
        val citation: String,
        val title: VerseWidgetSource = VerseWidgetSource.VERSE_OF_THE_DAY,
        val premiumTag: Boolean = false,
    )

    companion object {
        private const val TAG = "VerseWidget"

        /** The widget's chosen option (VerseWidgetSource.raw), kept in its own Glance state. */
        val SOURCE = stringPreferencesKey("verse.source")

        /** The widget's own Background ("app", the default, follows Widget Styles), kept in its Glance state. */
        val BACKGROUND = stringPreferencesKey("verse.background")
        private val MEDIUM = DpSize(250.dp, 110.dp)
        private val LARGE = DpSize(250.dp, 260.dp)

        /** Redraws every placed widget (the Bible changed, or the app opened on a new day). */
        suspend fun refresh(context: Context) = VerselyWidgets.refresh(context)
    }
}

/** The small capitals above the verse, per option (as iOS: Random Verse reads "A Verse for You"). */
internal val VerseWidgetSource.titleRes: Int
    get() = when (this) {
        VerseWidgetSource.VERSE_OF_THE_DAY -> R.string.verse_of_the_day
        VerseWidgetSource.RANDOM -> R.string.a_verse_for_you
        VerseWidgetSource.FROM_YOUR_READING -> R.string.from_your_reading
        VerseWidgetSource.HOPE -> R.string.category_hope
        VerseWidgetSource.PEACE -> R.string.category_peace
        VerseWidgetSource.FAITH -> R.string.category_faith
        VerseWidgetSource.STRENGTH -> R.string.category_strength
        VerseWidgetSource.COMFORT -> R.string.category_comfort
        VerseWidgetSource.LOVE -> R.string.category_love
        VerseWidgetSource.GRATITUDE -> R.string.category_gratitude
        VerseWidgetSource.GUIDANCE -> R.string.category_guidance
    }

/** The option's name in the widget's settings (Random Verse by its own name there). */
internal val VerseWidgetSource.optionRes: Int
    get() = if (this == VerseWidgetSource.RANDOM) R.string.source_random else titleRes

/**
 * What a verse widget wears: its painted pictures (one per shape) and the
 * ink that reads on them, as WidgetArtInk on iOS: light on Night and the
 * scenes, the paper's own colours on the others, the brand's on Classic.
 */
internal data class WidgetLook(
    val art: Map<com.genesis.core.domain.widgets.WidgetArtShape, android.graphics.Bitmap?>,
    val text: androidx.glance.unit.ColorProvider,
    val secondary: androidx.glance.unit.ColorProvider,
    val accent: androidx.glance.unit.ColorProvider,
    /** A Premium style chosen without Premium: Classic, with a Premium tag. */
    val styleTag: Boolean = false,
) {
    companion object {
        fun of(style: com.genesis.core.domain.widgets.WidgetArtStyle, art: Map<com.genesis.core.domain.widgets.WidgetArtShape, android.graphics.Bitmap?>, styleTag: Boolean): WidgetLook {
            if (!style.isPainted) return WidgetLook(emptyMap(), WidgetPalette.text, WidgetPalette.secondary, WidgetPalette.accent, styleTag)
            fun fixed(hex: Long) = androidx.glance.unit.ColorProvider(Color(hex))
            if (style.isDark) return WidgetLook(art, fixed(0xFFF6EEE2), fixed(0xFFDCCBB6), fixed(0xFFEBC08F), styleTag)
            val palette = (com.genesis.core.domain.share.VerseImageStyle.entries.firstOrNull { it.rawValue == style.rawValue }
                ?: com.genesis.core.domain.share.VerseImageStyle.PAPER).theme(com.genesis.core.domain.theme.ReaderTheme.PAPER).palette
            return WidgetLook(art, fixed(0xFF000000 or palette.text.toLong()), fixed(0xFF000000 or palette.secondaryText.toLong()), fixed(0xFF000000 or palette.accent.toLong()), styleTag)
        }
    }
}
