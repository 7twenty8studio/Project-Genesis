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
import com.genesis.core.domain.link.GenesisLink
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

/**
 * The Verse of the Day widget, free in Versely's Classic look at every size
 * (WidgetAccess on iOS): the day's verse verbatim from the Bible being read,
 * its reference, and a tap that opens the reader there. The brand's cream,
 * copper and walnut, walnut at night (WidgetPalette). Premium backgrounds,
 * categories and Random Verse come with Premium in phase 5.
 */
class VerseOfTheDayWidget : GlanceAppWidget() {
    override val sizeMode = SizeMode.Responsive(setOf(SMALL, MEDIUM, LARGE))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val day = load(context)
        provideContent { Content(day) }
    }

    /** Today's verse from the person's Bible, read once per update. */
    private suspend fun load(context: Context): WidgetVerse? = withContext(Dispatchers.IO) {
        val app = context.applicationContext as VerselyApplication
        val bible = app.readerSettings.currentBible?.let { id -> BundledBible.entries.firstOrNull { it.id == id } }
            ?: BundledBible.default(Locale.getDefault().language)
        val verse = DailyVerse.verse(LocalDate.now(), ZoneId.systemDefault())
        runCatching {
            BibleRepository.open(context, bible).use { repository ->
                val text = repository.verses(listOf(verse))[verse]?.plainText ?: return@use null
                val translation = repository.translation
                WidgetVerse(
                    link = GenesisLink.read(verse),
                    text = text,
                    citation = ReferenceParser.describe(verse.rawValue, language = translation.language) + " · " + translation.abbreviation,
                )
            }
        }.onFailure { Log.e(TAG, "Couldn't read the verse of the day", it) }.getOrNull()
    }

    @Composable
    private fun Content(day: WidgetVerse?) {
        val size = LocalSize.current
        val small = size.width < MEDIUM.width
        val lines = when {
            size.height >= LARGE.height -> 12
            small -> 6
            else -> 4
        }
        val open = Intent(Intent.ACTION_VIEW, Uri.parse(day?.link ?: "versely://read"))
            .setClass(androidx.glance.LocalContext.current, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .background(ImageProvider(R.drawable.widget_background))
                .cornerRadius(20.dp)
                .padding(if (small) 14.dp else 18.dp)
                .clickable(actionStartActivity(open)),
            verticalAlignment = Alignment.Top,
        ) {
            Eyebrow(androidx.glance.LocalContext.current.getString(R.string.verse_of_the_day))
            Spacer(GlanceModifier.height(if (small) 6.dp else 10.dp))
            Text(
                day?.text ?: "",
                maxLines = lines,
                style = TextStyle(
                    color = Palette.text,
                    fontFamily = FontFamily.Serif,
                    fontSize = if (small) 14.sp else 16.sp,
                ),
                modifier = GlanceModifier.defaultWeight(),
            )
            if (day != null) {
                Spacer(GlanceModifier.height(6.dp))
                Text(
                    day.citation,
                    maxLines = 1,
                    style = TextStyle(color = Palette.secondary, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, fontSize = 12.sp),
                )
            }
        }
    }

    @Composable
    private fun Eyebrow(title: String) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Image(
                ImageProvider(R.drawable.widget_mark),
                contentDescription = null,
                modifier = GlanceModifier.width(13.dp).height(9.dp),
            )
            Spacer(GlanceModifier.width(5.dp))
            Text(
                title.uppercase(),
                maxLines = 1,
                style = TextStyle(color = Palette.accent, fontWeight = FontWeight.Bold, fontSize = 10.sp),
                modifier = GlanceModifier.semantics { contentDescription = title },
            )
        }
    }

    private data class WidgetVerse(val link: String, val text: String, val citation: String)

    /** WidgetPalette on iOS: deepened brand colours so small text keeps its contrast. */
    private object Palette {
        val accent = ColorProvider(day = Color(0xFF9A6640), night = Color(0xFFE0B48D))
        val text = ColorProvider(day = Color(0xFF4A2E1A), night = Color(0xFFF3E2CC))
        val secondary = ColorProvider(day = Color(0xFF8A6243), night = Color(0xFFC7A27F))
    }

    companion object {
        private const val TAG = "VerseWidget"
        private val SMALL = DpSize(110.dp, 110.dp)
        private val MEDIUM = DpSize(250.dp, 110.dp)
        private val LARGE = DpSize(250.dp, 260.dp)

        /** Redraws every placed widget (the Bible changed, or the app opened on a new day). */
        suspend fun refresh(context: Context) {
            runCatching { VerseOfTheDayWidget().updateAll(context) }
                .onFailure { Log.w(TAG, "Couldn't refresh the widget", it) }
        }
    }
}
