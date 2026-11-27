package com.genesis.core.domain.bible

/** How a translation renders the original languages (TranslationApproach on iOS; ids are the catalog's). */
enum class TranslationApproach(val id: String) {
    WORD_FOR_WORD("word_for_word"), BALANCED("balanced"), THOUGHT_FOR_THOUGHT("thought_for_thought");

    companion object { fun of(id: String?): TranslationApproach? = entries.firstOrNull { it.id == id } }
}

/** How a translation reads. */
enum class ReadingLevel(val id: String) {
    TRADITIONAL("traditional"), FORMAL("formal"), EVERYDAY("everyday");

    companion object { fun of(id: String?): ReadingLevel? = entries.firstOrNull { it.id == id } }
}

/** What each way of reading is best served by ("Which Bible is right for me?"). */
enum class ReadingPurpose { STUDY, EVERYDAY, CLASSIC }

/**
 * What the Bibles screen tells people about a translation, as
 * TranslationProfile.swift. Each part may be unknown; the catalog's values
 * win over what the app knows.
 */
data class TranslationProfile(
    val approach: TranslationApproach? = null,
    val readingLevel: ReadingLevel? = null,
    /** 1 = most read in its language. */
    val popularity: Int? = null,
) {
    fun filling(other: TranslationProfile?): TranslationProfile =
        if (other == null) this else TranslationProfile(approach ?: other.approach, readingLevel ?: other.readingLevel, popularity ?: other.popularity)

    companion object {
        /** What the app knows without the server (the bundled Bibles and today's downloads). */
        val builtIn: Map<String, TranslationProfile> = mapOf(
            "KJV" to TranslationProfile(TranslationApproach.WORD_FOR_WORD, ReadingLevel.TRADITIONAL, 1),
            "BSB" to TranslationProfile(TranslationApproach.BALANCED, ReadingLevel.EVERYDAY, 2),
            "WEB" to TranslationProfile(TranslationApproach.WORD_FOR_WORD, ReadingLevel.EVERYDAY, 3),
            "ASV" to TranslationProfile(TranslationApproach.WORD_FOR_WORD, ReadingLevel.TRADITIONAL, 4),
            "RV1909" to TranslationProfile(TranslationApproach.WORD_FOR_WORD, ReadingLevel.TRADITIONAL, 1),
        )

        fun of(item: DownloadableBible?, id: String): TranslationProfile =
            TranslationProfile(TranslationApproach.of(item?.approach), ReadingLevel.of(item?.readingLevel), item?.popularity).filling(builtIn[id])

        /** The best Bible for a way of reading; `bibles` is most read first, so the first best score wins ties. */
        fun <T> suggestion(purpose: ReadingPurpose, bibles: List<Pair<T, TranslationProfile>>): T? =
            bibles.mapNotNull { (bible, profile) -> score(profile, purpose)?.let { bible to it } }.minByOrNull { it.second }?.first

        /** Lower is better; null means it doesn't suit the purpose. */
        private fun score(profile: TranslationProfile, purpose: ReadingPurpose): Int? {
            val approach = profile.approach ?: return null
            val level = profile.readingLevel ?: return null
            return when (purpose) {
                ReadingPurpose.STUDY -> if (approach != TranslationApproach.WORD_FOR_WORD) null
                else listOf(ReadingLevel.EVERYDAY, ReadingLevel.FORMAL, ReadingLevel.TRADITIONAL).indexOf(level)
                ReadingPurpose.EVERYDAY -> if (level != ReadingLevel.EVERYDAY) null
                else listOf(TranslationApproach.BALANCED, TranslationApproach.THOUGHT_FOR_THOUGHT, TranslationApproach.WORD_FOR_WORD).indexOf(approach)
                ReadingPurpose.CLASSIC -> if (level == ReadingLevel.TRADITIONAL) 0 else null
            }
        }
    }
}
