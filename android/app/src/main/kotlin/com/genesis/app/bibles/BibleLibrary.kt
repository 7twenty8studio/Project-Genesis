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
import com.genesis.core.domain.studyresources.PackedFile
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
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
class BibleLibrary(context: Context, private val client: SupabaseClient?) {
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
    }

    /** Every Bible on the phone: the bundled ones, then downloads (a download never replaces a bundled id). */
    fun installed(downloads: Map<String, InstalledBibleRecord> = _downloads.value): List<InstalledBible> =
        BundledBible.entries.map { InstalledBible.of(it) } +
            downloads.values.filter { record -> BundledBible.entries.none { it.id == record.bible.id } }
                .sortedBy { it.bible.name }
                .map { InstalledBible(it.bible.id, file = File(directory, it.fileName)) }

    /** The Bible with this id, if it's on the phone. */
    fun resolve(id: String?): InstalledBible? = id?.let { wanted -> installed().firstOrNull { it.id == wanted } }

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
                files.filter { !it.isYouVersion }
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
            }
        }
    }

    /** Rows this version can't read are left out, never the whole list. */
    private fun rows(body: String): List<DownloadableBible> =
        (json.parseToJsonElement(body) as JsonArray).mapNotNull { row ->
            runCatching { json.decodeFromJsonElement(DownloadableBible.serializer(), row) }.getOrNull()
        }

    suspend fun download(item: DownloadableBible, hasPremium: Boolean) {
        _problem.value = null
        if (item.premium && !hasPremium) {
            _problem.value = BibleDownloadProblem.NEEDS_PREMIUM
            return
        }
        try {
            install(item)
        } catch (error: BibleDownload) {
            _problem.value = error.problem
        }
    }

    private class BibleDownload(val problem: BibleDownloadProblem) : Exception(problem.name)

    private suspend fun install(item: DownloadableBible) {
        if (item.id in _downloading.value) return
        _downloading.update { it + item.id }
        try {
            // A new file per edition: the old one may still be open for reading.
            val fileName = "${item.id}-${item.version}.sqlite"
            withContext(Dispatchers.IO) { fetch(item, File(directory, fileName)) }
            _downloads.update { it + (item.id to InstalledBibleRecord(item, fileName, System.currentTimeMillis())) }
            saveInstalled()
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
        File(directory, record.fileName).delete()
    }

    private fun isMetered(): Boolean =
        (context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).isActiveNetworkMetered

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
        directory.listFiles()?.filter { (it.name.endsWith(".sqlite") || it.name.endsWith(".partial")) && it.name !in keep && it.name != "installed.json.partial" }
            ?.forEach { it.delete() }
    }

    private companion object {
        const val TAG = "BibleLibrary"
    }
}
