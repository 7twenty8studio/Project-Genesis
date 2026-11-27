package com.genesis.core.cloud

import kotlinx.serialization.Serializable

/** A signed-in Supabase session, as AuthSession on iOS. */
@Serializable
data class AuthSession(
    val accessToken: String,
    val refreshToken: String,
    /** Milliseconds since 1970. */
    val expiresAt: Long,
    val user: AuthUser,
) {
    /** True when the access token expires within the next minute. */
    fun needsRefresh(now: Long = System.currentTimeMillis()): Boolean = expiresAt - now < 60_000
}

@Serializable
data class AuthUser(
    val id: String,
    val email: String? = null,
    /** How the account signs in ("apple", "google", "email"), from app_metadata and identities. */
    val providers: List<String> = emptyList(),
    /** The name the sign-in gave (Google's, or Apple's when shared), from user_metadata. */
    val name: String? = null,
) {
    val usesSignInWithApple: Boolean get() = "apple" in providers
    val usesSignInWithGoogle: Boolean get() = "google" in providers
}

/** What went wrong talking to Supabase. The app turns these into its own words. */
sealed class SupabaseError(message: String) : Exception(message) {
    /** The server refused; `message` is its own text (Supabase's English). */
    class Http(val status: Int, message: String) : SupabaseError(message)

    /** Sign-up worked, but the account must be confirmed from the email first. */
    class EmailConfirmationRequired : SupabaseError("email confirmation required")

    class InvalidResponse : SupabaseError("invalid response")

    /** Connected, but the answer took too long. */
    class Timeout(cause: Throwable) : SupabaseError(cause.message ?: "timeout")

    /** No connection, or it dropped. */
    class Network(cause: Throwable) : SupabaseError(cause.message ?: "network") {
        init {
            initCause(cause)
        }
    }
}
