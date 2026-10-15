package app.winters.octo.player

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf

// The frames something on screen already draws over and over (the moving
// background), offered to slower things that move with them (a progress
// line), so those step on the same frames instead of waking the window on
// frames of their own. Used on the main thread.
class FrameTicker {
    private val listeners = mutableListOf<(Long) -> Unit>()

    // Whether frames are coming: while they are, listeners take their steps
    // from them.
    var running by mutableStateOf(false)

    // Called from inside a frame, with its time, by what draws the frames.
    fun tick(nanos: Long) {
        for (i in listeners.indices.reversed()) listeners.getOrNull(i)?.invoke(nanos)
    }

    fun listen(listener: (Long) -> Unit): () -> Unit {
        listeners += listener
        return { listeners -= listener }
    }
}

val LocalFrameTicker = staticCompositionLocalOf<FrameTicker?> { null }
