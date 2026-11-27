package com.genesis.app.memorise

import android.content.Context
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.runtime.collectAsState
import androidx.core.content.edit
import com.genesis.app.R
import com.genesis.app.prayer.fieldColors
import com.genesis.app.reader.MemoryPassage
import com.genesis.core.data.UserDatabase
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ReferenceParser
import com.genesis.core.domain.bible.VerseId
import com.genesis.core.domain.memorise.MemoriseSuggestions
import com.genesis.core.domain.memorise.MemoryLevel
import com.genesis.core.domain.memorise.MemoryMastery
import com.genesis.core.domain.memorise.MemoryVerse
import com.genesis.core.domain.memorise.PracticeStreak
import kotlinx.coroutines.launch
import java.time.LocalDate

/** Where Memorize reads its passages: verbatim from a Bible on this device. */
class MemoryTexts(
    /** The Bible new passages are added in (the one being read). */
    val bibleId: String,
    val language: String,
    val passage: suspend (MemoryVerse, nearby: Boolean) -> MemoryPassage?,
    val hasVerse: suspend (VerseId) -> Boolean,
)

/** The days-in-a-row practice streak, kept on this device only (as on iOS). */
internal object MemoryStreak {
    private const val KEY = "memorise.practiceStreak"
    private fun prefs(context: Context) = context.getSharedPreferences("memorise", Context.MODE_PRIVATE)

    fun load(context: Context): PracticeStreak = PracticeStreak.decode(prefs(context).getString(KEY, null))

    fun record(context: Context) {
        val next = load(context).recording(LocalDate.now())
        prefs(context).edit { putString(KEY, next.encode()) }
    }
}

enum class MemoryGameMode { FILL_GAPS, WORD_ORDER, SPEED }

private sealed interface MemoryRoute {
    data class Review(val cards: List<String>) : MemoryRoute
    data class Game(val mode: MemoryGameMode, val cards: List<String>) : MemoryRoute
}

/**
 * Memorize Scripture (Premium), as MemoriseView on iOS: the passages being
 * learned, what's due today, games, and a way to add more. Only verse ids
 * and the schedule are saved; the words come from the Bible every time.
 */
