package app.winters.octo.desktop.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.withFrameNanos
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

// How long a frame is waited for before it counts as drawn anyway: a
// hidden or minimized window draws none, and draws nothing old either.
private const val FrameWaitMs = 1_000L

// Skia images, shaders and pictures that were replaced while a frame may
// still draw them: each one waiting here is closed once a whole frame has
// been drawn since it was put here, so its native memory goes back at once
// rather than whenever the Java heap is next collected in full. Closing one
// that a frame still draws ends the app, so nothing is closed sooner. Any
// thread may hand them in; the window closes them (see FollowLateCloses),
// and without a window to follow they close after a moment.
object LateClose {
    private class Waiting(val thing: AutoCloseable, val frame: Long, val at: Long)

    private val waiting = ConcurrentLinkedQueue<Waiting>()
    private val frames = AtomicLong()
    private val arrived = Channel<Unit>(Channel.CONFLATED)

    @Volatile private var followed = false

    // Closes what waited a second while no window follows frames.
    private val timer: ScheduledExecutorService by lazy {
        Executors.newSingleThreadScheduledExecutor { task -> Thread(task, "Octo late close").apply { isDaemon = true } }
    }

    // Hands `thing` in to be closed after the next whole frame.
    fun close(thing: AutoCloseable?) {
        thing ?: return
        waiting.add(Waiting(thing, frames.get(), System.nanoTime()))
        arrived.trySend(Unit)
        if (!followed) timer.schedule({ if (!followed) closeOverdue() }, FrameWaitMs + 10, TimeUnit.MILLISECONDS)
    }

    // How many wait to be closed, for the tests.
    val count: Int get() = waiting.size

    // Counts one frame drawn, and closes what waited through a whole one.
    fun frameDrawn() {
        val now = frames.incrementAndGet()
        while (true) {
            val first = waiting.peek() ?: break
            if (first.frame > now - 2) break
            if (waiting.remove(first)) runCatching { first.thing.close() }
        }
    }

    // Without a window following frames: what has waited a second.
    private fun closeOverdue() {
        val due = System.nanoTime() - FrameWaitMs * 1_000_000
        while (true) {
            val first = waiting.peek() ?: break
            if (first.at > due) break
            if (waiting.remove(first)) runCatching { first.thing.close() }
        }
    }

    // Asks for frames only while something waits, so a still window is not
    // drawn again for this.
    internal suspend fun follow() {
        followed = true
        try {
            while (true) {
                arrived.receive()
                while (waiting.isNotEmpty()) {
                    withTimeoutOrNull(FrameWaitMs) { withFrameNanos { } }
                    frameDrawn()
                }
            }
        } finally {
            followed = false
        }
    }
}

// A Skia object the window draws and other threads may work from too: it
// closes (through LateClose) once the window has let it go and no other
// thread is still using it.
class Shared<T : AutoCloseable>(val thing: T) {
    private var users = 1

    // Runs `block` with the object unless it was let go already.
    fun <R> use(block: (T) -> R): R? {
        synchronized(this) {
            if (users == 0) return null
            users++
        }
        try {
            return block(thing)
        } finally {
            release()
        }
    }

    // The window lets go of it.
    fun release() {
        val last = synchronized(this) {
            if (users == 0) return
            --users == 0
        }
        if (last) LateClose.close(thing)
    }
}

// Closes what LateClose holds as this window draws.
@Composable
fun FollowLateCloses() {
    LaunchedEffect(Unit) { LateClose.follow() }
}
