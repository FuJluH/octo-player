package app.winters.octo.playback

import android.content.ComponentName
import android.content.Context
import android.media.AudioManager
import android.os.SystemClock
import androidx.core.content.ContextCompat
import androidx.media3.common.DeviceInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import app.winters.octo.catalog.CatalogDao
import com.google.common.util.concurrent.ListenableFuture
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// What the app shows about the song that is on.
data class NowPlaying(
    val trackId: String? = null,
    val title: String? = null,
    val artist: String? = null,
    val artwork: String? = null,
    val album: String? = null,
    val albumId: String? = null,
    val artistId: String? = null,
    val quality: AudioQuality? = null,
    val isPlaying: Boolean = false,
    val durationMs: Long = 0,
    val shuffle: Boolean = false,
    val repeatMode: Int = Player.REPEAT_MODE_OFF,
    // Playing on a TV or speaker, and that device's volume from 0 to 1.
    val casting: Boolean = false,
    val deviceVolume: Float? = null,
    // Marked explicit, for the "E" by its title.
    val explicit: Boolean = false,
    // Meant to play: true while it plays, and while it connects or buffers.
    val playWhenReady: Boolean = false,
    // A live station on now, with what it has on air.
    val live: LiveNow? = null,
)

// The app's line to the playback service. Screens ask it to play things and
// read what is playing from it; the service does the rest.
@Singleton
class PlaybackConnection @Inject constructor(
    @ApplicationContext private val context: Context,
    private val catalog: CatalogDao,
    private val lengths: RealLengths,
) {
    private val scope = MainScope()
    private var future: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null
    // Requests made before the connection is up run as soon as it is.
    private val waiting = mutableListOf<(MediaController) -> Unit>()

    private val _now = MutableStateFlow(NowPlaying())
    val now: StateFlow<NowPlaying> = _now

    // The current song and everything after it, in the order they will play.
    private val _upNext = MutableStateFlow<List<QueueEntry>>(emptyList())
    val upNext: StateFlow<List<QueueEntry>> = _upNext

    // The songs played before the current one, oldest first.
    private val _played = MutableStateFlow<List<QueueEntry>>(emptyList())
    val played: StateFlow<List<QueueEntry>> = _played

    // Counts the times the player said its clock moved other than by
    // playing on: a seek, a new song, play or pause, or a new speed. The
    // lyrics take a fresh anchor on each.
    private val _timeEvents = MutableStateFlow(0)
    val timeEvents: StateFlow<Int> = _timeEvents

    init {
        // A song's real length found out while it plays reaches the queue
        // rows already on screen.
        scope.launch {
            lengths.corrected.collect {
                controller?.let { c ->
                    publish(c)
                    publishQueue(c)
                }
            }
        }
    }

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            publish(player)
            if (events.containsAny(
                    Player.EVENT_POSITION_DISCONTINUITY,
                    Player.EVENT_MEDIA_ITEM_TRANSITION,
                    Player.EVENT_IS_PLAYING_CHANGED,
                    Player.EVENT_PLAYBACK_PARAMETERS_CHANGED,
                )
            ) {
                _timeEvents.value++
            }
            if (events.containsAny(Player.EVENT_TIMELINE_CHANGED, Player.EVENT_MEDIA_ITEM_TRANSITION, Player.EVENT_SHUFFLE_MODE_ENABLED_CHANGED)) {
                publishQueue(player)
            }
        }
    }

    // Called when the app comes to the front.
    fun connect() {
        if (future != null) return
        val token = SessionToken(context, ComponentName(context, OctoPlaybackService::class.java))
        val pending = MediaController.Builder(context, token).buildAsync()
        future = pending
        pending.addListener(
            {
                val ready = runCatching { pending.get() }.getOrNull() ?: return@addListener
                controller = ready
                ready.addListener(listener)
                publish(ready)
                publishQueue(ready)
                waiting.forEach { it(ready) }
                waiting.clear()
            },
            ContextCompat.getMainExecutor(context),
        )
    }

    // Called when the app leaves the front, so the service can stop when
    // nothing is playing.
    fun release() {
        controller?.removeListener(listener)
        future?.let(MediaController::releaseFuture)
        future = null
        controller = null
    }

    fun positionMs(): Long = controller?.currentPosition ?: 0

    // How fast the player is playing now, 1 being normal.
    fun speed(): Float = controller?.playbackParameters?.speed ?: 1f

    // Plays a list of songs, starting at one of them, or shuffled.
    // `source` names the list for the queue's headings ("OK Computer").
    fun playTracks(trackIds: List<String>, startIndex: Int = 0, shuffle: Boolean = false, source: String? = null) =
        play(trackIds, startIndex, shuffle, QueueSource.Played(source).encoded())

    // Plays a station's songs from one of them, under its name; as they run
    // low, more of its kind are added. Shuffled, its songs are put in a new
    // order, so the songs added later still come after them.
    fun playStation(trackIds: List<String>, startIndex: Int, id: String, name: String, shuffle: Boolean = false) {
        val ids = if (shuffle) trackIds.shuffled() else trackIds
        play(ids, if (shuffle) 0 else startIndex, false, QueueSource.Station(id, name).encoded())
    }

    private fun play(trackIds: List<String>, startIndex: Int, shuffle: Boolean, word: String) {
        if (trackIds.isEmpty()) return
        withController { c ->
            val items = trackIds.map { songRequest(it, word) }
            c.shuffleModeEnabled = shuffle
            if (shuffle) c.setMediaItems(items, true) else c.setMediaItems(items, startIndex, 0)
            c.prepare()
            c.play()
        }
    }

    // Puts a list of songs in place of the queue, at one of them and a place
    // in it, paused: for picking up a queue from another device.
    fun loadQueue(trackIds: List<String>, index: Int, positionMs: Long) {
        if (trackIds.isEmpty()) return
        withController { c ->
            c.shuffleModeEnabled = false
            c.setMediaItems(trackIds.map(::songRequest), index.coerceIn(trackIds.indices), positionMs.coerceAtLeast(0))
            c.pause()
            c.prepare()
        }
    }

    fun playAlbum(albumId: String, shuffle: Boolean = false) {
        scope.launch { playTracks(catalog.albumTrackIds(albumId), 0, shuffle, catalog.album(albumId).first()?.title) }
    }

    // Plays the stations a list holds, in its order, from the one tapped:
    // Back and Next go through them.
    fun playLineup(stationIds: List<String>, startIndex: Int, source: String? = null) =
        playTracks(stationIds, startIndex.coerceIn(0, (stationIds.size - 1).coerceAtLeast(0)), source = source)

    // With nothing queued, the play button shuffles the whole library. A
    // station that is connecting counts as playing, so the button stops it.
    fun togglePlayPause() = withController { c ->
        when {
            c.mediaItemCount == 0 -> scope.launch { playTracks(catalog.allTrackIds(), shuffle = true) }
            c.isPlaying -> c.pause()
            c.playWhenReady && c.currentMediaItem?.mediaId?.let(::isRadio) == true -> c.pause()
            else -> {
                if (c.playbackState == Player.STATE_IDLE) c.prepare()
                c.play()
            }
        }
    }

    // Plays what was asked for out loud, like "Drake". The service works out
    // what that means; saying nothing in particular shuffles everything.
    fun playFromSearch(query: String) = withController { c ->
        val request = MediaItem.RequestMetadata.Builder().setSearchQuery(query).build()
        c.setMediaItem(MediaItem.Builder().setRequestMetadata(request).build())
        c.prepare()
        c.play()
    }

    fun seekTo(positionMs: Long) = withController { it.seekTo(positionMs.coerceAtLeast(0)) }

    // The volume of the TV or speaker music is cast to, from 0 to 1.
    fun setDeviceVolume(fraction: Float) = withController { c ->
        val max = c.deviceInfo.maxVolume.coerceAtLeast(1)
        c.setDeviceVolume(Math.round(fraction.coerceIn(0f, 1f) * max), 0)
    }

    // A volume button pressed while casting: the device goes up or down a
    // step. Answers whether it was taken, which it is only while casting.
    fun stepDeviceVolume(up: Boolean): Boolean {
        val c = controller ?: return false
        if (!_now.value.casting) return false
        if (up) c.increaseDeviceVolume(0) else c.decreaseDeviceVolume(0)
        return true
    }

    fun toggleShuffle() = withController { it.shuffleModeEnabled = !it.shuffleModeEnabled }

    // Off, then the whole queue, then just this song.
    fun cycleRepeat() = withController { c ->
        c.repeatMode = when (c.repeatMode) {
            Player.REPEAT_MODE_OFF -> Player.REPEAT_MODE_ALL
            Player.REPEAT_MODE_ALL -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
    }

    fun next() = withController { it.seekToNext() }

    fun previous() = withController { it.seekToPrevious() }

    // Asked of the service by name, so it can tell "Play next" from "Add to
    // queue" and put the songs right after the current one under shuffle too.
    fun playNext(trackIds: List<String>) = withController { c ->
        if (trackIds.isNotEmpty()) c.sendCustomCommand(PLAY_NEXT, playNextArgs(trackIds))
    }

    fun playLast(trackIds: List<String>) = withController { c -> c.addMediaItems(trackIds.map(::songRequest)) }

    // Moves from the "Up next" list, by position in the queue. Taking songs
    // out goes through QueueEditor, by each song's key.
    fun moveInQueue(from: Int, to: Int) = withController { it.moveMediaItem(from, to) }

    fun playAt(index: Int) = withController { c ->
        c.seekToDefaultPosition(index)
        if (c.playbackState == Player.STATE_IDLE) c.prepare()
        c.play()
    }

    // ---- Play next with an undo, for a swipe on a song row ----

    // Puts songs next, like playNext, then hands `inserted` a way to take
    // those same songs back out, wherever they have moved to since.
    fun playNextUndoable(trackIds: List<String>, inserted: (undo: () -> Unit) -> Unit) {
        if (trackIds.isEmpty()) return
        withController { c ->
            // Through the same command as Play next, so it lands right after
            // the current song in shuffled order too. It goes in just after
            // the current song in the list, which is where undo looks first.
            val at = (c.currentMediaItemIndex + 1).coerceAtMost(c.mediaItemCount)
            c.sendCustomCommand(PLAY_NEXT, playNextArgs(trackIds))
            inserted { removeInserted(trackIds, at) }
        }
    }

    private fun removeInserted(trackIds: List<String>, insertedAt: Int) = withController { c ->
        val queue = List(c.mediaItemCount) { c.getMediaItemAt(it).mediaId }
        val start = findInserted(queue, trackIds, insertedAt) ?: return@withController
        c.removeMediaItems(start, start + trackIds.size)
    }

    // ---- End of play next with an undo ----

    private fun withController(action: (MediaController) -> Unit) {
        val ready = controller
        if (ready != null) action(ready) else {
            waiting += action
            connect()
        }
    }

    private val liveClock = LiveClock(SystemClock::elapsedRealtime)

    private fun publish(player: Player) {
        val item: MediaItem? = player.currentMediaItem
        val meta = item?.mediaMetadata
        val station = item?.takeIf { isRadio(it.mediaId) }
        val since = liveClock.heard(station?.let { it.entryId ?: it.mediaId }, player.isPlaying, player.playWhenReady)
        val live = station?.let {
            liveNowOf(it.mediaId, meta?.icyRead(), List(player.mediaItemCount) { i -> player.getMediaItemAt(i).mediaId }, player.currentMediaItemIndex, since)
        }
        _now.value = NowPlaying(
            trackId = item?.mediaId,
            title = meta?.title?.toString(),
            artist = meta?.artist?.toString(),
            artwork = meta?.artworkRef(),
            album = meta?.albumTitle?.toString(),
            albumId = meta?.extra(EXTRA_ALBUM_ID),
            artistId = meta?.extra(EXTRA_ARTIST_ID),
            quality = audioQuality(meta?.extra(EXTRA_MIME), player.currentTracks)
                ?.playingAt(if (player.deviceInfo.playbackType == DeviceInfo.PLAYBACK_TYPE_REMOTE) null else outputRate()),
            isPlaying = player.isPlaying,
            durationMs = songLengthMs(listedLengthMs(item), player.duration),
            shuffle = player.shuffleModeEnabled,
            repeatMode = player.repeatMode,
            casting = player.deviceInfo.playbackType == DeviceInfo.PLAYBACK_TYPE_REMOTE,
            deviceVolume = deviceVolumeOf(player),
            explicit = meta?.isExplicit() == true,
            playWhenReady = player.playWhenReady,
            live = live,
        )
    }

    private fun deviceVolumeOf(player: Player): Float? {
        val info = player.deviceInfo
        if (info.playbackType != DeviceInfo.PLAYBACK_TYPE_REMOTE || !player.isCommandAvailable(Player.COMMAND_GET_DEVICE_VOLUME)) return null
        val span = (info.maxVolume - info.minVolume).coerceAtLeast(1)
        return ((player.deviceVolume - info.minVolume).toFloat() / span).coerceIn(0f, 1f)
    }

    private fun publishQueue(player: Player) {
        val timeline = player.currentTimeline
        val shuffle = player.shuffleModeEnabled
        val items = List(player.mediaItemCount, player::getMediaItemAt)
        val trackIds = items.map { it.mediaId }
        val entryIds = items.map { it.entryId }
        val current = player.currentMediaItemIndex
        fun entry(slot: QueueSlot): QueueEntry {
            val item = items[slot.index]
            val meta = item.mediaMetadata
            return QueueEntry(
                key = slot.key,
                index = slot.index,
                trackId = trackIds[slot.index],
                title = meta.title?.toString().orEmpty(),
                artist = meta.artist?.toString().orEmpty(),
                artwork = meta.artworkRef(),
                durationMs = listedLengthMs(item),
                explicit = meta.isExplicit(),
                autoplay = item.isAutoplay,
                source = item.queueSource,
            )
        }
        _upNext.value = upNextOrder(trackIds, current, entryIds) {
            timeline.getNextWindowIndex(it, Player.REPEAT_MODE_OFF, shuffle)
        }.map(::entry)
        _played.value = playedOrder(trackIds, current, entryIds) {
            timeline.getPreviousWindowIndex(it, Player.REPEAT_MODE_OFF, shuffle)
        }.map(::entry)
    }

    // A song's listed length, corrected where playing it found it wrong.
    private fun listedLengthMs(item: MediaItem?): Long =
        item?.let { lengths.lengthMs(it.mediaId, it.mediaMetadata.durationMs ?: 0) } ?: 0

    // The rate the phone's audio output mixes at, which Android resamples
    // songs to unless it plays them bit for bit.
    private fun outputRate(): Int? =
        context.getSystemService(AudioManager::class.java)?.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)?.toIntOrNull()
}
