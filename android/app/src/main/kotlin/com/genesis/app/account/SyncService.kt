package com.genesis.app.account

import android.content.Context
import android.util.Log
import androidx.core.content.edit
import com.genesis.core.cloud.RemoteBookmark
import com.genesis.core.cloud.RemoteHighlight
import com.genesis.core.cloud.RemoteNote
import com.genesis.core.cloud.RemotePlan
import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.cloud.SupabaseError
import com.genesis.core.cloud.SyncTable
import com.genesis.core.cloud.Timestamps
import com.genesis.core.data.BookmarkRecord
import com.genesis.core.data.HighlightRecord
import com.genesis.core.data.NoteRecord
import com.genesis.core.data.PlanRecord
import com.genesis.core.domain.plans.PlanEnrollment
import java.time.LocalDate
import com.genesis.core.data.UserDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

data class SyncState(
    val isSyncing: Boolean = false,
    val lastSyncedAt: Long? = null,
    /** Why the last sync failed, in words for the person. */
    val failure: AccountMessage? = null,
)

/**
 * Keeps highlights, notes and bookmarks in step with the person's account,
 * as SyncService on iOS (the same tables, columns and rules, so the iPhone
 * and Android share them): pull server changes first (newest edit wins per
 * record), then push local edits and deletions. Everything works offline;
 * sync catches up the next time it runs (on opening the app, after an
 * edit, after signing in, or Sync Now).
 */
