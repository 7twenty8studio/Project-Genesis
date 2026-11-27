package com.genesis.app.plans

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Header
import com.genesis.core.data.UserDatabase
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.bible.BibleBooks
import com.genesis.core.domain.bible.ChapterId
import com.genesis.core.domain.plans.PlanDay
import com.genesis.core.domain.plans.PlanEnrollment
import com.genesis.core.domain.plans.ReadingPlan
import java.time.LocalDate
import java.util.UUID

/**
 * Reading plans, as PlansView on iOS: the plans the person follows, the
 * plans they can start (or make), and one plan's days. Free, synced with
 * the person's account.
 */
@Composable
fun PlansFlow(
    store: UserDatabase.PlanStore,
    openPlanId: String?,
    onRead: (ChapterId) -> Unit,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val enrollments by store.all.collectAsStateWithLifecycle()
    var open by rememberSaveable { mutableStateOf(openPlanId) }
    var creating by rememberSaveable { mutableStateOf(false) }
    val opened = open?.let { id -> enrollments.firstOrNull { it.id == id } }

    BackHandler(enabled = creating) { creating = false }
    BackHandler(enabled = !creating && opened != null) { open = null }

    when {
        creating -> CustomPlanScreen(
            onCreate = { title, books, days ->
                val plan = ReadingPlan.custom("custom-${UUID.randomUUID().toString().lowercase()}", title, books, days)
                open = store.start(plan, title, LocalDate.now()).id
                creating = false
            },
            onCancel = { creating = false },
            modifier = modifier,
        )
        opened != null -> PlanDetailScreen(
            enrollment = opened,
            onRead = onRead,
            onToggle = { day, done -> store.setDay(day, done, opened.id) },
            onRestart = { store.restart(opened.id, LocalDate.now()) },
            onRemove = {
                store.delete(opened.id)
                open = null
            },
            onBack = { open = null },
            modifier = modifier,
        )
        else -> PlansList(
            enrollments = enrollments,
            onOpen = { open = it },
            onStart = { plan, title -> open = store.start(plan, title, LocalDate.now()).id },
            onCustom = { creating = true },
            onDone = onDone,
            modifier = modifier,
        )
    }
}

