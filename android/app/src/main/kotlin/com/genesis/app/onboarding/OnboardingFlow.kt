package com.genesis.app.onboarding

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.core.bible.BundledBible
import com.genesis.core.bible.Translation
import com.genesis.core.design.BrandColors
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ChapterId
import kotlinx.coroutines.launch
import java.util.Locale

private enum class Step { HERO, PAGES, TRANSLATION, FEATURES }

/**
 * First launch, as OnboardingView on iOS: the hero (Get Started), a few
 * welcome pages, choosing a Bible and where to begin, then "Make Versely
 * yours" (which optional features to show).
 */
@Composable
fun OnboardingFlow(
    translations: List<Pair<com.genesis.core.bible.InstalledBible, Translation>>,
    onBegin: (com.genesis.core.bible.InstalledBible, ChapterId) -> Unit,
) {
    var step by rememberSaveable { mutableStateOf(Step.HERO) }
    // The Bible and chapter chosen, kept until the features are chosen.
    var begin by remember { mutableStateOf<Pair<com.genesis.core.bible.InstalledBible, ChapterId>?>(null) }
    BackHandler(enabled = step != Step.HERO) { step = Step.entries[step.ordinal - 1] }

    AnimatedContent(
        targetState = step,
        transitionSpec = {
            (fadeIn(tween(300)) + slideInHorizontally(tween(300)) { it / 8 }) togetherWith fadeOut(tween(180))
        },
        label = "onboarding",
    ) { current ->
        when (current) {
            Step.HERO -> Hero { step = Step.PAGES }
            Step.PAGES -> WelcomePages { step = Step.TRANSLATION }
            Step.TRANSLATION -> ChooseTranslation(translations) { bible, chapter ->
                begin = bible to chapter
                step = Step.FEATURES
            }
            Step.FEATURES -> com.genesis.app.features.MakeVerselyYours {
                val (bible, chapter) = begin ?: (com.genesis.core.bible.InstalledBible.of(BundledBible.default(Locale.getDefault().language)) to ChapterId.genesis1)
                onBegin(bible, chapter)
            }
        }
    }
}

