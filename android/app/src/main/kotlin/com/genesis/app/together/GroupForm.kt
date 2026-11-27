package com.genesis.app.together

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.app.plans.planTitle
import com.genesis.app.prayer.fieldColors
import com.genesis.core.cloud.community.GroupPlanChoice
import com.genesis.core.cloud.community.GroupSummary
import com.genesis.core.design.LocalReaderColors
import com.genesis.core.domain.plans.GroupPlan
import com.genesis.core.domain.plans.ReadingPlan
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** The group's plan, if any, from its columns. */
internal val GroupSummary.plan: ReadingPlan?
    get() = GroupPlan.plan(id, planId, planTitle, planBooks, planDays)

/** Today's day in the group's plan (0 before it starts), or null without one. */
internal fun GroupSummary.planDay(today: LocalDate = LocalDate.now()): Int? {
    val plan = plan ?: return null
    val start = GroupPlan.startDate(planStart) ?: return null
    return GroupPlan.day(plan, start, today)
}

/** A plan's name: a group's custom plan keeps the title its leader gave it. */
@Composable
internal fun groupPlanTitle(group: GroupSummary, plan: ReadingPlan): String =
    if (plan.isBuiltIn) planTitle(plan) else group.planTitle?.takeIf { it.isNotBlank() } ?: stringResource(R.string.group_plan)

/**
 * Start a group, or edit one you lead (GroupFormView on iOS): its name, what
 * it's for, and a plan to read together from a chosen day.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun GroupForm(existing: GroupSummary?, onSaved: (String) -> Unit, onCancel: () -> Unit) {
    val app = LocalContext.current.applicationContext as VerselyApplication
    val state by app.community.state.collectAsStateWithLifecycle()
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    val existingPlan = existing?.plan
    // A group's own custom plan is offered too, so editing doesn't replace it.
    val customPlan = existingPlan?.takeIf { !it.isBuiltIn }
    var name by rememberSaveable { mutableStateOf(existing?.name.orEmpty()) }
    var purpose by rememberSaveable { mutableStateOf(existing?.description.orEmpty()) }
    var hasPlan by rememberSaveable { mutableStateOf(existing == null || existingPlan != null) }
    var planId by rememberSaveable { mutableStateOf(existingPlan?.id ?: ReadingPlan.GOSPELS) }
    var start by rememberSaveable { mutableStateOf((GroupPlan.startDate(existing?.planStart) ?: LocalDate.now()).toString()) }
    var pickingDate by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    val choices = listOfNotNull(customPlan) + ReadingPlan.builtIns
    val titles = choices.associate { plan -> plan.id to if (plan === customPlan) groupPlanTitle(existing!!, plan) else planTitle(plan) }

    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(stringResource(if (existing == null) R.string.start_group else R.string.edit_group)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(value = name, onValueChange = { name = it.take(60) }, placeholder = { Text(stringResource(R.string.group_name)) }, singleLine = true, colors = fieldColors())
                OutlinedTextField(value = purpose, onValueChange = { purpose = it.take(300) }, placeholder = { Text(stringResource(R.string.group_purpose)) }, minLines = 2, colors = fieldColors())
                Row(Modifier.fillMaxWidth().padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.read_plan_together), color = colors.text, modifier = Modifier.weight(1f))
                    Switch(checked = hasPlan, onCheckedChange = { hasPlan = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.accent, checkedThumbColor = colors.background))
                }
                if (hasPlan) {
                    Text(stringResource(R.string.plan_label), style = MaterialTheme.typography.labelLarge, color = colors.secondaryText)
                    choices.forEach { plan ->
                        Row(Modifier.fillMaxWidth().clickable { planId = plan.id }, verticalAlignment = Alignment.CenterVertically) {
                            RadioButton(selected = planId == plan.id, onClick = { planId = plan.id }, colors = RadioButtonDefaults.colors(selectedColor = colors.accent))
                            Text(titles.getValue(plan.id), color = colors.text)
                        }
                    }
                    Row(Modifier.fillMaxWidth().clickable { pickingDate = true }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.starts), color = colors.text, modifier = Modifier.weight(1f))
                        Text(LocalDate.parse(start).format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)), color = colors.accent)
                    }
                }
                Text(stringResource(R.string.group_plan_footer), style = MaterialTheme.typography.bodySmall, color = colors.secondaryText)
                state.error?.let { Text(stringResource(it.text()), style = MaterialTheme.typography.bodySmall, color = colors.accent) }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    val plan = choices.firstOrNull { it.id == planId }?.takeIf { hasPlan }?.let { chosen ->
                        GroupPlanChoice(
                            id = chosen.id,
                            title = titles.getValue(chosen.id),
                            books = chosen.custom?.books,
                            days = chosen.custom?.days,
                            start = start,
                        )
                    }
                    saving = true
                    scope.launch {
                        val id = if (existing == null) {
                            app.community.createGroup(name, purpose, plan)
                        } else {
                            existing.id.takeIf { app.community.updateGroup(existing.id, name, purpose, plan) }
                        }
                        saving = false
                        id?.let(onSaved)
                    }
                },
                enabled = name.isNotBlank() && !saving,
            ) { Text(stringResource(if (existing == null) R.string.create else R.string.save), color = colors.accent, fontWeight = FontWeight.SemiBold) }
        },
        dismissButton = { TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
    )

    if (pickingDate) {
        // The picker works in UTC midnights.
        val picker = rememberDatePickerState(initialSelectedDateMillis = LocalDate.parse(start).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextButton(onClick = {
                    picker.selectedDateMillis?.let { start = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate().toString() }
                    pickingDate = false
                }) { Text(stringResource(R.string.ok), color = colors.accent) }
            },
            dismissButton = { TextButton(onClick = { pickingDate = false }) { Text(stringResource(R.string.cancel), color = colors.secondaryText) } },
        ) { DatePicker(state = picker) }
    }
}
