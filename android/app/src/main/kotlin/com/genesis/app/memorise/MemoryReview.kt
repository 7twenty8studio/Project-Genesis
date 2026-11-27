package com.genesis.app.memorise

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.reader.MemoryPassage
import com.genesis.app.settings.Entitlements
import com.genesis.app.settings.LocalReaderPreferences
import com.genesis.core.data.UserDatabase
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.design.rememberFontFamily
import com.genesis.core.domain.memorise.MemoryGame
import com.genesis.core.domain.memorise.MemoryGrade
import com.genesis.core.domain.memorise.MemoryHint
import com.genesis.core.domain.memorise.MemoryVerse
import kotlinx.coroutines.delay

/** The reader's font at a size, for the words of a passage. */
@Composable
internal fun scriptureStyle(size: Int, weight: FontWeight = FontWeight.Normal): TextStyle =
    TextStyle(
        fontFamily = rememberFontFamily(LocalReaderPreferences.current.font.available(Entitlements.isPremium)),
        fontSize = size.sp,
        lineHeight = (size * 1.45f).sp,
        fontWeight = weight,
    )

/** A full screen over Memorize: Close, a title and the session's content. */
@Composable
internal fun SessionScaffold(title: String, onClose: () -> Unit, modifier: Modifier, content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalReaderColors.current
    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().navigationBarsPadding()) {
        Box(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 8.dp)) {
            TextButton(onClick = onClose, modifier = Modifier.align(Alignment.CenterStart)) { Text(stringResource(R.string.close), color = colors.accent) }
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text, modifier = Modifier.align(Alignment.Center))
        }
        Column(
            Modifier.fillMaxSize().padding(horizontal = 20.dp).padding(bottom = 20.dp).widthIn(max = 620.dp).align(Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            content = content,
        )
    }
}

/** A rounded card holding one passage. */
@Composable
internal fun PassageCard(modifier: Modifier = Modifier, onClick: (() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalReaderColors.current
    val shape = RoundedCornerShape(22.dp)
    Column(
        modifier.fillMaxWidth().background(colors.surface, shape).border(1.dp, colors.separator, shape)
            .let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(22.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
        content = content,
    )
}

@Composable
internal fun PassageHeader(verse: MemoryVerse, passage: MemoryPassage?, size: Int = 24) {
    val colors = LocalReaderColors.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            verse.reference.description(passage?.language ?: "en"),
            style = scriptureStyle(size, FontWeight.SemiBold),
            color = colors.text,
            modifier = Modifier.weight(1f),
        )
        passage?.let { Text(it.abbreviation, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.secondaryText) }
    }
}

@Composable
internal fun SessionProgress(done: Int, total: Int) {
    val colors = LocalReaderColors.current
    LinearProgressIndicator(
        progress = { if (total == 0) 0f else done.toFloat() / total },
        color = colors.accent,
        trackColor = colors.separator,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
internal fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
        modifier = modifier.heightIn(min = 48.dp),
    ) { Text(text, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center) }
}

@Composable
internal fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, tint: Color? = null) {
    val colors = LocalReaderColors.current
    OutlinedButton(onClick = onClick, modifier = modifier.heightIn(min = 48.dp)) {
        Text(text, color = tint ?: colors.accent, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, maxLines = 1)
    }
}

/** The end of a session: how many passages, and an optional extra line. */
@Composable
internal fun SessionFinished(message: String, detail: String? = null, onDone: () -> Unit) {
    val colors = LocalReaderColors.current
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
        Text("✓", style = MaterialTheme.typography.displayMedium, color = colors.accent)
        Text(stringResource(R.string.memorise_well_done), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
        Text(message, style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText, textAlign = TextAlign.Center)
        detail?.let { Text(it, style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText, textAlign = TextAlign.Center) }
        PrimaryButton(stringResource(R.string.done), onDone)
    }
}

