package app.winters.octo.desktop.animated

import app.winters.octo.desktop.lruMap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import app.winters.octo.animated.AnimatedArtBook
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.animated.KnownArt
import app.winters.octo.animated.LoopFetcher
import app.winters.octo.animated.LoopFile
import app.winters.octo.animated.LoopShelf
import app.winters.octo.animated.PlayerLoop
import app.winters.octo.animated.albumsToAsk
import app.winters.octo.animated.inPlayer
import app.winters.octo.desktop.server.Connection
import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedClip
import app.winters.octo.subsonic.OCTO_ANIMATED_ART
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import java.io.File
import java.security.MessageDigest

// The two shapes an album's loops come in, as their files are named.
enum class LoopShape(val key: String) { Square("square"), Tall("tall") }

// The clip of this shape, if the album has one.
fun AnimatedArt.clip(shape: LoopShape): AnimatedClip? = when (shape) {
    LoopShape.Square -> square
    LoopShape.Tall -> tall
}?.takeIf { it.video.isNotBlank() }

// The size a loop is fetched for is rounded up to this step, so a window
// moving by a few pixels does not ask for its playlists again.
private const val SizeStep = 64

// How much the loop shelf holds on the disk, least lately used out first.
const val LOOP_SHELF_BYTES = 256L * 1024 * 1024

