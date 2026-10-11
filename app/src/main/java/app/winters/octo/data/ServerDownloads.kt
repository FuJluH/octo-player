package app.winters.octo.data

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.catalog.FIND_PREFIX
import app.winters.octo.catalog.SourceDao
import app.winters.octo.catalog.isFind
import app.winters.octo.subsonic.Acquisition
import app.winters.octo.subsonic.FoundCandidate
import app.winters.octo.subsonic.FoundSongs
import app.winters.octo.subsonic.OCTO_ACQUISITIONS
import app.winters.octo.subsonic.OCTO_DOWNLOAD_LOG_VERSION
import app.winters.octo.subsonic.OCTO_LIBRARY_ACTIONS
import app.winters.octo.subsonic.OCTO_REPLACE_ANYWAY_VERSION
import app.winters.octo.subsonic.PickResult
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.Upgrade
import app.winters.octo.ui.downloads.DownloadLogWatch
import app.winters.octo.ui.downloads.DownloadRow
import app.winters.octo.ui.downloads.DownloadsSource
import app.winters.octo.ui.downloads.DownloadsWatch
import app.winters.octo.ui.downloads.FindSongsWatch
import app.winters.octo.ui.downloads.FindSource
import app.winters.octo.ui.common.Feedback
import app.winters.octo.ui.downloads.PickQuestion
import app.winters.octo.ui.downloads.ReplaceEnd
import app.winters.octo.ui.downloads.Replacements
import app.winters.octo.ui.downloads.Replacing
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

// What the server downloads sheet shows: the list, one download's log, or
// Find songs for one song.
sealed interface SheetView {
    data object List : SheetView

    data class Log(val key: String) : SheetView

    // `id` is the song's id on the server; `title` names it until the
    // server answers. `from` is the log it was opened from, if any.
    data class Find(val id: String, val title: String, val from: String? = null) : SheetView
}

