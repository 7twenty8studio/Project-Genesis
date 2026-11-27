package com.genesis.app.bibles

import android.content.Context
import android.net.ConnectivityManager
import android.util.Log
import com.genesis.core.bible.BibleRepository
import com.genesis.core.bible.BundledBible
import com.genesis.core.bible.InstalledBible
import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.cloud.SupabaseError
import com.genesis.core.domain.bible.DownloadableBible
import com.genesis.core.domain.bible.InstalledBibleRecord
import com.genesis.core.domain.bible.YouVersionBuild
import com.genesis.core.domain.studyresources.PackedFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI
import java.util.Locale

/** Why a Bible didn't download, shown on the Bibles screen. */
enum class BibleDownloadProblem { NOT_CONFIGURED, OFFLINE, DAMAGED, NOT_A_BIBLE, NEEDS_PREMIUM, BUSY }

/**
 * The Bibles on this phone and those offered, as BibleLibrary on iOS: the
 * bundled ones (KJV, WEB, ASV, Bíblia Livre) and downloads from
 * public.bible_translations, kept in no-backup storage (they can always be
 * fetched again). A download whose row leaves the catalog is removed; a
 * newer edition replaces it on Wi-Fi. Every Bible Versely offers free is
 * free; only a Premium row needs Premium.
 */
