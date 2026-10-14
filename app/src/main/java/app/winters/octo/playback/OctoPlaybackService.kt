package app.winters.octo.playback

import android.app.PendingIntent
import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSourceBitmapLoader
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.CacheBitmapLoader
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSession.ConnectionResult
import androidx.media3.session.MediaSession.MediaItemsWithStartPosition
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import app.winters.octo.MainActivity
import app.winters.octo.catalog.OnlineDao
import app.winters.octo.catalog.isFind
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.design.OctoIcons
import app.winters.octo.discovery.Downloads
import app.winters.octo.discovery.FindLengths
import app.winters.octo.discovery.asTrack
import app.winters.octo.liveradio.LiveLookup
import app.winters.octo.offline.Prefetcher
import app.winters.octo.output.Casting
import app.winters.octo.output.DeviceMedia
import app.winters.octo.output.OutputSwitch
import app.winters.octo.output.Outputs
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.PlayerSettings
import app.winters.octo.server.QueueSync
import app.winters.octo.sound.AlbumRun
import app.winters.octo.sound.AudioSession
import app.winters.octo.sound.DeckSound
import app.winters.octo.sound.OctoRenderersFactory
import app.winters.octo.sound.SoundEngine
import app.winters.octo.ui.common.Feedback
import app.winters.octo.widget.QuickPicks
import app.winters.octo.widget.WidgetRemote
import app.winters.octo.widget.WidgetUpdates
import app.winters.octo.widget.widgetCommand
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.guava.future
import kotlinx.coroutines.isActive
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject

// The like toggle offered in the notification and on the lock screen, the
// download that stands in for it on a song found online, and Close.
private val LIKE = SessionCommand("app.winters.octo.LIKE", Bundle.EMPTY)
private val DOWNLOAD = SessionCommand("app.winters.octo.DOWNLOAD", Bundle.EMPTY)
private val CLOSE = SessionCommand("app.winters.octo.CLOSE", Bundle.EMPTY)

// "Play next" from the app, with the song ids to play.
internal val PLAY_NEXT = SessionCommand("app.winters.octo.PLAY_NEXT", Bundle.EMPTY)
private const val ARG_IDS = "ids"

internal fun playNextArgs(trackIds: List<String>) = Bundle().apply { putStringArrayList(ARG_IDS, ArrayList(trackIds)) }

// Apps that drive playback from a car or by voice: Android Auto and the
// assistant. They get full control even when not system apps.
private val carApps = setOf(
    "com.google.android.projection.gearhead",
    "com.google.android.carassistant",
    "com.google.android.googlequicksearchbox",
)

// Plays music with the screen off, and answers the lock screen, the
// notification, headphone buttons and the app.
@OptIn(UnstableApi::class)
@AndroidEntryPoint
class OctoPlaybackService : MediaLibraryService() {
    @Inject lateinit var playable: PlayableSongs
    @Inject lateinit var streams: Streams
    @Inject lateinit var likes: LikeStore
    @Inject lateinit var queue: QueueStore
    @Inject lateinit var plays: PlayStore
    @Inject lateinit var sleep: SleepTimer
    @Inject lateinit var playerSettings: PlayerSettings
    @Inject lateinit var car: CarLibrary
    @Inject lateinit var sound: SoundEngine
    @Inject lateinit var audioSession: AudioSession
    @Inject lateinit var serverQueue: QueueSync
    @Inject lateinit var quickPicks: QuickPicks
    @Inject lateinit var prefetch: Prefetcher
    @Inject lateinit var coversAhead: CoversAhead
    @Inject lateinit var editor: QueueEditor
    @Inject lateinit var autoplay: Autoplay
    @Inject lateinit var stationRefill: StationRefill
    @Inject lateinit var downloads: Downloads
    @Inject lateinit var online: OnlineDao
    @Inject lateinit var lengths: FindLengths
    @Inject lateinit var realLengths: RealLengths
    @Inject lateinit var outputs: Outputs
    @Inject lateinit var deviceMedia: DeviceMedia
    @Inject lateinit var feedback: Feedback
    @Inject lateinit var switcher: ServerSwitch
    @Inject lateinit var sessions: SessionRepository
    @Inject lateinit var liveLookup: LiveLookup

