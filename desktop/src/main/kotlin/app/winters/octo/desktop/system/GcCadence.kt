package app.winters.octo.desktop.system

import app.winters.octo.desktop.player.DesktopPlayer
import kotlinx.coroutines.delay

// Set to milliseconds, a collection of the Java heap is asked for that
// often while music plays (with -XX:+ExplicitGCInvokesConcurrent, one that
// runs beside the app). Skia's images and the engine's objects are small
// on the heap and large outside it, and what they hold outside goes back
// only once a collection finds them gone.
const val COLLECT_EVERY = "octo.collectEveryMs"

suspend fun collectWhilePlaying(player: DesktopPlayer, everyMs: Long) {
    while (true) {
        delay(everyMs)
        if (player.state.value.playing) System.gc()
    }
}
