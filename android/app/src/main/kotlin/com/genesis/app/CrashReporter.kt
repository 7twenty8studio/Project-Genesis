package com.genesis.app

import android.content.Context
import android.util.Log
import io.sentry.Sentry
import io.sentry.android.core.SentryAndroid

/**
 * Crash and error reporting through Sentry, as CrashReporter on iOS: the same
 * project, no performance tracing, no session replay, no personal data. Off
 * when the build has no DSN. Never include Scripture, notes or journal text.
 */
object CrashReporter {
    private const val TAG = "Versely"

    fun start(context: Context) {
        val dsn = BuildConfig.SENTRY_DSN
        if (dsn.isBlank()) {
            Log.i(TAG, "Sentry DSN not configured; crash reporting is off.")
            return
        }
        SentryAndroid.init(context) { options ->
            options.dsn = dsn
            options.isSendDefaultPii = false
            options.tracesSampleRate = null
            options.isEnableAutoSessionTracking = true
            options.isAttachScreenshot = false
            options.isAttachViewHierarchy = false
            options.environment = if (BuildConfig.DEBUG) "debug" else "production"
            options.setTag("platform", "android")
        }
    }

    /** Records a non-fatal error with where it happened. */
    fun record(error: Throwable, context: String) {
        Log.e(TAG, context, error)
        Sentry.captureException(error) { scope -> scope.setTag("context", context) }
    }
}
