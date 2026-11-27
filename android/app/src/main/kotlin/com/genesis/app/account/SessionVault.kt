package com.genesis.app.account

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import androidx.core.content.edit
import com.genesis.core.cloud.AuthSession
import kotlinx.serialization.json.Json
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps the signed-in session, as the Keychain does on iOS: sealed with
 * AES-GCM under a key in the Android Keystore that never leaves this
 * device, so a backup restored on another phone can't be opened there (it
 * signs in again). A session that can't be opened is dropped, never half-read.
 */
internal class SessionVault(context: Context) {
    private val prefs = context.getSharedPreferences("account", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    fun load(): AuthSession? {
        val sealed = prefs.getString(SESSION, null) ?: return null
        return runCatching {
            val bytes = Base64.decode(sealed, Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes, 0, IV_LENGTH))
            json.decodeFromString<AuthSession>(String(cipher.doFinal(bytes, IV_LENGTH, bytes.size - IV_LENGTH)))
        }.onFailure {
            Log.w(TAG, "Couldn't open the saved session; signing out", it)
            clear()
        }.getOrNull()
    }

    fun save(session: AuthSession) {
        runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, key())
            val sealed = cipher.iv + cipher.doFinal(json.encodeToString(session).toByteArray())
            prefs.edit { putString(SESSION, Base64.encodeToString(sealed, Base64.NO_WRAP)) }
        }.onFailure { Log.e(TAG, "Couldn't save the session", it) }
    }

    fun clear() = prefs.edit { remove(SESSION) }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val TAG = "Account"
        const val SESSION = "session"
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "versely.session"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
    }
}
