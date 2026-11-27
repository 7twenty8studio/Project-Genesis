package com.genesis.app.account

import android.content.Context
import android.util.Log
import androidx.annotation.StringRes
import androidx.core.content.edit
import com.genesis.app.BuildConfig
import com.genesis.app.R
import com.genesis.core.cloud.AuthSession
import com.genesis.core.cloud.AuthUser
import com.genesis.core.cloud.OAuth
import com.genesis.core.cloud.OAuthPKCE
import com.genesis.core.cloud.OAuthProvider
import com.genesis.core.cloud.SupabaseClient
import com.genesis.core.cloud.SupabaseError
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/** A line under the sign-in form: the app's own words, or the server's. */
data class AccountMessage(@param:StringRes val res: Int? = null, val text: String? = null, val isError: Boolean)

data class AccountUiState(
    val user: AuthUser? = null,
    val isWorking: Boolean = false,
    val message: AccountMessage? = null,
)

/**
 * Who is signed in, as AuthService on iOS. Without an account the app works
 * fully offline as a guest; signing in (Apple, Google, or email and
 * password: the same Supabase accounts as the iPhone and Church Studio)
 * adds free backup and sync.
 */
class AccountService(context: Context, private val scope: CoroutineScope) {
    private val vault = SessionVault(context)
    private val prefs = context.getSharedPreferences("account.oauth", Context.MODE_PRIVATE)
    private val client: SupabaseClient? = BuildConfig.SUPABASE_URL.takeIf { it.startsWith("https://") && BuildConfig.SUPABASE_ANON_KEY.isNotEmpty() }
        ?.let { SupabaseClient(it, BuildConfig.SUPABASE_ANON_KEY) }
    private var session: AuthSession? = if (client != null) vault.load() else null
    private val refreshing = Mutex()

    private val _state = MutableStateFlow(AccountUiState(user = session?.user))
    val state: StateFlow<AccountUiState> = _state.asStateFlow()

    /** False when the build has no Supabase configuration. */
    val isAvailable: Boolean get() = client != null

    fun signIn(email: String, password: String) = run { it.signIn(clean(email), password) }

    fun signUp(email: String, password: String) = run { it.signUp(clean(email), password) }

    fun sendPasswordReset(email: String) {
        val client = client ?: return
        working {
            withContext(Dispatchers.IO) { client.sendPasswordReset(clean(email)) }
            _state.update { it.copy(message = AccountMessage(R.string.reset_sent, isError = false)) }
        }
    }

    /**
     * Starts signing in with Apple or Google: the address of Supabase's page
     * to open in the browser. The verifier waits on the device (even if the
     * app is closed meanwhile) for versely://auth-callback.
     */
    fun startOAuth(provider: OAuthProvider): String? {
        val client = client ?: return null.also { notConfigured() }
        val verifier = OAuthPKCE.verifier()
        prefs.edit {
            putString(VERIFIER, verifier)
            putString(PROVIDER, provider.id)
        }
        _state.update { it.copy(message = null) }
        return OAuth.authorizeUrl(client.baseUrl, provider, OAuthPKCE.challenge(verifier))
    }

    /** True when the link was the sign-in callback (handled here, whatever its outcome). */
    fun handleCallback(link: String): Boolean {
        if (!OAuth.isCallback(link)) return false
        val verifier = prefs.getString(VERIFIER, null)
        val failed = if (prefs.getString(PROVIDER, null) == OAuthProvider.APPLE.id) R.string.apple_failed else R.string.google_failed
        prefs.edit {
            remove(VERIFIER)
            remove(PROVIDER)
        }
        when (val callback = OAuth.parse(link)) {
            is OAuth.Callback.Code -> if (verifier != null) {
                run { it.signInWithCode(callback.code, verifier) }
            } else {
                _state.update { it.copy(message = AccountMessage(failed, isError = true)) }
            }
            is OAuth.Callback.Error -> _state.update {
                it.copy(message = AccountMessage(res = if (callback.description == null) failed else null, text = callback.description, isError = true))
            }
            OAuth.Callback.Invalid -> _state.update { it.copy(message = AccountMessage(failed, isError = true)) }
        }
        return true
    }

    fun signOut() {
        val ending = session
        session = null
        vault.clear()
        _state.update { AccountUiState() }
        if (ending != null && client != null) scope.launch(Dispatchers.IO) { client.signOut(ending) }
    }

    fun clearMessage() = _state.update { it.copy(message = null) }

    /** A current access token, refreshed when close to expiry (for sync). */
    suspend fun accessToken(): String {
        val client = client ?: throw SupabaseError.InvalidResponse()
        return refreshing.withLock {
            val current = session ?: throw SupabaseError.Http(401, "signed out")
            if (!current.needsRefresh()) return@withLock current.accessToken
            try {
                val refreshed = withContext(Dispatchers.IO) { client.refresh(current) }
                store(refreshed)
                refreshed.accessToken
            } catch (error: SupabaseError.Http) {
                if (error.status == 400 || error.status == 401) {
                    // The refresh token was revoked: the person needs to sign in again.
                    signOut()
                    _state.update { it.copy(message = AccountMessage(R.string.session_ended, isError = true)) }
                }
                throw error
            }
        }
    }

    private fun run(operation: (SupabaseClient) -> AuthSession) {
        val client = client ?: return notConfigured()
        working {
            val newSession = withContext(Dispatchers.IO) { operation(client) }
            store(newSession)
        }
    }

    private fun working(block: suspend () -> Unit) {
        if (_state.value.isWorking) return
        _state.update { it.copy(isWorking = true, message = null) }
        scope.launch {
            try {
                block()
            } catch (error: SupabaseError) {
                Log.w(TAG, "Account request refused", error)
                _state.update { it.copy(message = message(error)) }
            } catch (error: Exception) {
                Log.e(TAG, "Account request failed", error)
                _state.update { it.copy(message = AccountMessage(R.string.unexpected_response, isError = true)) }
            } finally {
                _state.update { it.copy(isWorking = false) }
            }
        }
    }

    private fun store(newSession: AuthSession) {
        session = newSession
        vault.save(newSession)
        _state.update { it.copy(user = newSession.user) }
    }

    private fun notConfigured() = _state.update { it.copy(message = AccountMessage(R.string.cloud_not_set_up, isError = true)) }

    private fun message(error: SupabaseError): AccountMessage = when (error) {
        is SupabaseError.EmailConfirmationRequired -> AccountMessage(R.string.confirm_email, isError = false)
        is SupabaseError.Http -> AccountMessage(text = error.message, isError = true)
        is SupabaseError.Network -> AccountMessage(R.string.server_unreachable, isError = true)
        is SupabaseError.InvalidResponse -> AccountMessage(R.string.unexpected_response, isError = true)
    }

    private fun clean(email: String) = email.trim().lowercase()

    private companion object {
        const val TAG = "Account"
        const val VERIFIER = "verifier"
        const val PROVIDER = "provider"
    }
}