    private val scope = MainScope()
    // While the server in use changes, the emptied player is not saved over
    // the queue handed over.
    private var holding = false
    private val side = Side()
    // Whether crossfade is on, read by the decks' audio path.
    private val crossfadeOn = AtomicBoolean(false)
    // The phone's own player (two decks for crossfade), and the player the
    // session holds, which is the phone's or, while casting, the one that
    // drives the TV or speaker.
    private lateinit var local: OctoPlayer
    private lateinit var player: OutputSwitch
    private lateinit var casting: Casting
    private lateinit var tracker: PlayTracker
    private lateinit var headsets: HeadsetResume
    private var session: MediaLibrarySession? = null
    private val currentId = MutableStateFlow<String?>(null)
    private val queueChanged = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    private var positionSaver: Job? = null
    // Done once last session's queue is back, or there was none.
    private val restored = CompletableDeferred<Unit>()
    // Set by Close, until something plays again.
    private var closed = false
    // The home screen widgets: what they show, and what their buttons do.
    private val widgets by lazy { WidgetUpdates(this, scope) }
    private val widgetRemote by lazy { WidgetRemote(this, player, quickPicks, playable::items) }

    @kotlin.OptIn(FlowPreview::class)
    override fun onCreate() {
        super.onCreate()
        // Both decks shape their sound from the same settings, and share one
        // memory of the last album for Smart ReplayGain, since a crossfade
        // hands the next song to the other deck.
        val albums = AlbumRun()
        // While crossfade is on, each deck's sound processor stays in the
        // path so a blend can be shaped there.
        val sounds = HashMap<ExoPlayer, DeckSound>()
        // Each deck's buffering, told how long a stream waits before it starts.
        val loads = ArrayList<OctoLoadControl>()
        fun deck(): ExoPlayer {
            val renderers = OctoRenderersFactory(this, { sound.playing.value }, albums, crossfadeOn::get)
            val control = OctoLoadControl().also(loads::add)
            return buildDeck(this, streams.mediaSourceFactory(), renderers, audioSession.id, control)
                .also { deck -> renderers.sound?.let { sounds[deck] = it } }
        }
        val scout = Scout(streams.scoutSourceFactory(), streams.extractors())
        val profiles = ServerProfiles(scope) { (sessions.state.value as? SessionState.SignedIn)?.session }
        local = OctoPlayer(this, deck(), deck(), sounds::get, scout, profiles, realLengths)
        player = OutputSwitch(local)
        tracker = PlayTracker(plays::started, plays::record, isPlaying = { player.isPlaying })
        player.addListener(tracker)
        player.addListener(Watcher())
        player.addListener(RadioWatch(player, scope, liveLookup::known) { liveLookup.look(it) })
        sleep.attach(player)
        // Saving songs ahead is for the phone's own playing.
        prefetch.attach(local)
        // The covers of the song on and the next ones, wherever it plays.
        coversAhead.attach(player)
        editor.attach(player)
        stationRefill.attach(player, scope) { autoplay.check() }
        autoplay.attach(player, scope)
        // Casting to a TV or speaker swaps the session's player to one that
        // drives the device, and back.
        casting = Casting(this, player, local, deviceMedia, feedback, scope)
        outputs.attach(casting)

        session = MediaLibrarySession.Builder(this, player, Callback())
            .setBitmapLoader(CacheBitmapLoader(OctoArtLoader(this, DataSourceBitmapLoader.Builder(this).build())))
            .setSessionActivity(
                PendingIntent.getActivity(
                    this,
                    0,
                    Intent(this, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                ),
            )
            .build()

        scope.launch {
            try {
                // Whether crossfade is on decides how the decks' sound path
                // is set up, so it is known before anything is loaded.
                crossfadeOn.set(playerSettings.prefs.first().crossfade)
                restoreQueue()
            } finally {
                restored.complete(Unit)
            }
        }
        // The heart follows the song, the likes list, and for a song found
        // online, whether its download was asked for.
        scope.launch {
            combine(currentId, likes.liked, downloads.states, ::notificationHeart).distinctUntilChanged().collect(::showButtons)
        }
        // Crossfade, speed and pitch, and skipping silence follow their
        // settings, each only when it changes, so a blend is not cut short.
        val prefs = playerSettings.prefs.stateIn(scope, SharingStarted.Eagerly, PlayerPrefs())
        // These belong to the phone's own player, and wait there while casting.
        scope.launch {
            prefs.map { it.automix }.distinctUntilChanged().collect {
                crossfadeOn.set(it.maxOverlapMs > 0)
                local.automix = it
            }
        }
        scope.launch {
            prefs.map { it.pace }.distinctUntilChanged().collect { local.setPlaybackParameters(PlaybackParameters(it.speed, it.pitch)) }
        }
        scope.launch { prefs.map { it.skipSilence }.distinctUntilChanged().collect { local.skipSilence = it } }
        scope.launch {
            playerSettings.streamPrefs.map { it.startAfter.ms }.distinctUntilChanged().collect { ms -> loads.forEach { it.startAfterMs = ms } }
        }
        // Headphones connecting can start the music again. With that on, the
        // service stays in the foreground for the whole 30 minutes it waits
        // after a pause, since Android may refuse to bring it back later.
        // It is the phone's player that headphones bring back, never a TV.
        headsets = HeadsetResume(this, local) { prefs.value }.also { it.start() }
        scope.launch {
            prefs.map { it.resumeWired || it.resumeBluetooth }.distinctUntilChanged().collect { on ->
                setForegroundServiceTimeoutMs(if (on) RESUME_WINDOW_MS else DEFAULT_FOREGROUND_SERVICE_TIMEOUT_MS)
            }
        }
        // Editing the queue saves it once things settle.
        scope.launch { queueChanged.debounce(500).collect { saveQueue() } }
        // A switch of server stops the music and brings the other's queue.
        switcher.attach(side)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    // A widget button, once any saved queue is back.
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val result = super.onStartCommand(intent, flags, startId)
        widgetCommand(intent)?.let { command ->
            // With no app connected yet, the session must be added by hand
            // for its notification to show once music plays.
            session?.let { if (!isSessionAdded(it)) addSession(it) }
            scope.launch {
                restored.await()
                widgetRemote.run(command)
            }
        }
        return result
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        saveQueue()
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        switcher.detach(side)
        saveQueue()
        widgets.clear()
        tracker.flush()
        headsets.stop()
        sleep.detach()
        prefetch.detach()
        coversAhead.detach()
        editor.detach()
        autoplay.detach()
        stationRefill.detach()
        outputs.detach(casting)
        casting.release()
        session?.release()
        player.release()
        audioSession.close()
        session = null
        scope.cancel()
        super.onDestroy()
    }

    // Previous, play and next keep their places. The heart (or download)
    // comes first after them and Close second. The phone's own media
    // controls only take extra buttons offered for the overflow slot, and
    // show the first two of those alongside previous, play and next, so
    // these two are always in view there. Apps that know Media3's slots put the heart
    // beside next and Close beside previous.
    private fun showButtons(heart: NotificationHeart) {
        val buttons = buildList {
            when (heart) {
                is NotificationHeart.Like -> add(
                    CommandButton.Builder(if (heart.liked) CommandButton.ICON_HEART_FILLED else CommandButton.ICON_HEART_UNFILLED)
                        .setDisplayName(if (heart.liked) "Unlike" else "Like")
                        .setSessionCommand(LIKE)
                        .setSlots(CommandButton.SLOT_FORWARD_SECONDARY, CommandButton.SLOT_OVERFLOW)
                        .build(),
                )
                NotificationHeart.Download -> add(
                    CommandButton.Builder(CommandButton.ICON_UNDEFINED)
                        .setCustomIconResId(OctoIcons.AddToLibrary)
                        .setDisplayName("Add to your library")
                        .setSessionCommand(DOWNLOAD)
                        .setSlots(CommandButton.SLOT_FORWARD_SECONDARY, CommandButton.SLOT_OVERFLOW)
                        .build(),
                )
                NotificationHeart.None -> Unit
            }
            add(
                CommandButton.Builder(CommandButton.ICON_UNDEFINED)
                    .setCustomIconResId(OctoIcons.Close)
                    .setDisplayName("Close")
                    .setSessionCommand(CLOSE)
                    .setSlots(CommandButton.SLOT_BACK_SECONDARY, CommandButton.SLOT_OVERFLOW)
                    .build(),
            )
        }
        session?.setMediaButtonPreferences(buttons)
    }

    // Close: the music stops, the queue is kept for next time, the
    // notification goes, and the service stops once the app lets go of it.
    private fun close() {
        saveQueue()
        sleep.cancel()
        // Casting ends too, with the music stopped.
        if (player.isRemote) outputs.stopCasting()
        closed = true
        // A stopped player normally keeps its notification; this one goes.
        setShowNotificationForIdlePlayer(SHOW_NOTIFICATION_FOR_IDLE_PLAYER_NEVER)
        player.pause()
        player.stop()
        pauseAllPlayersAndStopSelf()
    }

    // A song can come with no length (many found online do), or with one
    // that is not its sound's (a find listed with another copy's length).
    // Once the phone's own player has opened it, its length is the one
    // plays are counted by, and a listing more than a second off is
    // corrected for the queue, the rows and, for a find, in storage. A TV
    // or speaker's idea of the length is not trusted for this.
    private fun learnLength() {
        if (player.isRemote || player.isCurrentMediaItemLive) return
        val item = player.currentMediaItem ?: return
        val listed = item.mediaMetadata.durationMs ?: 0
        val measured = player.duration.takeIf { it != C.TIME_UNSET }
        tracker.lengthFound(item.mediaId, playingLengthMs(realLengths.lengthMs(item.mediaId, listed), measured))
        if (measured == null) return
        scope.launch {
            try {
                lengths.learn(item.mediaId, listed, measured)
            } catch (e: Exception) {
                Log.w("Octo", "could not keep a song's length", e)
            }
        }
    }

    // Asks the server to download the song found online that is on now.
    private fun downloadCurrent() {
        val id = currentId.value?.takeIf(::isFind) ?: return
        scope.launch {
            val track = online.byIds(listOf(id)).firstOrNull()?.asTrack() ?: return@launch
            if (!downloads.request(track)) Log.w("Octo", "notification download: not asked")
        }
    }

    // Brings back the queue from last time, paused where it was left: at
    // the saved song and place, or at the start when that song is gone.
    private suspend fun restoreQueue() {
        val saved = queue.load() ?: return
        // Each song back with where it came from, so a station keeps going.
        val each = playable.itemsEach(saved.trackIds).mapIndexed { i, item -> item?.let { withSavedSource(it, saved.sources.getOrNull(i)) } }
        val items = each.filterNotNull()
        if (items.isEmpty() || player.mediaItemCount > 0) return
        val found = each.map { it != null }
        val (index, positionMs) = restorePoint(found, saved.index, saved.positionMs)
        player.setMediaItems(items, index, positionMs)
        player.repeatMode = saved.repeatMode
        // The saved shuffle order, less any songs that are gone.
        restoredShuffle(saved.shuffleOrder, found)?.let(player::setPlayOrder)
        player.shuffleModeEnabled = saved.shuffle
        // A station waits unopened: Play joins it live.
        if (items.getOrNull(index)?.mediaId?.let(::isRadio) != true) player.prepare()
        serverQueue.restored(snapshot())
    }

    private fun saveQueue() {
        if (!::player.isInitialized || holding) return
        queue.save(snapshot())
    }

    // What a change of server asks of the player. Each runs on the main thread.
    private inner class Side : PlayerSide {
        override suspend fun leave(): LeftQueue = withContext(Dispatchers.Main) {
            holding = true
            val wasPlaying = player.isPlaying
            val left = snapshot()
            empty()
            LeftQueue(left.takeIf { it.trackIds.isNotEmpty() }, wasPlaying)
        }

        override suspend fun restore() = withContext(Dispatchers.Main) {
            try {
                empty()
                restoreQueue()
            } finally {
                holding = false
            }
            saveQueue()
        }

        override suspend fun keep() = withContext(Dispatchers.Main) {
            holding = false
        }

        // A car reads its tabs again, since the library under them changed.
        override fun libraryChanged() {
            scope.launch {
                val library = session ?: return@launch
                for (node in listOf(CarNode.Root, CarNode.Recent, CarNode.Playlists, CarNode.Albums, CarNode.Artists)) {
                    val id = carId(node)
                    library.notifyChildrenChanged(id, car.children(id, 0, Int.MAX_VALUE).size, null)
                }
            }
        }

        // What plays stops and counts, casting ends, and the player is empty.
        private fun empty() {
            if (player.mediaItemCount == 0) return
            tracker.flush()
            positionSaver?.cancel()
            sleep.cancel()
            if (player.isRemote) outputs.stopCasting()
            player.pause()
            player.stop()
            player.clearMediaItems()
        }
    }

    private fun snapshot(): QueueSnapshot {
        return QueueSnapshot(
            trackIds = List(player.mediaItemCount) { player.getMediaItemAt(it).mediaId },
            shuffleOrder = shuffleOrderOf(player).toList(),
            index = player.currentMediaItemIndex,
            positionMs = player.currentPosition,
            repeatMode = player.repeatMode,
            shuffle = player.shuffleModeEnabled,
            sources = List(player.mediaItemCount) { player.getMediaItemAt(it).queueSource.encoded() },
        )
    }

    private inner class Watcher : Player.Listener {
        // Songs that failed one after another, back to 0 once one plays.
        private var failedInARow = 0

        // The item that was on, and where, for a station that ends.
        private var lastId: String? = null
        private var lastIndex = C.INDEX_UNSET

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            val endedStation = lastId?.takeIf(::isRadio)
            val endedAt = lastIndex
            lastId = mediaItem?.mediaId
            lastIndex = player.currentMediaItemIndex
            // A station's stream that ended for good stops on that station
            // rather than moving on to the next one by itself.
            if (reason == Player.MEDIA_ITEM_TRANSITION_REASON_AUTO && endedStation != null && mediaItem != null && isRadio(mediaItem.mediaId) &&
                endedAt in 0 until player.mediaItemCount
            ) {
                scope.launch {
                    player.seekToDefaultPosition(endedAt)
                    player.pause()
                    val name = radioOf(endedStation)?.second?.takeIf(String::isNotBlank) ?: "The station"
                    feedback.show("$name stopped: its stream ended")
                }
            }
            currentId.value = mediaItem?.mediaId
            saveQueue()
            widgets.show(player)
            serverQueue.changed(snapshot())
            stationRefill.check()
            autoplay.check()
            learnLength()
        }

        override fun onRepeatModeChanged(repeatMode: Int) {
            stationRefill.check()
            autoplay.check()
        }

        override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
            stationRefill.check()
            autoplay.check()
        }