// Animated album covers for the server in use: what each album has (one
// book per server, asked once per album), the loop files kept on the disk
// for them (a downloaded album's beside its songs, the rest on a shelf in
// the cache), and the next song's loop fetched before it starts.
@Stable
class AnimatedArtModel(
    http: OkHttpClient,
    private val scope: CoroutineScope,
    private val connection: () -> Connection?,
    // The loops kept with downloaded albums.
    val kept: KeptLoops? = null,
    // Whether the computer saves power, which holds every loop.
    val powerSaving: PowerSaving = PowerSaving(null),
) {
    private val fetcher = LoopFetcher(http)

    // Where loops of albums not downloaded are kept; Main gives it a
    // folder in the cache. None keeps nothing (the tests).
    var shelf: LoopShelf? = null

    // The book of the server in use, and which server that is.
    var book by mutableStateOf<AnimatedArtBook?>(null)
        private set
    private var bookServer: String? = null

    // The sizes the player last showed loops at, in pixels, for fetching
    // the next song's at the size it will want.
    @Volatile var squarePx: Int = 600
    @Volatile var tallPx: Pair<Int, Int> = 675 to 900

    // The words' color over each tall loop once worked out, by its video,
    // so the player opens straight onto it the next time (the last few
    // hundred).
    val tallInks: MutableMap<String, androidx.compose.ui.graphics.Color> = lruMap(256)

    // The loop files on screen, which trimming the shelf keeps.
    private val onScreen = HashSet<File>()

    // Version playlists already read, by the clip and size asked.
    private val located = object : LinkedHashMap<String, LoopFile>(32, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, LoopFile>?) = size > 128
    }

    // One fetch per file at a time, however many views want it.
    private val fetching = HashMap<String, Deferred<File?>>()

    // Starts a book for the server in use, unless it already has one.
    fun follow(now: Connection?) {
        val server = now?.server?.id
        if (server == bookServer) return
        bookServer = server
        book = now?.let { connection ->
            AnimatedArtBook(
                scope,
                offered = { if (connection.supports(OCTO_ANIMATED_ART)) true else offeredLive(connection) },
                ask = { albumId -> connection.client.animatedArt(albumId) },
            )
        }
    }

    // A server listed without the extension at sign-in may have it on since:
    // its extensions are asked again once.
    private suspend fun offeredLive(connection: Connection): Boolean? =
        runCatching { connection.client.extensions().any { it.name == OCTO_ANIMATED_ART } }.getOrNull()

    // Keeps the art getAlbum came with.
    fun note(albumId: String, art: AnimatedArt?) {
        book?.note(albumId, art)
    }

    // The album's art as it becomes known: a downloaded album's kept answer
    // at once, else what the book holds and then the server's answer. Each
    // album has a state of its own: one state for every album kept the album
    // before's art when the next one's was already known (the next song's
    // album is asked about ahead), and Full screen went on playing that
    // album's loop.
    @Composable
    fun artOf(albumId: String?): State<AnimatedArt?> {
        val book = book
        val server = connection()?.server?.id
        val held = albumId?.let { id -> kept?.art(server, id) ?: (book?.peek(id) as? KnownArt.Has)?.art }
        val art = remember(book, albumId, server) { mutableStateOf(held) }
        LaunchedEffect(art) {
            if (albumId == null || art.value != null) return@LaunchedEffect
            art.value = withContext(Dispatchers.IO) { kept?.art(server, albumId) } ?: book?.art(albumId)
        }
        return art
    }

    // A song started: its album and the next one's are asked about, and the
    // next song's loop is fetched so it is there at the change.
    fun songChanged(playing: String?, next: String?, setting: AnimatedArtSetting) {
        val book = book ?: return
        val albums = albumsToAsk(playing, listOf(next))
        if (albums.isEmpty()) return
        book.ahead(albums)
        if (setting == AnimatedArtSetting.Off || next.isNullOrBlank()) return
        scope.launch {
            val art = runCatching { book.art(next) }.getOrNull() ?: return@launch
            when (val loop = setting.inPlayer(art)) {
                is PlayerLoop.Cover -> loopFile(next, LoopShape.Square, loop.clip, squarePx, squarePx)
                is PlayerLoop.Backdrop -> {
                    posterFile(next, LoopShape.Tall, loop.clip)
                    loopFile(next, LoopShape.Tall, loop.clip, tallPx.first, tallPx.second)
                }
                PlayerLoop.None -> Unit
            }
        }
    }

    // The loop's file on this computer for a space `width` by `height`
    // pixels: a downloaded album's own, else one on the shelf, fetched now
    // if it is not there. Null when it cannot be had.
    suspend fun loopFile(albumId: String, shape: LoopShape, clip: AnimatedClip, width: Int, height: Int): File? {
        val server = connection()?.server?.id
        withContext(Dispatchers.IO) { kept?.loop(server, albumId, shape) }?.let { return it }
        val shelf = shelf ?: return null
        val w = roundUp(width)
        val h = roundUp(height)
        val key = "${clip.video}|$w|$h"
        val loop = synchronized(located) { located[key] } ?: fetcher.locate(clip, w, h)?.also { synchronized(located) { located[key] = it } } ?: return null
        val target = shelf.fileFor(loop.url)
        return once(target.path) {
            if (fetcher.fetch(loop, target)) {
                withContext(Dispatchers.IO) {
                    shelf.touch(target)
                    shelf.trim(synchronized(onScreen) { onScreen.toSet() } + target)
                }
                target
            } else {
                null
            }
        }
    }

    // The clip's still on this computer, fetched now if it is not there.
    suspend fun posterFile(albumId: String, shape: LoopShape, clip: AnimatedClip): File? {
        val server = connection()?.server?.id
        withContext(Dispatchers.IO) { kept?.poster(server, albumId, shape) }?.let { return it }
        val shelf = shelf ?: return null
        val url = clip.poster?.toHttpUrlOrNull() ?: return null
        val target = File(shelf.dir, "posters${File.separator}${digest(url.toString())}.jpg")
        return once(target.path) { if (fetcher.fetchPoster(clip, target)) target else null }
    }

    // Marks a loop file as on screen, or no longer, so trimming keeps it.
    fun showing(file: File, on: Boolean) {
        synchronized(onScreen) { if (on) onScreen += file else onScreen -= file }
        if (on) shelf?.let { shelf -> scope.launch(Dispatchers.IO) { shelf.touch(file) } }
    }

    private suspend fun once(key: String, make: suspend () -> File?): File? {
        val mine = CompletableDeferred<File?>()
        val running = synchronized(fetching) { fetching[key] ?: mine.also { fetching[key] = it } }
        if (running !== mine) return running.await()
        val made = runCatching { make() }.getOrNull()
        synchronized(fetching) { fetching.remove(key) }
        mine.complete(made)
        return made
    }
}

private fun roundUp(px: Int): Int = ((px.coerceAtLeast(1) + SizeStep - 1) / SizeStep) * SizeStep

internal fun digest(text: String): String =
    MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).take(16).joinToString("") { "%02x".format(it) }
