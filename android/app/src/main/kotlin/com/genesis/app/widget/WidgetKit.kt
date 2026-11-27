package com.genesis.app.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.ColumnScope
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontFamily
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import com.genesis.app.MainActivity
import com.genesis.app.R

/** WidgetPalette on iOS: deepened brand colours so small text keeps its contrast. */
internal object WidgetPalette {
    val accent = ColorProvider(day = Color(0xFF9A6640), night = Color(0xFFE0B48D))
    val text = ColorProvider(day = Color(0xFF4A2E1A), night = Color(0xFFF3E2CC))
    val secondary = ColorProvider(day = Color(0xFF8A6243), night = Color(0xFFC7A27F))
    val track = ColorProvider(day = Color(0x338A6243), night = Color(0x33C7A27F))
}

/** Opens a versely:// link in the app. */
internal fun openIntent(context: Context, link: String): Intent =
    Intent(Intent.ACTION_VIEW, Uri.parse(link))
        .setClass(context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

/** Versely's Classic widget card: cream to a warm glow (walnut at night), and a tap that opens [link]. */
@Composable
internal fun WidgetCard(link: String, small: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(ImageProvider(R.drawable.widget_background))
            .cornerRadius(20.dp)
            .padding(if (small) 14.dp else 18.dp)
            .clickable(actionStartActivity(openIntent(LocalContext.current, link))),
        verticalAlignment = Alignment.Top,
        content = content,
    )
}

/** The small capitals over every widget, starting with Versely's V (VerselyMark). */
@Composable
internal fun Eyebrow(title: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Image(ImageProvider(R.drawable.widget_mark), contentDescription = null, modifier = GlanceModifier.width(13.dp).height(9.dp))
        Spacer(GlanceModifier.width(5.dp))
        Text(
            title.uppercase(),
            maxLines = 1,
            style = TextStyle(color = WidgetPalette.accent, fontWeight = FontWeight.Bold, fontSize = 10.sp),
            modifier = GlanceModifier.semantics { contentDescription = title },
        )
    }
}

/** A small copper symbol. */
@Composable
internal fun Symbol(resource: Int, size: Int = 18) {
    Image(
        ImageProvider(resource),
        contentDescription = null,
        colorFilter = ColorFilter.tint(WidgetPalette.accent),
        modifier = GlanceModifier.size(size.dp),
    )
}

/** How far through a book or plan: a thin track with a copper fill. */
@Composable
internal fun ProgressBar(fraction: Double) {
    LinearProgressIndicator(
        progress = fraction.coerceIn(0.0, 1.0).toFloat(),
        color = WidgetPalette.accent,
        backgroundColor = WidgetPalette.track,
        modifier = GlanceModifier.fillMaxWidth().height(5.dp),
    )
}

@Composable
internal fun Headline(text: String, size: Int = 18, maxLines: Int = 2) {
    Text(text, maxLines = maxLines, style = TextStyle(color = WidgetPalette.text, fontFamily = FontFamily.Serif, fontWeight = FontWeight.Medium, fontSize = size.sp))
}

@Composable
internal fun Caption(text: String, maxLines: Int = 1, serif: Boolean = false, size: Int = 12) {
    Text(text, maxLines = maxLines, style = TextStyle(color = WidgetPalette.secondary, fontFamily = if (serif) FontFamily.Serif else null, fontSize = size.sp))
}

@Composable
internal fun string(id: Int, vararg args: Any): String = LocalContext.current.getString(id, *args)

/**
 * Every Versely widget, redrawn together whenever what they show may have
 * changed (the app opened or went to the background, reading, a plan day,
 * a prayer or a Memorize review), as WidgetCenter.reloadAllTimelines on iOS.
 */
object VerselyWidgets {
    private const val TAG = "VerselyWidgets"

    private fun all(): List<GlanceAppWidget> = listOf(
        VerseOfTheDayWidget(),
        ContinueReadingWidget(),
        ReadingProgressWidget(),
        StreakWidget(),
        PrayerReminderWidget(),
        TodaysReadingWidget(),
        MemoriseWidget(),
    )

    suspend fun refresh(context: Context) {
        for (widget in all()) {
            runCatching { widget.updateAll(context) }.onFailure { Log.w(TAG, "Couldn't refresh ${widget::class.simpleName}", it) }
        }
    }
}
