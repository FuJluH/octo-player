package app.winters.octo.player

import android.os.Build
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.animated.AnimatedArts
import app.winters.octo.animated.FULL_SCREEN_BACKGROUND_GAIN
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.OnlineDao
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.isFind
import app.winters.octo.discovery.asTrack
import app.winters.octo.lyrics.Lyrics
import app.winters.octo.lyrics.LyricsAnswer
import app.winters.octo.lyrics.LyricsChoices
import app.winters.octo.lyrics.LyricsRepository
import app.winters.octo.lyrics.LyricsSong
import app.winters.octo.lyrics.NetworkWatch
import app.winters.octo.playback.DeviceVolume
import app.winters.octo.playback.LikeStore
import app.winters.octo.playback.NowPlaying
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.playback.PlaylistStore
import app.winters.octo.playback.QueueEditor
import app.winters.octo.playback.QueueEntry
import app.winters.octo.playback.SleepState
import app.winters.octo.playback.SleepTimer
import app.winters.octo.playback.isRadio
import app.winters.octo.player.immersive.BackgroundMode
import app.winters.octo.player.immersive.WashArtwork
import app.winters.octo.player.immersive.drawnMode
import app.winters.octo.player.immersive.drawnRange
import app.winters.octo.player.immersive.over
import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.ui.common.Feedback
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.shareIn
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

