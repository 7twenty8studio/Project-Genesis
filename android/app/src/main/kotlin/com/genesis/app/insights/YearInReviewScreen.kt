package com.genesis.app.insights

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.insights.YearInReview
import com.genesis.core.domain.study.HighlightColor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.text.NumberFormat
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * "Your year with Versely", as YearInReviewView.swift: a few pages to swipe
 * through (days, time, chapters, highlights, notes and prayers), ending with
 * a summary to share. Free for everyone, built from what's on this phone;
 * with Reading insights (Premium) the share holds the days and books too.
 */
@Composable
fun YearInReviewScreen(year: Int, language: String, onDone: () -> Unit) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val record by app.progress.record.collectAsStateWithLifecycle()
    val notes by app.userData.notes.all.collectAsStateWithLifecycle()
    val prayers by app.userData.prayers.all.collectAsStateWithLifecycle()
    val highlightMap by app.userData.highlights.all.collectAsStateWithLifecycle()
    val preferences = LocalReaderPreferences.current
    val font = preferences.font.available(Entitlements.isPremium)
    val premium = Entitlements.isPremium
    BackHandler(onBack = onDone)

    val chapters = record.chaptersByYear[year].orEmpty()
    val review by produceState<YearInReview?>(null, record, notes, prayers, highlightMap) {
        value = withContext(Dispatchers.IO) {
            YearInReview.make(
                year = year,
                readingDays = record.readingDays,
                readingSeconds = record.readingSeconds,
                chapters = chapters,
                highlights = app.userData.highlights.dated().map { (verse, color, created) -> YearInReview.HighlightRecord(created, verse, color) },
                notes = notes.filter { it.title.isNotBlank() || it.body.isNotBlank() }.map { it.createdAt },
                prayers = prayers.map { YearInReview.PrayerRecord(it.createdAt, it.answeredAt) },
            )
        }
    }
    val theme = YearCards.theme(preferences.theme.resolved(androidx.compose.foundation.isSystemInDarkTheme()))
    val cards by produceState<List<Bitmap>>(emptyList(), review, premium, theme, font) {
        val current = review ?: return@produceState
        if (!current.hasActivity) return@produceState
        value = withContext(Dispatchers.Default) {
            buildList {
                add(YearCards.summary(context, current, theme, font, language))
                if (premium) {
                    if (current.daysRead > 0) add(YearCards.days(context, current, record.readingDays, theme, font))
                    if (current.chaptersRead > 0) add(YearCards.books(context, current, chapters, theme, font, language))
                }
            }
        }
    }

    Column(Modifier.fillMaxSize().background(colors.background).statusBarsPadding().navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold) }
            Text(year.toString(), style = MaterialTheme.typography.titleMedium, color = colors.text, textAlign = TextAlign.Center, modifier = Modifier.weight(1f).semantics { heading() })
            if (cards.isNotEmpty()) {
                TextButton(onClick = { share(context, cards, context.getString(R.string.year_my_year_with, year.toString())) }) {
                    Text(stringResource(R.string.share), color = colors.accent)
                }
            } else Spacer(Modifier.size(72.dp, 1.dp))
        }
        val current = review ?: return@Column
        if (!current.hasActivity) {
            Column(Modifier.fillMaxSize().padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                Text(stringResource(R.string.year_nothing_yet), style = MaterialTheme.typography.titleLarge, color = colors.text)
                Text(stringResource(R.string.year_nothing_yet_detail), color = colors.secondaryText, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
            }
            return@Column
        }
        val pages = pages(current, language, cards)
        val pager = rememberPagerState { pages.size }
        HorizontalPager(pager, Modifier.weight(1f).fillMaxWidth()) { index ->
            Box(Modifier.fillMaxSize().padding(28.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.widthIn(max = 560.dp)) { pages[index]() }
            }
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp).clearAndSetSemantics {}, horizontalArrangement = Arrangement.Center) {
            repeat(pages.size) { index ->
                Box(Modifier.padding(4.dp).size(7.dp).clip(CircleShape).background(if (index == pager.currentPage) colors.accent else colors.separator))
            }
        }
    }
}

