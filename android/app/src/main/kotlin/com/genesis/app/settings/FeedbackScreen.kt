package com.genesis.app.settings

import android.os.Build
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.genesis.app.R
import com.genesis.app.VerselyApplication
import com.genesis.core.design.LocalReaderColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** What someone is telling us about (iOS's FeedbackCategory; the ids are the table's). */
private enum class FeedbackCategory(val id: String, val title: Int) {
    BUG("bug", R.string.feedback_bug),
    IDEA("idea", R.string.feedback_idea),
    QUESTION("question", R.string.feedback_question),
    SCRIPTURE("scripture", R.string.feedback_scripture),
    OTHER("other", R.string.feedback_other),
}

/**
 * Settings › Send Feedback, as FeedbackView.swift: a topic, the message, an
 * optional email when signed out and, if wanted, the app and device details.
 * Saved to public.app_feedback (anyone can send; only the owner reads them).
 */
@Composable
fun FeedbackScreen(readingContext: String?, onDone: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current
    val app = context.applicationContext as VerselyApplication
    val signedIn = app.account.state.value.user != null
    val scope = rememberCoroutineScope()
    var category by rememberSaveable { mutableStateOf(FeedbackCategory.BUG) }
    var message by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var includesDetails by rememberSaveable { mutableStateOf(true) }
    var sending by remember { mutableStateOf(false) }
    var sent by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<Int?>(null) }
    val version = remember {
        val info = runCatching { context.packageManager.getPackageInfo(context.packageName, 0) }.getOrNull()
        "${info?.versionName ?: "?"} (${info?.longVersionCode ?: "?"})"
    }
    val device = "${Build.MANUFACTURER} ${Build.MODEL}"
    val language = com.genesis.app.plans.appLanguage().let { if (it in setOf("es", "pt")) it else "en" }

    fun send() {
        val client = app.account.client ?: run { error = R.string.feedback_unavailable; return }
        sending = true
        error = null
        scope.launch {
            val row = buildJsonObject {
                put("category", category.id)
                put("message", message.trim().take(4000))
                email.trim().takeIf { it.isNotEmpty() && !signedIn }?.let { put("contact_email", it.take(320)) }
                if (includesDetails) {
                    put("app_version", version)
                    put("os_version", "Android ${Build.VERSION.RELEASE}")
                    put("device", device)
                    readingContext?.let { put("context", it) }
                }
                put("language", language)
            }
            val ok = runCatching {
                val token = if (signedIn) runCatching { app.account.accessToken() }.getOrNull() else null
                withContext(Dispatchers.IO) { client.insert("app_feedback", buildJsonArray { add(row) }.toString(), token) }
            }.isSuccess
            sending = false
            if (ok) sent = true else error = R.string.feedback_failed
        }
    }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 8.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onDone) { Text("‹ " + stringResource(R.string.settings), color = colors.accent) }
            Text(
                stringResource(R.string.send_feedback),
                style = MaterialTheme.typography.titleMedium,
                color = colors.text,
                textAlign = TextAlign.Center,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            Spacer(Modifier.size(96.dp, 1.dp))
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            if (sent) {
                Group {
                    Column(Modifier.fillMaxWidth().padding(vertical = 28.dp, horizontal = 16.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("✓", fontSize = 40.sp, color = colors.accent)
                        Text(stringResource(R.string.thank_you), style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.SemiBold, color = colors.text)
                        Text(stringResource(R.string.feedback_sent), color = colors.secondaryText, textAlign = TextAlign.Center)
                    }
                }
                return@Column
            }
            Header(stringResource(R.string.feedback_about))
            Group {
                FeedbackCategory.entries.forEachIndexed { index, item ->
                    if (index > 0) HorizontalDivider(Modifier.padding(start = 16.dp), color = colors.separator)
                    Row(
                        Modifier.fillMaxWidth().selectable(category == item, role = Role.RadioButton) { category = item }.padding(horizontal = 16.dp, vertical = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(item.title), color = colors.text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
                        if (category == item) Text("✓", color = colors.accent, fontWeight = FontWeight.SemiBold)
                    }
                }
            }
            Header(stringResource(R.string.feedback_message))
            OutlinedTextField(
                value = message,
                onValueChange = { message = it },
                modifier = Modifier.fillMaxWidth().heightIn(min = 140.dp),
            )
            Footer(stringResource(if (category == FeedbackCategory.SCRIPTURE) R.string.feedback_scripture_hint else R.string.feedback_hint))
            Spacer(Modifier.size(20.dp))
            if (!signedIn) {
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it },
                    label = { Text(stringResource(R.string.feedback_email)) },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.size(12.dp))
            }
            Group { SettingSwitch(stringResource(R.string.feedback_include_details), includesDetails) { includesDetails = it } }
            Footer(stringResource(R.string.feedback_details_android, version, Build.VERSION.RELEASE, device))
            Spacer(Modifier.size(20.dp))
            Button(
                onClick = ::send,
                enabled = message.isNotBlank() && !sending,
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (sending) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Color.White)
                else Text(stringResource(R.string.send), fontWeight = FontWeight.SemiBold)
            }
            error?.let { Text(stringResource(it), color = Color(0xFFC2410C), style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 8.dp)) }
        }
    }
}
