package com.genesis.app.memorise

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.keyframes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.core.data.UserDatabase
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.memorise.FillGapsGame
import com.genesis.core.domain.memorise.MemoryGame
import com.genesis.core.domain.memorise.MemoryMastery
import com.genesis.core.domain.memorise.WordOrderGame
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * Fill the Gaps or Word Order over some passages, one at a time, as
 * MemoryGameView on iOS. A solved passage shows in full, verbatim, and the
 * result goes to the schedule (if it was due) and the practice streak.
 */
@Composable
fun MemoryGameScreen(store: UserDatabase.MemoryStore, texts: MemoryTexts, mode: MemoryGameMode, cards: List<String>, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val all by store.all.collectAsState()
    var queue by remember { mutableStateOf(cards) }
    var completed by remember { mutableIntStateOf(0) }
    var solvedText by remember { mutableStateOf<String?>(null) }

    val verse = queue.firstOrNull()?.let { id -> all.firstOrNull { it.id == id } }
    LaunchedEffect(queue, all) { if (queue.isNotEmpty() && verse == null) queue = queue.drop(1) }
    val passage = rememberPassage(verse, texts, nearby = mode == MemoryGameMode.FILL_GAPS)

    SessionScaffold(stringResource(mode.title), onClose, modifier) {
        if (verse == null) {
            SessionFinished(
                if (completed == 1) stringResource(R.string.memorise_practiced_one) else stringResource(R.string.memorise_practiced_many, completed),
                onDone = onClose,
            )
            return@SessionScaffold
        }
        SessionProgress(completed, completed + queue.size)
        PassageCard(Modifier.weight(1f)) {
            PassageHeader(verse, passage)
            val solved = solvedText
            when {
                solved != null -> {
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                        // Always the passage verbatim from the Bible.
                        Text(solved, style = scriptureStyle(21), color = colors.text)
                    }
                    PrimaryButton(stringResource(R.string.next), {
                        solvedText = null
                        queue = queue.drop(1)
                        completed++
                    }, Modifier.fillMaxWidth())
                }
                passage == null -> Box(Modifier.weight(1f))
                else -> key(verse.id, passage.bibleId) {
                    val onSolved = { mistakes: Int, steps: Int ->
                        store.recordGame(verse.id, MemoryGame.grade(mistakes, steps))
                        MemoryStreak.record(context)
                        haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                        solvedText = passage.text
                    }
                    when (mode) {
                        MemoryGameMode.FILL_GAPS -> FillGapsBoard(passage.text, verse.mastery, passage.nearby, onSolved, Modifier.weight(1f))
                        else -> WordOrderBoard(passage.verses, onSolved, Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/** A word from the verse as a quiet rounded chip, in the reader's font. */
@Composable
private fun WordChip(text: String, shake: Float, onClick: () -> Unit) {
    val colors = LocalReaderColors.current
    val shape = RoundedCornerShape(12.dp)
    Text(
        text,
        style = scriptureStyle(19),
        color = colors.text,
        modifier = Modifier.offset { IntOffset(shake.roundToInt(), 0) }
            .heightIn(min = 44.dp)
            .background(colors.background, shape)
            .border(1.dp, colors.separator, shape)
            .clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 8.dp),
    )
}

/** A small sideways shake for a wrong tap. */
private suspend fun Animatable<Float, *>.shake() {
    snapTo(0f)
    animateTo(0f, keyframes {
        durationMillis = 300
        14f at 40
        -14f at 110
        10f at 170
        -6f at 230
    })
}

/**
 * Fill the Gaps for one passage: some words hidden; choose each in turn from
 * a few of the verse's own words. The better it's known, the more gaps.
 */
@Composable
private fun FillGapsBoard(text: String, mastery: MemoryMastery, nearby: List<String>, onSolved: (Int, Int) -> Unit, modifier: Modifier) {
    val colors = LocalReaderColors.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    var game by remember { mutableStateOf(FillGapsGame.start(text, mastery, nearby, MemoryGame.randomSeed())) }
    val shake = remember { Animatable(0f) }
    var shaking by remember { mutableStateOf<String?>(null) }
    val missing = stringResource(R.string.memorise_missing_word)
    val missingCurrent = stringResource(R.string.memorise_missing_word_current)

    Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        FlowRow(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            game.words.tokens.forEachIndexed { index, token ->
                if (game.isHidden(index)) {
                    val current = game.currentGap == index
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.semantics { contentDescription = if (current) missingCurrent else missing },
                    ) {
                        Text(token.leadingPunctuation, style = scriptureStyle(21), color = colors.text)
                        Box(
                            Modifier.size(width = 64.dp, height = 26.dp)
                                .background(if (current) colors.accent.copy(alpha = 0.18f) else colors.separator.copy(alpha = 0.45f), RoundedCornerShape(6.dp))
                                .border(1.dp, if (current) colors.accent else colors.separator.copy(alpha = 0f), RoundedCornerShape(6.dp)),
                        )
                        Text(token.trailingPunctuation, style = scriptureStyle(21), color = colors.text)
                    }
                } else {
                    Text(token.text, style = scriptureStyle(21), color = if (game.wasFilled(index)) colors.accent else colors.text)
                }
            }
        }
        if (!game.isSolved) {
            Text(stringResource(R.string.memorise_choose_missing), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                game.currentChoices.forEach { choice ->
                    WordChip(choice, if (shaking == choice) shake.value else 0f) {
                        val (next, right) = game.choose(choice)
                        game = next
                        if (right) {
                            haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                            if (next.isSolved) onSolved(next.mistakes, next.gaps.size)
                        } else {
                            haptics.performHapticFeedback(HapticFeedbackType.Reject)
                            shaking = choice
                            scope.launch { shake.shake() }
                        }
                    }
                }
            }
        }
    }
}

/**
 * Word Order for one passage: each verse's words, shuffled as chips, tapped
 * back in order (several verses go one verse at a time).
 */
@Composable
private fun WordOrderBoard(verseTexts: List<String>, onSolved: (Int, Int) -> Unit, modifier: Modifier) {
    val colors = LocalReaderColors.current
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    var stage by remember { mutableIntStateOf(0) }
    var game by remember { mutableStateOf(WordOrderGame.start(verseTexts.firstOrNull().orEmpty(), MemoryGame.randomSeed())) }
    var earlierMistakes by remember { mutableIntStateOf(0) }
    var earlierSteps by remember { mutableIntStateOf(0) }
    val shake = remember { Animatable(0f) }
    var shaking by remember { mutableStateOf<Int?>(null) }

    Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
            val built = (verseTexts.take(stage) + game.builtText).filter { it.isNotEmpty() }.joinToString(" ")
            Text(built, style = scriptureStyle(21), color = colors.text)
        }
        if (verseTexts.size > 1) {
            Text(stringResource(R.string.memorise_verse_of, stage + 1, verseTexts.size), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            game.shuffled.forEach { index ->
                if (!game.isPlaced(index)) {
                    WordChip(game.words.tokens[index].text, if (shaking == index) shake.value else 0f) {
                        val (next, right) = game.tap(index)
                        if (!right) {
                            game = next
                            haptics.performHapticFeedback(HapticFeedbackType.Reject)
                            shaking = index
                            scope.launch { shake.shake() }
                            return@WordChip
                        }
                        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                        if (!next.isSolved) {
                            game = next
                            return@WordChip
                        }
                        earlierMistakes += next.mistakes
                        earlierSteps += next.words.tokens.size
                        if (stage + 1 < verseTexts.size) {
                            stage++
                            game = WordOrderGame.start(verseTexts[stage], MemoryGame.randomSeed())
                        } else {
                            game = next
                            onSolved(earlierMistakes, earlierSteps)
                        }
                    }
                }
            }
        }
    }
}
