package app.winters.octo.covers

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred

// How many covers that are not urgent download at once.
const val COVER_LANES = 4

// Decides when each cover download goes to the server. The covers the
// player shows now and next are urgent: they go at once, past any queue.
// Every other cover waits for one of a few lanes, newest ask first, since
// the newest is the one most likely still on screen. An ask whose picture
// went away (its coroutine cancelled) leaves the queue, and one waiting
// for a cover that turns urgent goes at once.
class CoverLanes(private val lanes: Int = COVER_LANES) {
    private class Turn(val cover: String) {
        val go = CompletableDeferred<Unit>()

        // Whether the turn holds a lane, once it may go.
        var lane = false
    }

    private val lock = Any()
    private val waiting = ArrayList<Turn>()
    private var busy = 0

    @Volatile private var urgent: Set<String> = emptySet()

    fun isUrgent(cover: String): Boolean = cover in urgent

    // The covers the player shows now and next, replacing those before.
    fun setUrgent(covers: Collection<String>) {
        val now = covers.toSet()
        synchronized(lock) {
            urgent = now
            val hurried = waiting.filter { it.cover in now }
            waiting.removeAll(hurried.toSet())
            hurried.forEach { it.go.complete(Unit) }
        }
    }

    // Runs `download` for `cover` when its turn comes.
    suspend fun <T> pass(cover: String, download: suspend () -> T): T {
        val turn = Turn(cover)
        synchronized(lock) {
            when {
                cover in urgent -> turn.go.complete(Unit)
                busy < lanes -> {
                    busy++
                    turn.lane = true
                    turn.go.complete(Unit)
                }
                else -> waiting += turn
            }
        }
        try {
            turn.go.await()
        } catch (e: CancellationException) {
            // Still waiting: it simply leaves. Given a lane meanwhile: the
            // lane goes to the next.
            val held = synchronized(lock) { !waiting.remove(turn) && turn.lane }
            if (held) release()
            throw e
        }
        try {
            return download()
        } finally {
            if (turn.lane) release()
        }
    }

    private fun release() {
        synchronized(lock) {
            val next = waiting.removeLastOrNull()
            if (next == null) {
                busy--
            } else {
                next.lane = true
                next.go.complete(Unit)
            }
        }
    }

    // How many asks wait for a lane.
    internal val queued: Int get() = synchronized(lock) { waiting.size }
}

// How many times an ask waits for another download of its cover before it
// downloads the cover itself.
private const val MAX_WAITS = 3

// Downloads of covers under way, so a cover is downloaded once however many
// places ask for it at once: an ask waits for a download of the same cover
// at its size or larger, then reads the copy that download kept.
class CoverDownloads {
    private class Running(val bucket: Int) {
        val done = CompletableDeferred<Unit>()
    }

    private val lock = Any()
    private val running = HashMap<String, MutableList<Running>>()

    // A kept copy of `cover` answering an ask at `bucket` (`kept`), else a
    // download of it at `bucket`. Null when neither gives one.
    suspend fun <T : Any> get(cover: String, bucket: Int, kept: suspend () -> T?, download: suspend () -> T?): T? {
        var waits = 0
        while (true) {
            kept()?.let { return it }
            val mine = Running(bucket)
            val ahead = synchronized(lock) {
                val found = if (waits < MAX_WAITS) running[cover]?.firstOrNull { it.bucket >= bucket } else null
                if (found == null) running.getOrPut(cover) { ArrayList() } += mine
                found
            }
            if (ahead == null) return run(cover, mine, download)
            ahead.done.await()
            waits++
        }
    }

    private suspend fun <T : Any> run(cover: String, mine: Running, download: suspend () -> T?): T? {
        try {
            return download()
        } finally {
            synchronized(lock) {
                running[cover]?.let { list ->
                    list.remove(mine)
                    if (list.isEmpty()) running.remove(cover)
                }
            }
            mine.done.complete(Unit)
        }
    }
}
