package app.winters.octo.playback

import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.OnlineDao
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.UserDao
import app.winters.octo.catalog.isFind
import app.winters.octo.catalog.searchKey
import app.winters.octo.discovery.asTrack
import app.winters.octo.output.OutputSwitch
import app.winters.octo.player.PlayerSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

// Songs played this recently are not picked again.
private const val RECENT_PLAYS = 50

// How near the end of the last song the new songs go in: early enough for
// the server to answer and for a crossfade to load the next one.
private const val LEAD_MS = 20_000L
private const val LOAD_AHEAD_MS = 15_000L

// How often to look at how far into the last song the player is.
private const val WATCH_EVERY_MS = 1_000L

// Whether it is time to add songs: Autoplay is on, repeat is off, nothing
// comes after the song that is on, and it is within `leadMs` of its end.
fun autoplayDue(enabled: Boolean, repeatMode: Int, hasNext: Boolean, remainingMs: Long, leadMs: Long): Boolean =
    enabled && repeatMode == Player.REPEAT_MODE_OFF && !hasNext && remainingMs <= leadMs

// Keeps music playing when the queue runs out. Near the end of the last
// song, with repeat off, it adds songs like it, marked as Autoplay's so the
// queue can tell them from the listener's own. The service attaches its
// player and calls `check` whenever the song, the queue, repeat or playing
// changes. Turning the setting off stops it adding.
@OptIn(UnstableApi::class)
@Singleton
class Autoplay @Inject constructor(
    private val settings: PlayerSettings,
    private val radio: LibraryRadio,
    private val catalog: CatalogDao,
    private val online: OnlineDao,
    private val user: UserDao,
    private val playable: PlayableSongs,
    private val stations: StationRefill,
) {
    private var player: OutputSwitch? = null
    private var scope: CoroutineScope? = null
    private var enabled = false
    private var settingsJob: Job? = null

    // Watches the last song until it is time, then adds; for one entry at a time.
    private var watch: Job? = null
    private var watching: String? = null

    // The last song Autoplay added after, so it tries once per song.
    private var doneFor: String? = null

    fun attach(player: OutputSwitch, scope: CoroutineScope) {
        this.player = player
        this.scope = scope
        settingsJob = scope.launch {
            settings.prefs.map { it.autoplay }.distinctUntilChanged().collect { on ->
                enabled = on
                check()
            }
        }
    }

    fun detach() {
        settingsJob?.cancel()
        stop()
        player = null
        scope = null
    }

    fun check() {
        val player = player ?: return
        val item = player.currentMediaItem
        val key = item?.entryId
        val last = enabled && key != null && key != doneFor && !isRadio(item.mediaId) && !stations.keepsGoing(item) &&
            player.repeatMode == Player.REPEAT_MODE_OFF && !player.hasNextMediaItem() &&
            (player.isPlaying || player.playbackState == Player.STATE_ENDED)
        if (!last) {
            // Paused, repeat on, songs added, or switched off: stand down.
            stop()
            return
        }
        if (watch?.isActive == true && watching == key) return
        stop()
        watching = key
        watch = scope?.launch { watchAndAdd(player, key, item.mediaId) }
    }

    private fun stop() {
        watch?.cancel()
        watch = null
        watching = null
    }

    private suspend fun watchAndAdd(player: OutputSwitch, key: String, seedId: String) {
        // A planned blend can start up to LONGEST_EARLY_EXIT_MS before the end.
        val early = if (player.crossfadeMs > 0) LONGEST_EARLY_EXIT_MS else 0
        val lead = maxOf(LEAD_MS, player.crossfadeMs + early + LOAD_AHEAD_MS)
        while (!autoplayDue(enabled, player.repeatMode, player.hasNextMediaItem(), player.remainingMs(), lead)) {
            delay(WATCH_EVERY_MS)
        }
        val entries = List(player.mediaItemCount) { player.getMediaItemAt(it) }
        val queued = entries.map { it.mediaId }
        // The listener's own songs keep Autoplay near their taste.
        val anchors = entries.takeLast(30).filterNot { it.isAutoplay }.map { it.mediaId }.filter { it != seedId }.takeLast(10).reversed()
        val items = playable.items(picksAfter(seedId, queued, anchors)).map { it.markedAutoplay() }
        // Tried once for this song, whatever came of it.
        doneFor = key
        if (items.isEmpty()) {
            Log.i("Octo", "autoplay: nothing to add")
            return
        }
        // Only if the song is still the last one and the setting still on.
        if (!enabled || player.currentMediaItem?.entryId != key || player.hasNextMediaItem()) return
        val first = player.mediaItemCount
        player.addMediaItems(first, items)
        // The song already ended while the server answered: carry on.
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(first, 0)
            player.play()
        }
        Log.i("Octo", "autoplay: added ${items.size}")
    }

    // Octo's radio for the seed and the listener's own recent songs
    // (`anchors`), from the library and the server's suggestions; else the
    // library's songs by the same artist, then in the same genre.
    private suspend fun picksAfter(seedId: String, queued: List<String>, anchors: List<String>): List<String> {
        val seed = seedTrack(seedId) ?: return emptyList()
        val recent = user.playedTracks().first().sortedByDescending { it.lastPlayedAt }.take(RECENT_PLAYS).map { it.track.id }
        val exclude = (queued + recent + seed.id).toSet()
        val own = catalog.tracksByIdsUnordered(anchors).associateBy { it.id }
        val seeds = listOf(seed) + anchors.mapNotNull(own::get)
        val mixed = radio.songsLike(seeds, AUTOPLAY_BATCH, exclude, before = queued.takeLast(30))
        if (mixed.isNotEmpty()) return mixed
        return autoplayPicks(emptyList(), sameArtist(seed).shuffled(), sameGenre(seed).shuffled(), exclude)
    }

    // The song as the library has it, or as found online.
    private suspend fun seedTrack(id: String): TrackEntity? =
        if (isFind(id)) online.byIds(listOf(id)).firstOrNull()?.asTrack() else catalog.track(id)

    // The library's songs by the seed's artist. A song found online is
    // matched to a library artist by name.
    private suspend fun sameArtist(seed: TrackEntity): List<String> {
        val artistIds = if (isFind(seed.id)) catalog.artistsWithKeys(listOf(searchKey(seed.artist))).map { it.id } else listOf(seed.artistId)
        return artistIds.flatMap { catalog.artistAlbums(it).first() }.flatMap { catalog.albumTrackIds(it.id) }
    }

    private suspend fun sameGenre(seed: TrackEntity): List<String> =
        if (seed.genre.isBlank()) emptyList() else catalog.genreTrackIds(seed.genre)

    // How long until the song ends, in real time at the current speed.
    private fun OutputSwitch.remainingMs(): Long {
        val length = duration.takeIf { it > 0 } ?: currentMediaItem?.mediaMetadata?.durationMs ?: return 0
        return ((length - currentPosition).coerceAtLeast(0) / playbackParameters.speed).toLong()
    }
}
