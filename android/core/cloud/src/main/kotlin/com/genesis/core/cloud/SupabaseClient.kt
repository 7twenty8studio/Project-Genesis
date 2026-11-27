package com.genesis.core.cloud

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URI

/** One HTTP exchange; swapped for a stand-in in tests. */
fun interface HttpTransport {
    fun send(request: HttpRequest): HttpResponse
}

data class HttpRequest(val method: String, val url: String, val headers: Map<String, String>, val body: String?)

data class HttpResponse(val status: Int, val body: String)

/** The real transport: HttpURLConnection, 30 s timeouts. Blocking: call it off the main thread. */
object UrlConnectionTransport : HttpTransport {
    override fun send(request: HttpRequest): HttpResponse {
        val connection = URI(request.url).toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = request.method
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            request.headers.forEach { (name, value) -> connection.setRequestProperty(name, value) }
            if (request.body != null) {
                connection.doOutput = true
                connection.outputStream.use { it.write(request.body.toByteArray()) }
            }
            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()
            return HttpResponse(status, body)
        } finally {
            connection.disconnect()
        }
    }
}

/**
 * A small client for Supabase's Auth API, as SupabaseClient on iOS (the
 * same endpoints and bodies, so both phones sign in to the same accounts).
 * Blocking calls: run them off the main thread.
 */
