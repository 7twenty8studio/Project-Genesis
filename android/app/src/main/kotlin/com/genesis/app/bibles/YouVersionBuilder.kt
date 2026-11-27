package com.genesis.app.bibles

import android.content.Context
import android.util.Log
import com.genesis.app.bibles.BibleLibrary.BibleDownload
import com.genesis.core.bible.BibleRepository
import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.cloud.SupabaseError
import com.genesis.core.domain.bible.DownloadableBible
import com.genesis.core.domain.bible.InstalledBibleRecord
import com.genesis.core.domain.bible.YouVersionBible
import com.genesis.core.domain.bible.YouVersionBook
import com.genesis.core.domain.bible.YouVersionBuild
import com.genesis.core.domain.bible.YouVersionFreshness
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import kotlin.coroutines.coroutineContext
import kotlin.random.Random

/**
 * Builds a YouVersion Platform Bible on the phone, as YouVersionBibleBuilder
 * on iOS: fetched book by book through the yvp-bible function (which holds
 * the Platform key), waiting its turn when Versely's shared pace asks, kept
 * sealed (BibleProtection) and opened only into memory, so it reads offline
 * like any other Bible while its text never sits in a readable file. An
 * unfinished download keeps its books (sealed) for a week and carries on
 * where it stopped. The publishers allow these Bibles on a phone with their
 * conditions: every footnote shown, the text encrypted, a link to the
 * publisher (LICENSED_BIBLES.md › 5).
 */
internal class YouVersionBuilder(context: Context, private val client: SupabaseClient?, private val json: Json) {
    private val context = context.applicationContext
    private val _progress = MutableStateFlow<Map<String, Int>>(emptyMap())
    val progress: StateFlow<Map<String, Int>> = _progress.asStateFlow()
    private val indexLock = Mutex()
    private val indexSerializer = MapSerializer(String.serializer(), Long.serializer())

    private fun partsFolder(item: DownloadableBible, folder: File) = File(folder, "${item.id}-${item.version}-books")

    /** When each saved book was fetched, for those recent enough to use. */
    private fun savedDates(parts: File): Map<Int, Long> {
        val index = runCatching { json.decodeFromString(indexSerializer, File(parts, "index.json").readText()) }.getOrDefault(emptyMap())
        val now = System.currentTimeMillis()
        return index.mapNotNull { (key, saved) ->
            val number = key.toIntOrNull() ?: return@mapNotNull null
            if (now - saved < YouVersionBuild.SAVED_BOOK_LIFETIME_MS && File(parts, "$number.json").exists()) number to saved else null
        }.toMap()
    }

    fun savedBookCount(item: DownloadableBible, folder: File): Int = savedDates(partsFolder(item, folder)).size

    fun discard(item: DownloadableBible, folder: File) {
        partsFolder(item, folder).deleteRecursively()
        _progress.update { it - item.id }
    }

    /** Forgets everything kept beside a removed Bible. */
    fun forget(item: DownloadableBible, folder: File) {
        folder.listFiles()?.filter { it.name.startsWith("${item.id}-") && it.name.endsWith("-books") }?.forEach { it.deleteRecursively() }
        freshnessFile(item.id, folder).delete()
    }

