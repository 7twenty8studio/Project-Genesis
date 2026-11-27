package com.genesis.core.cloud

import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Base64

/**
 * PKCE (RFC 7636) for signing in through a browser, as OAuthPKCE on iOS: a
 * random verifier stays on the device, the server gets only its SHA-256
 * challenge, and the one-time code from the callback is worthless without it.
 */
object OAuthPKCE {
    private const val CHARACTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    private val random = SecureRandom()

    /** A random verifier; RFC 7636 allows 43–128 characters. */
    fun verifier(length: Int = 64): String {
        val count = length.coerceIn(43, 128)
        return buildString { repeat(count) { append(CHARACTERS[random.nextInt(CHARACTERS.length)]) } }
    }

    /** The S256 challenge: base64url (no padding) of the verifier's SHA-256. */
    fun challenge(verifier: String): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()))
}

/**
 * Signing in with Google or Apple through Supabase's OAuth (PKCE) flow, with
 * no SDK, as GoogleOAuth on iOS: Supabase's /authorize page sends the person
 * to the provider, the provider back to Supabase, and Supabase to
 * versely://auth-callback?code=…, which the app swaps (with the verifier) for
 * a session. The redirect is already in Supabase's allowed list for iOS.
 */
enum class OAuthProvider(val id: String) {
    APPLE("apple"),
    GOOGLE("google"),
}

object OAuth {
    const val REDIRECT_URL = "versely://auth-callback"

    fun authorizeUrl(baseUrl: String, provider: OAuthProvider, challenge: String): String {
        val query = listOf(
            "provider" to provider.id,
            "redirect_to" to REDIRECT_URL,
            "code_challenge" to challenge,
            "code_challenge_method" to "s256",
        ).joinToString("&") { (name, value) -> "$name=${URLEncoder.encode(value, Charsets.UTF_8)}" }
        return "${baseUrl.trimEnd('/')}/auth/v1/authorize?$query"
    }

    sealed interface Callback {
        data class Code(val code: String) : Callback

        /** The server or the provider refused; its description when it sent one. */
        data class Error(val description: String?) : Callback

        /** Not our callback, or neither a code nor an error. */
        data object Invalid : Callback
    }

    fun isCallback(link: String): Boolean = link.startsWith(REDIRECT_URL)

    /** Reads the code (or the error) from the callback's query, or its fragment, where Supabase puts some errors. */
    fun parse(link: String): Callback {
        if (!isCallback(link)) return Callback.Invalid
        val rest = link.removePrefix(REDIRECT_URL)
        if (rest.isNotEmpty() && rest[0] !in "/?#") return Callback.Invalid
        val query = rest.substringAfter('?', "").substringBefore('#')
        val fragment = rest.substringAfter('#', "")
        val items = (query.split('&') + fragment.split('&')).filter { it.isNotEmpty() }.map { pair ->
            val name = URLDecoder.decode(pair.substringBefore('='), Charsets.UTF_8)
            val value = if ('=' in pair) URLDecoder.decode(pair.substringAfter('='), Charsets.UTF_8) else ""
            name to value
        }
        fun value(name: String) = items.firstOrNull { it.first == name }?.second?.takeIf { it.isNotEmpty() }
        value("code")?.let { return Callback.Code(it) }
        if (value("error") != null || value("error_description") != null) return Callback.Error(value("error_description"))
        return Callback.Invalid
    }
}
