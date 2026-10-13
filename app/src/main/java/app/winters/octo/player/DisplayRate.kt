package app.winters.octo.player

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import android.view.Display
import android.view.Window
import androidx.activity.compose.LocalActivity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.FrameRateCategory
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.preferredFrameRate
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState

// Asks the display for the refresh rate `needHz` calls for (see
// `playerRefreshNeed`) while the app is in view, and gives the request back
// when the need drops, the app leaves the screen, or this leaves the
// composition.
//
// The window's preferred display mode is the request that phones honor
// from Android 10 on, including skins that otherwise hold apps at 60 Hz;
// the preferred rate beside it is for skins that read only that. Android 15
// and later also take a per-layer vote, given by `displayRateModifier`.
@Composable
fun RequestDisplayRate(needHz: Float) {
    val window = LocalActivity.current?.window
    val view = LocalView.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val state by lifecycle.currentStateAsState()
    val inView = state.isAtLeast(Lifecycle.State.STARTED)
    DisposableEffect(window, view, needHz, inView) {
        val display = view.display
        val modeId = if (window != null && display != null && inView) displayModeFor(display, needHz) else null
        if (window == null || modeId == null) return@DisposableEffect onDispose { }
        val rate = display.supportedModes.first { it.modeId == modeId }.refreshRate
        val before = window.attributes
        val heldId = before.preferredDisplayModeId
        val heldRate = before.preferredRefreshRate
        window.setPreferredMode(modeId, rate)
        onDispose { window.setPreferredMode(heldId, heldRate) }
    }
}

// The per-layer frame rate vote for the same need, for the player's root.
// Android 15 and later apply it only while the layers under it draw, so a
// still screen still slows down; earlier versions ignore it.
fun Modifier.displayRateModifier(needHz: Float): Modifier = when {
    needHz <= 0f -> this
    needHz.isInfinite() -> preferredFrameRate(FrameRateCategory.High)
    else -> preferredFrameRate(needHz)
}

private fun Window.setPreferredMode(modeId: Int, rate: Float) {
    val params = attributes
    if (params.preferredDisplayModeId == modeId && params.preferredRefreshRate == rate) return
    params.preferredDisplayModeId = modeId
    params.preferredRefreshRate = rate
    attributes = params
}

private fun displayModeFor(display: Display, needHz: Float): Int? {
    val current = display.mode.toScreenMode()
    val seamless = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) display.mode.alternativeRefreshRates.toList() else emptyList()
    return pickScreenMode(display.supportedModes.map { it.toScreenMode() }, current, seamless, needHz)
}

private fun Display.Mode.toScreenMode() = ScreenMode(modeId, physicalWidth, physicalHeight, refreshRate)

// Whether battery saver is on, kept up to date while shown.
@Composable
fun rememberPowerSave(): Boolean {
    val context = LocalContext.current
    val power = remember(context) { context.getSystemService(PowerManager::class.java) }
    var on by remember { mutableStateOf(power?.isPowerSaveMode == true) }
    DisposableEffect(context, power) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                on = power?.isPowerSaveMode == true
            }
        }
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(PowerManager.ACTION_POWER_SAVE_MODE_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        onDispose { context.unregisterReceiver(receiver) }
    }
    return on
}
