package com.genesis.app.reader.backdrop

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState

/** Android's Remove Animations (animator scale 0), the counterpart of iOS's Reduce Motion. */
@Composable
internal fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember { Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
}

/** Battery Saver, followed as it changes (iOS's Low Power Mode). */
@Composable
internal fun rememberPowerSave(): Boolean {
    val context = LocalContext.current
    val power = remember { context.getSystemService(PowerManager::class.java) }
    var saving by remember { mutableStateOf(power?.isPowerSaveMode == true) }
    DisposableEffect(power) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) { saving = power?.isPowerSaveMode == true }
        }
        context.registerReceiver(receiver, IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED))
        onDispose { context.unregisterReceiver(receiver) }
    }
    return saving
}

/** True while the app is in front (motion never runs behind another app). */
@Composable
internal fun rememberResumed(): Boolean {
    val state by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    return state.isAtLeast(Lifecycle.State.RESUMED)
}

/**
 * Seconds since the backdrop appeared, moved on only every `interval(time)`
 * seconds (20 or 30 frames a second, 60 only while something quick passes),
 * and held while `running` is false, so a paused sky resumes where it was.
 */
@Composable
internal fun rememberMotionTime(running: Boolean, interval: (Double) -> Double): State<Double> {
    val clock = remember { MotionClock() }
    return produceState(clock.time, running) {
        if (!running) return@produceState
        var origin = -1L
        val base = clock.time
        var last = base
        while (true) {
            withFrameNanos { now ->
                if (origin < 0) origin = now
                val time = base + (now - origin) / 1e9
                if (time - last >= interval(time)) {
                    last = time
                    clock.time = time
                    value = time
                }
            }
        }
    }
}

private class MotionClock { var time = 0.0 }
