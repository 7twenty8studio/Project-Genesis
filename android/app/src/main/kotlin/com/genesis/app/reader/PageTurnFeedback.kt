package com.genesis.app.reader

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.VibrationEffect
import android.os.VibratorManager
import android.util.Log
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * The page-turn sound and haptic, as PageTurnFeedback on iOS. The sound is
 * the same recording at five loudness levels (Genesis/Resources/Sounds,
 * page-turn-1…5.caf, shared with iOS); Android can't play CAF, so its
 * 16-bit PCM is wrapped as WAV in the cache the first time. The haptic is a
 * short tick at the chosen strength.
 */
class PageTurnFeedback(private val context: Context) {
    private val pool = SoundPool.Builder()
        .setMaxStreams(2)
        .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
        .build()
    private val loaded = mutableMapOf<Int, Int>()

    /** Plays the sound at the level for this volume (0, 0.25 … 1 picks one of five recordings). */
    fun playSound(volume: Double) {
        val level = (volume * 4).toInt().coerceIn(0, 4) + 1
        val id = loaded[level] ?: load(level)?.also { loaded[level] = it } ?: return
        // The first play after loading may be silent while SoundPool decodes; later turns play.
        pool.play(id, 1f, 1f, 1, 0, 1f)
    }

    fun haptic(strength: Double) {
        val vibrator = context.getSystemService(VibratorManager::class.java)?.defaultVibrator ?: return
        if (!vibrator.hasVibrator()) return
        val amplitude = (strength.coerceIn(0.0, 1.0) * 255).toInt().coerceIn(1, 255)
        runCatching { vibrator.vibrate(VibrationEffect.createOneShot(14, if (vibrator.hasAmplitudeControl()) amplitude else VibrationEffect.DEFAULT_AMPLITUDE)) }
    }

    private fun load(level: Int): Int? = runCatching {
        val wav = File(context.cacheDir, "page-turn-$level.wav")
        if (!wav.exists()) {
            val caf = context.assets.open("page-turn-$level.caf").use { it.readBytes() }
            wav.writeBytes(cafToWav(caf))
        }
        pool.load(wav.path, 1)
    }.onFailure { Log.w("PageTurnFeedback", "Couldn't load the page-turn sound", it) }.getOrNull()

    companion object {
        /** A CAF file of linear PCM (as make_page_turn.py writes) as a WAV file. */
        internal fun cafToWav(caf: ByteArray): ByteArray {
            val input = ByteBuffer.wrap(caf).order(ByteOrder.BIG_ENDIAN)
            require(String(caf, 0, 4, Charsets.US_ASCII) == "caff") { "Not a CAF file" }
            input.position(8)
            var sampleRate = 44_100.0
            var channels = 1
            var bits = 16
            var littleEndian = true
            var data: ByteArray? = null
            while (input.remaining() >= 12) {
                val type = ByteArray(4).also { input.get(it) }.toString(Charsets.US_ASCII)
                val size = input.long
                val start = input.position()
                when (type) {
                    "desc" -> {
                        sampleRate = input.double
                        input.int // format id ("lpcm")
                        val flags = input.int
                        input.int // bytes per packet
                        input.int // frames per packet
                        channels = input.int
                        bits = input.int
                        littleEndian = flags and 2 != 0
                    }
                    "data" -> {
                        input.int // edit count
                        val length = if (size < 0) input.remaining() else (size - 4).toInt()
                        data = ByteArray(length).also { input.get(it) }
                    }
                }
                if (size < 0) break
                input.position(start + size.toInt())
            }
            var pcm = requireNotNull(data) { "No audio in the CAF file" }
            if (!littleEndian && bits == 16) pcm = pcm.copyOf().also { for (i in 0 until it.size - 1 step 2) { val t = it[i]; it[i] = it[i + 1]; it[i + 1] = t } }
            val out = ByteBuffer.allocate(44 + pcm.size).order(ByteOrder.LITTLE_ENDIAN)
            out.put("RIFF".toByteArray()).putInt(36 + pcm.size).put("WAVE".toByteArray())
            out.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(channels.toShort()).putInt(sampleRate.toInt())
                .putInt(sampleRate.toInt() * channels * bits / 8).putShort((channels * bits / 8).toShort()).putShort(bits.toShort())
            out.put("data".toByteArray()).putInt(pcm.size).put(pcm)
            return out.array()
        }
    }
}
