package app.winters.octo.offline

import android.content.Context
import android.util.Log
import app.winters.octo.animated.AnimatedArts
import app.winters.octo.animated.KnownArt
import app.winters.octo.animated.LoopFetcher
import app.winters.octo.animated.playableLoopCodecs
import app.winters.octo.animated.shape
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.playback.Streams
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.math.min

// How long downloads settle before the loops follow them: longer than a
// removal can be taken back, so an undone removal keeps its loops.
private const val SETTLE_MS = 12_000L

// Keeps the animated art of albums downloaded whole on the phone, beside
// their songs: the record of the art, and each loop (sized for this
// screen, in H.264) with its still. They go when the album's downloads go.
@OptIn(FlowPreview::class)
@Singleton
class LoopKeeper @Inject constructor(
    @ApplicationContext private val context: Context,
    private val dao: DownloadDao,
    private val sessions: SessionRepository,
    private val arts: AnimatedArts,
    private val streams: Streams,
    private val settings: OfflineSettings,
    http: OkHttpClient,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val fetcher = LoopFetcher(http)
    private val codecs by lazy { playableLoopCodecs() }
    private val store by lazy { OfflineLoopStore(offlineLoopsDir(context)) }
    private val pokes = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private var started = false

    fun start() {
        if (started) return
        started = true
        scope.launch {
            pokes.debounce(SETTLE_MS).collect {
                try {
                    keepInStep()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.w("Octo", "keeping loops failed: ${e.javaClass.simpleName}")
                }
            }
        }
        scope.launch { sessions.state.collect { poke() } }
        poke()
    }

    // Something about the downloads changed.
    fun poke() {
        pokes.tryEmit(Unit)
    }

    private suspend fun keepInStep() {
        val wanted = dao.downloadedAlbums().map { LoopAlbum(it.sourceId, it.albumId) }.toSet()
        store.keepOnly(wanted)
        val source = (sessions.state.value as? SessionState.SignedIn)?.session?.sourceId ?: return
        // Loops come with the songs: on Wi-Fi only when downloads wait for it.
        if (if (settings.prefs.first().wifiOnly) !streams.onWifi() else !streams.online()) return
        for (album in wanted.filter { it.sourceId == source }) {
            val kept = store.read(album)
            if (kept != null && store.complete(kept)) continue
            // The server's answer is asked again (a relayed loop's address can
            // change); without one, the art already kept is fetched.
            val asked = arts.answerFor(album.sourceId, album.albumId)
            val known = if (asked == KnownArt.Unknown && kept?.art != null) KnownArt.Has(kept.art) else asked
            when (known) {
                KnownArt.Unknown -> continue
                KnownArt.HasNone -> store.write(KeptLoops(album.sourceId, album.albumId, null))
                is KnownArt.Has -> {
                    for ((shape, clip) in shapes(known.art)) {
                        val (width, height) = loopSpace(shape, clip.shape())
                        fetcher.locate(clip, width, height, codecs)?.let { fetcher.fetch(it, store.loopFile(album, shape)) }
                        fetcher.fetchPoster(clip, store.posterFile(album, shape))
                    }
                    store.write(KeptLoops(album.sourceId, album.albumId, known.art))
                }
            }
        }
    }

    // The space a kept loop fills on this screen: the square one the
    // player's cover (about the screen's width), the tall one the screen's
    // width at its own shape (`aspect`, width over height).
    private suspend fun loopSpace(shape: String, aspect: Float): Pair<Int, Int> = withContext(Dispatchers.Main) {
        val metrics = context.resources.displayMetrics
        val short = min(metrics.widthPixels, metrics.heightPixels)
        if (shape == SQUARE_LOOP) short to short else short to (short / aspect).toInt()
    }
}
