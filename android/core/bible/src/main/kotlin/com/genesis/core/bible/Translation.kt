package com.genesis.core.bible

/**
 * A Bible translation. The bundled ones are public domain (KJV, WEB, ASV)
 * plus the owner-approved Bíblia Livre (CC BY 4.0 Brasil, credit kept under
 * every chapter). Name, language and licence come from the file's own
 * `meta` table, so they always match the text.
 */
data class Translation(
    val id: String,
    val name: String,
    val abbreviation: String,
    val language: String,
    val license: String,
    val year: String?,
) {
    /** True for anything that isn't public domain: its notice shows under every chapter. */
    val showsLicenseUnderChapters: Boolean
        get() = license != "Public domain" && license != "Dominio público" && !license.startsWith("Public domain.")
}

/** The Bibles inside the app, as asset files. */
enum class BundledBible(val id: String, val asset: String) {
    KJV("KJV", "KJV.sqlite"),
    WEB("WEB", "WEB.sqlite"),
    ASV("ASV", "ASV.sqlite"),
    BLIVRE("BLIVRE", "BLIVRE.sqlite");

    companion object {
        /** The first Bible on a new phone: the Bíblia Livre in Portuguese, else the KJV (setup offers more in phase 2). */
        fun default(language: String): BundledBible = if (language.startsWith("pt")) BLIVRE else KJV
    }
}