private fun pages(review: YearInReview, language: String, cards: List<Bitmap>): List<@Composable () -> Unit> = buildList {
    val number = NumberFormat.getIntegerInstance()
    add { ReviewPage("✦", stringResource(R.string.year_your_year), review.year.toString(), stringResource(R.string.year_swipe)) }
    if (review.daysRead > 0) add {
        ReviewPage(
            "📅", stringResource(R.string.year_days_in_word), number.format(review.daysRead),
            if (review.longestStreak > 1) stringResource(R.string.year_longest_streak, review.longestStreak) else stringResource(R.string.year_every_day_counts),
        )
    }
    if (review.minutesRead > 0) add {
        val day = review.longestDay?.let { DateTimeFormatter.ofPattern(android.text.format.DateFormat.getBestDateTimePattern(Locale.getDefault(), "MMMMd")).format(it) }
        ReviewPage(
            "🕰", stringResource(R.string.year_time_reading), duration(review.minutesRead * 60L),
            day?.let { stringResource(R.string.year_longest_day, it, review.longestDayMinutes) } ?: "",
        )
    }
    if (review.chaptersRead > 0) add {
        val detail = listOfNotNull(
            if (review.booksFinished > 0) stringResource(R.string.year_books_finished_sentence, review.booksFinished) else null,
            review.topBook?.let { stringResource(R.string.year_most_time_in, BibleBooks.withNumber(it).name(language)) },
        ).joinToString(" ")
        ReviewPage("📖", stringResource(R.string.year_chapters_read), number.format(review.chaptersRead), detail)
    }
    if (review.highlights > 0) add {
        ReviewPage(
            "🖍", stringResource(R.string.year_verses_highlighted), number.format(review.highlights),
            review.mostHighlightedBook?.let { stringResource(R.string.year_most_in, BibleBooks.withNumber(it).name(language)) } ?: "",
            swatch = review.favoriteColor,
        )
    }
    if (review.notes > 0 || review.prayersAdded > 0) add {
        ReviewPage(
            "🙏", stringResource(R.string.year_notes_and_prayers), number.format(review.notes + review.prayersAdded),
            if (review.prayersAnswered > 0) stringResource(R.string.year_wrote_answered, review.notes, review.prayersAdded, review.prayersAnswered)
            else stringResource(R.string.year_wrote, review.notes, review.prayersAdded),
        )
    }
    add {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp), modifier = Modifier.fillMaxWidth()) {
            // The cards to share, fanned out like prints on a table (the summary on top).
            Box(Modifier.height(320.dp).fillMaxWidth().clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
                cards.withIndex().reversed().forEach { (index, card) ->
                    val angle = listOf(0f, 7f, -7f)[index % 3]
                    val offset = listOf(0, 60, -60)[index % 3]
                    Image(
                        card.asImageBitmap(), null,
                        Modifier.height(280.dp).offset(x = offset.dp).rotate(angle).shadow(8.dp, RoundedCornerShape(14.dp)).clip(RoundedCornerShape(14.dp)),
                    )
                }
            }
            Text(stringResource(R.string.year_share_hint), style = MaterialTheme.typography.bodySmall, color = LocalReaderColors.current.secondaryText)
        }
    }
}

/** Home (December and January) and Insights: "Your 2026 in Review". */
@Composable
internal fun YearInReviewCard(onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    androidx.compose.foundation.layout.Row(
        Modifier.fillMaxWidth().clip(androidx.compose.foundation.shape.RoundedCornerShape(20.dp)).background(colors.surface).clickable(onClick = onClick).padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Text("✦", fontSize = 22.sp, color = colors.accent)
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.year_in_review, YearInReview.reviewedYear().toString()), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
            Text(stringResource(R.string.year_in_review_detail), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
        }
        Text("›", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
    }
}

/** One page: a symbol, a label, a big number and a sentence. */
@Composable
private fun ReviewPage(symbol: String, eyebrow: String, big: String, detail: String, swatch: HighlightColor? = null) {
    val colors = LocalReaderColors.current
    val family = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium))
    Column(Modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Text(symbol, fontSize = 34.sp, color = colors.accent)
        Text(eyebrow.uppercase(), style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.4.sp), fontWeight = FontWeight.SemiBold, color = colors.secondaryText)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            if (swatch != null) Box(Modifier.size(26.dp).clip(CircleShape).background(Color(0xFF000000 or swatch.hex.toLong())))
            Text(big, fontFamily = family, fontSize = 64.sp, fontWeight = FontWeight.SemiBold, color = colors.text, maxLines = 1)
        }
        if (detail.isNotEmpty()) Text(detail, fontFamily = family, fontSize = 19.sp, lineHeight = 27.sp, color = colors.text, textAlign = TextAlign.Center)
    }
}

/** The cards, through Versely's file provider. */
private fun share(context: Context, cards: List<Bitmap>, title: String) {
    val folder = File(context.cacheDir, "images").apply { mkdirs() }
    val uris = ArrayList<Uri>(cards.mapIndexed { index, card ->
        val file = File(folder, "year-${index + 1}.png")
        file.outputStream().use { card.compress(Bitmap.CompressFormat.PNG, 100, it) }
        FileProvider.getUriForFile(context, context.packageName + ".files", file)
    })
    val send = if (uris.size == 1) Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris.first())
    else Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
    send.setType("image/png").putExtra(Intent.EXTRA_TITLE, title).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, title))
}
