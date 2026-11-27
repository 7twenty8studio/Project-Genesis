package com.genesis.app.settings

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import com.genesis.core.domain.theme.AppIconChoice

/**
 * The home screen icon, as AppIconSettings on iOS. Android has no alternate
 * icons, so each icon is an activity-alias in the manifest (AppIconStandard,
 * AppIconNight…) and only the shown one is enabled. Seasons is applied again
 * whenever Versely opens, so it changes with the calendar; without Premium
 * the standard icon comes back, keeping the choice.
 */
object AppIcons {
    private const val PREFS = "app_icon"
    private const val KEY = "choice"

    fun choice(context: Context): AppIconChoice =
        AppIconChoice.of(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null))

    fun choose(context: Context, choice: AppIconChoice) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, choice.rawValue).apply()
        apply(context)
    }

    /** Enables the alias for the icon shown today and disables the rest. */
    fun apply(context: Context, premium: Boolean = Entitlements.isPremium) {
        val shown = choice(context).shown(premium).icon()
        val manager = context.packageManager
        // Enable the new one first, so there is never a moment with no launcher entry.
        val ordered = AppIconChoice.entries.filter { it != AppIconChoice.SEASONS }.sortedBy { it != shown }
        for (icon in ordered) {
            val component = component(context, icon)
            val wanted = if (icon == shown) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            val current = manager.getComponentEnabledSetting(component)
            val isOn = current == PackageManager.COMPONENT_ENABLED_STATE_ENABLED ||
                (current == PackageManager.COMPONENT_ENABLED_STATE_DEFAULT && icon == AppIconChoice.STANDARD)
            if (isOn == (icon == shown)) continue
            runCatching { manager.setComponentEnabledSetting(component, wanted, PackageManager.DONT_KILL_APP) }
        }
    }

    private fun component(context: Context, icon: AppIconChoice): ComponentName {
        val name = icon.rawValue.replaceFirstChar { it.uppercase() }
        return ComponentName(context.packageName, "com.genesis.app.AppIcon$name")
    }
}