class SyncService(
    context: Context,
    private val database: UserDatabase,
    private val account: AccountService,
    private val scope: CoroutineScope,
) {
    private val prefs = context.getSharedPreferences("sync", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true; explicitNulls = true }
    private val running = Mutex()
    private var scheduled: Job? = null

    private val _state = MutableStateFlow(SyncState(lastSyncedAt = account.state.value.user?.let { prefs.longOrNull(key("lastSyncedAt", it.id)) }))
    val state: StateFlow<SyncState> = _state.asStateFlow()

    /** Follows sign-ins and the person's edits. Call once. */
    @OptIn(FlowPreview::class)
    fun start() {
        scope.launch {
            account.state.map { it.user?.id }.distinctUntilChanged().collect { userId ->
                if (userId == null) {
                    scheduled?.cancel()
                    _state.value = SyncState()
                } else {
                    didSignIn(userId)
                }
            }
        }
        scope.launch {
            // A burst of edits becomes one sync, a few seconds after the last.
            database.localEdits.drop(1).collect { schedule(delayMillis = 3_000) }
        }
    }

    fun schedule(delayMillis: Long = 0) {
        if (account.state.value.user == null || account.client == null) return
        scheduled?.cancel()
        scheduled = scope.launch {
            if (delayMillis > 0) delay(delayMillis)
            syncNow()
        }
    }

    suspend fun syncNow() {
        val user = account.state.value.user ?: return
        val client = account.client ?: return
        running.withLock {
            _state.update { it.copy(isSyncing = true, failure = null) }
            try {
                val token = account.accessToken()
                withContext(Dispatchers.IO) { sync(user.id, client, token) }
                val now = System.currentTimeMillis()
                prefs.edit { putLong(key("lastSyncedAt", user.id), now) }
                _state.update { it.copy(isSyncing = false, lastSyncedAt = now) }
            } catch (error: SupabaseError) {
                Log.w(TAG, "Sync failed", error)
                _state.update { it.copy(isSyncing = false, failure = failure(error)) }
            } catch (error: Exception) {
                Log.e(TAG, "Sync failed", error)
                _state.update { it.copy(isSyncing = false, failure = AccountMessage(com.genesis.app.R.string.unexpected_response, isError = true)) }
            }
        }
    }

    /**
     * Someone signed in. Guest data joins their account; data left by a
     * *different* account is removed from this device first so it can't
     * leak across (as iOS does).
     */
    private fun didSignIn(userId: String) {
        val owner = prefs.getString(OWNER, null)
        if (owner != null && owner != userId) eraseDevice()
        prefs.edit { putString(OWNER, userId) }
        _state.update { SyncState(lastSyncedAt = prefs.longOrNull(key("lastSyncedAt", userId))) }
        schedule()
    }

    /**
     * Signs out, as AccountView on iOS: the data stays in the account either
     * way; on this device it stays (and joins whoever signs in next, unless
     * that's another account) or is removed.
     */
    suspend fun signOut(removeLocalData: Boolean) {
        scheduled?.cancel()
        running.withLock {
            account.signOut()
            if (removeLocalData) withContext(Dispatchers.IO) { eraseDevice() }
        }
    }

    /** Deletes the account; this device's copy of its data goes too. */
    suspend fun deleteAccount(): Boolean {
        scheduled?.cancel()
        return running.withLock {
            account.deleteAccount().also { deleted -> if (deleted) withContext(Dispatchers.IO) { eraseDevice() } }
        }
    }

    /** Removes the synced data and every cursor, so the next sync starts from scratch. */
    private fun eraseDevice() {
        database.sync.eraseAll()
        prefs.edit { clear() }
    }

    private fun sync(userId: String, client: SupabaseClient, token: String) {
        val pushStartedAt = System.currentTimeMillis()

        pull(SyncTable.HIGHLIGHTS, RemoteHighlight.serializer(), client, token, userId) { rows ->
            database.sync.applyHighlights(rows.mapNotNull { it.record() })
        }
        pull(SyncTable.BOOKMARKS, RemoteBookmark.serializer(), client, token, userId) { rows ->
            database.sync.applyBookmarks(rows.mapNotNull { it.record() })
        }
        pull(SyncTable.NOTES, RemoteNote.serializer(), client, token, userId, pageSize = 50) { rows ->
            database.sync.applyNotes(rows.mapNotNull { it.record() })
        }

        pull(SyncTable.READING_PLANS, RemotePlan.serializer(), client, token, userId) { rows ->
            database.sync.applyPlans(rows.mapNotNull { it.record() })
        }

        // Everything edited since the last successful push, deletions included.
        val since = prefs.getLong(key("lastPushedAt", userId), 0)
        push(SyncTable.HIGHLIGHTS, RemoteHighlight.serializer(), database.sync.highlightsChanged(since).map { it.remote(userId) }, client, token)
        push(SyncTable.BOOKMARKS, RemoteBookmark.serializer(), database.sync.bookmarksChanged(since).map { it.remote(userId) }, client, token)
        push(SyncTable.NOTES, RemoteNote.serializer(), database.sync.notesChanged(since).map { it.remote(userId) }, client, token, batch = 50)
        push(SyncTable.READING_PLANS, RemotePlan.serializer(), database.sync.plansChanged(since).map { it.remote(userId) }, client, token)
        for ((table, ids) in database.sync.pendingDeletions()) {
            client.markDeleted(table, ids, System.currentTimeMillis(), token)
            database.sync.clearPendingDeletions(table, ids)
        }
        prefs.edit { putLong(key("lastPushedAt", userId), pushStartedAt) }
    }

    private fun <Row> pull(
        table: String,
        serializer: KSerializer<Row>,
        client: SupabaseClient,
        token: String,
        userId: String,
        pageSize: Int = 500,
        apply: (List<Row>) -> Unit,
    ) where Row : Any {
        val cursorKey = key("cursor.$table", userId)
        var cursor = prefs.getString(cursorKey, null)
        while (true) {
            val body = client.changes(table, cursor, pageSize, token)
            val objects = json.parseToJsonElement(body.ifEmpty { "[]" }) as? JsonArray ?: throw SupabaseError.InvalidResponse()
            val rows = json.decodeFromJsonElement(ListSerializer(serializer), objects)
            apply(rows)
            val last = (objects.lastOrNull() as? JsonObject)?.get("server_updated_at")?.let { (it as? kotlinx.serialization.json.JsonPrimitive)?.content }
            if (last != null) {
                cursor = last
                prefs.edit { putString(cursorKey, last) }
            }
            if (rows.size < pageSize) break
        }
    }

    /** Upserts in batches; every row has the same columns, and server_updated_at is the server's to set. */
    private fun <Row> push(table: String, serializer: KSerializer<Row>, rows: List<Row>, client: SupabaseClient, token: String, batch: Int = 200) {
        for (chunk in rows.chunked(batch)) {
            val array = JsonArray(chunk.map { row -> JsonObject(json.encodeToJsonElement(serializer, row).jsonObject - "server_updated_at") })
            client.upsert(table, array.toString(), token)
        }
    }

    private fun failure(error: SupabaseError) = when (error) {
        is SupabaseError.Network -> AccountMessage(com.genesis.app.R.string.server_unreachable, isError = true)
        is SupabaseError.Http -> AccountMessage(text = error.message, isError = true)
        else -> AccountMessage(com.genesis.app.R.string.unexpected_response, isError = true)
    }

    private fun key(name: String, userId: String) = "$name.$userId"

    private fun android.content.SharedPreferences.longOrNull(key: String): Long? = if (contains(key)) getLong(key, 0) else null

    private companion object {
        const val TAG = "Sync"
        const val OWNER = "localDataOwner"
    }
}

