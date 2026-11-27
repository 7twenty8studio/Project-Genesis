package com.genesis.core.domain.audio

/**
 * A background sound to read and pray with, as AmbientSound.swift. Each is
 * a seamless loop shared with iOS (Genesis/Resources/Ambient/ambient-<id>.m4a,
 * built by Tools/Ambient/make_ambient.py; credits in AmbientCredits.txt).
 */
enum class AmbientSound(val id: String, val loopSeconds: Double, val defaultVolume: Float) {
    RAIN("rain", 90.0, 0.8f),
    WAVES("waves", 96.0, 0.8f),
    WIND("wind", 100.0, 0.6f),
    FIREPLACE("fireplace", 120.0, 0.8f),
    BIRDSONG("birdsong", 180.0, 0.6f),
    PAD("pad", 120.0, 0.7f);

    /** The bundled file's name. */
    val fileName: String get() = "ambient-$id.m4a"

    companion object {
        fun withId(id: String): AmbientSound? = entries.firstOrNull { it.id == id }
    }
}

/** A ready-made blend of sounds. */
data class AmbientMix(val id: String, val volumes: Map<AmbientSound, Float>) {
    companion object {
        val all = listOf(
            AmbientMix("quiet-rain", mapOf(AmbientSound.RAIN to 0.8f)),
            AmbientMix("fireside", mapOf(AmbientSound.FIREPLACE to 0.85f, AmbientSound.RAIN to 0.35f)),
            AmbientMix("garden", mapOf(AmbientSound.BIRDSONG to 0.65f, AmbientSound.WIND to 0.3f)),
            AmbientMix("seaside", mapOf(AmbientSound.WAVES to 0.8f, AmbientSound.WIND to 0.25f)),
            AmbientMix("sanctuary", mapOf(AmbientSound.PAD to 0.7f, AmbientSound.RAIN to 0.25f)),
        )

        /** The ready-made mix this is exactly, if any. */
        fun matching(mix: Map<AmbientSound, Float>): AmbientMix? = all.firstOrNull { it.volumes == mix }
    }
}

/** The rules AmbientSoundService.swift keeps, pure. */
object AmbientRules {
    val timerChoices = listOf(15, 30, 45, 60, 90)
    const val DUCK_FACTOR = 0.45f

    /** The volume a sound plays at: quieter while the Bible is read aloud. */
    fun effective(volume: Float, ducked: Boolean): Float = if (ducked) volume * DUCK_FACTOR else volume

    /** The mix saved as "rain=0.8,wind=0.3". */
    fun encode(mix: Map<AmbientSound, Float>): String =
        mix.entries.sortedBy { it.key.ordinal }.joinToString(",") { "${it.key.id}=${it.value}" }

    /** A saved mix, ignoring anything unknown and clamping volumes to 0...1. */
    fun decode(text: String?): Map<AmbientSound, Float> =
        text.orEmpty().split(',').mapNotNull { part ->
            val (id, value) = part.split('=').takeIf { it.size == 2 } ?: return@mapNotNull null
            val sound = AmbientSound.withId(id.trim()) ?: return@mapNotNull null
            val volume = value.trim().toFloatOrNull() ?: return@mapNotNull null
            sound to volume.coerceIn(0f, 1f)
        }.toMap()

    /** Adds the sound at its starting volume, or takes it out. */
    fun toggle(mix: Map<AmbientSound, Float>, sound: AmbientSound): Map<AmbientSound, Float> =
        if (sound in mix) mix - sound else mix + (sound to sound.defaultVolume)
}
