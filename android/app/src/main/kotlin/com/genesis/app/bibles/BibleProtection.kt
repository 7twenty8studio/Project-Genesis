package com.genesis.app.bibles

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.KeyStore
import java.util.zip.GZIPInputStream
import java.util.zip.GZIPOutputStream
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Keeps licensed Bible text sealed on the phone, as BibleProtection on iOS:
 * AES-GCM with a key in the Android Keystore that never leaves this phone
 * (not in backups, not exportable). The publishers' agreements ask for the
 * text to be encrypted; it's only ever opened into memory.
 * File layout: a 12-byte nonce, then the sealed gzip of the content.
 */
object BibleProtection {
    private const val ALIAS = "versely.bibles"
    private const val NONCE = 12

    private fun key(): SecretKey = synchronized(this) {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        generator.generateKey()
    }

    /** Seals `data` into `file` (written beside it first, then moved into place). */
    fun write(data: ByteArray, file: File) {
        val packed = ByteArrayOutputStream().also { out -> GZIPOutputStream(out).use { it.write(data) } }.toByteArray()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val sealed = cipher.iv + cipher.doFinal(packed)
        file.parentFile?.mkdirs()
        val partial = File(file.parentFile, file.name + ".partial")
        partial.writeBytes(sealed)
        if (!partial.renameTo(file)) {
            partial.delete()
            error("Couldn't save ${file.name}")
        }
    }

    /** Opens a sealed file into memory; throws if it was changed or sealed on another phone. */
    fun read(file: File): ByteArray {
        val sealed = file.readBytes()
        require(sealed.size > NONCE) { "Too short" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, sealed, 0, NONCE))
        val packed = cipher.doFinal(sealed, NONCE, sealed.size - NONCE)
        return GZIPInputStream(packed.inputStream()).use { it.readBytes() }
    }
}