@Composable
private fun TopBar(title: String, action: String, onAction: () -> Unit, leading: Boolean = false) {
    val colors = LocalReaderColors.current
    Row(Modifier.padding(start = if (leading) 4.dp else 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        if (leading) {
            TextButton(onClick = onAction) { Text(action, color = colors.accent) }
        }
        Text(
            title,
            style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
            color = colors.text,
            maxLines = 1,
            modifier = Modifier.weight(1f).padding(start = if (leading) 8.dp else 0.dp).semantics { heading() },
        )
        if (!leading) {
            TextButton(onClick = onAction) { Text(action, color = colors.accent, fontWeight = FontWeight.SemiBold) }
        }
    }
}

@Composable
private fun PlansList(
    enrollments: List<PlanEnrollment>,
    onOpen: (String) -> Unit,
    onStart: (ReadingPlan, String) -> Unit,
    onCustom: () -> Unit,
    onDone: () -> Unit,
    modifier: Modifier,
) {
    val colors = LocalReaderColors.current
    val language = appLanguage()
    val today = LocalDate.now()
    var pending by remember { mutableStateOf<ReadingPlan?>(null) }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        TopBar(stringResource(R.string.plans_title), stringResource(R.string.done), onDone)
        LazyColumn(contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp)) {
            if (enrollments.isNotEmpty()) {
                item { Header(stringResource(R.string.your_plans)) }
                item {
                    Group {
                        enrollments.forEachIndexed { index, enrollment ->
                            val progress = enrollment.progress
                            Column(
                                Modifier.fillMaxWidth().clickable { onOpen(enrollment.id) }.padding(16.dp),
                                verticalArrangement = Arrangement.spacedBy(6.dp),
                            ) {
                                Text(enrollmentTitle(enrollment), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
                                if (progress != null) {
                                    val day = progress.todaysDay(today)
                                    if (progress.isComplete) {
                                        Text(stringResource(R.string.completed), style = MaterialTheme.typography.bodyMedium, color = colors.accent)
                                    } else if (day != null) {
                                        Text(
                                            stringResource(R.string.plan_day_title, day.number, day.title(language)),
                                            style = MaterialTheme.typography.bodyMedium,
                                            color = colors.secondaryText,
                                        )
                                    }
                                    Progress(progress.fractionComplete)
                                }
                            }
                            if (index < enrollments.lastIndex) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                        }
                    }
                }
            }
            item { Header(stringResource(R.string.start_a_plan)) }
            item {
                Group {
                    ReadingPlan.builtIns.forEach { plan ->
                        Column(
                            Modifier.fillMaxWidth().clickable { pending = plan }.padding(16.dp),
                            verticalArrangement = Arrangement.spacedBy(4.dp),
                        ) {
                            Text(planTitle(plan), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.text)
                            Text(planSummary(plan), style = MaterialTheme.typography.bodyMedium, color = colors.secondaryText)
                            Text(
                                stringResource(R.string.plan_days, plan.dayCount),
                                style = MaterialTheme.typography.labelMedium,
                                fontWeight = FontWeight.SemiBold,
                                color = colors.accent,
                            )
                        }
                        HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    }
                    Text(
                        "+  " + stringResource(R.string.create_your_own_plan),
                        style = MaterialTheme.typography.bodyLarge,
                        color = colors.accent,
                        modifier = Modifier.fillMaxWidth().clickable(onClick = onCustom).padding(16.dp),
                    )
                }
            }
        }
    }

    pending?.let { plan ->
        val title = planTitle(plan)
        AlertDialog(
            onDismissRequest = { pending = null },
            title = { Text(title) },
            text = { Text(planSummary(plan)) },
            confirmButton = {
                TextButton(onClick = {
                    pending = null
                    onStart(plan, title)
                }) { Text(stringResource(R.string.start_today), color = colors.accent, fontWeight = FontWeight.SemiBold) }
            },
            dismissButton = { TextButton(onClick = { pending = null }) { Text(stringResource(R.string.cancel), color = colors.accent) } },
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.secondaryText,
        )
    }
}

@Composable
internal fun Progress(fraction: Double, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val label = stringResource(R.string.plan_progress)
    LinearProgressIndicator(
        progress = { fraction.toFloat() },
        color = colors.accent,
        trackColor = colors.separator,
        modifier = modifier.fillMaxWidth().semantics { contentDescription = label },
    )
}

