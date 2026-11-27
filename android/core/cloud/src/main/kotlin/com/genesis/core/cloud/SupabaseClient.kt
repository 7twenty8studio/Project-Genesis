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
        parseUser(json.parseToJsonElement(send("GET", "auth/v1/user", "", null, accessToken)).jsonObject)

    fun sendPasswordReset(email: String) {
        send("POST", "auth/v1/recover", "", buildJsonObject { put("email", email) }.toString(), null)
    }

    private fun tokenRequest(path: String, query: String, body: JsonObject): AuthSession {
        val response = json.parseToJsonElement(send("POST", path, query, body.toString(), null)).jsonObject
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

    private fun send(method: String, path: String, query: String, body: String?, accessToken: String?): String {
        val url = "$baseUrl/$path" + if (query.isNotEmpty()) "?$query" else ""
        val headers = mapOf(
            "apikey" to anonKey,
            "Authorization" to "Bearer ${accessToken ?: anonKey}",
            "Content-Type" to "application/json",
            "Accept" to "application/json",
        )
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
        return response.body.ifEmpty { "{}" }
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
