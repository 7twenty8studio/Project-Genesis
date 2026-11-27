package com.genesis.app.moments

import android.content.Context
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.features.shows
import com.genesis.app.reader.backdrop.rememberReduceMotion
import com.genesis.app.settings.Entitlements
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.features.OptionalFeature
import com.genesis.core.domain.moments.ChapterMomentRule
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import java.time.LocalDate
import java.util.UUID

/**
 * A brief gold-ribbon moment when a chapter or a plan day is finished, as
 * ChapterMoments.swift (part of the deluxe look, Premium themes; the
 * overlay checks access and the Chapter Ribbons switch). At most once per
 * chapter (or plan day) per day.
 */
object ChapterMoments {
    enum class Place { READER, PLANS, HOME }

    sealed interface Kind {
        data class Chapter(val chapter: ChapterId) : Kind
        data class PlanDay(val day: Int) : Kind
    }

    data class Moment(val kind: Kind, val place: Place, val createdAt: Long = System.currentTimeMillis(), val id: String = UUID.randomUUID().toString()) {
        /** A moment nobody saw (its screen wasn't showing) isn't shown later. */
        val isFresh: Boolean get() = System.currentTimeMillis() - createdAt < 3_000
    }

    private val _current = MutableStateFlow<Moment?>(null)
    val current: StateFlow<Moment?> = _current.asStateFlow()

    private const val CELEBRATED = "moments.celebrated"

    /** The person reached the end of a chapter by reading. */
    fun chapterFinished(context: Context, chapter: ChapterId, place: Place = Place.READER) =
        celebrate(context, Kind.Chapter(chapter), ChapterMomentRule.chapterSubject(chapter), place)

    /** A reading-plan day was newly marked as read. */
    fun planDayCompleted(context: Context, day: Int, planId: String, place: Place) =
        celebrate(context, Kind.PlanDay(day), ChapterMomentRule.planDaySubject(planId, day), place)

    fun dismiss(moment: Moment) = _current.update { if (it?.id == moment.id) null else it }

    private fun celebrate(context: Context, kind: Kind, subject: String, place: Place): Boolean {
        val today = LocalDate.now()
        val defaults = context.getSharedPreferences("moments", Context.MODE_PRIVATE)
        val key = ChapterMomentRule.key(subject, today)
        val celebrated = ChapterMomentRule.pruned(defaults.getStringSet(CELEBRATED, emptySet()).orEmpty(), today).toMutableSet()
        if (!ChapterMomentRule.shouldCelebrate(key, celebrated)) return false
        celebrated += key
        defaults.edit { putStringSet(CELEBRATED, celebrated) }
        _current.value = Moment(kind, place)
        return true
    }
}

/**
 * The chapter-complete moment, as ChapterMomentOverlay.swift: a gold ribbon
 * drops in from the top edge with a soft haptic, then lifts away (about
 * 1.5 s). It sits in the top corner, never takes touches, and with Reduce
 * Motion simply fades.
 */
@Composable
fun ChapterMomentOverlay(place: ChapterMoments.Place, topInset: Dp = 0.dp, playsHaptic: Boolean = true, language: String = "en") {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val moment by ChapterMoments.current.collectAsStateWithLifecycle()
    val features by app.features.enabled.collectAsStateWithLifecycle()
    val flags by app.flags.values.collectAsStateWithLifecycle()
    val reduceMotion = rememberReduceMotion()
    val haptics = LocalHapticFeedback.current
    val view = LocalView.current
    var shown by remember { mutableStateOf<ChapterMoments.Moment?>(null) }
    var visible by remember { mutableStateOf(false) }
    val chapterComplete = stringResource(R.string.chapter_complete)
    val dayComplete = stringResource(R.string.day_complete)

    LaunchedEffect(moment?.id) {
        val current = moment
        if (current == null || current.place != place || !current.isFresh) {
            visible = false
            return@LaunchedEffect
        }
        // Premium's deluxe look, and only for people who keep the ribbons on.
        if (!Entitlements.isPremium || !features.shows(OptionalFeature.MOMENTS, flags)) {
            ChapterMoments.dismiss(current)
            return@LaunchedEffect
        }
        shown = current
        visible = true
        if (playsHaptic) haptics.performHapticFeedback(HapticFeedbackType.Confirm)
        @Suppress("DEPRECATION")
        view.announceForAccessibility(if (current.kind is ChapterMoments.Kind.Chapter) chapterComplete else dayComplete)
        delay(1_050)
        visible = false
        delay(250)
        ChapterMoments.dismiss(current)
    }

    Box(Modifier.fillMaxSize().clearAndSetSemantics {}, contentAlignment = Alignment.TopEnd) {
        AnimatedVisibility(
            visible = visible,
            enter = if (reduceMotion) fadeIn(tween(200)) else slideInVertically(spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow)) { -it } + fadeIn(),
            exit = if (reduceMotion) fadeOut(tween(200)) else slideOutVertically(tween(200)) { -it } + fadeOut(tween(200)),
            modifier = Modifier.padding(end = 24.dp),
        ) {
            val kind = shown?.kind
            val detail = when (kind) {
                is ChapterMoments.Kind.Chapter -> kind.chapter.description(language)
                is ChapterMoments.Kind.PlanDay -> stringResource(R.string.day_number, kind.day)
                null -> ""
            }
            Ribbon(
                title = if (kind is ChapterMoments.Kind.PlanDay) dayComplete else chapterComplete,
                detail = detail,
                topInset = topInset,
                shines = !reduceMotion,
            )
        }
    }
}

private val GoldDark = Color(0xFF8C6D3F)
private val Gold = Color(0xFFB8955A)
private val GoldLight = Color(0xFFDCC28E)

/** A muted gold ribbon hanging from the top edge, with a small label beside it. */
@Composable
private fun Ribbon(title: String, detail: String, topInset: Dp, shines: Boolean) {
    val colors = LocalReaderColors.current
    val shine = remember { Animatable(0f) }
    LaunchedEffect(Unit) { if (shines) { delay(250); shine.animateTo(1f, tween(900)) } }
    Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(
            Modifier.padding(bottom = 4.dp).background(colors.surface.copy(alpha = 0.92f), RoundedCornerShape(50)).padding(horizontal = 12.dp, vertical = 7.dp),
            horizontalAlignment = Alignment.End,
        ) {
            Text(title, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
            Text(detail, style = MaterialTheme.typography.labelSmall, color = colors.secondaryText)
        }
        Canvas(Modifier.size(24.dp, topInset + 58.dp).shadow(3.dp, clip = false)) {
            val notch = minOf(size.width * 0.5f, size.height * 0.3f)
            val path = Path().apply {
                moveTo(0f, 0f); lineTo(size.width, 0f); lineTo(size.width, size.height)
                lineTo(size.width / 2, size.height - notch); lineTo(0f, size.height); close()
            }
            clipPath(path) {
                drawRect(Brush.horizontalGradient(listOf(GoldDark, GoldLight, Gold, GoldDark)))
                // One soft glint running down the ribbon.
                val travel = size.height + 80.dp.toPx()
                val y = -40.dp.toPx() + travel * shine.value
                drawRect(
                    Brush.verticalGradient(listOf(Color.Transparent, Color.White.copy(alpha = 0.35f), Color.Transparent), startY = y - 14.dp.toPx(), endY = y + 14.dp.toPx()),
                    topLeft = Offset(0f, y - 14.dp.toPx()),
                    size = androidx.compose.ui.geometry.Size(size.width, 28.dp.toPx()),
                )
            }
        }
    }
}
