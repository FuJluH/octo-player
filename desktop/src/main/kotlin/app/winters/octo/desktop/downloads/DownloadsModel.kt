package app.winters.octo.desktop.downloads

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.subsonic.Acquisition
import app.winters.octo.subsonic.FoundCandidate
import app.winters.octo.subsonic.FoundSongs
import app.winters.octo.subsonic.OCTO_ACQUISITIONS
import app.winters.octo.subsonic.OCTO_DOWNLOAD_LOG_VERSION
import app.winters.octo.subsonic.OCTO_REPLACE_ANYWAY_VERSION
import app.winters.octo.subsonic.PickResult
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.subsonic.Upgrade
import app.winters.octo.ui.downloads.DownloadLogWatch
import app.winters.octo.ui.downloads.DownloadRow
import app.winters.octo.ui.downloads.DownloadsSource
import app.winters.octo.ui.downloads.DownloadsWatch
import app.winters.octo.ui.downloads.FindSongsWatch
import app.winters.octo.ui.downloads.FindSource
import app.winters.octo.ui.downloads.PickQuestion
import app.winters.octo.ui.downloads.ReplaceEnd
import app.winters.octo.ui.downloads.Replacements
import app.winters.octo.ui.downloads.Replacing
import app.winters.octo.subsonic.OCTO_LIBRARY_ACTIONS
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

// How long after a server out of reach it is asked again whether it keeps
// logs.
const val PROBE_RETRY_MS = 15_000L

// What the downloads drawer shows: the list, one download's log, or Find
// songs for one song.
sealed interface DrawerView {
    data object List : DrawerView

    data class Log(val key: String) : DrawerView

    // `id` is the song's id on the server; `title` names it until the
    // server answers.
    data class Find(val id: String, val title: String, val from: String? = null) : DrawerView
}

