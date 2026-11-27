package com.genesis.app.studylibrary

import android.content.Context
import android.net.ConnectivityManager
import android.util.Log
import androidx.core.content.edit
import com.genesis.core.bible.StudyResourceRepository
import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.domain.studyresources.DownloadableStudyResource
import com.genesis.core.domain.studyresources.InstalledStudyResource
import com.genesis.core.domain.studyresources.PackedFile
import com.genesis.core.domain.studyresources.StudyResourceKind
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI

/** Why a download didn't finish, shown in the Study Library. */
enum class StudyDownloadProblem { NOT_CONFIGURED, OFFLINE, DAMAGED, NOT_A_STUDY_PACK }

/**
 * The study packs on this phone (study notes, commentaries, Bible
 * dictionaries, lexicons) and those offered for download, as
 * StudyResourceLibrary on iOS: kept in no-backup storage, updated on Wi-Fi
 * when a corrected edition comes out. Premium packs need Premium; the
 * screens check it.
 */
class StudyResourceLibrary(context: Context, private val client: SupabaseClient?) {
    private val context = context.applicationContext
    private val directory = File(this.context.noBackupFilesDir, "StudyResources")
    private val prefs = this.context.getSharedPreferences("studyResources", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = false; coerceInputValues = true }
    private val repositories = HashMap<String, StudyResourceRepository>()

    private val _catalog = MutableStateFlow<List<DownloadableStudyResource>>(emptyList())
    /** What's offered for download, from the server (empty offline). */
    val catalog: StateFlow<List<DownloadableStudyResource>> = _catalog.asStateFlow()

    private val _installed = MutableStateFlow(loadInstalled())
    val installed: StateFlow<Map<String, InstalledStudyResource>> = _installed.asStateFlow()

    private val _downloading = MutableStateFlow<Set<String>>(emptySet())
    val downloading: StateFlow<Set<String>> = _downloading.asStateFlow()

    private val _problem = MutableStateFlow<StudyDownloadProblem?>(null)
    val problem: StateFlow<StudyDownloadProblem?> = _problem.asStateFlow()

    private val _chosenCommentary = MutableStateFlow(prefs.getString(COMMENTARY_KEY, null))
    /** The commentary chosen beside a verse. */
    val chosenCommentary: StateFlow<String?> = _chosenCommentary.asStateFlow()

    init {
        removeLeftovers()
    }

    fun chooseCommentary(id: String?) {
        _chosenCommentary.value = id
        prefs.edit { putString(COMMENTARY_KEY, id) }
    }

    /** Installed packs of a kind, in the catalog's order (then by name). */
    fun installedResources(kind: StudyResourceKind, installed: Map<String, InstalledStudyResource> = _installed.value): List<DownloadableStudyResource> {
        val order = _catalog.value.map { it.id }
        return installed.values.map { it.resource }.filter { it.kind == kind }
            .sortedWith(compareBy({ order.indexOf(it.id).let { index -> if (index < 0) Int.MAX_VALUE else index } }, { it.name }))
    }

    /** Everything offered, installed or not, with installed packs the server no longer lists at the end. */
    fun all(catalog: List<DownloadableStudyResource>, installed: Map<String, InstalledStudyResource>): List<DownloadableStudyResource> {
        val listed = catalog.map { it.id }.toSet()
        return catalog + installed.values.map { it.resource }.filter { it.id !in listed }.sortedBy { it.name }
    }

    /** The commentary to show beside a verse: the one chosen, else the first installed. */
    fun commentary(allowsPremium: Boolean): DownloadableStudyResource? {
        val commentaries = installedResources(StudyResourceKind.COMMENTARY).filter { allowsPremium || !it.premium }
        return commentaries.firstOrNull { it.id == _chosenCommentary.value } ?: commentaries.firstOrNull()
    }

    fun resource(id: String): DownloadableStudyResource? = _installed.value[id]?.resource ?: _catalog.value.firstOrNull { it.id == id }

    /** The pack's database, opened once; null if it isn't installed. Call off the main thread. */
    fun repository(id: String): StudyResourceRepository? = synchronized(repositories) {
        repositories[id]?.let { return it }
        val item = _installed.value[id] ?: return null
        runCatching { StudyResourceRepository.open(File(directory, item.fileName)) }
            .onFailure { Log.e(TAG, "Couldn't open ${item.fileName}", it) }
            .getOrNull()?.also { repositories[id] = it }
    }