// The server downloads sheet on the signed-in Octo server: every download
// it is doing for this person or did lately, each one's log, and Find
// songs. Only on a server that lists octoAcquisitions at version 2, read
// from the extensions the session asks for at each start. The list is
// followed while the app runs: often while the sheet is open, every few
// seconds while something is on its way, and seldom otherwise. A library
// song's copy replaced from Find songs is followed until it ends, and a
// line says how it went: with Undo once replaced, which puts the old copy
// back through `files`.
@Singleton
class ServerDownloads @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessions: SessionRepository,
    private val sources: SourceDao,
    private val files: LibraryFiles,
    private val feedback: Feedback,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var running = false

    private val _supported = MutableStateFlow(false)

    // Whether the signed-in server keeps a log of its downloads.
    val supported: StateFlow<Boolean> = _supported

    private val _view = MutableStateFlow<SheetView?>(null)

    // What the sheet shows, or null while it is closed.
    val view: StateFlow<SheetView?> = _view

    private fun client() = (sessions.state.value as? SessionState.SignedIn)?.session?.client

    private fun session() = (sessions.state.value as? SessionState.SignedIn)?.session

    // The picture for a cover the server names, as the rest of the app draws
    // it: no picture when nobody is signed in.
    fun artwork(coverId: String?): String? {
        val sourceId = session()?.sourceId ?: return null
        return coverId?.takeIf(String::isNotEmpty)?.let { ArtworkRef.Server(sourceId, it).encode() }
    }

    private val watch = DownloadsWatch(
        object : DownloadsSource {
            override suspend fun acquisitions(): List<Acquisition> = client()?.acquisitions() ?: emptyList()

            override suspend fun upgrades(): List<Upgrade> {
                val session = session() ?: return emptyList()
                return if ("$OCTO_LIBRARY_ACTIONS:2" in session.extensions) session.client.upgrades() else emptyList()
            }

            override suspend fun clear(key: String?) {
                client()?.clearAcquisitions(key)
            }
        },
        scope,
    )

    private val logWatch = DownloadLogWatch({ key -> client()?.acquisition(key) ?: throw SubsonicException.NotFound("Not signed in") }, scope)

    private val findWatch = FindSongsWatch(
        object : FindSource {
            override suspend fun start(id: String): FoundSongs = client()?.findSongs(id) ?: throw SubsonicException.NotFound("Not signed in")

            override suspend fun get(search: String): FoundSongs = client()?.foundSongs(search) ?: throw SubsonicException.NotFound("Not signed in")

            override suspend fun pick(search: String, copy: FoundCandidate, anyway: Boolean?): PickResult =
                client()?.pickFoundSong(search, copy, anyway) ?: PickResult("skipped", "Not signed in")
        },
        scope,
    )

    val rows: StateFlow<List<DownloadRow>> get() = watch.rows
    val loaded: StateFlow<Boolean> get() = watch.loaded
    val listedSince: StateFlow<Long?> get() = watch.listedSince
    val log: StateFlow<Acquisition?> get() = logWatch.row
    val logProblem: StateFlow<String?> get() = logWatch.problem
    val found: StateFlow<FoundSongs?> get() = findWatch.found
    val findProblem: StateFlow<String?> get() = findWatch.problem
    val picked: StateFlow<PickResult?> get() = findWatch.picked
    val question: StateFlow<PickQuestion?> get() = findWatch.question

    // Library songs being replaced by a copy picked in Find songs.
    private val replacements = Replacements()
    val replacing: StateFlow<Map<String, Replacing>> get() = replacements.now

    private val _asksFirst = MutableStateFlow(false)

    // Whether the server asks before a copy that is not better replaces the
    // library's, rather than saying no.
    val asksFirst: StateFlow<Boolean> = _asksFirst

    fun start() {
        if (running) return
        running = true
        (context.applicationContext as? Application)?.registerActivityLifecycleCallbacks(ForegroundCallbacks())
        scope.launch {
            watch.upgrades.collect { upgrades -> replacements.update(upgrades).forEach(::ended) }
        }
        scope.launch {
            // A new sign-in, or the same one with its extensions read again.
            sessions.state.distinctUntilChangedBy { (it as? SessionState.SignedIn)?.session }.collect { state ->
                watch.stop()
                watch.reset()
                replacements.clear()
                close()
                val session = (state as? SessionState.SignedIn)?.session
                val logs = session != null && "$OCTO_ACQUISITIONS:$OCTO_DOWNLOAD_LOG_VERSION" in session.extensions
                val asks = logs && "$OCTO_ACQUISITIONS:$OCTO_REPLACE_ANYWAY_VERSION" in session.extensions
                findWatch.asksFirst = asks
                _asksFirst.value = asks
                _supported.value = logs
                if (logs) watch.start()
            }
        }
    }

    // A song was asked for here: the list is asked again now.
    fun wake() = watch.wake()

    fun open() {
        if (!_supported.value) return
        watch.open = true
        if (_view.value == null) _view.value = SheetView.List
    }

    fun close() {
        watch.open = false
        logWatch.close()
        findWatch.close()
        _view.value = null
    }

    fun showList() {
        logWatch.close()
        findWatch.close()
        _view.value = SheetView.List
    }

    fun showLog(key: String) {
        findWatch.close()
        logWatch.follow(key)
        watch.open = true
        _view.value = SheetView.Log(key)
    }

    // Opens the sheet on a song's newest download, by the id it was asked
    // for with on the server, or on the list when the server has not
    // listed it yet.
    fun follow(serverId: String) {
        if (!_supported.value) return
        watch.keyFor(serverId)?.let(::showLog) ?: run {
            open()
            showList()
        }
    }

    // Follows a song's download from its button: a found song's id is the
    // server's id without its "find:".
    fun followTrack(trackId: String) = follow(trackId.removePrefix(FIND_PREFIX))

    // Find songs for a song by its id on the server.
    fun find(serverId: String, title: String, from: String? = null) {
        if (!_supported.value) return
        logWatch.close()
        watch.open = true
        findWatch.search(serverId)
        _view.value = SheetView.Find(serverId, title, from)
    }

    // Find songs for a song in the app's library or a found one: its copy
    // on the signed-in server, or the found song's own id.
    suspend fun findTrack(trackId: String, title: String): Boolean {
        val id = serverIdOf(trackId) ?: return false
        find(id, title)
        return true
    }

    suspend fun serverIdOf(trackId: String): String? {
        if (isFind(trackId)) return trackId.removePrefix(FIND_PREFIX)
        val session = session() ?: return null
        return sources.copies(trackId).filter { it.sourceId == session.sourceId }.minByOrNull { it.nativeId }?.nativeId
    }

    fun searchAgain() {
        (_view.value as? SheetView.Find)?.let { findWatch.search(it.id) }
    }

    // Fetches one copy from the Find songs search `search`. A queued pick
    // opens its download's log; a replacement waits in the upgrade queue
    // first, so the list shows it. Only while the sheet still shows that
    // search: closed meanwhile, or gone on to something else, it is left as
    // it is and only the list is asked again. A server that asks first may
    // answer with a question instead, held in `question` until
    // replaceAnyway or keepMine.
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

    // A replacement ended. Replaced: a line with Undo, which puts the old
    // copy back on the server it was replaced on. Kept: the server's words
    // why, with the downloads one tap away.
    private fun ended(end: ReplaceEnd) {
        when (end) {
            is ReplaceEnd.Replaced -> {
                val on = files.server()
                val back = end.putBack
                feedback.undoable(end.words) { files.launch(listOf(back), on = on) }
            }
            is ReplaceEnd.Kept -> feedback.show(end.words, "Show downloads", onAction = {
                open()
                showList()
            })
        }
    }

    // Leaves the library's copy as it is; nothing is sent.
    fun keepMine(question: PickQuestion? = null) = findWatch.keepMine(question)

    private fun picked(search: String, result: PickResult) {
        if (!result.queued) return
        watch.wake()
        if (!(_view.value is SheetView.Find && findWatch.showing(search))) return
        val key = result.key
        if (key != null) showLog(key) else showList()
    }

    fun clear(key: String? = null) {
        scope.launch { watch.clear(key) }
    }

    // Whether any of the app's screens is in front: the list is asked for
    // only at the slow pace while none is, and an open log not at all.
    private inner class ForegroundCallbacks : Application.ActivityLifecycleCallbacks {
        private val started = AtomicInteger(0)

        override fun onActivityStarted(activity: Activity) {
            if (started.incrementAndGet() == 1) {
                watch.foreground = true
                logWatch.foreground = true
                watch.wake()
            }
        }

        override fun onActivityStopped(activity: Activity) {
            if (started.decrementAndGet() <= 0) {
                started.set(0)
                watch.foreground = false
                logWatch.foreground = false
            }
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityResumed(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }
}