// The downloads drawer for one Octo server: every download it is doing for
// this person or did lately, each one's log, and Find songs. Whether the
// server keeps logs is asked live, as "Find higher quality" is, since the
// extensions saved at sign-in may be older than the server. Made with each
// connection and closed with it. `ended` hears each replacement of a
// library song's copy as it ends on the server.
@Stable
class DownloadsModel(
    private val client: SubsonicClient,
    parent: CoroutineScope,
    private val probeRetryMs: Long = PROBE_RETRY_MS,
    private val ended: (ReplaceEnd) -> Unit = {},
) {
    private val scope = CoroutineScope(parent.coroutineContext + SupervisorJob(parent.coroutineContext[Job]))

    private val watch = DownloadsWatch(
        object : DownloadsSource {
            override suspend fun acquisitions(): List<Acquisition> = client.acquisitions()

            override suspend fun upgrades(): List<Upgrade> =
                if (upgradesToo) client.upgrades() else emptyList()

            override suspend fun clear(key: String?) {
                client.clearAcquisitions(key)
            }
        },
        scope,
    )

    private val logWatch = DownloadLogWatch({ client.acquisition(it) }, scope)

    private val findWatch = FindSongsWatch(
        object : FindSource {
            override suspend fun start(id: String): FoundSongs = client.findSongs(id)

            override suspend fun get(search: String): FoundSongs = client.foundSongs(search)

            override suspend fun pick(search: String, copy: FoundCandidate, anyway: Boolean?): PickResult =
                client.pickFoundSong(search, copy, anyway)
        },
        scope,
    )

    // Whether the server lists its upgrades too (octoLibraryActions 2).
    @Volatile
    private var upgradesToo = false

    // Whether this server keeps a log of its downloads. Null until it said.
    var supported by mutableStateOf<Boolean?>(null)
        private set

    var view by mutableStateOf<DrawerView>(DrawerView.List)
        private set

    val rows: StateFlow<List<DownloadRow>> get() = watch.rows
    val loaded: StateFlow<Boolean> get() = watch.loaded
    val log: StateFlow<Acquisition?> get() = logWatch.row
    val logProblem: StateFlow<String?> get() = logWatch.problem
    val found: StateFlow<FoundSongs?> get() = findWatch.found
    val findProblem: StateFlow<String?> get() = findWatch.problem
    val picked: StateFlow<PickResult?> get() = findWatch.picked
    val question: StateFlow<PickQuestion?> get() = findWatch.question

    // Library songs being replaced by a copy picked here.
    private val replacements = Replacements()
    val replacing: StateFlow<Map<String, Replacing>> get() = replacements.now

    // Whether the server asks before a copy that is not better replaces the
    // library's, rather than saying no.
    var asksFirst by mutableStateOf(false)
        private set

    // Asks whether the server keeps logs, and follows its downloads if so.
    // A server out of reach is asked again a little later, until it says.
    // Each list of higher quality copies the server sends ends whichever
    // replacements it shows ended.
    fun start() {
        scope.launch {
            watch.upgrades.collect { upgrades -> replacements.update(upgrades).forEach(ended) }
        }
        scope.launch {
            while (isActive) {
                val logs = client.supportsIfKnown(OCTO_ACQUISITIONS, OCTO_DOWNLOAD_LOG_VERSION)
                val upgrades = logs?.let { client.supportsIfKnown(OCTO_LIBRARY_ACTIONS, 2) }
                val asks = if (logs == true && upgrades != null) client.supportsIfKnown(OCTO_ACQUISITIONS, OCTO_REPLACE_ANYWAY_VERSION) else false
                if (logs != null && upgrades != null && asks != null) {
                    upgradesToo = upgrades
                    findWatch.asksFirst = asks
                    asksFirst = asks
                    supported = logs
                    if (logs) watch.start()
                    return@launch
                }
                delay(probeRetryMs)
            }
        }
    }

    // The drawer is on screen: asked for often while it is.
    var open: Boolean
        get() = watch.open
        set(value) {
            watch.open = value
            if (!value) {
                logWatch.close()
                findWatch.close()
                view = DrawerView.List
            }
        }

    // A song was asked for here: the list is asked again now.
    fun wake() = watch.wake()

    // The log of a song's newest download, by the id it was asked for with.
    // False when this server keeps no log or has no download of it.
    fun showLogOf(id: String): Boolean {
        if (supported != true) return false
        val key = watch.keyFor(id) ?: return false
        showLog(key)
        return true
    }

    fun showList() {
        logWatch.close()
        findWatch.close()
        view = DrawerView.List
    }

    fun showLog(key: String) {
        findWatch.close()
        logWatch.follow(key)
        view = DrawerView.Log(key)
    }

    // Find songs for a song, from a download's row or a song's menu.
    fun find(id: String, title: String, from: String? = null) {
        logWatch.close()
        findWatch.search(id)
        view = DrawerView.Find(id, title, from)
    }

    fun searchAgain() {
        (view as? DrawerView.Find)?.let { findWatch.search(it.id) }
    }

    // Fetches one copy from the Find songs search `search`. A queued pick
    // opens its download's log, so the person can follow it from the start,
    // but only while the drawer still shows that search: closed meanwhile,
    // or gone on to something else, it is left as it is.
    // A server that asks first may answer with a question instead, held in
    // `question` until replaceAnyway or keepMine.
    fun pick(search: String, copy: FoundCandidate) {
        scope.launch { picked(search, findWatch.pick(search, copy)) }
    }

    // Answers the question yes: the pick goes again with anyway=true. A
    // library song's copy then shows as replacing on its row, followed
    // until it ends; any other pick goes on as usual.
    fun replaceAnyway() {
        val asked = findWatch.question.value ?: return
        scope.launch {
            val result = findWatch.replaceAnyway(asked) ?: return@launch
            val replacing = Replacing.of(asked)
            if (result.queued && replacing != null) {
                replacements.start(replacing, watch.upgrades.value)
                watch.wake()
            } else {
                picked(asked.search, result)
            }
        }
    }

    // Leaves the library's copy as it is; nothing is sent.
    fun keepMine(question: PickQuestion? = null) = findWatch.keepMine(question)

    private fun picked(search: String, result: PickResult) {
        if (!result.queued) return
        watch.wake()
        if (!(view is DrawerView.Find && findWatch.showing(search))) return
        // A replacement waits in the upgrade queue before it has a log
        // of its own; the list shows it meanwhile.
        val key = result.key
        if (key != null) showLog(key) else showList()
    }

    fun clear(key: String? = null) {
        scope.launch { watch.clear(key) }
    }

    // The server is left: nothing more is asked of it.
    fun close() {
        watch.stop()
        logWatch.close()
        findWatch.close()
        scope.cancel()
    }
}