    suspend fun build(item: DownloadableBible, destination: File) {
        val client = client ?: throw BibleDownload(BibleDownloadProblem.NOT_CONFIGURED)
        val folder = destination.parentFile ?: error("No folder")
        val parts = partsFolder(item, folder).apply { mkdirs() }
        try {
            val saved = savedDates(parts)
            val books = HashMap<Int, YouVersionBook>()
            val dates = HashMap<Int, Long>()
            for ((number, date) in saved) {
                val book = runCatching { json.decodeFromString(YouVersionBook.serializer(), BibleProtection.read(File(parts, "$number.json")).decodeToString()) }.getOrNull() ?: continue
                books[number] = book
                dates[number] = date
            }
            _progress.update { it + (item.id to books.size) }
            val missing = (1..YouVersionBuild.BOOK_CODES.size).filter { it !in books }.toMutableList()
            coroutineScope {
                // A few books at a time, each one function call reading every chapter.
                val workers = (0 until minOf(YouVersionBuild.PARALLEL_BOOKS, missing.size)).map {
                    async {
                        while (true) {
                            val number = synchronized(missing) { missing.removeFirstOrNull() } ?: break
                            val book = fetchBook(client, item.id, YouVersionBuild.BOOK_CODES[number - 1], number, parts)
                            val now = System.currentTimeMillis()
                            val count = synchronized(books) {
                                books[number] = book
                                dates[number] = now
                                books.size
                            }
                            // Noted one book at a time, so a stopped download knows what it has.
                            indexLock.withLock {
                                val index = synchronized(books) { dates.mapKeys { (key, _) -> key.toString() } }
                                runCatching { File(parts, "index.json").writeText(json.encodeToString(indexSerializer, index)) }
                            }
                            _progress.update { it + (item.id to count) }
                        }
                    }
                }
                workers.forEach { it.await() }
            }
            // Sealed in one step: the text never reaches the disk readable, and a half-built file is never opened.
            val whole = YouVersionBible(books.toMap())
            BibleProtection.write(json.encodeToString(YouVersionBible.serializer(), whole).encodeToByteArray(), destination)
            // Check it opens and holds a whole Bible.
            val verseCount = runCatching { BibleRepository.inMemory(whole.books, meta(item)).let { repository -> repository.verseCount().also { repository.release() } } }.getOrDefault(0)
            if (verseCount <= 30_000) {
                destination.delete()
                throw BibleDownload(BibleDownloadProblem.NOT_A_BIBLE)
            }
            // When each chapter must be fetched again if it's opened online.
            var freshness = YouVersionFreshness()
            for ((number, book) in books) {
                val fetched = dates[number] ?: System.currentTimeMillis()
                for (chapter in book.chapters) freshness = freshness.setting(number, chapter.chapter, fetched, chapter.maxAge)
            }
            saveFreshness(item.id, folder, freshness)
            parts.deleteRecursively()
        } finally {
            _progress.update { it - item.id }
        }
    }

    /** One book, tried up to three times, waiting its turn when the server's shared pace asks. */
    private suspend fun fetchBook(client: SupabaseClient, id: String, code: String, number: Int, parts: File): YouVersionBook {
        val body = buildJsonObject { put("id", id); put("book", code) }.toString()
        var attempt = 0
        var waited = 0.0
        while (true) {
            coroutineContext.ensureActive()
            attempt++
            val response = try {
                client.callFunctionWithStatus("yvp-bible", body, 90_000)
            } catch (error: SupabaseError.Timeout) {
                // Online, but the book kept taking too long: the source is busy.
                if (attempt < 3) {
                    delay(2_000L * attempt)
                    continue
                }
                throw BibleDownload(BibleDownloadProblem.BUSY)
            } catch (error: SupabaseError.Network) {
                throw BibleDownload(BibleDownloadProblem.OFFLINE)
            }
            when {
                response.status == 200 -> {
                    val book = runCatching { json.decodeFromString(YouVersionBook.serializer(), response.body) }.getOrNull()
                    if (book == null || book.chapters.isEmpty()) throw BibleDownload(BibleDownloadProblem.DAMAGED)
                    // Kept sealed until the Bible is built (licensed text).
                    runCatching { BibleProtection.write(response.body.encodeToByteArray(), File(parts, "$number.json")) }
                    return book
                }
                response.status == 429 -> {
                    // Waiting for a turn: the server paces every request to the Platform
                    // (shared by all readers) and says how long to wait.
                    val wait = YouVersionBuild.retryAfter(response.body)
                    waited += wait
                    if (wait > YouVersionBuild.LONGEST_WAIT_SECONDS || waited > YouVersionBuild.TOTAL_WAIT_SECONDS) throw BibleDownload(BibleDownloadProblem.BUSY)
                    attempt = 0
                    delay(((wait + Random.nextDouble(0.0, 2.0)) * 1000).toLong())
                }
                response.status in 500..599 && attempt < 3 -> delay(2_000L * attempt)
                // 404: the Bible left the catalog; anything else: try later.
                else -> throw BibleDownload(BibleDownloadProblem.DAMAGED)
            }
        }
    }

