package com.genesis.app.journal

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.edit
import com.genesis.core.data.UserDatabase
import com.genesis.core.domain.journal.Attachment
import com.genesis.core.domain.journal.AttachmentStorage
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.Scope
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import java.io.File

/**
 * Copies attachment files to the person's own Google Drive (its hidden app
 * folder), as AttachmentTransfers does with iCloud on iOS: files are saved
 * on the device first, then uploaded when the person has turned the backup
 * on; only then does the attachment's row sync (its storage_path names the
 * Drive file), so another Android device can fetch the file when it's
 * shown. Failed transfers wait 30 s, doubling to 6 hours. Versely's own
 * servers never hold the files.
 */
class AttachmentTransfers(
    private val context: Context,
    private val store: () -> UserDatabase.AttachmentStore,
    private val scope: CoroutineScope,
) {
    /** What stops files reaching Drive, for the note under attachments. */
    enum class Problem { ACCESS_NEEDED, DRIVE_FULL }

    private val prefs = context.getSharedPreferences("attachments", Context.MODE_PRIVATE)
    private val running = Mutex()
    private var retry: Job? = null

    private val _enabled = MutableStateFlow(prefs.getBoolean(ENABLED, false))
    /** Whether the person turned on the Google Drive backup. */
    val enabled: StateFlow<Boolean> = _enabled.asStateFlow()

    private val _problem = MutableStateFlow<Problem?>(null)
    val problem: StateFlow<Problem?> = _problem.asStateFlow()

    private val _pending = MutableStateFlow(0)
    /** Files still to upload. */
    val pending: StateFlow<Int> = _pending.asStateFlow()

    /** Asking Drive for access: either a token now, or the screen Google shows to ask the person. */
    sealed interface Access {
        data class Granted(val token: String) : Access
        data class Ask(val intent: PendingIntent) : Access
        data object Unavailable : Access
    }

    /** Asks for access to the app folder; the person sees Google's screen only the first time. */
    suspend fun requestAccess(): Access = runCatching {
        val result = Identity.getAuthorizationClient(context).authorize(request()).await()
        access(result)
    }.getOrElse {
        Log.w(TAG, "Drive authorization failed", it)
        Access.Unavailable
    }

    /** Google's screen answered; true when the person allowed it (the backup then turns on). */
    fun finishAccess(data: Intent?): Boolean {
        val result = runCatching { Identity.getAuthorizationClient(context).getAuthorizationResultFromIntent(data) }.getOrNull()
        val granted = result?.accessToken != null
        if (granted) turnOn()
        return granted
    }

    fun turnOn() {
        prefs.edit { putBoolean(ENABLED, true); putInt(FAILURES, 0) }
        _enabled.value = true
        _problem.value = null
        kick()
    }

    /** Turns the backup off; files already in Drive stay there and keep syncing their rows. */
    fun turnOff() {
        prefs.edit { putBoolean(ENABLED, false) }
        _enabled.value = false
        _problem.value = null
        retry?.cancel()
    }

    /** Uploads waiting files and removes deleted ones (after an edit, a sync, or opening the app). */
    fun kick() {
        _pending.value = runCatching { store().pendingUploads().size }.getOrDefault(0)
        if (!_enabled.value) return
        scope.launch { runOnce() }
    }

    /** Remembers Drive files to remove (their attachments were deleted). */
    fun queueDeletion(attachments: List<Attachment>) {
        val names = attachments.mapNotNull { AttachmentStorage.driveName(it.storagePath) }
        if (names.isEmpty()) return
        synchronized(prefs) {
            val queued = prefs.getStringSet(DELETIONS, emptySet()).orEmpty() + names
            prefs.edit { putStringSet(DELETIONS, queued) }
        }
        kick()
    }

    /**
     * Brings a synced attachment's file down from Drive when it's shown and
     * isn't on this device yet. False when it can't (no access, offline, or
     * stored in iCloud by an iPhone).
     */
    suspend fun download(attachment: Attachment): Boolean {
        val target = AttachmentFiles.file(context, attachment)
        if (target.exists()) return true
        val name = AttachmentStorage.driveName(attachment.storagePath) ?: return false
        val token = silentToken() ?: return false
        return withContext(Dispatchers.IO) {
            runCatching { DriveClient(token).download(name, target) }
                .onFailure { Log.w(TAG, "Download failed", it) }
                .getOrDefault(false)
        }
    }

    /** Deletes every file Versely put in the person's Drive (deleting the account). */
    suspend fun deleteEverything() {
        retry?.cancel()
        val token = if (_enabled.value) silentToken() else null
        if (token != null) withContext(Dispatchers.IO) { runCatching { DriveClient(token).deleteAll() } }
        prefs.edit { clear() }
        _enabled.value = false
        _problem.value = null
    }

    private suspend fun runOnce(): Unit = running.withLock {
        val token = silentToken() ?: run {
            _problem.value = Problem.ACCESS_NEEDED
            return@withLock
        }
        val drive = DriveClient(token)
        val failed = withContext(Dispatchers.IO) {
            var failed = false
            // Removals first, so a full Drive gets room.
            for (name in prefs.getStringSet(DELETIONS, emptySet()).orEmpty()) {
                runCatching { drive.delete(name) }
                    .onSuccess { synchronized(prefs) { prefs.edit { putStringSet(DELETIONS, prefs.getStringSet(DELETIONS, emptySet()).orEmpty() - name) } } }
                    .onFailure { failed = true; Log.w(TAG, "Couldn't remove $name", it) }
            }
            for (attachment in store().pendingUploads()) {
                val file: File = AttachmentFiles.file(context, attachment)
                if (!file.exists()) continue
                val outcome = runCatching { drive.upload(file, attachment.fileName, AttachmentStorage.mimeType(attachment.kind)) }
                outcome.onSuccess {
                    store().uploaded(attachment.id, AttachmentStorage.drivePath(attachment.fileName))
                }.onFailure { error ->
                    failed = true
                    Log.w(TAG, "Upload failed", error)
                    if (error is DriveClient.Failure && error.isFull) _problem.value = Problem.DRIVE_FULL
                    if (error is DriveClient.Failure && error.isUnauthorized) _problem.value = Problem.ACCESS_NEEDED
                }
                if (_problem.value != null) break
            }
            failed
        }
        _pending.value = store().pendingUploads().size
        if (failed) {
            val failures = prefs.getInt(FAILURES, 0) + 1
            prefs.edit { putInt(FAILURES, failures) }
            retry?.cancel()
            retry = scope.launch {
                delay(AttachmentStorage.retryDelayMillis(failures))
                runOnce()
            }
        } else {
            prefs.edit { putInt(FAILURES, 0) }
            _problem.value = null
        }
    }

    /** A token without asking the person (null when Google needs to ask them again). */
    private suspend fun silentToken(): String? = when (val access = requestAccess()) {
        is Access.Granted -> access.token
        else -> null
    }

    private fun access(result: AuthorizationResult): Access = when {
        result.hasResolution() -> result.pendingIntent?.let { Access.Ask(it) } ?: Access.Unavailable
        result.accessToken != null -> Access.Granted(result.accessToken!!)
        else -> Access.Unavailable
    }

    private fun request() = AuthorizationRequest.builder()
        .setRequestedScopes(listOf(Scope(DRIVE_APPDATA)))
        .build()

    private companion object {
        const val TAG = "AttachmentTransfers"
        const val DRIVE_APPDATA = "https://www.googleapis.com/auth/drive.appdata"
        const val ENABLED = "drive.enabled"
        const val FAILURES = "drive.failures"
        const val DELETIONS = "drive.deletions"
    }
}
