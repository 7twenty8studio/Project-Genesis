package com.genesis.app.account

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.text.format.DateUtils
import androidx.compose.foundation.BorderStroke
import androidx.compose.runtime.remember
import androidx.compose.material3.AlertDialog
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.genesis.app.R
import com.genesis.app.settings.Footer
import com.genesis.app.settings.Group
import com.genesis.app.settings.Header
import com.genesis.app.settings.Row_
import com.genesis.core.cloud.OAuthProvider
import com.genesis.core.design.LocalReaderColors

/**
 * Account, as AccountView on iOS. Signed out: why to sign in, Sign in with
 * Apple then Google (alike in size and shape), email and password (Sign In
 * or Create Account, Forgot password?), and Continue as Guest. Signed in:
 * who, and Sign Out. Sync and account deletion join with sync.
 */
@Composable
fun AccountScreen(
    account: AccountService,
    state: AccountUiState,
    sync: SyncService,
    syncState: SyncState,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalReaderColors.current
    val context = LocalContext.current

    fun openBrowser(provider: OAuthProvider) {
        val url = account.startOAuth(provider) ?: return
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        } catch (_: ActivityNotFoundException) {
            account.clearMessage()
        }
    }

    Column(modifier.fillMaxSize().background(colors.background).statusBarsPadding().imePadding()) {
        Row(Modifier.padding(start = 20.dp, end = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.account),
                style = MaterialTheme.typography.headlineMedium.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
                color = colors.text,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            TextButton(onClick = onDone) {
                Text(stringResource(R.string.done), color = colors.accent, fontWeight = FontWeight.SemiBold)
            }
        }
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 8.dp)) {
            val user = state.user
            if (user != null) {
                Group {
                    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp)) {
                        Text(stringResource(R.string.signed_in_as), style = MaterialTheme.typography.labelLarge, color = colors.secondaryText)
                        Text(user.email ?: user.name.orEmpty(), style = MaterialTheme.typography.bodyLarge, color = colors.text)
                    }
                }
                CloudSync(sync, syncState)
                AccountActions(sync, state)
            } else {
                SignedOut(account, state, onApple = { openBrowser(OAuthProvider.APPLE) }, onGoogle = { openBrowser(OAuthProvider.GOOGLE) }, onGuest = onDone)
            }
        }
    }
}

