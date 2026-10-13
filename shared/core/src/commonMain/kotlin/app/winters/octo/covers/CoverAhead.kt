package app.winters.octo.covers

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.launch

// How many songs after the one playing have their covers fetched ahead.
const val COVERS_AHEAD = 2

// How many covers fetched ahead are remembered, so they are not fetched again.
private const val REMEMBERED = 64

// Fetches the covers the player shows now and next, all at once, and marks
// them urgent in `lanes` so they never wait behind other covers. Each
// `want` replaces the covers wanted before: a fetch for a cover no longer
// wanted stops. A cover fetched lately is not fetched again. `urgentKey`
// is what `lanes` knows a cover by.
class CoverAhead(
    private val scope: CoroutineScope,
    private val lanes: CoverLanes? = null,
    private val urgentKey: (String) -> String = { it },
    private val fetch: suspend (String) -> Unit,
) {
    private val lock = Any()
    private val running = HashMap<String, Job>()
    private val done = object : LinkedHashMap<String, Unit>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Unit>?) = size > REMEMBERED
    }

    // The covers to have, the playing song's first.
    fun want(covers: List<String>) {
        val wanted = covers.distinct()
        lanes?.setUrgent(wanted.map(urgentKey))
        synchronized(lock) {
            running.keys.filter { it !in wanted }.forEach { running.remove(it)?.cancel() }
            for (cover in wanted) {
                if (cover in done || cover in running) continue
                val job = scope.launch(start = CoroutineStart.LAZY) { fetchOne(cover) }
                running[cover] = job
                job.start()
            }
        }
    }

    // Stops every fetch and leaves nothing urgent.
    fun stop() {
        lanes?.setUrgent(emptyList())
        synchronized(lock) {
            running.values.forEach { it.cancel() }
            running.clear()
        }
    }

    private suspend fun fetchOne(cover: String) {
        val me = currentCoroutineContext()[Job]
        val fetched = try {
            fetch(cover)
            true
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            // Left for the next change to try again.
            false
        } finally {
            synchronized(lock) { if (running[cover] === me) running.remove(cover) }
        }
        if (fetched) synchronized(lock) { done[cover] = Unit }
    }
}
