package com.genesis.app.journal

import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * The few Google Drive calls attachments need, in the person's own Drive's
 * hidden app folder (appDataFolder: only Versely can see it, it doesn't
 * show among their files, and it counts toward their own storage). Plain
 * HTTPS with the access token from [DriveAuthorization]; no Drive SDK.
 */
internal class DriveClient(private val token: String) {
    class Failure(val status: Int, message: String) : IOException(message) {
        /** The person's Drive is full. */
        val isFull get() = status == 403 && message.orEmpty().contains("storageQuotaExceeded")
        /** The token was refused (expired, or access removed). */
        val isUnauthorized get() = status == 401
    }

    data class DriveFile(val id: String, val name: String)

    private fun driveFile(json: JSONObject) = DriveFile(json.getString("id"), json.optString("name"))

    /** The file named [name] in the app folder, if there is one. */
    fun find(name: String): DriveFile? {
        val query = "name = '${name.replace("'", "\\'")}' and trashed = false"
        return list(query).firstOrNull()
    }

    /** Every file in the app folder. */
    fun all(): List<DriveFile> = list(null)

    private fun list(query: String?): List<DriveFile> {
        val found = mutableListOf<DriveFile>()
        var page: String? = null
        do {
            val url = buildString {
                append("$API/files?spaces=appDataFolder&pageSize=1000&fields=nextPageToken,files(id,name)")
                query?.let { append("&q=").append(encode(it)) }
                page?.let { append("&pageToken=").append(encode(it)) }
            }
            val body = request("GET", url) { }
            val list = JSONObject(body)
            val files = list.optJSONArray("files") ?: JSONArray()
            for (i in 0 until files.length()) found += driveFile(files.getJSONObject(i))
            page = list.optString("nextPageToken").ifEmpty { null }
        } while (page != null)
        return found
    }

    /** Uploads [file] as [name] (resumable upload, so files of any size up to 250 MB go in one stream). */
    fun upload(file: File, name: String, mimeType: String): DriveFile {
        val existing = find(name)
        val (method, start) = if (existing != null) {
            "PATCH" to "$UPLOAD/files/${existing.id}?uploadType=resumable"
        } else {
            "POST" to "$UPLOAD/files?uploadType=resumable"
        }
        val metadata = if (existing != null) "{}" else JSONObject().put("name", name).put("parents", JSONArray().put("appDataFolder")).toString()
        val session = connection(method, start).apply {
            doOutput = true
            setRequestProperty("Content-Type", "application/json; charset=UTF-8")
            setRequestProperty("X-Upload-Content-Type", mimeType)
            setRequestProperty("X-Upload-Content-Length", file.length().toString())
        }
        val location = try {
            session.outputStream.use { it.write(metadata.toByteArray()) }
            check(session)
            session.getHeaderField("Location") ?: throw Failure(session.responseCode, "No upload location")
        } finally {
            session.disconnect()
        }
        val put = (URL(location).openConnection() as HttpURLConnection).apply {
            requestMethod = "PUT"
            doOutput = true
            connectTimeout = 20_000
            readTimeout = 120_000
            setFixedLengthStreamingMode(file.length())
            setRequestProperty("Content-Type", mimeType)
        }
        try {
            file.inputStream().use { input -> put.outputStream.use { input.copyTo(it, 64 * 1024) } }
            val body = check(put)
            return driveFile(JSONObject(body))
        } finally {
            put.disconnect()
        }
    }

    /** Downloads the file named [name] into [target]; false when Drive has no such file. */
    fun download(name: String, target: File): Boolean {
        val found = find(name) ?: return false
        val connection = connection("GET", "$API/files/${found.id}?alt=media")
        try {
            if (connection.responseCode == 404) return false
            if (connection.responseCode !in 200..299) check(connection)
            val partial = File(target.parentFile, "${target.name}.part")
            connection.inputStream.use { input -> partial.outputStream().use { input.copyTo(it, 64 * 1024) } }
            if (!partial.renameTo(target)) { partial.delete(); throw IOException("Couldn't save ${target.name}") }
            return true
        } finally {
            connection.disconnect()
        }
    }

    /** Deletes the file named [name]; a file that's already gone counts as deleted. */
    fun delete(name: String) {
        val found = find(name) ?: return
        deleteById(found.id)
    }

    /** Deletes everything in the app folder (when the person deletes their account). */
    fun deleteAll() {
        all().forEach { deleteById(it.id) }
    }

    private fun deleteById(id: String) {
        val connection = connection("DELETE", "$API/files/$id")
        try {
            if (connection.responseCode != 404) check(connection)
        } finally {
            connection.disconnect()
        }
    }

    private fun request(method: String, url: String, configure: HttpURLConnection.() -> Unit): String {
        val connection = connection(method, url).apply(configure)
        try {
            return check(connection)
        } finally {
            connection.disconnect()
        }
    }

    private fun connection(method: String, url: String): HttpURLConnection =
        (URL(url).openConnection() as HttpURLConnection).apply {
            if (method == "PATCH") {
                requestMethod = "POST"
                setRequestProperty("X-HTTP-Method-Override", "PATCH")
            } else {
                requestMethod = method
            }
            connectTimeout = 20_000
            readTimeout = 60_000
            setRequestProperty("Authorization", "Bearer $token")
        }

    private fun check(connection: HttpURLConnection): String {
        val status = connection.responseCode
        if (status in 200..299) return connection.inputStream.use { it.readBytes().decodeToString() }
        val error = runCatching { connection.errorStream?.use { it.readBytes().decodeToString() } }.getOrNull().orEmpty()
        throw Failure(status, error.take(500))
    }

    private fun encode(text: String) = URLEncoder.encode(text, "UTF-8")

    private companion object {
        const val API = "https://www.googleapis.com/drive/v3"
        const val UPLOAD = "https://www.googleapis.com/upload/drive/v3"
    }
}