// Converting between the device's records and the server's rows. Ids are
// compared in lower case (Postgres writes uuids that way; iOS sends upper).

private fun millis(text: String?): Long? = text?.let(Timestamps::millis)

private fun RemoteHighlight.record(): HighlightRecord? {
    val updated = millis(updatedAt) ?: return null
    return HighlightRecord(id.lowercase(), verse, color, millis(createdAt) ?: updated, updated, millis(deletedAt))
}

private fun RemoteBookmark.record(): BookmarkRecord? {
    val updated = millis(updatedAt) ?: return null
    return BookmarkRecord(id.lowercase(), verse, millis(createdAt) ?: updated, updated, millis(deletedAt))
}

private fun RemoteNote.record(): NoteRecord? {
    val updated = millis(updatedAt) ?: return null
    return NoteRecord(
        id.lowercase(), title, body, kind, anchorType, startVerse, endVerse, book, chapter, theme,
        millis(createdAt) ?: updated, updated, millis(deletedAt),
    )
}

private fun HighlightRecord.remote(userId: String) = RemoteHighlight(
    id, userId, verse, color, Timestamps.string(createdAt), Timestamps.string(updatedAt), deletedAt?.let(Timestamps::string),
)

private fun BookmarkRecord.remote(userId: String) = RemoteBookmark(
    id, userId, verse, Timestamps.string(createdAt), Timestamps.string(updatedAt), deletedAt?.let(Timestamps::string),
)

private fun NoteRecord.remote(userId: String) = RemoteNote(
    id, userId, title, body, kind, anchorType, startVerse, endVerse, book, chapter, theme,
    Timestamps.string(createdAt), Timestamps.string(updatedAt), deletedAt?.let(Timestamps::string),
)

private fun RemotePlan.record(): PlanRecord? {
    val updated = millis(updatedAt) ?: return null
    val start = runCatching { LocalDate.parse(startDate.take(10)) }.getOrNull() ?: return null
    return PlanRecord(
        PlanEnrollment(
            id = id.lowercase(),
            planId = planId,
            title = title,
            startDate = start,
            completedDays = completedDays.toSet(),
            customBooks = customBooks,
            customDays = customDays,
            isActive = isActive,
            createdAt = millis(createdAt) ?: updated,
            updatedAt = updated,
        ),
        millis(deletedAt),
    )
}

private fun PlanRecord.remote(userId: String) = RemotePlan(
    id = enrollment.id,
    userId = userId,
    planId = enrollment.planId,
    title = enrollment.title,
    startDate = enrollment.startDate.toString(),
    completedDays = enrollment.completedDays.sorted(),
    customBooks = enrollment.customBooks,
    customDays = enrollment.customDays,
    isActive = enrollment.isActive,
    createdAt = Timestamps.string(enrollment.createdAt),
    updatedAt = Timestamps.string(enrollment.updatedAt),
    deletedAt = deletedAt?.let(Timestamps::string),
)