@Composable
private fun SignedOut(account: AccountService, state: AccountUiState, onApple: () -> Unit, onGoogle: () -> Unit, onGuest: () -> Unit) {
    val colors = LocalReaderColors.current
    var creating by rememberSaveable { mutableStateOf(false) }
    var email by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    val enabled = account.isAvailable && !state.isWorking
    val canSubmit = enabled && "@" in email && password.length >= 6
    fun submit() {
        if (!canSubmit) return
        if (creating) account.signUp(email, password) else account.signIn(email, password)
    }

    Text(
        stringResource(R.string.keep_notes_safe),
        style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold),
        color = colors.text,
        modifier = Modifier.padding(top = 8.dp),
    )
    Text(
        stringResource(R.string.sign_in_message),
        style = MaterialTheme.typography.bodyMedium,
        color = colors.secondaryText,
        modifier = Modifier.padding(top = 8.dp, bottom = 20.dp),
    )
    if (!account.isAvailable) {
        Text(stringResource(R.string.cloud_not_set_up), color = colors.secondaryText, modifier = Modifier.padding(bottom = 16.dp))
    }

    // Apple first, then Google, alike in size and shape (as on iOS).
    AppleButton(enabled, onApple)
    Spacer(Modifier.size(12.dp))
    GoogleButton(enabled, onGoogle)
    Spacer(Modifier.size(24.dp))

    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        listOf(false, true).forEachIndexed { index, mode ->
            SegmentedButton(
                selected = creating == mode,
                onClick = {
                    creating = mode
                    account.clearMessage()
                },
                shape = SegmentedButtonDefaults.itemShape(index, 2),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = colors.accent.copy(alpha = 0.16f),
                    activeContentColor = colors.text,
                    inactiveContainerColor = colors.surface,
                    inactiveContentColor = colors.secondaryText,
                ),
                icon = {},
            ) { Text(stringResource(if (mode) R.string.create_account else R.string.sign_in)) }
        }
    }
    val fieldColors = OutlinedTextFieldDefaults.colors(
        focusedTextColor = colors.text,
        unfocusedTextColor = colors.text,
        focusedBorderColor = colors.accent,
        unfocusedBorderColor = colors.separator,
        cursorColor = colors.accent,
        focusedLabelColor = colors.accent,
        unfocusedLabelColor = colors.secondaryText,
    )
    OutlinedTextField(
        value = email,
        onValueChange = { email = it },
        label = { Text(stringResource(R.string.email)) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, autoCorrectEnabled = false, imeAction = ImeAction.Next),
        colors = fieldColors,
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    )
    OutlinedTextField(
        value = password,
        onValueChange = { password = it },
        label = { Text(stringResource(if (creating) R.string.password_new else R.string.password)) },
        singleLine = true,
        visualTransformation = PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Go),
        keyboardActions = KeyboardActions(onGo = { submit() }),
        colors = fieldColors,
        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
    )
    Button(
        onClick = ::submit,
        enabled = canSubmit,
        colors = ButtonDefaults.buttonColors(containerColor = colors.accent),
        modifier = Modifier.fillMaxWidth().padding(top = 16.dp).heightIn(min = 50.dp),
    ) {
        if (state.isWorking) {
            CircularProgressIndicator(Modifier.size(20.dp), color = Color.White, strokeWidth = 2.dp)
        } else {
            Text(stringResource(if (creating) R.string.create_account else R.string.sign_in), fontWeight = FontWeight.SemiBold)
        }
    }
    if (!creating) {
        TextButton(onClick = { account.sendPasswordReset(email) }, enabled = enabled && "@" in email) {
            Text(stringResource(R.string.forgot_password), color = colors.accent)
        }
    }
    state.message?.let { message ->
        Text(
            message.text ?: message.res?.let { stringResource(it) }.orEmpty(),
            style = MaterialTheme.typography.bodyMedium,
            color = if (message.isError) Color(0xFFC0392B) else colors.secondaryText,
            modifier = Modifier.padding(top = 8.dp),
        )
    }

    Spacer(Modifier.size(16.dp))
    Group { Row_(stringResource(R.string.continue_as_guest), onClick = onGuest) }
    Footer(stringResource(R.string.guest_footer))
    Spacer(Modifier.size(24.dp))
}

/**
 * Apple's style: black (white in a dark theme) and its words. Apple's logo
 * goes in front once its official artwork is added (Apple's design
 * resources); it can't be drawn here.
 */
@Composable
private fun AppleButton(enabled: Boolean, onClick: () -> Unit) {
    val dark = LocalReaderColors.current.isDark
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (dark) Color.White else Color.Black,
            contentColor = if (dark) Color.Black else Color.White,
        ),
        modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
    ) {
        Text(stringResource(R.string.sign_in_with_apple), fontWeight = FontWeight.Medium)
    }
}

/** Google's style (its branding guidelines): white or near-black, grey outline, the four-colour G. */
@Composable
private fun GoogleButton(enabled: Boolean, onClick: () -> Unit) {
    val dark = LocalReaderColors.current.isDark
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        shape = CircleShape,
        border = BorderStroke(1.dp, if (dark) Color(0xFF8E918F) else Color(0xFF747775)),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = if (dark) Color(0xFF131314) else Color.White,
            contentColor = if (dark) Color(0xFFE3E3E3) else Color(0xFF1F1F1F),
        ),
        modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            GoogleLogo(Modifier.size(18.dp))
            Text(stringResource(R.string.sign_in_with_google), fontWeight = FontWeight.Medium)
        }
    }
}