    /** Fetches the catalog and quietly brings downloaded packs up to date on Wi-Fi. */
    suspend fun refreshCatalog() {
        val client = client ?: return
        val items = withContext(Dispatchers.IO) {
            runCatching {
                val body = client.select("study_resources", listOf("select" to "*", "enabled" to "eq.true", "order" to "sort.asc,name.asc"), null)
                // Rows this version can't use (a new kind) are left out, never the whole list.
                (json.parseToJsonElement(body) as JsonArray).mapNotNull { row ->
                    runCatching { json.decodeFromJsonElement(DownloadableStudyResource.serializer(), row) }.getOrNull()
                }
            }.onFailure { Log.w(TAG, "Couldn't fetch the catalog", it) }.getOrNull()
        } ?: return
        _catalog.value = items
        val unmetered = !isMetered()
        for (item in items) {
            val current = _installed.value[item.id] ?: continue
            when {
                item.version > current.resource.version && unmetered -> runCatching { install(item) }
                item.version == current.resource.version -> _installed.update { it + (item.id to InstalledStudyResource(item, current.fileName)) }
            }
        }
        saveInstalled()
    }

    suspend fun download(item: DownloadableStudyResource) {
        _problem.value = null
        try {
            install(item)
        } catch (error: StudyDownload) {
            _problem.value = error.problem
        }
    }

    private class StudyDownload(val problem: StudyDownloadProblem) : Exception(problem.name)

    private suspend fun install(item: DownloadableStudyResource) {
        if (item.id in _downloading.value) return
        _downloading.update { it + item.id }
        try {
            // A new file per edition: the old one may still be open for reading.
            val fileName = "${item.id}-${item.version}.sqlite"
            withContext(Dispatchers.IO) { fetch(item, File(directory, fileName)) }
            synchronized(repositories) { repositories.remove(item.id) }
            _installed.update { it + (item.id to InstalledStudyResource(item, fileName)) }
            saveInstalled()
        } finally {
            _downloading.update { it - item.id }
        }
    }

    private fun fetch(item: DownloadableStudyResource, destination: File) {
        val uri = runCatching { URI(item.fileUrl) }.getOrNull()
        if (uri == null || uri.scheme != "https") throw StudyDownload(StudyDownloadProblem.DAMAGED)
        val data = try {
            val connection = uri.toURL().openConnection() as HttpURLConnection
            try {
                connection.connectTimeout = 30_000
                connection.readTimeout = 300_000
                if (connection.responseCode !in 200..299) throw StudyDownload(StudyDownloadProblem.DAMAGED)
                connection.inputStream.use { it.readBytes() }
            } finally {
                connection.disconnect()
            }
        } catch (error: IOException) {
            throw StudyDownload(StudyDownloadProblem.OFFLINE)
        }
        val database = try {
            PackedFile.unpack(data, item.databaseBytes, item.sha256)
        } catch (error: PackedFile.Damaged) {
            throw StudyDownload(StudyDownloadProblem.DAMAGED)
        }
        directory.mkdirs()
        val partial = File(directory, destination.name + ".partial")
        partial.writeBytes(database)
        if (!partial.renameTo(destination)) {
            partial.delete()
            throw StudyDownload(StudyDownloadProblem.DAMAGED)
        }
        // Make sure it opens and is the pack the catalog promised.
        val matches = runCatching { StudyResourceRepository.open(destination).use { it.packId() == item.id } }.getOrDefault(false)
        if (!matches) {
            destination.delete()
            throw StudyDownload(StudyDownloadProblem.NOT_A_STUDY_PACK)
        }
    }

    fun remove(id: String) {
        val item = _installed.value[id] ?: return
        _installed.update { it - id }
        synchronized(repositories) { repositories.remove(id)?.close() }
        if (_chosenCommentary.value == id) chooseCommentary(null)
        saveInstalled()
        File(directory, item.fileName).delete()
    }

    private fun isMetered(): Boolean =
        (context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager).isActiveNetworkMetered

    private fun loadInstalled(): Map<String, InstalledStudyResource> {
        val file = File(directory, "installed.json")
        val items = runCatching { json.decodeFromString(ListSerializer(InstalledStudyResource.serializer()), file.readText()) }.getOrDefault(emptyList())
        return items.filter { File(directory, it.fileName).exists() }
            .groupBy { it.resource.id }
            .mapValues { (_, copies) -> copies.maxBy { it.resource.version } }
    }

    private fun saveInstalled() {
        directory.mkdirs()
        val items = _installed.value.values.sortedBy { it.resource.id }
        runCatching {
            val partial = File(directory, "installed.json.partial")
            partial.writeText(json.encodeToString(ListSerializer(InstalledStudyResource.serializer()), items))
            partial.renameTo(File(directory, "installed.json"))
        }
    }

    /** Old editions replaced by an update are deleted on the next launch. */
    private fun removeLeftovers() {
        val keep = _installed.value.values.map { it.fileName }.toSet()
        directory.listFiles()?.filter { (it.name.endsWith(".sqlite") || it.name.endsWith(".partial")) && it.name !in keep && it.name != "installed.json.partial" }
            ?.forEach { it.delete() }
    }

    private companion object {
        const val TAG = "StudyLibrary"
        const val COMMENTARY_KEY = "studyResources.commentary"
    }
}
