package com.genesis.app.push

import android.content.Context
import android.util.Log
import com.genesis.app.BuildConfig
import com.genesis.app.VerselyApplication
import com.genesis.core.cloud.Timestamps
import com.genesis.core.domain.notifications.ReminderKind
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.messaging.FirebaseMessaging
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext

/**
 * Group announcements and nudges on Android, as PushNotifications on iOS:
 * the phone is registered with Firebase Cloud Messaging (its token saved in
 * public.android_push_tokens) while Group Announcements or Nudges from
 * Friends is wanted, and which of the two arrive is kept on the server
 * (profiles.accepts_announcements / accepts_nudges), so group-notify sends
 * only what the person chose. Off until the Firebase project exists
 * (FIREBASE_* in local.properties, android/PLAY_SETUP.md); reminders are
 * local and never need it.
 */
object AndroidPush {
    private const val TAG = "AndroidPush"
    private const val PREFS = "push"
    private const val SAVED_TOKEN = "token"
    private const val SAVED_USER = "user"

    val isConfigured: Boolean
        get() = BuildConfig.FIREBASE_APP_ID.isNotBlank() && BuildConfig.FIREBASE_API_KEY.isNotBlank() &&
            BuildConfig.FIREBASE_PROJECT_ID.isNotBlank() && BuildConfig.FIREBASE_SENDER_ID.isNotBlank()

    /** Starts Firebase from the build's settings (no google-services.json); false when it isn't set up. */
    fun start(context: Context): Boolean {
        if (!isConfigured) return false
        if (FirebaseApp.getApps(context).isEmpty()) {
            val options = FirebaseOptions.Builder()
                .setApplicationId(BuildConfig.FIREBASE_APP_ID)
                .setApiKey(BuildConfig.FIREBASE_API_KEY)
                .setProjectId(BuildConfig.FIREBASE_PROJECT_ID)
                .setGcmSenderId(BuildConfig.FIREBASE_SENDER_ID)
                .build()
            runCatching { FirebaseApp.initializeApp(context, options) }.onFailure { Log.w(TAG, "Firebase didn't start", it); return false }
        }
        return true
    }

    /**
     * Brings the server in line with the person's choices: the two switches
     * on their profile, and this phone's token while either is wanted
     * (removed when neither is, or after signing out). Best effort: it runs
     * again on the next launch, sign-in and settings change.
     */
    suspend fun sync(app: VerselyApplication, newToken: String? = null) {
        val prefs = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val api = app.community.api
        val user = app.account.state.value.user?.id?.lowercase()
        val settings = app.notifications.state.value
        val announcements = settings.allows(ReminderKind.GROUPS)
        val nudges = settings.allows(ReminderKind.NUDGES)
        withContext(Dispatchers.IO) {
            if (api == null || user == null) {
                prefs.edit().remove(SAVED_TOKEN).remove(SAVED_USER).apply()
                return@withContext
            }
            runCatching { api.setAcceptsAnnouncements(announcements) }
            runCatching { api.setAcceptsNudges(nudges) }
            if (!start(app)) return@withContext
            val wanted = announcements || nudges
            val saved = prefs.getString(SAVED_TOKEN, null)
            val token = newToken ?: if (wanted) runCatching { FirebaseMessaging.getInstance().token.await() }.getOrNull() else saved
            if (token == null) return@withContext
            if (wanted) {
                if (saved != null && saved != token) runCatching { api.removeAndroidPushToken(saved) }
                runCatching { api.registerAndroidPushToken(token, Timestamps.string(System.currentTimeMillis())) }
                    .onSuccess { prefs.edit().putString(SAVED_TOKEN, token).putString(SAVED_USER, user).apply() }
                    .onFailure { Log.w(TAG, "Couldn't save the push token", it) }
            } else if (saved != null) {
                runCatching { api.removeAndroidPushToken(saved) }
                    .onSuccess { prefs.edit().remove(SAVED_TOKEN).remove(SAVED_USER).apply() }
            }
        }
    }
}