/** Google's G, drawn as on iOS (GoogleLogo): a ring open at the top right and a blue crossbar. Decorative. */
@Composable
private fun GoogleLogo(modifier: Modifier) {
    Canvas(modifier) {
        val side = size.minDimension
        val line = side * 0.2f
        val radius = (side - line) / 2
        val center = Offset(size.width / 2, size.height / 2)
        val box = Size(radius * 2, radius * 2)
        val topLeft = Offset(center.x - radius, center.y - radius)
        listOf(
            Triple(0f, 45f, Color(0xFF4285F4)),
            Triple(45f, 145f, Color(0xFF34A853)),
            Triple(145f, 215f, Color(0xFFFBBC05)),
            Triple(215f, 318f, Color(0xFFEA4335)),
        ).forEach { (from, to, color) ->
            drawArc(color, startAngle = from, sweepAngle = to - from, useCenter = false, topLeft = topLeft, size = box, style = Stroke(width = line))
        }
        drawRect(Color(0xFF4285F4), topLeft = Offset(center.x, center.y - line / 2), size = Size(side / 2, line))
    }
}

@Composable
private fun CloudSync(sync: SyncService, state: SyncState) {
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    Header(stringResource(R.string.cloud_sync))
    Group {
        Row_(stringResource(R.string.sync_now), onClick = { if (!state.isSyncing) scope.launch { sync.syncNow() } })
        val failure = state.failure
        val status = when {
            state.isSyncing -> stringResource(R.string.syncing)
            failure != null -> failure.text ?: failure.res?.let { stringResource(it) }.orEmpty()
            state.lastSyncedAt != null && System.currentTimeMillis() - state.lastSyncedAt < DateUtils.MINUTE_IN_MILLIS ->
                stringResource(R.string.synced_just_now)
            state.lastSyncedAt != null -> stringResource(
                R.string.synced,
                DateUtils.getRelativeTimeSpanString(state.lastSyncedAt, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString(),
            )
            else -> stringResource(R.string.waiting_to_sync)
        }
        Text(
            status,
            style = MaterialTheme.typography.bodySmall,
            color = if (failure != null && !state.isSyncing) Color(0xFFC0392B) else colors.secondaryText,
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp),
        )
    }
    Footer(stringResource(R.string.sync_footer))
}

/** Sign Out (keeping or removing this device's copy) and Delete Account, as on iOS. */
@Composable
private fun AccountActions(sync: SyncService, state: AccountUiState) {
    val colors = LocalReaderColors.current
    val scope = rememberCoroutineScope()
    var confirmSignOut by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val destructive = Color(0xFFC0392B)

    Spacer(Modifier.size(24.dp))
    Group { Row_(stringResource(R.string.sign_out), onClick = { confirmSignOut = true }) }
    Spacer(Modifier.size(24.dp))
    Group {
        Row_(stringResource(R.string.delete_account), onClick = { if (!state.isWorking) confirmDelete = true })
        state.message?.takeIf { it.isError }?.let { message ->
            Text(
                message.text ?: message.res?.let { stringResource(it) }.orEmpty(),
                style = MaterialTheme.typography.bodySmall,
                color = destructive,
                modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp),
            )
        }
    }
    Footer(stringResource(R.string.delete_account_footer))

    if (confirmSignOut) {
        AlertDialog(
            onDismissRequest = { confirmSignOut = false },
            title = { Text(stringResource(R.string.sign_out_question)) },
            text = {
                Column {
                    Text(stringResource(R.string.sign_out_message))
                    Spacer(Modifier.size(16.dp))
                    TextButton(onClick = { confirmSignOut = false; scope.launch { sync.signOut(removeLocalData = false) } }) {
                        Text(stringResource(R.string.sign_out_keep_data), color = colors.accent)
                    }
                    TextButton(onClick = { confirmSignOut = false; scope.launch { sync.signOut(removeLocalData = true) } }) {
                        Text(stringResource(R.string.sign_out_remove_data), color = destructive)
                    }
                }
            },
            confirmButton = {},
            dismissButton = {
                TextButton(onClick = { confirmSignOut = false }) { Text(stringResource(R.string.cancel), color = colors.accent) }
            },
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.secondaryText,
        )
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(stringResource(R.string.delete_account_question)) },
            text = { Text(stringResource(R.string.delete_account_message)) },
            confirmButton = {
                TextButton(onClick = { confirmDelete = false; scope.launch { sync.deleteAccount() } }) {
                    Text(stringResource(R.string.delete_account), color = destructive)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text(stringResource(R.string.cancel), color = colors.accent) }
            },
            containerColor = colors.surface,
            titleContentColor = colors.text,
            textContentColor = colors.secondaryText,
        )
    }
}