        // While music plays, a song that cannot, like a stream with no
        // connection or a file that is gone, is skipped instead of stopping
        // the music, and one line says which and why. Once every song in the
        // queue has failed, it stops.
        override fun onPlayerError(error: PlaybackException) {
            if (!player.playWhenReady) return
            failedInARow++
            val title = player.currentMediaItem?.mediaMetadata?.title?.toString()?.takeIf(String::isNotBlank) ?: "a song"
            val why = playFailureOf(error, isFind(player.currentMediaItem?.mediaId.orEmpty())).words
            // A station that cannot play stops there: the next station is
            // the listener's to choose.
            if (failedInARow >= player.mediaItemCount || !player.hasNextMediaItem() || isRadio(player.currentMediaItem?.mediaId.orEmpty())) {
                feedback.show(stoppedLine(title, why))
                return
            }
            feedback.show(skippedLine(title, why))
            scope.launch {
                player.seekToNextMediaItem()
                player.prepare()
            }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            if (playbackState == Player.STATE_READY) {
                failedInARow = 0
                learnLength()
            }
            // Equalizer apps let go once the music has stopped, not at a pause.
            if (playbackState == Player.STATE_IDLE || playbackState == Player.STATE_ENDED || player.isRemote) audioSession.close()
            // Playing again after Close: a stop keeps its notification again.
            if (closed && playbackState != Player.STATE_IDLE) {
                closed = false
                setShowNotificationForIdlePlayer(SHOW_NOTIFICATION_FOR_IDLE_PLAYER_AFTER_STOP_OR_ERROR)
            }
            stationRefill.check()
            autoplay.check()
        }

