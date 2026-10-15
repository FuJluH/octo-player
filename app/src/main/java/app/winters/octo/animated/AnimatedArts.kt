package app.winters.octo.animated

import android.content.Context
import android.util.LruCache
import app.winters.octo.catalog.OnlineDao
import app.winters.octo.catalog.SourceDao
import app.winters.octo.catalog.isFind
import app.winters.octo.data.Session
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.offline.LoopAlbum
import app.winters.octo.offline.OfflineLoopStore
import app.winters.octo.offline.offlineLoopsDir
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.player.PlayerSettings
import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedClip
import app.winters.octo.subsonic.OCTO_ANIMATED_ART
import app.winters.octo.subsonic.SubsonicClient
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

// How long a song must be on before its album's art, and the next song's,
// are asked for, so skipping quickly through the queue asks for nothing.
private const val AHEAD_SETTLE_MS = 400L

// Albums' animated art from the signed-in server: one book per server
// session, asked by the server's own album ids. An album downloaded whole
// keeps its art and loops on the phone, and those come first, with no
// connection too.
@OptIn(ExperimentalCoroutinesApi::class)
@Singleton
class AnimatedArts @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessions: SessionRepository,
    private val sources: SourceDao,
    private val online: OnlineDao,
    private val playback: PlaybackConnection,
    private val settings: PlayerSettings,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val store by lazy { OfflineLoopStore(offlineLoopsDir(context)) }

    // The server in use and its book.
    private class Shelf(val client: SubsonicClient, val sourceId: String, val book: AnimatedArtBook)

    private val shelf = MutableStateFlow<Shelf?>(null)

    // Each song's album on the server, by "<source>|<song>".
    private val albumOfSong = LruCache<String, String>(512)

    private var started = false

    fun start() {
        if (started) return
        started = true
        scope.launch { sessions.state.collect { shelf.value = shelfFor((it as? SessionState.SignedIn)?.session) } }
        scope.launch { askAhead() }
    }

    private fun shelfFor(session: Session?): Shelf? {
        if (session == null) return null
        val client = session.client
        shelf.value?.takeIf { it.client === client }?.let { return it }
        val book = AnimatedArtBook(scope, offered = { client.supportsIfKnown(OCTO_ANIMATED_ART) }, ask = { client.animatedArt(it) })
        return Shelf(client, session.sourceId, book)
    }

    // The album a song is in, by the server's own id: a library song's copy
    // on the server, or a song found online's album there. Null for a song
    // the server does not have, or with no server signed in.
    suspend fun serverAlbumOf(trackId: String?): String? {
        if (trackId.isNullOrBlank()) return null
        val here = shelf.value ?: return null
        val key = "${here.sourceId}|$trackId"
        albumOfSong.get(key)?.let { return it }
        val found = withContext(Dispatchers.IO) {
            if (isFind(trackId)) {
                online.song(trackId)?.takeIf { it.sourceId == here.sourceId }?.albumId?.takeIf(String::isNotBlank)
            } else {
                sources.copies(trackId).firstOrNull { it.sourceId == here.sourceId }?.let { sources.albumNativeId(it.albumId) }
            }
        } ?: return null
        albumOfSong.put(key, found)
        return found
    }

    // The server's id for an album of the library, from its songs.
    suspend fun serverAlbumOf(trackIds: List<String>): String? {
        for (id in trackIds.take(8)) serverAlbumOf(id)?.let { return it }
        return null
    }

    // Keeps the art getAlbum came with, when it came from the server in use.
    fun note(client: SubsonicClient, albumId: String, art: AnimatedArt?) {
        shelf.value?.takeIf { it.client === client }?.book?.note(albumId, art)
    }

    // The album's art as it becomes known: what the phone keeps for a
    // downloaded album, else what the book holds, then the server's answer,
    // then anything getAlbum brings meanwhile. Null for none.
    fun artOf(albumId: String?): Flow<AnimatedArt?> {
        return shelf.flatMapLatest<Shelf?, AnimatedArt?> { here ->
            if (here == null || albumId.isNullOrBlank()) {
                flowOf(null)
            } else {
                flow<AnimatedArt?> {
                    val kept = withContext(Dispatchers.IO) { store.read(LoopAlbum(here.sourceId, albumId)) }
                    if (kept != null) {
                        emit(withContext(Dispatchers.IO) { store.local(kept) })
                        return@flow
                    }
                    emit(here.book.known(albumId))
                    here.book.art(albumId)
                    here.book.version.collect { emit(here.book.known(albumId)) }
                }
            }
        }.distinctUntilChanged()
    }

    // The loop an album page plays in place of its cover: the square one of
    // `album` (the server's id for the page's album) while the setting
    // plays loops on album pages.
    fun pageLoop(album: Flow<String?>): Flow<AnimatedClip?> =
        settings.prefs.map { it.animatedArt }.distinctUntilChanged().flatMapLatest { setting ->
            if (setting == AnimatedArtSetting.Off) {
                flowOf(null)
            } else {
                album.distinctUntilChanged().flatMapLatest { artOf(it) }.map { setting.onAlbumPage(it) }
            }
        }.distinctUntilChanged()

    // What the server says of an album of `sourceId` now, for keeping it
    // with a download: asked when not known yet. Unknown while the server
    // is not the one in use, or could not say.
    suspend fun answerFor(sourceId: String, albumId: String): KnownArt {
        val here = shelf.value?.takeIf { it.sourceId == sourceId } ?: return KnownArt.Unknown
        here.book.art(albumId)
        return here.book.peek(albumId)
    }

    // When a song starts, its album's art and the next song's are asked for,
    // so they are ready when the player or the next song shows them.
    private suspend fun askAhead() {
        combine(
            settings.prefs.map { it.animatedArt }.distinctUntilChanged(),
            playback.now.map { it.trackId }.distinctUntilChanged(),
            playback.upNext.map { it.getOrNull(1)?.trackId }.distinctUntilChanged(),
            shelf,
        ) { setting, playing, next, here -> Ahead(setting, playing, next, here) }
            .collectLatest { (setting, playing, next, here) ->
                if (setting == AnimatedArtSetting.Off || here == null || playing == null) return@collectLatest
                delay(AHEAD_SETTLE_MS)
                try {
                    val ids = albumsToAsk(serverAlbumOf(playing), listOf(serverAlbumOf(next)))
                    val kept = withContext(Dispatchers.IO) { ids.filter { store.read(LoopAlbum(here.sourceId, it)) != null }.toSet() }
                    here.book.ahead(ids.filterNot { it in kept })
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // The library being rebuilt, say: asked again with the next song.
                }
            }
    }

    private data class Ahead(val setting: AnimatedArtSetting, val playing: String?, val next: String?, val here: Shelf?)
}

// What the book holds for an album now: its art, or null.
fun AnimatedArtBook.known(albumId: String): AnimatedArt? = (peek(albumId) as? KnownArt.Has)?.art
