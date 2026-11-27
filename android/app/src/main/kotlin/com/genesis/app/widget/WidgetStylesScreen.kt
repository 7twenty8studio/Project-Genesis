package com.genesis.app.widget

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.reader.PremiumTag
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.Footer
import com.genesis.core.bible.BibleRepository
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.home.DailyVerse
import com.genesis.core.domain.share.VerseImageStyle
import com.genesis.core.domain.theme.ReaderTheme
import com.genesis.core.domain.widgets.WidgetArtShape
import com.genesis.core.domain.widgets.WidgetArtStyle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId

/**
 * Settings › Widget Styles, as WidgetStylesView on iOS: every look the verse
 * widget can wear, each previewed with today's verse. The choice goes to
 * every verse widget whose Background is "Chosen in Versely" (the default).
 * Anyone can look; Premium styles carry a tag (and can be chosen once the
 * Premium screen comes with Google Play Billing).
 */
@Composable
fun WidgetStylesScreen(onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val premium = Entitlements.isPremium
    val chosen by WidgetStylePreference.style.collectAsStateWithLifecycle()
    var shape by remember { mutableIntStateOf(WidgetArtShape.MEDIUM.ordinal) }
    LaunchedEffect(Unit) { WidgetStylePreference.current(context) }

    // The painted backgrounds the previews (and widgets) show, drawn now if they aren't yet.
    var drawn by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        WidgetArt.drawIfNeeded(context, wait = false)
        drawn++
    }
    val verse by produceState<Pair<String, String>?>(null) {
        value = withContext(Dispatchers.IO) {
            runCatching {
                val app = context.applicationContext as VerselyApplication
                BibleRepository.open(context, app.currentBible).use { repository ->
                    val id = DailyVerse.verse(LocalDate.now(), ZoneId.systemDefault())
                    val text = repository.verses(listOf(id))[id]?.displayText ?: return@use null
                    text to ReferenceParser.describe(id.rawValue, language = repository.translation.language) + " · " + repository.translation.abbreviation
                }
            }.getOrNull()
        }
    }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.widget_styles),
                style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            val shapes = WidgetArtShape.entries
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(colors.surface).padding(3.dp)) {
                shapes.forEach { option ->
                    val selected = option.ordinal == shape
                    Text(
                        stringResource(
                            when (option) {
                                WidgetArtShape.SMALL -> R.string.widget_size_small
                                WidgetArtShape.MEDIUM -> R.string.widget_size_medium
                                WidgetArtShape.LARGE -> R.string.widget_size_large
                            },
                        ),
                        color = if (selected) colors.text else colors.secondaryText,
                        fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                        modifier = Modifier.weight(1f)
                            .clip(RoundedCornerShape(8.dp))
                            .background(if (selected) colors.background else Color.Transparent)
                            .semantics { this.selected = selected }
                            .clickable(role = Role.Tab) { shape = option.ordinal }
                            .padding(vertical = 8.dp),
                        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                    )
                }
            }
            Footer(stringResource(R.string.widget_styles_footer))

            WidgetArtStyle.galleryOrder.forEach { style ->
                val locked = style.needsPremium && !premium
                val selected = style == chosen && !locked
                Column(
                    Modifier.fillMaxWidth()
                        .padding(vertical = 8.dp)
                        .clip(RoundedCornerShape(16.dp))
                        .background(colors.surface)
                        .semantics { this.selected = selected }
                        .clickable(enabled = !locked, role = Role.RadioButton) { scope.launch { WidgetStylePreference.set(context, style) } }
                        .padding(14.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Preview(style, shapes[shape], verse, drawn)
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(style.titleRes), color = colors.text, modifier = Modifier.weight(1f))
                        when {
                            locked -> PremiumTag()
                            selected -> Text("✓", color = colors.accent, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
            Spacer(Modifier.size(32.dp))
        }
    }
}

/** One style at one widget size: the verse over its background, as the widget draws it. */
@Composable
private fun Preview(style: WidgetArtStyle, shape: WidgetArtShape, verse: Pair<String, String>?, drawn: Int) {
    val context = LocalContext.current
    val picture by produceState<Bitmap?>(null, style, shape, drawn) {
        value = if (style.isPainted) withContext(Dispatchers.IO) { WidgetArt.load(context, style, shape) } else null
    }
    val dark = style.isDark
    val palette = (VerseImageStyle.entries.firstOrNull { it.rawValue == style.rawValue } ?: VerseImageStyle.PAPER).theme(ReaderTheme.PAPER).palette
    fun hex(value: Int) = Color(0xFF000000 or value.toLong())
    val classic = !style.isPainted
    val text = when {
        classic -> Color(0xFF4A2E1A)
        dark -> Color(0xFFF6EEE2)
        else -> hex(palette.text)
    }
    val secondary = when {
        classic -> Color(0xFF8A6243)
        dark -> Color(0xFFDCCBB6)
        else -> hex(palette.secondaryText)
    }
    val accent = when {
        classic -> Color(0xFF9A6640)
        dark -> Color(0xFFEBC08F)
        else -> hex(palette.accent)
    }
    val label = stringResource(R.string.widget_style_preview, stringResource(style.titleRes))
    val width = if (shape == WidgetArtShape.SMALL) 170.dp else 360.dp
    Box(
        Modifier
            .widthIn(max = width)
            .fillMaxWidth()
            .aspectRatio(shape.width.toFloat() / shape.height)
            .clip(RoundedCornerShape(20.dp))
            .background(Brush.verticalGradient(listOf(Color(0xFFFBF1E4), Color(0xFFF2DCC2))))
            .clearAndSetSemantics { contentDescription = label },
    ) {
        picture?.let { Image(it.asImageBitmap(), contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize()) }
        Column(Modifier.fillMaxSize().padding(if (shape == WidgetArtShape.SMALL) 14.dp else 18.dp)) {
            Text(stringResource(R.string.verse_of_the_day).uppercase(), color = accent, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            Spacer(Modifier.size(if (shape == WidgetArtShape.SMALL) 6.dp else 10.dp))
            Text(
                verse?.first.orEmpty(),
                color = text,
                fontFamily = FontFamily.Serif,
                fontSize = if (shape == WidgetArtShape.LARGE) 19.sp else if (shape == WidgetArtShape.SMALL) 14.sp else 16.sp,
                lineHeight = if (shape == WidgetArtShape.LARGE) 25.sp else 20.sp,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            verse?.second?.let { Text(it, color = secondary, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, fontSize = 12.sp, maxLines = 1) }
        }
    }
}