        override fun onTimelineChanged(timeline: androidx.media3.common.Timeline, reason: Int) {
            queueChanged.tryEmit(Unit)
            serverQueue.changed(snapshot())
            stationRefill.check()
            autoplay.check()
            // The length is known once the song has opened.
            learnLength()
        }

        // A pause keeps the server's copy of the queue exact.
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (!playWhenReady) serverQueue.paused(snapshot())
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            positionSaver?.cancel()
            widgets.show(player)
            stationRefill.check()
            autoplay.check()
            if (isPlaying) {
                // Equalizer apps on the phone can attach to the music now,
                // unless it is playing on another device.
                if (!player.isRemote) audioSession.open()
                // Where in the song we are, every 15 seconds, in case the phone kills the app.
                positionSaver = scope.launch {
                    while (isActive) {
                        delay(15_000)
                        saveQueue()
                    }
                }
            } else {
                saveQueue()
            }
        }
    }

    private inner class Callback : MediaLibrarySession.Callback {
        override fun onConnectAsync(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
        ): ListenableFuture<ConnectionResult> {
            // Apps we don't trust keep the read-only access Media3 gives them.
            // A car and the voice assistant need to press play too.
            if (!controller.isTrusted && controller.packageName !in carApps) return super.onConnectAsync(session, controller)
            // The app connects only once the saved queue is back, so it never
            // mistakes a player still restoring for an empty one.
            return scope.future {
                restored.await()
                ConnectionResult.AcceptedResultBuilder(session, controller)
                    .setAvailableSessionCommands(
                        ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon()
                            .add(LIKE).add(DOWNLOAD).add(CLOSE).add(PLAY_NEXT)
                            .build(),
                    )
                    .build()
            }
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle,
        ): ListenableFuture<SessionResult> {
            when (customCommand) {
                LIKE -> currentId.value?.takeUnless(::isFind)?.let(likes::toggle)
                DOWNLOAD -> downloadCurrent()
                CLOSE -> close()
                PLAY_NEXT -> args.getStringArrayList(ARG_IDS)?.let { ids ->
                    scope.launch { player.addNext(playable.items(ids).map { it.withSource(QueueSource.You) }) }
                }
                else -> return super.onCustomCommand(session, controller, customCommand, args)
            }
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }

        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> = scope.future {
            // An album or playlist chosen in a car adds all its songs. Songs
            // added are the listener's own, for the queue's headings.
            val ids = mediaItems.flatMap { car.playFor(it.mediaId)?.first ?: listOf(it.mediaId) }
            playable.items(ids).map { it.withSource(QueueSource.You) }.toMutableList()
        }

        override fun onSetMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
            startIndex: Int,
            startPositionMs: Long,
        ): ListenableFuture<MediaItemsWithStartPosition> = scope.future {
            val single = mediaItems.singleOrNull()
            // Something said out loud, like "play Drake on Octo".
            single?.requestMetadata?.searchQuery?.let { query ->
                val (ids, shuffle) = car.forVoice(query)
                val songs = playable.items(ids)
                player.shuffleModeEnabled = shuffle
                val first = if (shuffle && songs.isNotEmpty()) songs.indices.random() else 0
                return@future MediaItemsWithStartPosition(songs, first, 0)
            }
            // An album, playlist, or a song inside one, chosen in a car.
            single?.let { car.playFor(it.mediaId) }?.let { (ids, start) ->
                val each = playable.itemsEach(ids)
                return@future MediaItemsWithStartPosition(each.filterNotNull(), chosenStart(each, start), 0)
            }
            val each = playable.itemsEach(mediaItems.map { it.mediaId })
            // The list's name, when the app gave one, goes on every song.
            val source = mediaItems.firstOrNull()?.requestedSource
            val resolved = each.filterNotNull().map { if (source != null) it.withSource(source) else it }
            // Keep starting on the chosen song even if some before it are gone.
            val index = if (startIndex == C.INDEX_UNSET) C.INDEX_UNSET else chosenStart(each, startIndex)
            MediaItemsWithStartPosition(resolved, index, startPositionMs)
        }

        override fun onPlaybackResumption(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            isForPlayback: Boolean,
        ): ListenableFuture<MediaItemsWithStartPosition> = scope.future {
            val saved = queue.load() ?: throw UnsupportedOperationException("Nothing to resume")
            val each = playable.itemsEach(saved.trackIds)
            val items = each.filterNotNull()
            if (items.isEmpty()) throw UnsupportedOperationException("Nothing to resume")
            // The saved song where it was left, or the first from its start.
            val (index, positionMs) = restorePoint(each.map { it != null }, saved.index, saved.positionMs)
            if (isForPlayback) {
                MediaItemsWithStartPosition(items, index, positionMs)
            } else {
                // The media controls only need the song to show.
                MediaItemsWithStartPosition(listOf(items[index]), 0, positionMs)
            }
        }

        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> = Futures.immediateFuture(LibraryResult.ofItem(car.root(), params))

        // Browsing from a car: its tabs, and the albums, songs and playlists in them.
        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = scope.future {
            val items = car.children(parentId, page, pageSize)
            car.grantArtwork(browser.packageName, items)
            LibraryResult.ofItemList(items, params)
        }

        override fun onSearch(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<Void>> = scope.future {
            session.notifySearchResultChanged(browser, query, car.search(query).size, params)
            LibraryResult.ofVoid()
        }

        override fun onGetSearchResult(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            query: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> = scope.future {
            val items = car.search(query).drop(page * pageSize).take(pageSize)
            car.grantArtwork(browser.packageName, items)
            LibraryResult.ofItemList(items, params)
        }
    }
}
