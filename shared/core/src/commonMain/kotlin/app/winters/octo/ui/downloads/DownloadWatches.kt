package app.winters.octo.ui.downloads

import app.winters.octo.subsonic.Acquisition
import app.winters.octo.subsonic.AcquisitionStage
import app.winters.octo.subsonic.FoundCandidate
import app.winters.octo.subsonic.FoundSongs
import app.winters.octo.subsonic.PICK_SKIPPED
import app.winters.octo.subsonic.PickResult
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.Upgrade
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

// How often the drawer's list is asked for: while it is open, while
// something runs (so its button can show it), and otherwise, to notice a
// download started somewhere else.
const val DOWNLOADS_OPEN_POLL_MS = 2_000L
const val DOWNLOADS_RUNNING_POLL_MS = 3_000L
const val DOWNLOADS_IDLE_POLL_MS = 30_000L

// How often an open log, and a running Find songs search, are asked for.
const val LOG_POLL_MS = 1_500L
const val FIND_POLL_MS = 1_500L

// How long a finished download's log is still asked for: its lyrics are
// looked for once the song is in, and their line comes a little after.
const val LOG_FINISHED_GRACE_MS = 60_000L

// What following the drawer needs from the app: the server's two lists.
interface DownloadsSource {
    // The downloads, or throws when the server cannot be asked now.
    suspend fun acquisitions(): List<Acquisition>

    // The higher quality copies asked for, or an empty list on a server
    // that cannot look for them.
    suspend fun upgrades(): List<Upgrade>

    // Takes finished downloads off the list on the server, or one by key.
    suspend fun clear(key: String?)
}