@Composable
private fun PlanDetailScreen(
    enrollment: PlanEnrollment,
    onRead: (ChapterId) -> Unit,
    onToggle: (Int, Boolean) -> Unit,
    onRestart: () -> Unit,
    onRemove: () -> Unit,
    onBack: () -> Unit,
    modifier: Modifier,
) {
    val colors = LocalReaderColors.current
    val language = appLanguage()
    val today = LocalDate.now()
    val plan = enrollment.plan ?: return
    val progress = enrollment.progress ?: return
    val scheduled = progress.scheduledDay(today)
    var confirmRestart by remember { mutableStateOf(false) }
    var confirmRemove by remember { mutableStateOf(false) }
    val list = rememberLazyListState()

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        TopBar(enrollmentTitle(enrollment), stringResource(R.string.all_plans), onBack, leading = true)
        LazyColumn(state = list, contentPadding = PaddingValues(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 32.dp)) {
            item {
                Column(
                    Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(14.dp)).padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    val day = progress.todaysDay(today)
                    if (progress.isComplete) {
                        Text(stringResource(R.string.plan_finished), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.accent)
                    } else if (day != null) {
                        Text(
                            stringResource(R.string.plan_today_eyebrow, day.number, plan.dayCount),
                            style = MaterialTheme.typography.labelMedium.copy(letterSpacing = 1.1.sp, fontWeight = FontWeight.SemiBold),
                            color = colors.accent,
                        )
                        Text(
                            day.title(language),
                            style = MaterialTheme.typography.headlineSmall.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                            color = colors.text,
                        )
                        ReadButtons(
                            done = day.number in enrollment.completedDays,
                            onRead = { day.spans.firstOrNull()?.let { onRead(it.first) } },
                            onMark = { onToggle(day.number, true) },
                        )
                        val behind = progress.daysBehind(today)
                        if (behind > 0) {
                            Text(
                                if (behind == 1) stringResource(R.string.one_day_behind) else stringResource(R.string.days_behind, behind),
                                style = MaterialTheme.typography.bodySmall,
                                color = colors.secondaryText,
                            )
                        }
                    }
                    Progress(progress.fractionComplete)
                    Text(
                        stringResource(R.string.percent_complete, (progress.fractionComplete * 100).toInt()),
                        style = MaterialTheme.typography.bodySmall,
                        color = colors.secondaryText,
                    )
                }
            }
            item { Header(stringResource(R.string.all_days)) }
            items(plan.days, key = { it.number }) { day ->
                DayRow(
                    day = day,
                    language = language,
                    isComplete = day.number in enrollment.completedDays,
                    isToday = day.number == scheduled,
                    onToggle = { onToggle(day.number, day.number !in enrollment.completedDays) },
                    onRead = { day.spans.firstOrNull()?.let { onRead(it.first) } },
                )
            }
            item {
                Spacer(Modifier.size(24.dp))
                Group {
                    Text(
                        stringResource(R.string.restart_plan),
                        color = colors.accent,
                        modifier = Modifier.fillMaxWidth().clickable { confirmRestart = true }.padding(16.dp),
                    )
                    HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    Text(
                        stringResource(R.string.remove_plan),
                        color = Destructive,
                        modifier = Modifier.fillMaxWidth().clickable { confirmRemove = true }.padding(16.dp),
                    )
                }
            }
        }
    }

    if (confirmRestart) {
        Confirm(
            title = stringResource(R.string.restart_question),
            message = stringResource(R.string.restart_message),
            action = stringResource(R.string.restart),
            onConfirm = onRestart,
            onDismiss = { confirmRestart = false },
        )
    }
    if (confirmRemove) {
        Confirm(
            title = stringResource(R.string.remove_question),
            message = null,
            action = stringResource(R.string.remove),
            onConfirm = onRemove,
            onDismiss = { confirmRemove = false },
        )
    }
}

private val Destructive = Color(0xFFC0392B)

@Composable
private fun Confirm(title: String, message: String?, action: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val colors = LocalReaderColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = message?.let { { Text(it) } },
        confirmButton = {
            TextButton(onClick = {
                onDismiss()
                onConfirm()
            }) { Text(action, color = Destructive) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), color = colors.accent) } },
        containerColor = colors.surface,
        titleContentColor = colors.text,
        textContentColor = colors.secondaryText,
    )
}

/** Read and Mark as Read (Done once it's ticked), as on iOS. */
@Composable
internal fun ReadButtons(done: Boolean, onRead: () -> Unit, onMark: () -> Unit) {
    val colors = LocalReaderColors.current
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Button(
            onClick = onRead,
            colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.background),
        ) { Text(stringResource(R.string.read_action)) }
        OutlinedButton(onClick = onMark, enabled = !done) {
            Text(stringResource(if (done) R.string.done else R.string.mark_as_read), color = colors.accent)
        }
    }
}

@Composable
private fun DayRow(day: PlanDay, language: String, isComplete: Boolean, isToday: Boolean, onToggle: () -> Unit, onRead: () -> Unit) {
    val colors = LocalReaderColors.current
    val label = stringResource(if (isComplete) R.string.day_read else R.string.day_not_read, day.number)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 2.dp).background(colors.surface, RoundedCornerShape(12.dp)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.clickable(onClick = onToggle).padding(14.dp).semantics { contentDescription = label },
        ) { Check(isComplete) }
        Column(Modifier.weight(1f).clickable(onClick = onRead).padding(vertical = 12.dp).padding(end = 16.dp)) {
            Text(
                if (isToday) stringResource(R.string.plan_day_today, day.number) else stringResource(R.string.plan_day, day.number),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                color = if (isToday) colors.accent else colors.secondaryText,
            )
            Text(
                day.title(language),
                style = MaterialTheme.typography.bodyLarge,
                color = colors.text,
                textDecoration = if (isComplete) TextDecoration.LineThrough else null,
            )
        }
    }
}

