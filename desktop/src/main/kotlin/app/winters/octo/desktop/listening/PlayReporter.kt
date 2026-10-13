package app.winters.octo.desktop.listening

import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.system.isOpenedFile
import app.winters.octo.playback.isRadio
import app.winters.octo.listening.PendingPlay
import app.winters.octo.listening.worthRetrying
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.io.IOException

// How often plays that could not be sent are tried again.
private const val RETRY_EVERY_MS = 5 * 60_000L

// Tells the signed-in server what is played here, as the phone does: the
// song playing now as soon as it is heard, and each play the moment it
// counts.
// Every counted play also goes in this computer's own play log. A play the
// server cannot take right now waits on disk and is sent later, oldest
// first. Nothing here ever holds up playback or shows an error.
class PlayReporter(
    private val player: DesktopPlayer,
    private val settings: SettingsStore,
    private val connection: () -> Connection?,
    // The settings folder; each account's listening goes in its own folder
    // there. Null keeps nothing.
    private val root: File?,
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    clock: () -> Long = { System.nanoTime() / 1_000_000 },
    wallClock: () -> Long = System::currentTimeMillis,
    // The most plays each account's log keeps.
    private val logMax: Int = MAX_LOGGED_PLAYS,
    // Waits that long; tests hold it.
    private val pause: suspend (Long) -> Unit = { delay(it) },
) {
    private val counter = PlayCounter(::started, ::counted, clock, wallClock)
    private val sending = Mutex()

    // Guards the waiting-plays file: a play finishing while an older one is
    // being taken off must not lose either.
    private val pendingFile = Any()

    // Plays the server has had (or refused) that could not be taken off the
    // waiting file yet, by that file: they are taken off, never sent again.
    // Only touched while `sending` is held.
    private val done = HashSet<Pair<File, PendingPlay>>()

    // While quitting, a counted play is written at once rather than later.
    private var quitting = false

    // Follows the player, and tries waiting plays again now and then.
    fun start(): Job = scope.launch {
        launch {
            player.state.collectLatest { state ->
                counter.update(state)
                // A play goes to the server the moment it counts, not when the
                // song moves on. A new state calls the wait off.
                while (true) {
                    val left = counter.msUntilCounted() ?: break
                    pause(maxOf(left, 1))
                    counter.check()
                }
            }
        }
        while (isActive) {
            delay(RETRY_EVERY_MS)
            sendWaiting()
        }
    }

    // A server was signed in to: plays from before may be waiting for it.
    fun signedIn() = sendWaiting()

    // Octo is quitting or signing out: the song playing counts now, if it
    // was heard long enough. Written before this returns.
    fun flush() {
        quitting = true
        try {
            counter.flush()
        } finally {
            quitting = false
        }
    }

    // One log for each account folder, kept, so it knows how long it is.
    private val logs = HashMap<File, PlayLog>()

    // The play log of the signed-in account, if there is one.
    fun log(): PlayLog? = folder()?.let(::logIn)

    private fun logIn(folder: File): PlayLog = synchronized(logs) { logs.getOrPut(folder) { PlayLog(File(folder, "plays.jsonl"), logMax) } }

    private fun folder(): File? = folderOf(connection())

    private fun folderOf(connection: Connection?): File? = root?.let { dir -> connection?.let { listeningFolder(dir, it.server) } }

    private fun reports(): Boolean = settings.current.listening.reportPlays

    private fun started(song: Song) {
        val client = connection()?.client ?: return
        if (!reports() || isOpenedFile(song.id) || isRadio(song.id)) return
        scope.launch(io) {
            try {
                client.scrobble(song.id, System.currentTimeMillis(), submission = false)
            } catch (e: SubsonicException) {
                // Only "playing now"; nothing to keep.
            }
        }
    }

    private fun counted(play: HeardPlay) {
        val folder = folder() ?: return
        val send = reports() && !isOpenedFile(play.song.id)
        // The log and the waiting file each go in on their own, so trouble
        // with one never keeps the play out of the other.
        val write = {
            runCatching { logIn(folder).add(LoggedPlay(play.startedAt, play.heardMs, play.song.logged())) }
            if (send) runCatching { synchronized(pendingFile) { PendingPlays(File(folder, "pending.txt")).add(PendingPlay(play.song.id, play.startedAt)) } }
        }
        if (quitting) {
            write()
            return
        }
        scope.launch(io) {
            write()
            if (send) sendWaiting()
        }
    }

    // Sends the waiting plays oldest first, and stops at the first one the
    // server cannot take right now. A play the server refused outright is
    // dropped, since it would refuse it again.
    private fun sendWaiting() = scope.launch(io) {
        if (!reports()) return@launch
        // The client and the folder of one server, read once: a switch to
        // another server in between must not send one's plays to the other.
        val now = connection() ?: return@launch
        val client = now.client
        val folder = folderOf(now) ?: return@launch
        val file = File(folder, "pending.txt")
        val pending = PendingPlays(file)
        sending.withLock {
            // A file that cannot be read now is tried again next time.
            val waiting = try {
                synchronized(pendingFile) { pending.all() }
            } catch (e: IOException) {
                return@withLock
            }
            for (play in waiting) {
                if ((file to play) !in done) {
                    val failure = try {
                        client.scrobble(play.serverId, play.startedAt, submission = true)
                        null
                    } catch (e: SubsonicException) {
                        e
                    }
                    if (failure != null && worthRetrying(failure)) break
                    done += file to play
                }
                try {
                    synchronized(pendingFile) { pending.remove(play) }
                } catch (e: IOException) {
                    // Still in the file; it comes off next time, unsent.
                    break
                }
                done -= file to play
            }
        }
    }
}