@Composable
fun MemoriseScreen(store: UserDatabase.MemoryStore, texts: MemoryTexts, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val verses by store.all.collectAsState()
    var route by remember { mutableStateOf<MemoryRoute?>(null) }
    var adding by rememberSaveable { mutableStateOf(false) }
    // Read again whenever a session closes, so the streak line is current.
    var streak by remember { mutableStateOf(MemoryStreak.load(context)) }

    route?.let { current ->
        val close = {
            route = null
            streak = MemoryStreak.load(context)
        }
        BackHandler(onBack = close)
        when (current) {
            is MemoryRoute.Review -> MemoryReviewScreen(store, texts, current.cards, onClose = close, modifier = modifier)
            is MemoryRoute.Game -> if (current.mode == MemoryGameMode.SPEED) SpeedRoundScreen(store, texts, current.cards, onClose = close, modifier = modifier)
            else MemoryGameScreen(store, texts, current.mode, current.cards, onClose = close, modifier = modifier)
        }
        return
    }
    BackHandler(onBack = onDone)

    if (!com.genesis.app.settings.Entitlements.isPremium) {
        // Premium: what it is, without the passages (anything saved stays).
        Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
            TextButton(onClick = onDone, modifier = Modifier.padding(start = 4.dp, top = 8.dp)) { Text("\u2039 " + stringResource(R.string.back), color = colors.accent) }
            Column(Modifier.padding(20.dp).widthIn(max = 620.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    stringResource(R.string.memorise_title),
                    style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                    color = colors.text,
                    modifier = Modifier.semantics { heading() },
                )
                Text(stringResource(R.string.premium), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.accent)
                Text(stringResource(R.string.memorise_premium_message), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText)
            }
        }
        return
    }

    val now = System.currentTimeMillis()
    val due = verses.filter { it.isDue(now) }
    val memorised = verses.count { it.mastery == MemoryMastery.MEMORISED }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.padding(start = 4.dp, end = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDone) { Text("‹ " + stringResource(R.string.back), color = colors.accent) }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { adding = true }) { Text(stringResource(R.string.memorise_add_verse), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        Text(
            stringResource(R.string.memorise),
            style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            color = colors.text,
            modifier = Modifier.padding(horizontal = 20.dp).semantics { heading() },
        )
        Column(
            Modifier.verticalScroll(rememberScrollState()).padding(20.dp).widthIn(max = 720.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            // Summary, level and streak.
            Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(18.dp)).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    if (due.isEmpty()) stringResource(R.string.memorise_caught_up) else stringResource(R.string.memorise_due_today, due.size),
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.SemiBold,
                    color = colors.text,
                )
                Text(stringResource(R.string.memorise_counts, verses.size, memorised), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                if (due.isNotEmpty()) {
                    Button(
                        onClick = { route = MemoryRoute.Review(due.map { it.id }) },
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
                        modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp),
                    ) { Text(stringResource(R.string.memorise_review_now), fontWeight = FontWeight.SemiBold) }
                }
                if (verses.isNotEmpty()) {
                    HorizontalDivider(color = colors.separator)
                    ProgressCard(memorised, streak)
                }
            }

            if (verses.isNotEmpty()) {
                Section(stringResource(R.string.memorise_games), footer = if (due.isEmpty()) stringResource(R.string.memorise_practice_only) else null) {
                    MemoryGameMode.entries.forEachIndexed { index, mode ->
                        if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                        GameRow(mode) {
                            // Games play what's due; when nothing is, any passages as practice.
                            val pool = if (due.isEmpty()) verses.shuffled() else due
                            val cards = if (mode == MemoryGameMode.SPEED) pool else pool.take(com.genesis.core.domain.memorise.MemoryGame.GAME_LENGTH)
                            route = MemoryRoute.Game(mode, cards.map { it.id })
                        }
                    }
                }
                Section(stringResource(R.string.memorise_your_verses)) {
                    verses.forEachIndexed { index, verse ->
                        if (index > 0) HorizontalDivider(Modifier.padding(start = 56.dp), color = colors.separator)
                        VerseRow(verse, texts.language, now, onOpen = { route = MemoryRoute.Review(listOf(verse.id)) }, onDelete = { store.delete(verse.id) })
                    }
                }
            } else {
                Column(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(R.string.memorise_empty_title), style = MaterialTheme.typography.titleMedium, color = colors.text)
                    Text(stringResource(R.string.memorise_empty_message), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
            }

            val suggestions = MemoriseSuggestions.all.filter { (start, _) -> verses.none { it.start == start } }
            if (suggestions.isNotEmpty() && verses.size < 12) {
                Section(stringResource(R.string.memorise_suggestions)) {
                    suggestions.take(if (verses.isEmpty()) 8 else 3).forEachIndexed { index, (start, end) ->
                        if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                        val reference = ReferenceParser.describe(start.rawValue, end.rawValue, texts.language)
                        Row(
                            Modifier.fillMaxWidth().clickable { store.memorise(start, end, texts.bibleId) }.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(reference, style = MaterialTheme.typography.bodyLarge, color = colors.text, modifier = Modifier.weight(1f))
                            Text("+", style = MaterialTheme.typography.titleLarge, color = colors.accent)
                        }
                    }
                }
            }
            Spacer(Modifier.size(12.dp))
        }
    }

    if (adding) AddVerseDialog(store, texts, onDismiss = { adding = false })
}

@Composable
private fun Section(title: String, footer: String? = null, content: @Composable () -> Unit) {
    val colors = LocalReaderColors.current
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title.uppercase(), style = MaterialTheme.typography.labelMedium, color = colors.secondaryText, modifier = Modifier.padding(start = 4.dp).semantics { heading() })
        Column(Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(18.dp))) { content() }
        footer?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = colors.secondaryText, modifier = Modifier.padding(horizontal = 4.dp)) }
    }
}

@Composable
private fun ProgressCard(memorised: Int, streak: PracticeStreak) {
    val colors = LocalReaderColors.current
    val level = MemoryLevel.level(memorised)
    val today = LocalDate.now()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(level.title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
        Text(
            level.next?.let { stringResource(R.string.memorise_next_level, stringResource(it.title)) } ?: stringResource(R.string.memorise_top_level),
            style = MaterialTheme.typography.bodySmall,
            color = colors.secondaryText,
        )
        LinearProgressIndicator(
            progress = { MemoryLevel.progress(memorised) },
            color = colors.accent,
            trackColor = colors.separator,
            modifier = Modifier.fillMaxWidth(),
        )
        val count = streak.current(today)
        Text(
            when (count) {
                0 -> stringResource(R.string.memorise_streak_none)
                1 -> stringResource(R.string.memorise_streak_one)
                else -> stringResource(R.string.memorise_streak_many, count)
            },
            style = MaterialTheme.typography.bodyMedium,
            color = colors.secondaryText,
        )
    }
}

