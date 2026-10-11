package app.winters.octo.desktop

import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.removeFromMyLibrary
import app.winters.octo.health.FixOutcome
import app.winters.octo.health.FixStep
import app.winters.octo.health.HealthCheck
import app.winters.octo.health.deletedLine
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.ui.downloads.ReplaceEnd
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Library health's fixes and deleting a song from disk. Each run says how
// it went in the notice line, with Undo when something changed, and reads
// the library again: once at once, and twice more after the server's scan
// has had time to see the change (it asks for one a few seconds after).

// How long after a change the library is read again, in milliseconds.
internal val CatchUpReads = listOf(15_000L, 45_000L)

// Runs fix steps through the server they were planned on (`on`, or the
// signed-in one); `line` words the notice from how it went. Undo runs the
// steps that put it all back, on that same server, and only while it is
// still the one signed in to. A run that could not start says why.
fun AppState.runFix(
    label: String,
    steps: List<FixStep>,
    settle: HealthCheck? = null,
    on: SubsonicClient? = null,
    line: (FixOutcome) -> String = { it.summary() },
) {
    val client = on ?: connection?.client
    val refused = health.run(label, steps, settle, client) { outcome ->
        val words = line(outcome)
        notice = words
        noticeDetail = null
        val undo = outcome.undo
        noticeAction = if (undo.isEmpty() || client == null) null else NoticeAction(words, "Undo") {
            noticeAction = null
            runFix("Putting it back", undo, on = client)
        }
        if (outcome.done.isNotEmpty()) catchUp()
    }
    if (refused != null) {
        notice = refused
        noticeDetail = null
        noticeAction = null
    }
}

// Takes songs off the server's disk, into its trash. Asked first by the
// caller; see askToDelete in the menus.
fun AppState.deleteFromDisk(songs: List<Song>) {
    val steps = songs.map { FixStep.Remove(it.id, it.title) }
    runFix("Deleting", steps) { outcome ->
        if (outcome.failed.isEmpty() && !outcome.rehearsed && !outcome.stopped) deletedLine(outcome.done.size, songs.singleOrNull()?.title)
        else outcome.summary()
    }
}

// Takes songs out of a family member's own library. The server refuses a
// song of the shared library, and says why in its own words.
fun AppState.removeFromMyLibrary(songs: List<Song>) {
    val client = connection?.client ?: return
    scope.launch {
        var removed = 0
        var refused: String? = null
        for (song in songs) {
            try {
                client.removeFromMyLibrary(song.id)
                removed++
            } catch (e: SubsonicException) {
                refused = e.message ?: "The server kept ${song.title}."
            }
        }
        notice = refused ?: if (removed == 1) "Removed ${songs.single().title} from your library" else "Removed $removed songs from your library"
        noticeDetail = null
        noticeAction = null
        if (removed > 0) catchUp()
    }
}

// A library song's copy picked in Find songs has replaced it, or not. The
// notice says which. Replaced, it offers Undo, which puts the old copy back
// on the server it was replaced on (the newer one then waits in Recently
// removed). Kept, the server's words say why and point to the drawer.
fun AppState.replaceEnded(end: ReplaceEnd) {
    notice = end.words
    noticeDetail = null
    when (end) {
        is ReplaceEnd.Replaced -> {
            val client = connection?.client
            val back = end.putBack
            noticeAction = client?.let {
                NoticeAction(end.words, "Undo") {
                    noticeAction = null
                    runFix("Putting back", listOf(back), on = it)
                }
            }
            catchUp()
        }
        is ReplaceEnd.Kept -> noticeAction = NoticeAction(end.words, "Show downloads") { showSidePanel(SidePanel.Downloads) }
    }
}

// Reads the library now and again once the server has scanned.
private fun AppState.catchUp() {
    library?.load()
    scope.launch {
        var waited = 0L
        for (at in CatchUpReads) {
            delay(at - waited)
            waited = at
            library?.load()
        }
    }
}