/** The very first screen: the icon and wordmark over misty mountains, always in the brand's colours. */
@Composable
private fun Hero(onStart: () -> Unit) {
    Box(Modifier.fillMaxSize().background(BrandColors.cream)) {
        Image(
            painterResource(R.drawable.welcome_mountains),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Column(
            Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.weight(1f))
            Image(
                painterResource(R.drawable.welcome_icon),
                contentDescription = null,
                modifier = Modifier.size(132.dp).shadow(20.dp, RoundedCornerShape(30.dp), ambientColor = BrandColors.walnut, spotColor = BrandColors.walnut),
            )
            Spacer(Modifier.height(26.dp))
            val label = stringResource(R.string.versely_bible_study_app)
            Image(
                painterResource(R.drawable.welcome_wordmark),
                contentDescription = label,
                modifier = Modifier.widthIn(max = 280.dp).semantics { heading() },
            )
            Spacer(Modifier.weight(2f))
            Box(
                Modifier
                    .widthIn(max = 460.dp)
                    .fillMaxWidth()
                    .heightIn(min = 54.dp)
                    .shadow(14.dp, CircleShape, ambientColor = BrandColors.walnut, spotColor = BrandColors.walnut)
                    .clip(CircleShape)
                    .background(Brush.verticalGradient(listOf(Color(0xFFC6936A), BrandColors.walnut)))
                    .border(BorderStroke(1.dp, Color.White.copy(alpha = 0.22f)), CircleShape)
                    .clickable(role = Role.Button, onClick = onStart),
                contentAlignment = Alignment.Center,
            ) {
                Text(stringResource(R.string.get_started), color = BrandColors.cream, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(16.dp))
            Text(stringResource(R.string.go_beyond_the_verse), color = BrandColors.cream.copy(alpha = 0.92f), style = MaterialTheme.typography.bodyLarge)
            Spacer(Modifier.height(28.dp))
        }
    }
}

private data class WelcomePage(val image: Int, val title: Int, val message: Int)

private val welcomePages = listOf(
    WelcomePage(R.drawable.onboarding_read, R.string.welcome_read_title, R.string.welcome_read_message),
    WelcomePage(R.drawable.onboarding_listen, R.string.welcome_listen_title, R.string.welcome_listen_message),
    WelcomePage(R.drawable.onboarding_pray, R.string.welcome_pray_title, R.string.welcome_pray_message),
)

/** What Versely is for, a page at a time; Skip goes straight to choosing a Bible. */
@Composable
private fun WelcomePages(onContinue: () -> Unit) {
    val colors = LocalReaderColors.current
    val pager = rememberPagerState { welcomePages.size }
    val scope = rememberCoroutineScope()
    val isLast = pager.currentPage == welcomePages.lastIndex

    Column(
        Modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(colors.background, colors.accent.copy(alpha = 0.10f).compositeOver(colors.background))))
            .statusBarsPadding()
            .navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 12.dp), contentAlignment = Alignment.CenterEnd) {
            if (!isLast) {
                TextButton(onClick = onContinue) { Text(stringResource(R.string.skip), color = colors.secondaryText) }
            }
        }
        HorizontalPager(pager, Modifier.weight(1f)) { index ->
            val page = welcomePages[index]
            Column(
                Modifier.fillMaxSize().padding(horizontal = 32.dp).semantics(mergeDescendants = true) {},
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Image(painterResource(page.image), contentDescription = null, modifier = Modifier.widthIn(max = 340.dp).heightIn(max = 320.dp))
                Spacer(Modifier.height(28.dp))
                Text(
                    stringResource(page.title),
                    fontFamily = FontFamily.Serif,
                    fontSize = 30.sp,
                    lineHeight = 36.sp,
                    color = colors.text,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.semantics { heading() },
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    stringResource(page.message),
                    style = MaterialTheme.typography.bodyLarge,
                    color = colors.secondaryText,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.widthIn(max = 520.dp),
                )
            }
        }
        val dots = stringResource(R.string.page_of, pager.currentPage + 1, welcomePages.size)
        Row(Modifier.padding(vertical = 22.dp).semantics { contentDescription = dots }, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            repeat(welcomePages.size) { index ->
                val current = index == pager.currentPage
                Box(
                    Modifier
                        .size(width = if (current) 22.dp else 7.dp, height = 7.dp)
                        .background(if (current) colors.accent else colors.secondaryText.copy(alpha = 0.3f), CircleShape),
                )
            }
        }
        Button(
            onClick = { if (isLast) onContinue() else scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } },
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
            modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 32.dp).widthIn(max = 560.dp).fillMaxWidth().heightIn(min = 50.dp),
        ) {
            Text(stringResource(if (isLast) R.string.continue_button else R.string.next), fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Choose a Bible (those in the phone's language first) and begin with Genesis or John. */
@Composable
private fun ChooseTranslation(
    translations: List<Pair<com.genesis.core.bible.InstalledBible, Translation>>,
    onBegin: (com.genesis.core.bible.InstalledBible, ChapterId) -> Unit,
) {
    val colors = LocalReaderColors.current
    val language = Locale.getDefault().language
    val ordered = translations.sortedBy { (_, translation) -> if (translation.language.startsWith(language)) 0 else 1 }
    var selection by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(ordered.isNotEmpty()) {
        if (selection == null && ordered.isNotEmpty()) {
            selection = (ordered.firstOrNull { it.second.language.startsWith(language) } ?: ordered.first()).first.id
        }
    }
    val chosen = ordered.firstOrNull { it.first.id == selection }?.first ?: com.genesis.core.bible.InstalledBible.of(BundledBible.default(language))

    Column(
        Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = 24.dp)
            .padding(bottom = 40.dp),
        verticalArrangement = Arrangement.spacedBy(32.dp),
    ) {
        Column(Modifier.padding(top = 60.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Versely", fontFamily = FontFamily.Serif, fontSize = 44.sp, color = colors.text)
            Text(stringResource(R.string.onboarding_tagline), style = MaterialTheme.typography.titleMedium, color = colors.secondaryText)
        }
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                stringResource(R.string.choose_translation),
                style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.semantics { heading() },
            )
            for ((bible, translation) in ordered) {
                val selected = bible.id == selection
                Row(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(18.dp))
                        .background(colors.surface)
                        .border(BorderStroke(1.5.dp, if (selected) colors.accent else Color.Transparent), RoundedCornerShape(18.dp))
                        .selectable(selected = selected, role = Role.RadioButton) { selection = bible.id }
                        .padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Box(
                        Modifier.size(22.dp).border(BorderStroke(2.dp, if (selected) colors.accent else colors.separator), CircleShape).padding(5.dp),
                    ) {
                        if (selected) Box(Modifier.fillMaxSize().background(colors.accent, CircleShape))
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.Bottom) {
                            Text(translation.name, style = MaterialTheme.typography.titleMedium, color = colors.text, modifier = Modifier.weight(1f, fill = false))
                            Spacer(Modifier.width(8.dp))
                            Text(translation.abbreviation, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = colors.accent)
                        }
                        bible.bundled?.summary?.let { Text(stringResource(it), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText) }
                    }
                }
            }
            Text(stringResource(R.string.switch_any_time), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Button(
                onClick = { onBegin(chosen, ChapterId.genesis1) },
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
                modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
            ) { Text(stringResource(R.string.begin_with_genesis), fontWeight = FontWeight.SemiBold) }
            TextButton(onClick = { onBegin(chosen, ChapterId.john1) }) {
                Text(stringResource(R.string.start_with_john), color = colors.accent)
            }
        }
    }
}

/** Each bundled Bible's line, as its `summary` on iOS. */
private val BundledBible.summary: Int?
    get() = when (this) {
        BundledBible.KJV -> R.string.summary_kjv
        BundledBible.WEB -> R.string.summary_web
        BundledBible.ASV -> R.string.summary_asv
        BundledBible.BLIVRE -> R.string.summary_blivre
    }


