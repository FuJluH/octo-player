package app.winters.octo.animated

import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import app.winters.octo.player.rememberPowerSave
import app.winters.octo.ui.common.LocalReduceMotion

// Whether the full player covers the pages, so a loop on a page is out of
// sight while it is open.
val LocalPlayerCovers = compositionLocalOf { false }

// What a loop on screen does now: `inView` says whether its own view can
// be seen (the player fully open, the page in front); the app must be in
// front with the screen on too. It holds while the phone saves power, and
// only the still shows with Reduce motion (Octo's or the phone's).
@Composable
fun rememberLoopPlay(inView: Boolean): LoopPlay {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val state by lifecycle.currentStateAsState()
    val front = state.isAtLeast(Lifecycle.State.STARTED)
    return loopPlay(seen = inView && front, powerSave = rememberPowerSave(), reduceMotion = LocalReduceMotion.current)
}