// Follows the drawer's rows for one server, for as long as it is started.
// Not tied to any thread: the rows are a StateFlow and every change goes
// through it.
class DownloadsWatch(
    private val source: DownloadsSource,
    private val scope: CoroutineScope,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val _rows = MutableStateFlow<List<DownloadRow>>(emptyList())

    // What the drawer shows, running first.
    val rows: StateFlow<List<DownloadRow>> = _rows

    // Whether the server has answered since the start.
    private val _loaded = MutableStateFlow(false)
    val loaded: StateFlow<Boolean> = _loaded

    private val wake = Channel<Unit>(Channel.CONFLATED)
    private var job: Job? = null
    private var lastAcquisitions: List<Acquisition> = emptyList()
    private var lastUpgrades: List<Upgrade> = emptyList()

    // Rows cleared here that the server still lists: upgrades, which it
    // keeps a week for the apps to read.
    private val hidden = HashSet<String>()

    // Whether the drawer is open: it is then asked for every two seconds.
    @Volatile
    var open: Boolean = false
        set(value) {
            val opening = value && !field
            field = value
            if (opening) wake()
        }

    // Whether the app is in front; behind it, only running rows are
    // followed, at the slow pace.
    @Volatile
    var foreground: Boolean = true

    fun start() {
        if (job?.isActive == true) return
        job = scope.launch {
            while (isActive) {
                poll()
                withTimeoutOrNull(delayMs()) { wake.receive() }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    // Forgets what the last server said, for a sign-in to another one.
    fun reset() {
        lastAcquisitions = emptyList()
        lastUpgrades = emptyList()
        synchronized(hidden) { hidden.clear() }
        _loaded.value = false
        _rows.value = emptyList()
    }

    // Asks again now, as after a song was asked for.
    fun wake() {
        wake.trySend(Unit)
    }

    private fun delayMs(): Long = when {
        open && foreground -> DOWNLOADS_OPEN_POLL_MS
        runningCount(_rows.value) > 0 && foreground -> DOWNLOADS_RUNNING_POLL_MS
        else -> DOWNLOADS_IDLE_POLL_MS
    }

    // One look at the server.
    suspend fun poll() {
        try {
            lastAcquisitions = source.acquisitions()
            lastUpgrades = try {
                source.upgrades()
            } catch (e: SubsonicException) {
                lastUpgrades
            }
            _loaded.value = true
            show()
        } catch (e: SubsonicException) {
            // Kept as it was: a moment without the server changes nothing.
        }
    }

    private fun show() {
        _rows.value = synchronized(hidden) { drawerRows(lastAcquisitions, lastUpgrades, clock(), hidden.toSet()) }
    }

    // The key of the newest download of a song by the id it was asked for
    // with, so a song's own button can open its log.
    fun keyFor(id: String): String? =
        lastAcquisitions.filter { it.id == id || it.libraryId == id }.maxByOrNull { it.startedAt.orEmpty() }?.key

    // Takes finished rows off the list, or the one with this key. The
    // server forgets its downloads; upgrades stay on it and are hidden here.
    suspend fun clear(key: String? = null) {
        val gone = _rows.value.filter { it.finished && (key == null || it.key == key) }
        if (gone.isEmpty()) return
        synchronized(hidden) { gone.forEach { hidden += it.key } }
        show()
        try {
            if (key == null) source.clear(null) else gone.mapNotNull { it.logKey }.forEach { source.clear(it) }
        } catch (e: SubsonicException) {
            // Hidden here anyway; the server lets them go on its own.
        }
        wake()
    }
}

// Follows one download's log while it is open: often while it runs, and
// for a minute once it has finished, since lyrics are looked for once the
// song is in; then no more. A log that finished longer ago than that is
// read once. Behind the app it waits until the app is in front again.
class DownloadLogWatch(
    private val load: suspend (String) -> Acquisition,
    private val scope: CoroutineScope,
    private val pollMs: Long = LOG_POLL_MS,
    private val graceMs: Long = LOG_FINISHED_GRACE_MS,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val _row = MutableStateFlow<Acquisition?>(null)
    val row: StateFlow<Acquisition?> = _row

    private val _problem = MutableStateFlow<String?>(null)

    // Why the log could not be read, in words, while it cannot.
    val problem: StateFlow<String?> = _problem

    private val front = MutableStateFlow(true)

    // Whether the app is in front; behind it, the log is not asked for.
    var foreground: Boolean
        get() = front.value
        set(value) {
            front.value = value
        }

    private var job: Job? = null

    // Whether the log is still being asked for.
    val following: Boolean get() = job?.isActive == true

    // Follows the download with this key until it has finished a while,
    // another is followed, or the log closes.
    fun follow(key: String) {
        job?.cancel()
        _row.value = null
        _problem.value = null
        job = scope.launch {
            // How long it has been seen finished here.
            var finishedFor = 0L
            while (isActive) {
                front.first { it }
                try {
                    val now = load(key)
                    _row.value = now
                    _problem.value = null
                    if (now.stage == AcquisitionStage.Done || now.stage == AcquisitionStage.Failed) {
                        val age = ageMs(now.updatedAt, clock()) ?: 0L
                        if (finishedFor >= graceMs || age >= graceMs) break
                        finishedFor += pollMs
                    }
                } catch (e: SubsonicException) {
                    _problem.value = if (e is SubsonicException.NotFound) "This download is no longer on the server" else "Could not reach the server"
                    if (e is SubsonicException.NotFound) break
                }
                kotlinx.coroutines.delay(pollMs)
            }
        }
    }

    fun close() {
        job?.cancel()
        job = null
        _row.value = null
        _problem.value = null
    }
}

// What Find songs needs from the app: the server's three calls. `anyway`
// is null when it is not to be sent at all.
interface FindSource {
    suspend fun start(id: String): FoundSongs

    suspend fun get(search: String): FoundSongs

    suspend fun pick(search: String, copy: FoundCandidate, anyway: Boolean?): PickResult
}

// A picked copy the server would not take without a yes: it is not better
// than the library's. `words` is the whole question, as the server put it.
data class PickQuestion(val search: String, val copy: FoundCandidate, val words: String)

// What is asked when the server sends no words of its own.
const val REPLACE_ANYWAY_FALLBACK = "This copy is not better than yours. Replace yours anyway?"
const val REPLACE_ANYWAY = "Replace anyway"
const val KEEP_MINE = "Keep mine"

// A Find songs search, followed until every source has answered, and the
// copy picked from it.
class FindSongsWatch(
    private val source: FindSource,
    private val scope: CoroutineScope,
    private val pollMs: Long = FIND_POLL_MS,
) {
    private val _found = MutableStateFlow<FoundSongs?>(null)

    // The search as the server last said it.
    val found: StateFlow<FoundSongs?> = _found

    private val _problem = MutableStateFlow<String?>(null)
    val problem: StateFlow<String?> = _problem

    private val _picked = MutableStateFlow<PickResult?>(null)

    // What the last pick did.
    val picked: StateFlow<PickResult?> = _picked

    private val _question = MutableStateFlow<PickQuestion?>(null)

    // A pick waiting for "Replace anyway" or "Keep mine", while its search
    // is the one on screen.
    val question: StateFlow<PickQuestion?> = _question

    // Whether the server asks before a copy that is not better replaces the
    // library's (octoAcquisitions 3). Only then is `anyway` sent; an older
    // server never gets it and says no in words instead.
    @Volatile
    var asksFirst: Boolean = false

    private var job: Job? = null

    // Starts a search for a song by its id on the server.
    fun search(id: String) {
        job?.cancel()
        _found.value = null
        _problem.value = null
        _picked.value = null
        _question.value = null
        job = scope.launch {
            var now = try {
                source.start(id)
            } catch (e: SubsonicException) {
                _problem.value = e.message ?: "Could not start the search"
                return@launch
            }
            _found.value = now
            while (isActive && now.searching) {
                kotlinx.coroutines.delay(pollMs)
                now = try {
                    source.get(now.id)
                } catch (e: SubsonicException) {
                    _problem.value = e.message ?: "Could not reach the server"
                    return@launch
                }
                _found.value = now
            }
        }
    }

    // Fetches one copy from the search `search` (the id the server gave
    // it), and answers what the server did. Never while the search runs,
    // nor from a list that another search has replaced: a copy's place
    // there could name another copy by then. What the server did is shown
    // only while its search is still the one on screen.
    // A server that asks first may answer with a question instead, which
    // waits in `question` for replaceAnyway or keepMine.
    suspend fun pick(search: String, copy: FoundCandidate): PickResult {
        _question.value = null
        return send(search, copy, if (asksFirst) false else null)
    }

    // Sends the pick the question was about again, to replace the library's
    // copy all the same. Null when that question is no longer the one
    // waiting (answered already, or its search gone), and nothing is sent.
    suspend fun replaceAnyway(question: PickQuestion): PickResult? {
        if (!_question.compareAndSet(question, null)) return null
        return send(question.search, question.copy, true)
    }

    // Leaves the library's copy as it is: nothing is sent. Given a
    // question, only that one is let go, not one asked since.
    fun keepMine(question: PickQuestion? = null) {
        if (question == null) _question.value = null else _question.compareAndSet(question, null)
    }

    private suspend fun send(search: String, copy: FoundCandidate, anyway: Boolean?): PickResult {
        val now = _found.value
        val refused = when {
            now == null || now.id != search -> FIND_LIST_CHANGED
            now.searching -> FIND_PICK_WAIT
            else -> null
        }
        if (refused != null) return PickResult(PICK_SKIPPED, refused).also { _picked.value = it }
        val result = try {
            source.pick(search, copy, anyway)
        } catch (e: SubsonicException) {
            PickResult(PICK_SKIPPED, e.message ?: "The server could not be asked")
        }
        if (showing(search)) {
            if (result.confirm) {
                _picked.value = null
                _question.value = PickQuestion(search, copy, result.detail?.takeIf(String::isNotBlank) ?: REPLACE_ANYWAY_FALLBACK)
            } else {
                _picked.value = result
            }
        }
        return result
    }

    // Whether the search `search` is still the one followed: not closed,
    // and not replaced by another.
    fun showing(search: String): Boolean = _found.value?.id == search

    fun close() {
        job?.cancel()
        job = null
        _found.value = null
        _problem.value = null
        _picked.value = null
        _question.value = null
    }
}
