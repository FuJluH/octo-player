package app.winters.octo.desktop.system

import app.winters.octo.desktop.library.coverBytes
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.subsonic.SubsonicClient
import coil3.ImageLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.security.MessageDigest
import kotlin.coroutines.CoroutineContext
import kotlin.math.abs

// Finds the cover of a song for the system's player.
fun interface CoverSource {
    suspend fun load(coverId: String): CoverArt?
}

// Covers from the signed-in server, fetched with the app's HTTP client and
// kept as a file in the cache folder. The system is only ever given the
// picture or that file, never the server's signed address, which would
// hand the listener's sign-in to every program that asks what is playing.
// With an image loader from `images`, the picture comes through its caches
// and downloads, shared with every other place that shows the cover.
class ServerCovers(
    private val http: OkHttpClient,
    private val client: () -> SubsonicClient?,
    private val folder: File,
    private val size: Int = 600,
    private val images: () -> ImageLoader? = { null },
) : CoverSource {
    override suspend fun load(coverId: String): CoverArt? = withContext(Dispatchers.IO) {
        val server = client() ?: return@withContext null
        val name = sha(server.primaryUrl.host + "/" + coverId).take(24) + ".img"
        val file = File(folder, name)
        if (file.isFile && file.length() > 0) return@withContext CoverArt(file.readBytes(), file)
        val loader = images()
        val bytes = runCatching {
            if (loader != null) {
                coverBytes(loader, server, coverId, size)?.takeIf { it.isNotEmpty() && looksLikeImage(it) }
            } else {
                http.newCall(Request.Builder().url(server.coverArtUrl(coverId, size)).build()).execute().use { response ->
                    if (!response.isSuccessful) null else response.body.bytes().takeIf { it.isNotEmpty() && looksLikeImage(it) }
                }
            }
        }.getOrNull() ?: return@withContext null
        runCatching {
            folder.mkdirs()
            // Only the last few covers are kept; the rest are for songs gone by.
            folder.listFiles()?.sortedByDescending { it.lastModified() }?.drop(KEPT_COVERS)?.forEach { it.delete() }
            val temp = File(folder, "$name.tmp")
            temp.writeBytes(bytes)
            if (!temp.renameTo(file)) temp.delete()
        }
        CoverArt(bytes, file)
    }

    private companion object {
        const val KEPT_COVERS = 8
    }
}

// Whether bytes start like a JPEG, PNG, GIF or WebP picture, so an error
// page is never handed to the system as a cover.
fun looksLikeImage(bytes: ByteArray): Boolean {
    fun at(i: Int) = bytes.getOrNull(i)?.toInt()?.and(0xFF) ?: -1
    return (at(0) == 0xFF && at(1) == 0xD8) ||
        (at(0) == 0x89 && at(1) == 0x50 && at(2) == 0x4E && at(3) == 0x47) ||
        (at(0) == 0x47 && at(1) == 0x49 && at(2) == 0x46) ||
        (at(0) == 0x52 && at(1) == 0x49 && at(2) == 0x46 && at(3) == 0x46 && at(8) == 0x57 && at(9) == 0x45)
}

private fun sha(text: String): String =
    MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).joinToString("") { "%02x".format(it) }