    /** The meta table a YouVersion Bible is built with (its abbreviation is its id, "NIrV"). */
    fun meta(item: DownloadableBible): Map<String, String> = buildMap {
        put("abbreviation", item.id)
        put("name", item.name)
        put("year", item.year)
        put("license", item.license)
        put("language", item.language)
        item.publisherUrl?.let { put("publisher_url", it) }
    }

    /** Opens a built Bible into memory. */
    fun open(record: InstalledBibleRecord, file: File): BibleRepository {
        val whole = json.decodeFromString(YouVersionBible.serializer(), BibleProtection.read(file).decodeToString())
        return BibleRepository.inMemory(whole.books, meta(record.bible))
    }

    /**
     * Fetches a chapter again if its lifetime has passed; when it changed,
     * `patch` puts it into the open Bible and the sealed copy is rewritten.
     */
    suspend fun refreshIfStale(record: InstalledBibleRecord, file: File, book: Int, chapter: Int, patch: (YouVersionBook.Chapter) -> Unit): Boolean {
        val client = client ?: return false
        val folder = file.parentFile ?: return false
        val freshness = loadFreshness(record.bible.id, folder)
        val now = System.currentTimeMillis()
        if (!freshness.isStale(book, chapter, now)) return false
        val code = YouVersionBuild.BOOK_CODES.getOrNull(book - 1) ?: return false
        val body = buildJsonObject { put("id", record.bible.id); put("book", code); put("chapter", chapter) }.toString()
        val response = client.callFunctionWithStatus("yvp-bible", body, 30_000)
        if (response.status != 200) return false
        val fresh = json.decodeFromString(YouVersionBook.serializer(), response.body).chapters.firstOrNull { it.chapter == chapter } ?: return false
        saveFreshness(record.bible.id, folder, freshness.setting(book, chapter, now, fresh.maxAge))
        val whole = json.decodeFromString(YouVersionBible.serializer(), BibleProtection.read(file).decodeToString())
        val stored = whole.books[book]?.chapters?.firstOrNull { it.chapter == chapter }
        if (stored != null && !YouVersionBuild.differs(stored, fresh)) return false
        patch(fresh)
        val bookNow = whole.books[book] ?: YouVersionBook(emptyList())
        val chapters = (bookNow.chapters.filter { it.chapter != chapter } + fresh).sortedBy { it.chapter }
        val updated = YouVersionBible(whole.books + (book to YouVersionBook(chapters)))
        BibleProtection.write(json.encodeToString(YouVersionBible.serializer(), updated).encodeToByteArray(), file)
        Log.i(TAG, "Refreshed ${record.bible.id} $book:$chapter")
        return true
    }

    /** Counts a finished download anonymously, for the publishers' yearly reports; failures are ignored. */
    fun recordDownload(item: DownloadableBible) {
        val client = client ?: return
        runCatching { client.rpc("record_youversion_download", buildJsonObject { put("p_bible", item.id) }.toString(), null) }
    }

    private fun freshnessFile(id: String, folder: File) = File(folder, "$id.freshness.json")

    private fun loadFreshness(id: String, folder: File): YouVersionFreshness =
        runCatching { json.decodeFromString(YouVersionFreshness.serializer(), freshnessFile(id, folder).readText()) }.getOrDefault(YouVersionFreshness())

    private fun saveFreshness(id: String, folder: File, value: YouVersionFreshness) {
        runCatching { freshnessFile(id, folder).writeText(json.encodeToString(YouVersionFreshness.serializer(), value)) }
    }

    private companion object {
        const val TAG = "YouVersion"
    }
}