/** A card's passage, read again when the card changes. */
@Composable
internal fun rememberPassage(verse: MemoryVerse?, texts: MemoryTexts, nearby: Boolean = false): MemoryPassage? {
    val passage by produceState<MemoryPassage?>(null, verse?.id, verse?.translationId, texts.bibleId) {
        value = verse?.let { texts.passage(it, nearby) }
    }
    return passage
}

/**
 * Flashcards, as MemoryReviewView on iOS: the reference on the front; try to
 * say the passage, peek at its opening words if needed, then turn the card
 * and say how it went. Cards marked Again come back at the end.
 */
@Composable
fun MemoryReviewScreen(store: UserDatabase.MemoryStore, texts: MemoryTexts, cards: List<String>, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val all by store.all.collectAsState()
    var queue by remember { mutableStateOf(cards) }
    var reviewed by remember { mutableIntStateOf(0) }
    var revealed by remember { mutableStateOf(false) }
    var hintWords by remember { mutableIntStateOf(0) }

    val verse = queue.firstOrNull()?.let { id -> all.firstOrNull { it.id == id } }
    // A card deleted elsewhere (another device) is skipped.
    LaunchedEffect(queue, all) { if (queue.isNotEmpty() && verse == null) queue = queue.drop(1) }
    val passage = rememberPassage(verse, texts)

    fun reveal() {
        if (!revealed) haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        revealed = true
    }

    SessionScaffold(stringResource(R.string.memorise_review), onClose, modifier) {
        if (verse == null) {
            SessionFinished(
                if (reviewed == 1) stringResource(R.string.memorise_reviewed_one) else stringResource(R.string.memorise_reviewed_many, reviewed),
                onDone = onClose,
            )
            return@SessionScaffold
        }
        SessionProgress(reviewed, reviewed + queue.size)
        AnimatedContent(verse.id, transitionSpec = { fadeIn(tween(220)) togetherWith fadeOut(tween(150)) }, modifier = Modifier.weight(1f), label = "card") {
            PassageCard(Modifier.fillMaxSize(), onClick = { reveal() }) {
                PassageHeader(verse, passage, size = 26)
                val text = passage?.text.orEmpty()
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                    when {
                        revealed -> Text(text, style = scriptureStyle(21), color = colors.text)
                        hintWords > 0 -> Text(MemoryHint.opening(text, hintWords), style = scriptureStyle(21), color = colors.text)
                        else -> Text(stringResource(R.string.memorise_say_then_turn), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText)
                    }
                }
            }
        }
        if (revealed) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(stringResource(R.string.memorise_how_did_you_do), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    MemoryGrade.entries.forEach { grade ->
                        SecondaryButton(
                            stringResource(grade.title),
                            onClick = {
                                store.review(verse.id, grade)
                                // A review is practice too: it keeps the streak going.
                                MemoryStreak.record(context)
                                queue = queue.drop(1).let { if (grade == MemoryGrade.AGAIN) it + verse.id else it }
                                if (grade != MemoryGrade.AGAIN) reviewed++
                                revealed = false
                                hintWords = 0
                            },
                            modifier = Modifier.weight(1f),
                            tint = if (grade == MemoryGrade.AGAIN) Color(0xFFC77A2E) else null,
                        )
                    }
                }
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                SecondaryButton(
                    stringResource(if (hintWords == 0) R.string.memorise_hint else R.string.memorise_more_words),
                    onClick = {
                        // A few more words each time; the last step shows it all.
                        hintWords += MemoryHint.WORDS_PER_STEP
                        if (MemoryHint.isComplete(passage?.text.orEmpty(), hintWords)) reveal()
                    },
                    modifier = Modifier.weight(1f),
                )
                PrimaryButton(stringResource(R.string.memorise_show_verse), ::reveal, Modifier.weight(1f))
            }
        }
    }
}

/**
 * Speed Round, as SpeedRoundView on iOS: one minute to recall as many passages
 * as you can. "I knew it" counts as a good review, "Not yet" brings it back
 * soon (only for passages that are due).
 */