// Keeps the system's player in step with Octo's: the song, its cover,
// playing or paused, and where it is, and turns the system's buttons into
// player calls. Everything it does runs in `scope` (the window's main
// thread), so the player is only ever called from there.
class MediaSession(
    private val player: DesktopPlayer,
    private val controls: SystemMediaControls,
    private val covers: CoverSource?,
    private val scope: CoroutineScope,
    // The events that are not the player's: Raise, Quit, OpenUri, SetVolume,
    // Sleep and Wake. Sleep has already paused the music.
    private val others: (SystemEvent) -> Unit = {},
    // Milliseconds from any fixed point; the tests pass their own.
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
    private val checkEveryMs: Long = 1_000,
    private val refreshEveryMs: Long = 5_000,
    // Where the system is first reached, which can take seconds; the tests
    // pass their own.
    private val startOn: CoroutineContext = Dispatchers.IO,
) : AutoCloseable {
    private var shown: NowPlaying? = null
    private var coverJob: Job? = null
    private var volumeShown: Float? = null
    private var modesShown: Pair<Boolean, RepeatMode>? = null
    private val jobs = ArrayList<Job>()

    // Where the song was when last told, and when, to notice jumps.
    private var toldPosition = 0L
    private var toldAt = 0L

    var started = false
        private set

    // Reaches the system off the window's thread, then keeps it in step.
    // `onStarted` hears, in `scope`, whether the system took Octo on.
    fun start(onStarted: (Boolean) -> Unit = {}) {
        jobs += scope.launch {
            started = withContext(startOn) { controls.start { event -> scope.launch { handle(event) } } }
            onStarted(started)
            // A playing song's place is checked every so often; a paused
            // one only moves when the player changes (a seek is a change).
            player.state.collectLatest { state ->
                update()
                if (!state.playing) {
                    check()
                } else {
                    while (true) {
                        delay(checkEveryMs)
                        check()
                    }
                }
            }
        }
    }

    // Brings the system up to date with the player.
    fun update() {
        val state = player.state.value
        if (volumeShown != state.volume) {
            volumeShown = state.volume
            controls.showVolume(state.volume)
        }
        val modes = state.shuffle to state.repeat
        if (modesShown != modes) {
            modesShown = modes
            controls.showModes(modes.first, modes.second)
        }
        val now = nowPlayingOf(state)
        val before = shown
        shown = now
        if (now == null) {
            if (before != null) {
                coverJob?.cancel()
                controls.clear()
            }
            return
        }
        if (before == null || before.entryKey != now.entryKey || before.trackFields() != now.trackFields()) {
            showTrack(now)
            tell(now, jumped = false)
        } else if (before != now) {
            // After waiting for sound the song is behind where a system
            // moving the time on by itself thinks it is.
            tell(now, jumped = before.buffering && !now.buffering)
        }
    }

    // What the system shows about a song, apart from playing and paused.
    private fun NowPlaying.trackFields() = copy(playing = false, canPrevious = false, canNext = false, speed = 1f, buffering = false)

    private fun showTrack(now: NowPlaying) {
        coverJob?.cancel()
        val cover = now.coverId
        controls.showTrack(now, null)
        if (cover == null || covers == null) return
        coverJob = scope.launch {
            val art = covers.load(cover) ?: return@launch
            // Still the same song: show it again with its cover.
            val current = shown ?: return@launch
            if (current.entryKey != now.entryKey) return@launch
            controls.showTrack(current, art)
            tell(current, jumped = false)
        }
    }

    private fun tell(now: NowPlaying, jumped: Boolean) {
        val position = player.positionMs()
        toldPosition = position
        toldAt = clock()
        controls.showPlayback(now, position, jumped)
    }

    // Once a second: a jump the player made on its own (a seek from the
    // window) is told at once; otherwise the place is refreshed now and then
    // for systems that do not move the time on by themselves. The place
    // moves on at the song's speed, and not at all while waiting for sound.
    fun check() {
        val now = shown ?: return
        val position = player.positionMs()
        val expected = toldPosition + ((clock() - toldAt) * now.rate).toLong()
        when {
            abs(position - expected) > JUMP_MS -> tell(now, jumped = true)
            now.rate > 0 && clock() - toldAt >= refreshEveryMs -> tell(now, jumped = false)
        }
    }

    fun handle(event: SystemEvent) {
        when (event) {
            SystemEvent.Play -> player.resume()
            SystemEvent.Pause -> player.pause()
            SystemEvent.Toggle -> player.togglePlay()
            SystemEvent.Next -> player.next()
            SystemEvent.Previous -> player.previous()
            // Stop keeps the queue, as the phone does from its notification.
            SystemEvent.Stop -> player.pause()
            is SystemEvent.SeekTo -> player.seekTo(event.positionMs)
            is SystemEvent.SeekBy -> player.seekTo((player.positionMs() + event.offsetMs).coerceAtLeast(0))
            is SystemEvent.SetShuffle -> player.setShuffle(event.on)
            is SystemEvent.SetRepeat -> player.setRepeat(event.mode)
            SystemEvent.Sleep -> {
                if (player.state.value.playing) player.pause()
                others(event)
            }
            else -> others(event)
        }
        // The player's state flow tells the system most of this; a seek
        // while paused changes nothing there, so it is told here.
        if (event is SystemEvent.SeekTo || event is SystemEvent.SeekBy) shown?.let { tell(it, jumped = true) }
    }

    override fun close() {
        jobs.forEach { it.cancel() }
        coverJob?.cancel()
        controls.close()
    }

    private companion object {
        // A difference this big between where the song is and where it
        // should be is a jump, not the clocks drifting.
        const val JUMP_MS = 1_500L
    }
}