class SupabaseClient(
    baseUrl: String,
    private val anonKey: String,
    private val transport: HttpTransport = UrlConnectionTransport,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    val baseUrl: String = baseUrl.trimEnd('/')
    private val json = Json { ignoreUnknownKeys = true }

    fun signUp(email: String, password: String): AuthSession =
        tokenRequest("auth/v1/signup", "", buildJsonObject { put("email", email); put("password", password) })

    fun signIn(email: String, password: String): AuthSession =
        tokenRequest("auth/v1/token", "grant_type=password", buildJsonObject { put("email", email); put("password", password) })

    /** Swaps the code from an OAuth (PKCE) sign-in and the verifier only this device knows for a session. */
    fun signInWithCode(oauthCode: String, verifier: String): AuthSession =
        tokenRequest("auth/v1/token", "grant_type=pkce", buildJsonObject { put("auth_code", oauthCode); put("code_verifier", verifier) })

    fun refresh(current: AuthSession): AuthSession =
        tokenRequest("auth/v1/token", "grant_type=refresh_token", buildJsonObject { put("refresh_token", current.refreshToken) })

    /**
     * Ends this device's session only (`scope=local`): the default, global,
     * would sign the person out everywhere, Church Studio included. Quiet.
     */
    fun signOut(current: AuthSession) {
        runCatching { send("POST", "auth/v1/logout", "scope=local", "{}", current.accessToken) }
    }

    fun currentUser(accessToken: String): AuthUser =
        parseUser(json.parseToJsonElement(send("GET", "auth/v1/user", "", null, accessToken).ifEmpty { "{}" }).jsonObject)

    fun sendPasswordReset(email: String) {
        send("POST", "auth/v1/recover", "", buildJsonObject { put("email", email) }.toString(), null)
    }

    /** Calls an Edge Function as the signed-in person; the response body. */
    fun callFunction(name: String, bodyJson: String, accessToken: String): String =
        send("POST", "functions/v1/$name", "", bodyJson, accessToken)

    /** Calls an Edge Function with the anon key only (no account is sent). */
    fun callFunctionAnonymously(name: String, bodyJson: String): String =
        send("POST", "functions/v1/$name", "", bodyJson, null)

    /**
     * Calls an Edge Function with the anon key, waiting up to `timeoutMs` for
     * the answer, and returns its status and body whatever the status (the
     * caller reads a 429's `retryAfter`). Network failures throw Network.
     */
    fun callFunctionWithStatus(name: String, bodyJson: String, timeoutMs: Int): HttpResponse {
        val connection = URI("$baseUrl/functions/v1/$name").toURL().openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.connectTimeout = 30_000
            connection.readTimeout = timeoutMs
            connection.useCaches = false
            connection.setRequestProperty("apikey", anonKey)
            connection.setRequestProperty("Authorization", "Bearer $anonKey")
            connection.setRequestProperty("Content-Type", "application/json")
            connection.doOutput = true
            return try {
                connection.outputStream.use { it.write(bodyJson.toByteArray()) }
                val status = connection.responseCode
                val stream = if (status in 200..299) connection.inputStream else connection.errorStream
                HttpResponse(status, stream?.bufferedReader()?.use { it.readText() }.orEmpty())
            } catch (error: java.net.SocketTimeoutException) {
                throw SupabaseError.Timeout(error)
            } catch (error: IOException) {
                throw SupabaseError.Network(error)
            }
        } finally {
            connection.disconnect()
        }
    }

    /**
     * GETs a file (a sermon cover) as bytes, never cached; null for a 404.
     * Straight over HttpURLConnection, since the transport carries text.
     */
    fun getBytes(path: String, query: String, accessToken: String?): ByteArray? {
        val url = "$baseUrl/$path" + if (query.isNotEmpty()) "?$query" else ""
        val connection = URI(url).toURL().openConnection() as HttpURLConnection
        try {
            connection.connectTimeout = 30_000
            connection.readTimeout = 30_000
            connection.useCaches = false
            connection.setRequestProperty("apikey", anonKey)
            connection.setRequestProperty("Authorization", "Bearer ${accessToken ?: anonKey}")
            val status = try {
                connection.responseCode
            } catch (error: IOException) {
                throw SupabaseError.Network(error)
            }
            if (status == 404) return null
            if (status !in 200..299) throw SupabaseError.Http(status, "HTTP $status")
            return connection.inputStream.use { it.readBytes() }
        } finally {
            connection.disconnect()
        }
    }

    // MARK: REST (PostgREST), as on iOS

    /** Rows of `table` changed on the server after `cursor` (server_updated_at), oldest first. */
    fun changes(table: String, cursor: String?, limit: Int, accessToken: String): String {
        val query = buildList {
            add("select=*")
            add("order=server_updated_at.asc")
            add("limit=$limit")
            // "+" must be escaped: PostgREST reads it as a space, which would break "…+00:00".
            if (cursor != null) add("server_updated_at=gt.${encode(cursor)}")
        }.joinToString("&")
        return send("GET", "rest/v1/$table", query, null, accessToken)
    }

    /**
     * Inserts or updates rows by id. Only the columns sent change, so what
     * Android doesn't know (a note's handwritten page) stays as it was.
     */
    fun upsert(table: String, rowsJson: String, accessToken: String) {
        send("POST", "rest/v1/$table", "on_conflict=id", rowsJson, accessToken, prefer = "resolution=merge-duplicates,return=minimal")
    }

    /** Marks rows deleted so other devices remove them too. */
    fun markDeleted(table: String, ids: Collection<String>, atMillis: Long, accessToken: String) {
        if (ids.isEmpty()) return
        val stamp = Timestamps.string(atMillis)
        val body = buildJsonObject { put("deleted_at", stamp); put("updated_at", stamp) }.toString()
        send("PATCH", "rest/v1/$table", "id=in.(${ids.joinToString(",")})", body, accessToken, prefer = "return=minimal")
    }

    /** GET rows of a table or view; `query` pairs are URL-encoded (PostgREST filters such as "eq.x"). */
    fun select(table: String, query: List<Pair<String, String>>, accessToken: String?): String =
        send("GET", "rest/v1/$table", query.joinToString("&") { (key, value) -> "${encode(key)}=${encode(value)}" }, null, accessToken)

    fun insert(table: String, rowJson: String, accessToken: String?) {
        send("POST", "rest/v1/$table", "", rowJson, accessToken, prefer = "return=minimal")
    }

    fun delete(table: String, query: List<Pair<String, String>>, accessToken: String) {
        send("DELETE", "rest/v1/$table", query.joinToString("&") { (key, value) -> "${encode(key)}=${encode(value)}" }, null, accessToken, prefer = "return=minimal")
    }

    /** Calls a database function; the JSON it returns. */
    fun rpc(name: String, paramsJson: String, accessToken: String?): String =
        send("POST", "rest/v1/rpc/$name", "", paramsJson, accessToken)

    /** The server's switches (public.feature_flags), readable without signing in. */
    fun featureFlags(): Map<String, Boolean> {
        val rows = json.parseToJsonElement(select("feature_flags", listOf("select" to "key,enabled"), null).ifEmpty { "[]" }).jsonArray
        return rows.mapNotNull { row ->
            val obj = row as? JsonObject ?: return@mapNotNull null
            val key = obj.string("key") ?: return@mapNotNull null
            val enabled = (obj["enabled"] as? JsonPrimitive)?.contentOrNull == "true"
            key to enabled
        }.toMap()
    }

    private fun encode(value: String) = java.net.URLEncoder.encode(value, Charsets.UTF_8)

    private fun tokenRequest(path: String, query: String, body: JsonObject): AuthSession {
        val response = json.parseToJsonElement(send("POST", path, query, body.toString(), null).ifEmpty { "{}" }).jsonObject
        val accessToken = response.string("access_token")
        val refreshToken = response.string("refresh_token")
        val user = response["user"] as? JsonObject
        if (accessToken == null || refreshToken == null || user == null) {
            // Sign-up with email confirmation on returns the user alone, no session.
            if (response.string("id") != null) throw SupabaseError.EmailConfirmationRequired()
            throw SupabaseError.InvalidResponse()
        }
        val expiresIn = (response["expires_in"] as? JsonPrimitive)?.doubleOrNull ?: 3600.0
        return AuthSession(accessToken, refreshToken, clock() + (expiresIn * 1000).toLong(), parseUser(user))
    }

    private fun send(method: String, path: String, query: String, body: String?, accessToken: String?, prefer: String? = null): String {
        val url = "$baseUrl/$path" + if (query.isNotEmpty()) "?$query" else ""
        val headers = mapOf(
            "apikey" to anonKey,
            "Authorization" to "Bearer ${accessToken ?: anonKey}",
            "Content-Type" to "application/json",
            "Accept" to "application/json",
        ) + listOfNotNull(prefer?.let { "Prefer" to it })
        val response = try {
            transport.send(HttpRequest(method, url, headers, body))
        } catch (error: IOException) {
            throw SupabaseError.Network(error)
        }
        if (response.status !in 200..299) {
            val message = runCatching { json.parseToJsonElement(response.body).jsonObject }.getOrNull()?.let { error ->
                error.string("msg") ?: error.string("message") ?: error.string("error_description") ?: error.string("error")
            } ?: "HTTP ${response.status}"
            throw SupabaseError.Http(response.status, message)
        }
        return response.body
    }

    companion object {
        /** The account as AuthUser (providers from app_metadata and identities; the name from user_metadata). */
        internal fun parseUser(user: JsonObject): AuthUser {
            val app = user["app_metadata"] as? JsonObject
            val names = buildList {
                (app?.get("providers") as? JsonArray)?.forEach { it.stringOrNull()?.let(::add) }
                app?.string("provider")?.let(::add)
                (user["identities"] as? JsonArray)?.forEach { identity -> (identity as? JsonObject)?.string("provider")?.let(::add) }
            }.distinct()
            val metadata = user["user_metadata"] as? JsonObject
            val name = listOfNotNull(metadata?.string("full_name"), metadata?.string("name"))
                .map { it.trim() }
                .firstOrNull { it.isNotEmpty() }
            return AuthUser(
                id = user.string("id") ?: throw SupabaseError.InvalidResponse(),
                email = user.string("email"),
                providers = names,
                name = name,
            )
        }

        private fun JsonObject.string(key: String): String? = this[key]?.stringOrNull()

        private fun JsonElement.stringOrNull(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
    }
}