class BibleLibrary(context: Context, private val client: SupabaseClient?, private val scope: kotlinx.coroutines.CoroutineScope) {
    private val context = context.applicationContext
    private val directory = File(this.context.noBackupFilesDir, "Bibles")
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }

    private val _catalog = MutableStateFlow<List<DownloadableBible>>(emptyList())
    /** Everything offered for download, from the server (empty until fetched, or offline). */
    val catalog: StateFlow<List<DownloadableBible>> = _catalog.asStateFlow()

    /** True once the catalog has loaded this session. */
    private val _catalogLoaded = MutableStateFlow(false)
    val catalogLoaded: StateFlow<Boolean> = _catalogLoaded.asStateFlow()

    private val _downloads = MutableStateFlow(loadInstalled())
    /** Bibles downloaded on this phone, by id. */
    val downloads: StateFlow<Map<String, InstalledBibleRecord>> = _downloads.asStateFlow()

    private val _downloading = MutableStateFlow<Set<String>>(emptySet())
    val downloading: StateFlow<Set<String>> = _downloading.asStateFlow()

    private val _problem = MutableStateFlow<BibleDownloadProblem?>(null)
    val problem: StateFlow<BibleDownloadProblem?> = _problem.asStateFlow()

    init {
        removeLeftovers()
        com.genesis.core.bible.SealedBibles.opener = ::openSealed
    }

    /** Every Bible on the phone: the bundled ones, then downloads (a download never replaces a bundled id). */
    fun installed(downloads: Map<String, InstalledBibleRecord> = _downloads.value): List<InstalledBible> =
        BundledBible.entries.map { InstalledBible.of(it) } +
            downloads.values.filter { record -> BundledBible.entries.none { it.id == record.bible.id } }
                .sortedBy { it.bible.name }
                .map { InstalledBible(it.bible.id, file = File(directory, it.fileName), sealed = it.bible.isYouVersion) }

    /** The Bible with this id, if it's on the phone. */
    fun resolve(id: String?): InstalledBible? = id?.let { wanted -> installed().firstOrNull { it.id == wanted } }

    /**
     * The Bible Premium tools (Memorize and its widget, word study, the map's
     * verses) read with `bible`: itself, or for a YouVersion Bible, which no
     * Premium feature shows, a free Bible in its language (the Reina-Valera,
     * the Bíblia Livre, O Livro's pt-PT included), else the KJV.
     */
    fun premiumToolsBible(bible: InstalledBible): InstalledBible {
        if (!bible.sealed) return bible
        val language = _downloads.value[bible.id]?.bible?.baseLanguage
        if (language == "pt") return InstalledBible.of(BundledBible.BLIVRE)
        val free = _downloads.value.values.firstOrNull { !it.bible.isYouVersion && it.bible.rights == "public_domain" && it.bible.baseLanguage == language }
        return free?.let { resolve(it.bible.id) } ?: InstalledBible.of(BundledBible.KJV)
    }

    /** The first Bible on a new phone: the Bíblia Livre in Portuguese, else the KJV. */
    fun default(language: String = Locale.getDefault().language): InstalledBible = InstalledBible.of(BundledBible.default(language))

    /** The Bible the person reads, or the default when it's gone (removed, or left the catalog). */
    fun current(savedId: String?): InstalledBible = resolve(savedId) ?: default()

    fun clearProblem() { _problem.value = null }

    /** Fetches the catalog, removes downloads it no longer lists, and updates old editions on Wi-Fi. */
    suspend fun refreshCatalog() {
        val client = client ?: return
        val items = withContext(Dispatchers.IO) {
            runCatching {
                val files = rows(client.select("bible_translations", listOf("select" to "*", "enabled" to "eq.true", "order" to "sort.asc,name.asc"), null))
                    .filter { !it.isYouVersion }
                // Both lists or neither, so a half-loaded catalog never looks like a Bible was withdrawn.
                val youVersion = rows(
                    client.select(
                        "youversion_bibles",
                        listOf(
                            "select" to "id,yvp_id,name,year,license,summary,language,approach,reading_level,popularity,version,publisher_url",
                            "enabled" to "eq.true",
                            "order" to "sort.asc,name.asc",
                        ),
                        null,
                    ),
                ).map { it.copy(rights = "licensed", premium = false, publisherUrl = it.publisherUrl?.takeIf { url -> url.startsWith("https://") }) }
                val fileIds = files.map { it.id }.toSet()
                files + youVersion.filter { it.id !in fileIds }
            }.onFailure { Log.w(TAG, "Couldn't fetch the Bible catalog", it) }.getOrNull()
        } ?: return
        // Bundled Bibles aren't offered again.
        _catalog.value = items.filter { item -> BundledBible.entries.none { it.id == item.id } }
        _catalogLoaded.value = true
        val listed = items.associateBy { it.id }
        val unmetered = !isMetered()
        for ((id, record) in _downloads.value) {
            val item = listed[id]
            when {
                // Only a whole, loaded catalog removes a Bible (licensed text must go when its row does).
                item == null -> remove(id)
                item.version > record.bible.version && unmetered -> runCatching { install(item) }
                item.isYouVersion && (record.format ?: 0) < YouVersionBuild.FORMAT && unmetered -> runCatching { install(item) }
            }
        }
    }

    /** Rows this version can't read are left out, never the whole list. */
    private fun rows(body: String): List<DownloadableBible> =
        (json.parseToJsonElement(body) as JsonArray).mapNotNull { row ->
            runCatching { json.decodeFromJsonElement(DownloadableBible.serializer(), row) }.getOrNull()
        }

    private val jobs = HashMap<String, kotlinx.coroutines.Job>()

    /**
     * Starts a download that keeps going while the person reads elsewhere or
     * leaves Versely (BibleDownloadService); a YouVersion Bible keeps the
     * books it has if it stops, and carries on from there.
     */
    fun start(item: DownloadableBible, hasPremium: Boolean) {
        _problem.value = null
        if (item.premium && !hasPremium) {
            _problem.value = BibleDownloadProblem.NEEDS_PREMIUM
            return
        }
        if (item.isYouVersion) BibleDownloadService.start(context)
        val job = scope.launch {
            try {
                install(item)
            } catch (error: BibleDownload) {
                _problem.value = error.problem
            } catch (error: kotlinx.coroutines.CancellationException) {
                throw error
            } catch (error: Exception) {
                Log.w(TAG, "Couldn't download ${item.id}", error)
                _problem.value = BibleDownloadProblem.DAMAGED
            } finally {
                synchronized(jobs) { jobs.remove(item.id) }
            }
        }
        synchronized(jobs) { jobs[item.id] = job }
    }

    /** Pauses one download; a YouVersion Bible keeps the books it has and Continue carries on from there. */
    fun pause(id: String) {
        synchronized(jobs) { jobs[id] }?.cancel()
    }

    /** Stops every download; YouVersion books fetched so far are kept. */
    fun pauseAll() {
        synchronized(jobs) { jobs.values.toList() }.forEach { it.cancel() }
    }

    internal class BibleDownload(val problem: BibleDownloadProblem) : Exception(problem.name)

    internal val youVersion = YouVersionBuilder(context, client, json)

    /** How many of the 66 books each YouVersion download has in hand. */
    val bookProgress: StateFlow<Map<String, Int>> get() = youVersion.progress

    /** Books an unfinished YouVersion download already saved (0 when none). */
    fun savedBookCount(item: DownloadableBible): Int = youVersion.savedBookCount(item, directory)

    /** Forgets an unfinished YouVersion download. */
    fun discard(item: DownloadableBible) = youVersion.discard(item, directory)

    /** The free Bible in the same language a YouVersion one needs beside it, when it isn't on the phone. */
    private fun companionBible(item: DownloadableBible): DownloadableBible? {
        val language = item.baseLanguage
        // English and Portuguese have one in the app (the KJV, the Bíblia Livre).
        if (language == "en" || language == "pt") return null
        if (_downloads.value.values.any { !it.bible.isYouVersion && it.bible.baseLanguage == language && it.bible.rights == "public_domain" }) return null
        return _catalog.value.firstOrNull { !it.isYouVersion && !it.premium && it.rights == "public_domain" && it.baseLanguage == language }
    }

    private val sealedOpen = HashMap<String, BibleRepository>()

    /** A YouVersion Bible, opened into memory once for the process (it's sealed on disk). */
    fun openSealed(bible: InstalledBible): BibleRepository = synchronized(sealedOpen) {
        sealedOpen[bible.id]?.let { return it }
        val record = _downloads.value[bible.id] ?: error("${bible.id} isn't on this phone")
        val repository = youVersion.open(record, File(directory, record.fileName))
        sealedOpen[bible.id] = repository
        repository
    }

    private fun releaseSealed(id: String) = synchronized(sealedOpen) { sealedOpen.remove(id)?.release() }

    /**
     * Fetches a YouVersion chapter again when it's opened online after the
     * Platform's Cache-Control lifetime, and patches it in when it changed.
     * True when the chapter changed (the reader reloads it).
     */
    suspend fun refreshIfStale(bible: InstalledBible, book: Int, chapter: Int): Boolean {
        if (!bible.sealed || !isOnline()) return false
        val record = _downloads.value[bible.id] ?: return false
        return withContext(Dispatchers.IO) {
            runCatching { youVersion.refreshIfStale(record, File(directory, record.fileName), book, chapter) { fresh -> openSealed(bible).replaceChapter(book, fresh) } }
                .onFailure { Log.w(TAG, "Couldn't refresh ${bible.id} $book:$chapter", it) }
                .getOrDefault(false)
        }
    }

    private fun isOnline(): Boolean =
        (context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).activeNetwork != null

    private suspend fun install(item: DownloadableBible) {
        if (item.id in _downloading.value) return
        _downloading.update { it + item.id }
        try {
            if (item.isYouVersion) {
                val fileName = "${item.id}-${item.version}.sealed"
                withContext(Dispatchers.IO) { youVersion.build(item, File(directory, fileName)) }
                releaseSealed(item.id)
                _downloads.update { it + (item.id to InstalledBibleRecord(item, fileName, System.currentTimeMillis(), YouVersionBuild.FORMAT)) }
                saveInstalled()
                withContext(Dispatchers.IO) { youVersion.recordDownload(item) }
                // Premium tools read a free Bible in the same language beside it (the Reina-Valera for a Spanish one).
                companionBible(item)?.let { runCatching { install(it) } }
            } else {
                // A new file per edition: the old one may still be open for reading.
                val fileName = "${item.id}-${item.version}.sqlite"
                withContext(Dispatchers.IO) { fetch(item, File(directory, fileName)) }
                _downloads.update { it + (item.id to InstalledBibleRecord(item, fileName, System.currentTimeMillis())) }
                saveInstalled()
            }
        } finally {
            _downloading.update { it - item.id }
        }
    }

    private fun fetch(item: DownloadableBible, destination: File) {
        val url = downloadUrl(item)
        val data = try {
            val connection = url.toURL().openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 30_000
                connection.readTimeout = 300_000
                if (connection.responseCode !in 200..299) throw BibleDownload(BibleDownloadProblem.DAMAGED)
                connection.inputStream.use { it.readBytes() }
            } finally {
                connection.disconnect()
            }
        } catch (error: IOException) {
            throw BibleDownload(BibleDownloadProblem.OFFLINE)
        }
        val database = try {
            PackedFile.unpack(data, item.databaseBytes, item.sha256)
        } catch (error: PackedFile.Damaged) {
            throw BibleDownload(BibleDownloadProblem.DAMAGED)
        }
        directory.mkdirs()
        val partial = File(directory, destination.name + ".partial")
        partial.writeBytes(database)
        if (!partial.renameTo(destination)) {
            partial.delete()
            throw BibleDownload(BibleDownloadProblem.DAMAGED)
        }
        // Make sure it opens and holds a whole Bible before it's used.
        val whole = runCatching { BibleRepository.open(destination).use { it.verseCount() > 30_000 } }.getOrDefault(false)
        if (!whole) {
            destination.delete()
            throw BibleDownload(BibleDownloadProblem.NOT_A_BIBLE)
        }
    }

    /**
     * Where to fetch the file. A licensed Bible sits in a private bucket: the
     * bible-file function hands out a link that works for ten minutes, while
     * the publisher's licence lets Versely offer it.
     */
    private fun downloadUrl(item: DownloadableBible): URI {
        if (!item.isLicensedFile) {
            return runCatching { URI(item.fileUrl) }.getOrNull()?.takeIf { it.scheme == "https" }
                ?: throw BibleDownload(BibleDownloadProblem.DAMAGED)
        }
        val client = client ?: throw BibleDownload(BibleDownloadProblem.NOT_CONFIGURED)
        val body = buildJsonObject { put("id", item.id) }.toString()
        val answer = try {
            client.callFunctionAnonymously("bible-file", body)
        } catch (error: SupabaseError.Network) {
            throw BibleDownload(BibleDownloadProblem.OFFLINE)
        } catch (error: SupabaseError.Http) {
            throw BibleDownload(if (error.status == 403) BibleDownloadProblem.NEEDS_PREMIUM else BibleDownloadProblem.DAMAGED)
        }
        val link = runCatching { ((json.parseToJsonElement(answer) as JsonObject)["url"] as JsonPrimitive).content }.getOrNull()
        return link?.let { runCatching { URI(it) }.getOrNull() }?.takeIf { it.scheme == "https" }
            ?: throw BibleDownload(BibleDownloadProblem.DAMAGED)
    }

    /** Removes a download (highlights and notes stay: they're kept by verse). */
    fun remove(id: String) {
        val record = _downloads.value[id] ?: return
        _downloads.update { it - id }
        saveInstalled()
        releaseSealed(id)
        File(directory, record.fileName).delete()
        if (record.bible.isYouVersion) youVersion.forget(record.bible, directory)
    }

    private fun isMetered(): Boolean =
        (context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).isActiveNetworkMetered

    internal val folder: File get() = directory

    private fun loadInstalled(): Map<String, InstalledBibleRecord> {
        val file = File(directory, "installed.json")
        val items = runCatching { json.decodeFromString(ListSerializer(InstalledBibleRecord.serializer()), file.readText()) }.getOrDefault(emptyList())
        return items.filter { File(directory, it.fileName).exists() }
            .groupBy { it.bible.id }
            .mapValues { (_, copies) -> copies.maxBy { it.bible.version } }
    }

    @Synchronized
    private fun saveInstalled() {
        directory.mkdirs()
        val items = _downloads.value.values.sortedBy { it.bible.id }
        runCatching {
            val partial = File(directory, "installed.json.partial")
            partial.writeText(json.encodeToString(ListSerializer(InstalledBibleRecord.serializer()), items))
            partial.renameTo(File(directory, "installed.json"))
        }
    }

    /** Old editions replaced by an update, and unfinished files, are deleted on the next launch. */
    private fun removeLeftovers() {
        val keep = _downloads.value.values.map { it.fileName }.toSet()
        directory.listFiles()?.filter { (it.name.endsWith(".sqlite") || it.name.endsWith(".sealed") || it.name.endsWith(".partial")) && it.name !in keep && it.name != "installed.json.partial" }
            ?.forEach { it.delete() }
    }

    private companion object {
        const val TAG = "BibleLibrary"
    }
}