@Composable
fun SpeedRoundScreen(store: UserDatabase.MemoryStore, texts: MemoryTexts, cards: List<String>, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val all by store.all.collectAsState()
    // 0: ready, 1: playing, 2: finished.
    var phase by remember { mutableIntStateOf(0) }
    var queue by remember { mutableStateOf(cards) }
    var remaining by remember { mutableIntStateOf(SPEED_SECONDS) }
    var revealed by remember { mutableStateOf(false) }
    var known by remember { mutableIntStateOf(0) }
    var graded by remember { mutableIntStateOf(0) }

    LaunchedEffect(phase) {
        if (phase != 1) return@LaunchedEffect
        while (remaining > 0) {
            delay(1000)
            remaining--
        }
        phase = 2
    }
    val verse = queue.firstOrNull()?.let { id -> all.firstOrNull { it.id == id } }
    val passage = rememberPassage(verse, texts)

    SessionScaffold(stringResource(R.string.memorise_speed_round), onClose, modifier) {
        when {
            phase == 0 -> Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.CenterVertically)) {
                Text("⏱", style = MaterialTheme.typography.displayMedium, color = colors.accent)
                Text(stringResource(R.string.memorise_one_minute), style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(stringResource(R.string.memorise_speed_intro), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText, textAlign = TextAlign.Center)
                PrimaryButton(stringResource(R.string.start), { phase = if (queue.isEmpty()) 2 else 1 }, Modifier.fillMaxWidth())
            }
            phase == 2 || verse == null -> SessionFinished(
                if (graded == 1) stringResource(R.string.memorise_practiced_one) else stringResource(R.string.memorise_practiced_many, graded),
                detail = stringResource(R.string.memorise_knew_tally, known, graded),
                onDone = onClose,
            )
            else -> {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text("%d:%02d".format(remaining / 60, remaining % 60), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.secondaryText)
                    Spacer(Modifier.weight(1f))
                    LinearProgressIndicator(
                        progress = { remaining.toFloat() / SPEED_SECONDS },
                        color = colors.accent,
                        trackColor = colors.separator,
                        modifier = Modifier.size(width = 160.dp, height = 4.dp),
                    )
                }
                PassageCard(Modifier.weight(1f), onClick = { revealed = true }) {
                    PassageHeader(verse, passage, size = 26)
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                        if (revealed) Text(passage?.text.orEmpty(), style = scriptureStyle(21), color = colors.text)
                        else Text(stringResource(R.string.memorise_say_then_show), style = MaterialTheme.typography.bodyLarge, color = colors.secondaryText)
                    }
                }
                if (revealed) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        fun mark(knewIt: Boolean) {
                            store.recordGame(verse.id, MemoryGame.speedGrade(knewIt))
                            MemoryStreak.record(context)
                            graded++
                            if (knewIt) {
                                known++
                                haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                            }
                            revealed = false
                            // Each passage comes up once; the round ends early when all are done.
                            queue = queue.drop(1)
                            if (queue.isEmpty()) phase = 2
                        }
                        SecondaryButton(stringResource(R.string.memorise_not_yet), { mark(false) }, Modifier.weight(1f), tint = colors.secondaryText)
                        PrimaryButton(stringResource(R.string.memorise_knew_it), { mark(true) }, Modifier.weight(1f))
                    }
                } else {
                    PrimaryButton(stringResource(R.string.memorise_show_verse), { revealed = true }, Modifier.fillMaxWidth())
                }
            }
        }
    }
}

private const val SPEED_SECONDS = 60

internal val MemoryGrade.title: Int
    get() = when (this) {
        MemoryGrade.AGAIN -> R.string.memorise_grade_again
        MemoryGrade.HARD -> R.string.memorise_grade_hard
        MemoryGrade.GOOD -> R.string.memorise_grade_good
        MemoryGrade.EASY -> R.string.memorise_grade_easy
    }