@Composable
private fun GameRow(mode: MemoryGameMode, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(stringResource(mode.title), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = colors.text)
            Text(stringResource(mode.detail), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        Text("›", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
    }
}

@Composable
private fun VerseRow(verse: MemoryVerse, language: String, now: Long, onOpen: () -> Unit, onDelete: () -> Unit) {
    val colors = LocalReaderColors.current
    var menu by remember { mutableStateOf(false) }
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        val fraction = maxOf(0.04f, verse.mastery.fraction)
        Canvas(Modifier.size(26.dp)) {
            val stroke = 3.dp.toPx()
            val inset = stroke / 2
            val arc = Size(size.width - stroke, size.height - stroke)
            drawArc(colors.separator, 0f, 360f, false, Offset(inset, inset), arc, style = Stroke(stroke))
            drawArc(colors.accent, -90f, 360f * fraction, false, Offset(inset, inset), arc, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(verse.reference.description(language), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.Medium, color = colors.text)
            Text("${verse.translationId} · ${stringResource(verse.mastery.title)}", style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        Text(
            if (verse.isDue(now)) stringResource(R.string.memorise_due)
            else DateUtils.getRelativeTimeSpanString(verse.schedule.dueAt, now, DateUtils.DAY_IN_MILLIS).toString(),
            style = MaterialTheme.typography.bodySmall,
            color = if (verse.isDue(now)) colors.accent else colors.secondaryText,
        )
        Column {
            TextButton(onClick = { menu = true }) { Text("⋯", color = colors.secondaryText) }
            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, containerColor = colors.surface) {
                DropdownMenuItem(text = { Text(stringResource(R.string.delete), color = colors.text) }, onClick = {
                    menu = false
                    onDelete()
                })
            }
        }
    }
}

@Composable
private fun AddVerseDialog(store: UserDatabase.MemoryStore, texts: MemoryTexts, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var text by rememberSaveable { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    val needsReference = stringResource(R.string.memorise_add_reference)
    val tooMany = stringResource(R.string.memorise_add_too_many, MemoriseSuggestions.MAXIMUM_VERSES)
    val notInBible = stringResource(R.string.memorise_not_in_bible)

    fun add() {
        val reference = ReferenceParser.parse(text, portugueseFirst = texts.language == "pt")
        val chapter = reference?.chapter
        val first = reference?.verseStart
        if (reference == null || chapter == null || first == null) {
            error = needsReference
            return
        }
        val start = VerseId(reference.book.id, chapter, first)
        val end = VerseId(reference.book.id, chapter, maxOf(first, reference.verseEnd ?: first))
        if (end.verse - start.verse >= MemoriseSuggestions.MAXIMUM_VERSES) {
            error = tooMany
            return
        }
        scope.launch {
            if (!texts.hasVerse(start)) {
                error = notInBible
                return@launch
            }
            store.memorise(start, end, texts.bibleId)
            onDismiss()
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.memorise_add_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(error ?: stringResource(R.string.memorise_add_message), color = if (error != null) colors.accent else colors.secondaryText)
                OutlinedTextField(
                    value = text,
                    onValueChange = {
                        text = it
                        error = null
                    },
                    placeholder = { Text(stringResource(R.string.passage_hint)) },
                    singleLine = true,
                    colors = fieldColors(),
                )
            }
        },
        confirmButton = { TextButton(onClick = ::add, enabled = text.isNotBlank()) { Text(stringResource(R.string.add), color = colors.accent) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = colors.accent) } },
        containerColor = colors.surface,
        titleContentColor = colors.text,
        textContentColor = colors.secondaryText,
    )
}

internal val MemoryGameMode.title: Int
    get() = when (this) {
        MemoryGameMode.FILL_GAPS -> R.string.memorise_fill_gaps
        MemoryGameMode.WORD_ORDER -> R.string.memorise_word_order
        MemoryGameMode.SPEED -> R.string.memorise_speed_round
    }

private val MemoryGameMode.detail: Int
    get() = when (this) {
        MemoryGameMode.FILL_GAPS -> R.string.memorise_fill_gaps_detail
        MemoryGameMode.WORD_ORDER -> R.string.memorise_word_order_detail
        MemoryGameMode.SPEED -> R.string.memorise_speed_detail
    }

internal val MemoryMastery.title: Int
    get() = when (this) {
        MemoryMastery.NEW -> R.string.memorise_mastery_new
        MemoryMastery.LEARNING -> R.string.memorise_mastery_learning
        MemoryMastery.FAMILIAR -> R.string.memorise_mastery_familiar
        MemoryMastery.MEMORISED -> R.string.memorise_mastery_memorised
    }

private val MemoryLevel.title: Int
    get() = when (this) {
        MemoryLevel.SEED -> R.string.memorise_level_seed
        MemoryLevel.SPROUT -> R.string.memorise_level_sprout
        MemoryLevel.SAPLING -> R.string.memorise_level_sapling
        MemoryLevel.TREE -> R.string.memorise_level_tree
        MemoryLevel.CEDAR -> R.string.memorise_level_cedar
    }
