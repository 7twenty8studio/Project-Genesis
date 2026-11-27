package com.genesis.app.settings

import android.app.LocaleManager
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import java.util.Locale

/**
 * Settings › Language, as AppLanguageChoice on iOS: the phone's language,
 * English, Español or Português (Brazil). Android 13 and later keep the
 * choice as the app's own language (the same one Android's Settings › Apps ›
 * Versely › Language sets); on Android 12 Versely keeps it and applies it to
 * its screens itself.
 */
enum class AppLanguageChoice(val tag: String?) {
    SYSTEM(null),
    ENGLISH("en"),
    SPANISH("es"),
    PORTUGUESE("pt-BR");

    /** A language's own name, never translated. */
    val nativeName: String?
        get() = when (this) {
            SYSTEM -> null
            ENGLISH -> "English"
            SPANISH -> "Español"
            PORTUGUESE -> "Português"
        }

    companion object {
        private const val PREFS = "language"
        private const val KEY = "app.language"

        fun of(tag: String?): AppLanguageChoice {
            val language = tag?.let(Locale::forLanguageTag)?.language ?: return SYSTEM
            return entries.firstOrNull { it.tag != null && Locale.forLanguageTag(it.tag).language == language } ?: SYSTEM
        }

        fun saved(context: Context): AppLanguageChoice =
            if (Build.VERSION.SDK_INT >= 33) {
                val locales = context.getSystemService(LocaleManager::class.java).applicationLocales
                if (locales.isEmpty) SYSTEM else of(locales[0].toLanguageTag())
            } else {
                of(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null))
            }

        /** Saves the choice; Android 13+ redraws the screens itself, Android 12 needs a recreate. */
        fun save(context: Context, choice: AppLanguageChoice) {
            if (Build.VERSION.SDK_INT >= 33) {
                context.getSystemService(LocaleManager::class.java).applicationLocales =
                    choice.tag?.let(LocaleList::forLanguageTags) ?: LocaleList.getEmptyLocaleList()
            } else {
                context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, choice.tag).apply()
            }
        }

        /** Android 12: the activity's resources in the chosen language. */
        fun wrap(base: Context): Context {
            if (Build.VERSION.SDK_INT >= 33) return base
            val tag = base.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return base
            val locale = Locale.forLanguageTag(tag)
            Locale.setDefault(locale)
            val configuration = Configuration(base.resources.configuration).apply { setLocales(LocaleList(locale)) }
            return base.createConfigurationContext(configuration)
        }
    }
}
