package com.genesis.core.cloud

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

class OAuthTest {
    @Test
    fun challengeMatchesRfc7636() {
        // Checked against Python's hashlib and base64.
        assertEquals("3oc0AXQJrjSdTRRiBdLfehUqty_tahA3E3CeKSyD05U", OAuthPKCE.challenge("dBjftJeZ4CVP-mJ92K9mBkKyy4-jNYehpIa5f-sbBk"))
        val verifier = OAuthPKCE.verifier()
        assertEquals(64, verifier.length)
        assertTrue(verifier.all { it.isLetterOrDigit() || it in "-._~" })
    }

    @Test
    fun authorizeUrlAsIos() {
        assertEquals(
            "https://x.supabase.co/auth/v1/authorize?provider=google&redirect_to=versely%3A%2F%2Fauth-callback&code_challenge=abc&code_challenge_method=s256",
            OAuth.authorizeUrl("https://x.supabase.co/", OAuthProvider.GOOGLE, "abc"),
        )
    }

    @Test
    fun readsTheCallback() {
        assertEquals(OAuth.Callback.Code("123"), OAuth.parse("versely://auth-callback?code=123"))
        assertEquals(OAuth.Callback.Error("Access denied"), OAuth.parse("versely://auth-callback#error=access_denied&error_description=Access+denied"))
        assertEquals(OAuth.Callback.Invalid, OAuth.parse("versely://auth-callback"))
        assertEquals(OAuth.Callback.Invalid, OAuth.parse("versely://read/43003016"))
        assertEquals(OAuth.Callback.Invalid, OAuth.parse("versely://auth-callbackx?code=1"))
    }
}

class SupabaseClientTest {
    private val user = """
        {"id":"0b5c","email":"a@b.c","app_metadata":{"provider":"email","providers":["email","google"]},
         "identities":[{"provider":"google"}],"user_metadata":{"full_name":"  Ruth  "}}
    """.trimIndent()

    @Test
    fun signsInWithAPassword() {
        var sent: HttpRequest? = null
        val client = SupabaseClient("https://x.supabase.co", "anon", { request ->
            sent = request
            HttpResponse(200, """{"access_token":"a","refresh_token":"r","expires_in":3600,"user":$user}""")
        }, clock = { 1_000L })
        val session = client.signIn("a@b.c", "secret")
        assertEquals("https://x.supabase.co/auth/v1/token?grant_type=password", sent?.url)
        assertEquals("anon", sent?.headers?.get("apikey"))
        assertEquals(AuthSession("a", "r", 3_601_000L, AuthUser("0b5c", "a@b.c", listOf("email", "google"), "Ruth")), session)
        assertTrue(session.user.usesSignInWithGoogle)
    }

    @Test
    fun signUpWaitingForTheEmail() {
        val client = SupabaseClient("https://x.supabase.co", "anon", { HttpResponse(200, """{"id":"0b5c","email":"a@b.c"}""") })
        assertFailsWith<SupabaseError.EmailConfirmationRequired> { client.signUp("a@b.c", "secret") }
    }

    @Test
    fun serverErrorsKeepTheirMessage() {
        val client = SupabaseClient("https://x.supabase.co", "anon", { HttpResponse(400, """{"error":"invalid_grant","error_description":"Invalid login credentials"}""") })
        val error = assertFailsWith<SupabaseError.Http> { client.signIn("a@b.c", "wrong") }
        assertEquals(400, error.status)
        assertEquals("Invalid login credentials", error.message)
    }

    @Test
    fun sessionsRefreshAMinuteEarly() {
        val session = AuthSession("a", "r", expiresAt = 100_000L, user = AuthUser("1"))
        assertTrue(session.needsRefresh(now = 50_000L))
        assertEquals(false, session.needsRefresh(now = 30_000L))
    }
}

class SyncRowsTest {
    @Test
    fun timestampsRoundTripAtMilliseconds() {
        assertEquals("2026-09-29T17:46:00.123Z", Timestamps.string(Timestamps.millis("2026-09-29T17:46:00.123456+00:00")!!))
        assertEquals(Timestamps.millis("2026-09-29T17:46:00.123Z"), Timestamps.millis("2026-09-29 17:46:00.123+00"))
        assertEquals("2026-09-29T17:46:00.000Z", Timestamps.string(Timestamps.millis("2026-09-29T17:46:00Z")!!))
    }

    @Test
    fun changesPageByTheServersCursor() {
        var url = ""
        val client = SupabaseClient("https://x.supabase.co", "anon", { request -> url = request.url; HttpResponse(200, "[]") })
        client.changes(SyncTable.NOTES, "2026-09-29T17:46:00.123456+00:00", 50, "token")
        assertEquals(
            "https://x.supabase.co/rest/v1/notes?select=*&order=server_updated_at.asc&limit=50&server_updated_at=gt.2026-09-29T17%3A46%3A00.123456%2B00%3A00",
            url,
        )
    }
}