// Everything the full player shows, and what its buttons do.
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class PlayerViewModel @Inject constructor(
    private val playback: PlaybackConnection,
    palette: ArtworkPalette,
    private val likes: LikeStore,
    catalog: CatalogDao,
    online: OnlineDao,
    settings: PlayerSettings,
    private val deviceVolume: DeviceVolume,
    private val sleepTimer: SleepTimer,
    private val lyricsRepository: LyricsRepository,
    private val lyricsChoices: LyricsChoices,
    private val networkWatch: NetworkWatch,
    private val editor: QueueEditor,
    private val playlists: PlaylistStore,
    private val feedback: Feedback,
    private val artwork: WashArtwork,
    animatedArts: AnimatedArts,
) : ViewModel() {
    val now: StateFlow<NowPlaying> = playback.now
    val upNext: StateFlow<List<QueueEntry>> = playback.upNext
    val played: StateFlow<List<QueueEntry>> = playback.played

    // The album name for the top of the player, or nothing for a single. A
    // song found online has no album in the library to count, so it shows none.
    val albumLabel: StateFlow<String?> = playback.now
        .map { Triple(it.albumId, it.album, it.title) }
        .distinctUntilChanged()
        .flatMapLatest { (albumId, album, title) ->
            if (albumId.isNullOrEmpty()) {
                flowOf(null)
            } else {
                catalog.album(albumId).map { albumLabel(album, title, it?.songCount ?: 0) }
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // Whether the song on now is in Liked songs.
    val liked: StateFlow<Boolean> = combine(playback.now, likes.liked) { now, liked -> now.trackId in liked }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    fun toggleLike() {
        playback.now.value.trackId?.takeUnless(::isFind)?.let(likes::toggle)
    }

    // The song on now when it was found online, for the download button
    // that stands where the heart would be.
    val find: StateFlow<TrackEntity?> = playback.now
        .map { it.trackId }
        .distinctUntilChanged()
        .flatMapLatest { id ->
            if (id != null && isFind(id)) online.songFlow(id).map { it?.asTrack() } else flowOf(null)
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val prefs: StateFlow<PlayerPrefs> = settings.prefs
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerPrefs())

    // Colours follow the artwork, not the song, so an album plays through
    // without the background flickering. `content` is the colour for the
    // player's words and icons, decided from what the chosen background
    // draws (the prepared cover, shared with the background), and `show`
    // how far the background dims for them.
    // Under a tall loop in Full screen the background is drawn brighter
    // (FULL_SCREEN_BACKGROUND_GAIN), so `brightColors` decides the words'
    // color and dimming for that, the same way.
    private val drawn = combine(
        playback.now.map { it.artwork }.distinctUntilChanged(),
        settings.prefs.map { it.background to it.liveBackground }.distinctUntilChanged(),
    ) { ref, prefs -> ref to prefs }
        .mapLatest { (ref, prefs) ->
            val (background, live) = prefs
            val colors = palette.colorsFor(ref)
            val mode = drawnMode(background.mode, Build.VERSION.SDK_INT)
            val cover = if (mode == BackgroundMode.Default || mode == BackgroundMode.Artwork) {
                runCatching { artwork.prepare(ref, colors, background.tuning).range }.getOrNull()
            } else {
                null
            }
            colors to drawnRange(mode, colors, background, cover, live && LiveBackgroundSupported)
        }
        .shareIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), replay = 1)

    val colors: StateFlow<PlayerColors> = drawn
        .map { (colors, range) -> colors.over(range) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerColors.Quiet)

    val brightColors: StateFlow<PlayerColors> = drawn
        .map { (colors, range) -> colors.over(range?.scaled(FULL_SCREEN_BACKGROUND_GAIN)) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerColors.Quiet)

    // The animated art of the song's album, from its server, while the
    // setting has it on; none for a live station.
    val animatedArt: StateFlow<AnimatedArt?> = settings.prefs
        .map { it.animatedArt != AnimatedArtSetting.Off }
        .distinctUntilChanged()
        .flatMapLatest { on ->
            if (!on) {
                flowOf(null)
            } else {
                playback.now
                    .map { now -> now.trackId.takeIf { now.live == null } }
                    .distinctUntilChanged()
                    // The song's album, or null with no song on.
                    .mapLatest { id -> id?.let { AlbumOnServer(animatedArts.serverAlbumOf(it)) } }
                    .distinctUntilChanged()
                    .flatMapLatest { album -> if (album == null) flowOf(null) else animatedArts.artOf(album.id) }
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun positionMs() = playback.positionMs()
    fun seekTo(positionMs: Long) = playback.seekTo(positionMs)
    fun togglePlayPause() = playback.togglePlayPause()
    fun next() = playback.next()
    fun previous() = playback.previous()
    fun toggleShuffle() = playback.toggleShuffle()
    fun cycleRepeat() = playback.cycleRepeat()
    // The phone's volume, or while casting the TV or speaker's.
    val volume: StateFlow<Float> = combine(deviceVolume.level, playback.now) { phone, now -> now.deviceVolume ?: phone }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), deviceVolume.level.value)

    fun setVolume(fraction: Float) = if (playback.now.value.casting) playback.setDeviceVolume(fraction) else deviceVolume.set(fraction)
    fun moveInQueue(from: Int, to: Int) = playback.moveInQueue(from, to)
    fun playAt(index: Int) = playback.playAt(index)

    // Queue edits go by each song's key, so a quick second swipe never
    // takes out the wrong song. Those that take songs out can be undone.
    fun removeFromQueue(entry: QueueEntry) {
        val undo = editor.remove(entry.key) ?: return
        feedback.undoable("Removed from the queue") { editor.undo(undo) }
    }

    // Everything but the song that is on.
    fun clearQueue() {
        val undo = editor.clear() ?: return
        feedback.undoable("Queue cleared") { editor.undo(undo) }
    }

    fun removePlayed() {
        val undo = editor.removePlayed() ?: return
        feedback.undoable("Played songs removed") { editor.undo(undo) }
    }

    fun playNextInQueue(entry: QueueEntry) = editor.playNext(entry.key)

    // The listener's queue as a playlist: what played, the song on now and
    // what is still to come, without the songs Autoplay added.
    fun saveQueueAsPlaylist(name: String) {
        val ids = (played.value + upNext.value).filterNot { it.autoplay || isRadio(it.trackId) }.map { it.trackId }
        playlists.create(name, ids)
        feedback.show("Saved as ${name.trim()}")
    }

    val sleep: StateFlow<SleepState> = sleepTimer.state
    fun sleepIn(minutes: Int) = sleepTimer.start(minutes)
    fun sleepAtEndOfSong() = sleepTimer.startEndOfSong()
    fun sleepAfterSongs(count: Int) = sleepTimer.startAfterSongs(count)
    fun extendSleep(minutes: Int) = sleepTimer.extend(minutes)
    fun cancelSleep() = sleepTimer.cancel()

    // From a queue row's menu: the music stops once that song has played.
    fun sleepAfter(entry: QueueEntry) {
        sleepTimer.startAfter(entry.key, entry.title)
        feedback.undoable("Stops after ${entry.title}") { sleepTimer.cancel() }
    }

    // The rating of the song on now, 0 when it has none or was found online.
    val rating: StateFlow<Int> = playback.now
        .map { it.trackId }
        .distinctUntilChanged()
        .flatMapLatest { id ->
            if (id == null || isFind(id)) flowOf(0) else catalog.trackFlow(id).map { it?.rating ?: 0 }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    // Whether the lyrics show in place of the artwork. They are only looked
    // up while they show, and follow the song while they do.
    private val lyricsShown = MutableStateFlow(false)
    val lyricsOpen: StateFlow<Boolean> = lyricsShown
    fun toggleLyrics() {
        lyricsShown.value = !lyricsShown.value
    }

    // What the lyrics view shows. They follow the listener's choice for the
    // song too: picking other lyrics shows them at once, and hiding them
    // shows that they are hidden. A choice sent to the server, or a retry,
    // fetches them again at once. See lyricsStates for when they are
    // looked up.
    private val lyricsState = MutableStateFlow<LyricsState>(LyricsState.Hidden)
    val lyrics: StateFlow<LyricsState> = lyricsState.asStateFlow()

    // Whether the lyrics view is on screen: something shows this model's
    // lyrics. A short gap (turning the phone) does not count as leaving.
    private val lyricsWatched: Flow<Boolean> = lyricsState.subscriptionCount
        .map { it > 0 }
        .distinctUntilChanged()
        .transformLatest { on ->
            if (!on) delay(LYRICS_LEAVE_AFTER_MS)
            emit(on)
        }
        .onStart { emit(false) }
        .distinctUntilChanged()

    // Whether nothing shows the lyrics right now, for what a lookup saves.
    private fun lyricsAway() = lyricsState.subscriptionCount.value == 0

    // The song on now while lyrics are open.
    private val lyricsSong: Flow<String?> =
        combine(playback.now.map { it.trackId }.distinctUntilChanged(), lyricsShown) { id, open -> id.takeIf { open } }
            .distinctUntilChanged()

    init {
        viewModelScope.launch {
            val wanted = lyricsSong.flatMapLatest { id ->
                if (id == null) {
                    flowOf(null)
                } else {
                    combine(lyricsChoices.choiceFor(id), lyricsRepository.revisionOf(id)) { choice, revision ->
                        LyricsWanted(id, choice.hidden, choice.pick to revision)
                    }
                }
            }
            lyricsStates(wanted, lyricsWatched, ::lookUpLyrics, networkWatch::awaitChange).collect { lyricsState.value = it }
        }
    }

    private suspend fun lookUpLyrics(id: String, resumed: Boolean): LyricsAnswer {
        val now = playback.now.value.takeIf { it.trackId == id }
        val song = LyricsSong(id, now?.title.orEmpty(), now?.artist.orEmpty(), now?.album.orEmpty(), now?.durationMs ?: 0L)
        return lyricsRepository.answerFor(song, resumed, ::lyricsAway)
    }

    // While lyrics show on screen, the songs either side of this one have
    // theirs looked up once the song has settled, so skipping shows them at
    // once. A skip before then starts the wait again, so skipping quickly
    // through the queue asks for nothing.
    init {
        viewModelScope.launch {
            combine(lyricsSong, lyricsWatched) { id, on -> id.takeIf { on } }
                .distinctUntilChanged()
                .collectLatest { id ->
                    if (id == null) return@collectLatest
                    delay(LYRICS_PREFETCH_SETTLE_MS)
                    listOfNotNull(upNext.value.getOrNull(1), played.value.lastOrNull())
                        .filterNot { isRadio(it.trackId) || it.trackId == id }
                        .forEach { entry ->
                            // A neighbour's lyrics are only a head start; a lookup that
                            // fails saves nothing, and it is asked again when it plays.
                            lyricsRepository.answerFor(
                                LyricsSong(entry.trackId, entry.title, entry.artist, "", entry.durationMs),
                                away = ::lyricsAway,
                            )
                        }
                }
        }
    }
}

// A song's album by its id on the server; null when the server has none.
private data class AlbumOnServer(val id: String?)

// How long the lyrics view may be gone before it counts as off screen.
private const val LYRICS_LEAVE_AFTER_MS = 5_000L

// How long a song must stay on before its neighbours' lyrics are looked up.
private const val LYRICS_PREFETCH_SETTLE_MS = 1_200L

// What the lyrics view shows.
sealed interface LyricsState {
    data object Hidden : LyricsState
    // The listener hid this song's lyrics.
    data object HiddenForSong : LyricsState
    data object Loading : LyricsState
    data object None : LyricsState
    // The lookup could not finish (no network, the server did not answer):
    // not "no lyrics", and worth another try.
    data class Failed(val trackId: String) : LyricsState
    data class Found(val trackId: String, val lyrics: Lyrics) : LyricsState
}
