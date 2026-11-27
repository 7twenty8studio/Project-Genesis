package com.genesis.app.account

import android.content.Context
import android.util.Log
import androidx.core.content.edit
import com.genesis.core.cloud.RemoteBookmark
import com.genesis.core.cloud.RemoteHighlight
import com.genesis.core.cloud.RemoteNote
import com.genesis.core.cloud.RemotePlan
import com.genesis.core.cloud.RemoteMemoryVerse
import com.genesis.core.cloud.RemoteSermon
import com.genesis.core.cloud.RemoteSermonPush
import com.genesis.core.cloud.RemotePrayer
import com.genesis.core.cloud.RemotePrayerPassage
import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.cloud.SupabaseError
import com.genesis.core.cloud.SyncTable
import com.genesis.core.cloud.Timestamps
import com.genesis.core.data.BookmarkRecord
import com.genesis.core.data.HighlightRecord
import com.genesis.core.data.NoteRecord
import com.genesis.core.data.PlanRecord
import com.genesis.core.data.MemoryRecord
import com.genesis.core.data.SermonRecord
import com.genesis.core.data.PrayerRecord
import com.genesis.core.domain.prayer.Prayer
import com.genesis.core.domain.prayer.PrayerCategory
import com.genesis.core.domain.prayer.PrayerPassage
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
    private val context: Context,
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
                (context.applicationContext as? com.genesis.app.VerselyApplication)?.attachmentTransfers?.kick()
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
        // The group widget shows other people's names: it goes with the account.
        com.genesis.app.widget.GroupWidgetStore.clear(context)
    }

    /** Deletes the account; this device's copy of its data goes too. */
    suspend fun deleteAccount(): Boolean {
        scheduled?.cancel()
        return running.withLock {
            account.deleteAccount().also { deleted ->
                if (deleted) {
                    // The files in the person's Drive go with the account, as the iCloud zone does on iOS.
                    (context.applicationContext as? com.genesis.app.VerselyApplication)?.attachmentTransfers?.deleteEverything()
                    withContext(Dispatchers.IO) { eraseDevice() }
                }
            }
        }.also { if (it) com.genesis.app.widget.GroupWidgetStore.clear(context) }
    }

    /** Removes the synced data and every cursor, so the next sync starts from scratch. */
    private fun eraseDevice() {
        database.sync.eraseAll()
        com.genesis.app.journal.AttachmentFiles.folder(context).deleteRecursively()
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
        pull(SyncTable.PRAYERS, RemotePrayer.serializer(), client, token, userId, pageSize = 200) { rows ->
            database.sync.applyPrayers(rows.mapNotNull { row -> row.record()?.let { it to (row.passages == null) } })
        }
        pull(SyncTable.MEMORY_VERSES, RemoteMemoryVerse.serializer(), client, token, userId) { rows ->
            database.sync.applyMemory(rows.mapNotNull { it.record() })
        }
        pull(SyncTable.SERMONS, RemoteSermon.serializer(), client, token, userId, pageSize = 50) { rows ->
            database.sync.applySermons(rows.mapNotNull { it.record() })
        }
        pull(SyncTable.ATTACHMENTS, com.genesis.core.cloud.RemoteAttachment.serializer(), client, token, userId) { rows ->
            val removed = database.sync.applyAttachments(rows.mapNotNull { it.record() })
            com.genesis.app.journal.AttachmentFiles.remove(context, removed)
        }

        // Everything edited since the last successful push, deletions included.
        val since = prefs.getLong(key("lastPushedAt", userId), 0)
        push(SyncTable.HIGHLIGHTS, RemoteHighlight.serializer(), database.sync.highlightsChanged(since).map { it.remote(userId) }, client, token)
        push(SyncTable.BOOKMARKS, RemoteBookmark.serializer(), database.sync.bookmarksChanged(since).map { it.remote(userId) }, client, token)
        push(SyncTable.NOTES, RemoteNote.serializer(), database.sync.notesChanged(since).map { it.remote(userId) }, client, token, batch = 50)
        push(SyncTable.READING_PLANS, RemotePlan.serializer(), database.sync.plansChanged(since).map { it.remote(userId) }, client, token)
        push(SyncTable.PRAYERS, RemotePrayer.serializer(), database.sync.prayersChanged(since).map { it.remote(userId) }, client, token)
        push(SyncTable.MEMORY_VERSES, RemoteMemoryVerse.serializer(), database.sync.memoryChanged(since).map { it.remote(userId) }, client, token)
        // Sermons: the church sermon link and saved handouts are sent only when
        // set, each key set in its own request (every row in a request has the same keys).
        database.sync.sermonsChanged(since).map { it.remoteJson(userId) }.groupBy { it.keys }.values.forEach { rows ->
            for (chunk in rows.chunked(50)) client.upsert(SyncTable.SERMONS, JsonArray(chunk).toString(), token)
        }
        // Attachments whose file is in the person's Drive (or came from another device), within the server's limits.
        push(
            SyncTable.ATTACHMENTS,
            com.genesis.core.cloud.RemoteAttachment.serializer(),
            database.sync.attachmentsChanged(since).filter { com.genesis.core.domain.journal.AttachmentStorage.syncs(it.attachment) }.mapNotNull { it.remote(userId) },
            client,
            token,
        )
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

private fun RemotePrayer.record(): PrayerRecord? {
    val updated = millis(updatedAt) ?: return null
    return PrayerRecord(
        Prayer(
            id = id.lowercase(),
            title = title,
            body = body,
            category = PrayerCategory.lenient(category),
            isAnswered = isAnswered,
            answeredAt = millis(answeredAt),
            answerNote = answerNote,
            reminderAt = millis(reminderAt),
            reminderRepeatsDaily = reminderRepeatsDaily,
            passages = PrayerPassage.decode(passages.orEmpty().map { it.startVerse to it.endVerse }),
            lastPrayedAt = millis(lastPrayedAt),
            createdAt = millis(createdAt) ?: updated,
            updatedAt = updated,
        ),
        millis(deletedAt),
    )
}

private fun PrayerRecord.remote(userId: String) = RemotePrayer(
    id = prayer.id,
    userId = userId,
    title = prayer.title,
    body = prayer.body,
    category = prayer.category.id,
    isAnswered = prayer.isAnswered,
    answeredAt = prayer.answeredAt?.let(Timestamps::string),
    answerNote = prayer.answerNote,
    reminderAt = prayer.reminderAt?.let(Timestamps::string),
    reminderRepeatsDaily = prayer.reminderRepeatsDaily,
    passages = prayer.passages.map { RemotePrayerPassage(it.start.rawValue, it.end.rawValue) },
    lastPrayedAt = prayer.lastPrayedAt?.let(Timestamps::string),
    createdAt = Timestamps.string(prayer.createdAt),
    updatedAt = Timestamps.string(prayer.updatedAt),
    deletedAt = deletedAt?.let(Timestamps::string),
)

private fun RemoteMemoryVerse.record(): MemoryRecord? {
    val updated = millis(updatedAt) ?: return null
    val due = millis(dueAt) ?: return null
    return MemoryRecord(
        com.genesis.core.domain.memorise.MemoryVerse(
            id = id.lowercase(),
            start = com.genesis.core.domain.bible.VerseId(startVerse),
            end = com.genesis.core.domain.bible.VerseId(maxOf(endVerse, startVerse)),
            translationId = translationId,
            schedule = com.genesis.core.domain.memorise.MemorySchedule(ease, intervalDays, repetitions, due),
            lastReviewedAt = millis(lastReviewedAt),
            reviewCount = reviewCount,
            createdAt = millis(createdAt) ?: updated,
            updatedAt = updated,
        ),
        millis(deletedAt),
    )
}

private fun MemoryRecord.remote(userId: String) = RemoteMemoryVerse(
    id = verse.id,
    userId = userId,
    startVerse = verse.start.rawValue,
    endVerse = verse.end.rawValue,
    translationId = verse.translationId,
    ease = verse.schedule.ease,
    intervalDays = verse.schedule.intervalDays,
    repetitions = verse.schedule.repetitions,
    dueAt = Timestamps.string(verse.schedule.dueAt),
    lastReviewedAt = verse.lastReviewedAt?.let(Timestamps::string),
    reviewCount = verse.reviewCount,
    createdAt = Timestamps.string(verse.createdAt),
    updatedAt = Timestamps.string(verse.updatedAt),
    deletedAt = deletedAt?.let(Timestamps::string),
)

private fun RemoteSermon.record(): SermonRecord? {
    val updated = millis(updatedAt) ?: return null
    val created = millis(createdAt) ?: updated
    return SermonRecord(
        com.genesis.core.domain.sermons.Sermon(
            id = id.lowercase(),
            title = title,
            preacher = preacher,
            church = church,
            preachedAt = millis(preachedAt) ?: created,
            series = series,
            body = body,
            passages = PrayerPassage.decode(passages.map { it.startVerse to it.endVerse }),
            isFavourite = isFavourite,
            sourceSermonId = sourceSermonId,
            handoutsJson = handouts?.takeIf { it !is kotlinx.serialization.json.JsonNull }?.toString(),
            createdAt = created,
            updatedAt = updated,
        ),
        millis(deletedAt),
    )
}

private fun SermonRecord.remoteJson(userId: String): JsonObject {
    val row = syncJson.encodeToJsonElement(RemoteSermonPush.serializer(), remote(userId)).jsonObject.toMutableMap()
    sermon.sourceSermonId?.let { row["source_sermon_id"] = kotlinx.serialization.json.JsonPrimitive(it) }
    sermon.handoutsJson?.let { raw -> runCatching { syncJson.parseToJsonElement(raw) }.getOrNull() }
        ?.takeIf { it is JsonArray && it.isNotEmpty() }?.let { row["handouts"] = it }
    return JsonObject(row)
}

private val syncJson = kotlinx.serialization.json.Json { encodeDefaults = true; explicitNulls = true; ignoreUnknownKeys = true }

private fun SermonRecord.remote(userId: String) = RemoteSermonPush(
    id = sermon.id,
    userId = userId,
    title = sermon.title.take(200),
    preacher = sermon.preacher.take(120),
    church = sermon.church.take(120),
    preachedAt = Timestamps.string(sermon.preachedAt),
    series = sermon.series?.trim()?.ifEmpty { null }?.take(120),
    body = sermon.body.take(100_000),
    passages = sermon.passages.map { RemotePrayerPassage(it.start.rawValue, it.end.rawValue) },
    isFavourite = sermon.isFavourite,
    createdAt = Timestamps.string(sermon.createdAt),
    updatedAt = Timestamps.string(sermon.updatedAt),
    deletedAt = deletedAt?.let(Timestamps::string),
)

private fun com.genesis.core.cloud.RemoteAttachment.record(): com.genesis.core.data.AttachmentRecord? {
    val owner = com.genesis.core.domain.journal.AttachmentOwner.of(ownerKind) ?: return null
    val kind = com.genesis.core.domain.journal.AttachmentKind.of(kind) ?: return null
    return com.genesis.core.data.AttachmentRecord(
        com.genesis.core.domain.journal.Attachment(
            id = id.lowercase(),
            owner = owner,
            ownerId = ownerId.lowercase(),
            kind = kind,
            byteSize = bytes,
            durationSeconds = durationSeconds,
            pageCount = pageCount,
            caption = caption.ifEmpty { null },
            sortOrder = sortOrder,
            createdAt = Timestamps.millis(createdAt) ?: return null,
            updatedAt = Timestamps.millis(updatedAt) ?: return null,
            storagePath = storagePath,
        ),
        deletedAt?.let(Timestamps::millis),
    )
}

private fun com.genesis.core.data.AttachmentRecord.remote(userId: String): com.genesis.core.cloud.RemoteAttachment? {
    val path = attachment.storagePath ?: return null
    return com.genesis.core.cloud.RemoteAttachment(
        id = attachment.id,
        userId = userId,
        ownerKind = attachment.owner.id,
        ownerId = attachment.ownerId,
        kind = attachment.kind.id,
        storagePath = path.take(200),
        bytes = attachment.byteSize,
        durationSeconds = attachment.durationSeconds,
        pageCount = attachment.pageCount,
        caption = attachment.caption.orEmpty().take(500),
        sortOrder = attachment.sortOrder,
        createdAt = Timestamps.string(attachment.createdAt),
        updatedAt = Timestamps.string(attachment.updatedAt),
        deletedAt = deletedAt?.let(Timestamps::string),
    )
}