/** A round checkmark, drawn so the app needs no icon library. */
@Composable
private fun Check(on: Boolean) {
    val colors = LocalReaderColors.current
    Canvas(Modifier.size(24.dp)) {
        val radius = size.minDimension / 2 - 1.dp.toPx()
        if (on) {
            drawCircle(colors.accent, radius)
            val w = size.width
            val stroke = 2.2.dp.toPx()
            drawLine(colors.background, Offset(w * 0.28f, w * 0.52f), Offset(w * 0.44f, w * 0.67f), stroke, StrokeCap.Round)
            drawLine(colors.background, Offset(w * 0.44f, w * 0.67f), Offset(w * 0.73f, w * 0.36f), stroke, StrokeCap.Round)
        } else {
            drawCircle(colors.separator, radius, style = Stroke(1.5.dp.toPx()))
        }
    }
}

/** Build a plan from chosen books and a number of days, as CustomPlanView on iOS. */
@Composable
private fun CustomPlanScreen(onCreate: (String, List<Int>, Int) -> Unit, onCancel: () -> Unit, modifier: Modifier) {
    val colors = LocalReaderColors.current
    val language = appLanguage()
    var title by rememberSaveable { mutableStateOf("") }
    var selected by rememberSaveable { mutableStateOf(listOf<Int>()) }
    var days by rememberSaveable { mutableIntStateOf(30) }
    val fallbackTitle = stringResource(R.string.my_plan)

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        Row(Modifier.padding(start = 4.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.accent) }
            Text(
                stringResource(R.string.new_plan),
                style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(
                onClick = { onCreate(title.trim().ifEmpty { fallbackTitle }, selected, days) },
                enabled = selected.isNotEmpty(),
            ) { Text(stringResource(R.string.start), color = if (selected.isEmpty()) colors.secondaryText else colors.accent, fontWeight = FontWeight.SemiBold) }
        }
        LazyColumn(contentPadding = PaddingValues(start = 20.dp, end = 20.dp, bottom = 32.dp)) {
            item { Header(stringResource(R.string.plan_name)) }
            item {
                OutlinedTextField(
                    value = title,
                    onValueChange = { title = it },
                    placeholder = { Text(stringResource(R.string.plan_name_hint)) },
                    singleLine = true,
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = colors.text,
                        unfocusedTextColor = colors.text,
                        focusedBorderColor = colors.accent,
                        unfocusedBorderColor = colors.separator,
                        cursorColor = colors.accent,
                        focusedContainerColor = colors.surface,
                        unfocusedContainerColor = colors.surface,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            item {
                Spacer(Modifier.size(20.dp))
                Group {
                    Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.plan_days, days), color = colors.text, modifier = Modifier.weight(1f))
                        TextButton(onClick = { days = (days - 1).coerceAtLeast(1) }) { Text("−", color = colors.accent, fontSize = 22.sp) }
                        TextButton(onClick = { days = (days + 1).coerceAtMost(730) }) { Text("+", color = colors.accent, fontSize = 22.sp) }
                    }
                }
                if (selected.isNotEmpty()) Footer(customSummary(selected.sorted(), days))
            }
            for ((titleRes, books) in listOf(R.string.old_testament to BibleBooks.oldTestament, R.string.new_testament to BibleBooks.newTestament)) {
                item { Header(stringResource(titleRes)) }
                item {
                    Group {
                        val ids = books.map { it.id }
                        val all = selected.containsAll(ids)
                        Text(
                            stringResource(if (all) R.string.clear_all else R.string.select_all),
                            color = colors.accent,
                            modifier = Modifier.fillMaxWidth().clickable {
                                selected = if (all) selected - ids.toSet() else (selected + ids).distinct()
                            }.padding(16.dp),
                        )
                        books.forEach { book ->
                            val on = book.id in selected
                            HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                            Row(
                                Modifier.fillMaxWidth().clickable { selected = if (on) selected - book.id else selected + book.id }.padding(16.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Text(book.name(language), color = colors.text, modifier = Modifier.weight(1f))
                                if (on) Text("✓", color = colors.accent, fontWeight = FontWeight.SemiBold)
                            }
                        }
                    }
                }
            }
        }
    }
}
