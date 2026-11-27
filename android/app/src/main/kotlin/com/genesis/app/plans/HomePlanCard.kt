package com.genesis.app.plans

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.plans.PlanEnrollment
import java.time.LocalDate

/**
 * Home's Today's Reading, as on iOS: the most recently used active plan's
 * reading for today (Read, Mark as Read), or an invitation to start one.
 * The section header (with All Plans) is drawn by Home.
 */
@Composable
fun HomePlanCard(
    enrollment: PlanEnrollment?,
    onRead: (ChapterId) -> Unit,
    onMark: (PlanEnrollment, Int, Boolean) -> Unit,
    onOpen: (PlanEnrollment) -> Unit,
    onPlans: () -> Unit,
) {
    val colors = LocalReaderColors.current
    val progress = enrollment?.progress
    if (enrollment == null || progress == null) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).clickable(onClick = onPlans).background(colors.surface).padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            CalendarIcon()
            Column(Modifier.weight(1f)) {
                Text(stringResource(R.string.plans_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
                Text(stringResource(R.string.plans_card_message), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
            }
            Text("›", style = MaterialTheme.typography.titleLarge, color = colors.secondaryText)
        }
        return
    }
    val language = appLanguage()
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).clickable { onOpen(enrollment) }.background(colors.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(enrollmentTitle(enrollment), style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = colors.accent)
        val day = progress.todaysDay(LocalDate.now())
        if (progress.isComplete) {
            Text(stringResource(R.string.plan_complete), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
        } else if (day != null) {
            val done = day.number in enrollment.completedDays
            Text(
                day.title(language),
                style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
            )
            ReadButtons(
                done = done,
                onRead = { day.spans.firstOrNull()?.let { onRead(it.first) } },
                onMark = { onMark(enrollment, day.number, true) },
            )
        }
        Progress(progress.fractionComplete)
    }
}

/** A small calendar, drawn so the app needs no icon library. */
@Composable
private fun CalendarIcon() {
    val color = LocalReaderColors.current.accent
    Canvas(Modifier.size(28.dp)) {
        val stroke = 2.dp.toPx()
        val top = size.height * 0.18f
        drawRoundRect(color, Offset(stroke, top), Size(size.width - stroke * 2, size.height - top - stroke), CornerRadius(4.dp.toPx()), style = Stroke(stroke))
        drawLine(color, Offset(stroke, size.height * 0.4f), Offset(size.width - stroke, size.height * 0.4f), stroke)
        drawLine(color, Offset(size.width * 0.3f, 0f + stroke), Offset(size.width * 0.3f, top + stroke * 2), stroke, StrokeCap.Round)
        drawLine(color, Offset(size.width * 0.7f, 0f + stroke), Offset(size.width * 0.7f, top + stroke * 2), stroke, StrokeCap.Round)
    }
}
