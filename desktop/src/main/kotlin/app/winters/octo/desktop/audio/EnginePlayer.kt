package app.winters.octo.desktop.audio

import app.winters.octo.audio.AutomixSettings
import app.winters.octo.audio.DspSettings
import app.winters.octo.audio.EndReason
import app.winters.octo.audio.EngineEvent
import app.winters.octo.audio.EqSettings
import app.winters.octo.audio.ErrorKind
import app.winters.octo.audio.PlaybackState
import app.winters.octo.audio.ReplayGainSettings
import app.winters.octo.desktop.player.DEFAULT_OUTPUT
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.DeviceFormat
import app.winters.octo.desktop.player.OutputDevice
import app.winters.octo.desktop.player.PlayFormat
import app.winters.octo.desktop.player.PlayProblem
import app.winters.octo.desktop.player.PlayQueue
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.player.RESTART_AFTER_MS
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.desktop.player.SavedQueue
import app.winters.octo.desktop.player.SongFormat
import app.winters.octo.desktop.player.isLineup
import app.winters.octo.desktop.player.libraryFormat
import app.winters.octo.desktop.player.lineupStep
import app.winters.octo.desktop.player.liveNow
import app.winters.octo.desktop.player.shownLive
import app.winters.octo.discovery.knownLengthMs
import app.winters.octo.playback.PlayFailure
import app.winters.octo.playback.QueueSource
import app.winters.octo.playback.RealLengths
import app.winters.octo.playback.isRadio
import app.winters.octo.playback.playingLengthMs
import app.winters.octo.playback.withLengthMs
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.concurrent.Executors
import kotlin.random.Random
import app.winters.octo.audio.RepeatMode as EngineRepeat

// What the Sound page shapes the sound through: the engine's equalizer,
// loudness and speed, and the device playing now, whose settings apply.
interface SoundTarget {
    // The id of the device sound goes to now, once one is open.
    val deviceKey: StateFlow<String?>

    fun shape(eq: EqSettings, replayGain: ReplayGainSettings, dsp: DspSettings)

    fun setCrossfade(ms: Int)

    fun setAutomix(settings: AutomixSettings)

    fun setSpeed(speed: Float, pitch: Float)
}

// The player that makes sound: the Rust audio engine, driven from the same
// queue model the silent player keeps (PlayQueue, with the shared shuffle
// rules). The engine holds the songs in the order they play, so it can join
// them gaplessly or crossfade; this keeps that list in step whenever the
// queue, the shuffle or the order changes, and follows the engine's events
// for what is heard. Every call returns at once. Positions come from the
// engine's audio clock, which says what the listener hears now.
class EnginePlayer(
    val engine: AudioEngine,
    private val sources: SongSources,
    random: Random = Random.Default,
    volume: Float = 0.8f,
    // Plays to this device at the start, or follows the default with null.
    device: String? = null,
    // Milliseconds from any fixed point, for how long a jump may take.
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
    // Hands the engine the server's transition profiles of the songs about
    // to blend, when it has them.
    private val profiles: EngineProfiles? = null,
    override val lengths: RealLengths = RealLengths(),
) : DesktopPlayer, SoundTarget {
    private val queue = PlayQueue(random)
    private val lock = Any()

    private var shuffle = false
    private var repeat = RepeatMode.Off
    private var level = volume.coerceIn(0f, 1f)
    private var speed = 1f

    // The sleep timer's fade, on top of the volume.
    private var fade = 1f

    // Songs played to their end by themselves.
    private var ended = 0

    // The decoder's word on the entry that started last, and what the
    // device runs at.
    private var decoded: Pair<Long, SongFormat>? = null
    private var deviceFormat: DeviceFormat? = null

    // The decoder's length of the entry that started last, by its key.
    private var measured: Pair<Long, Long>? = null

    // What a live stream says it plays now (its StreamTitle, and the
    // address sent with it), by the entry's key.
    private var streamTitle: Triple<Long, String, String>? = null

    // The repeat the engine was last told, which is off while a station
    // plays, so a stream that stops is never started over by itself.
    private var engineRepeat: EngineRepeat = EngineRepeat.OFF

    // What the listener asked for: playing or not. The engine's own state
    // changes only override it when the engine stops by itself.
    private var playing = false
    private var buffering = false
    private var problem: PlayProblem? = null
    private var stopAfter = false

    // Times round the current entry by repeat one, the entry they count
    // for, and the entry the engine last said had started (null after a
    // jump or a load, so the start that follows is not taken for a repeat).
    private var rounds = 0
    private var roundsOf: Long? = null
    private var lastStarted: Long? = null

    // The entry keys the engine's queue holds, in its order.
    private var mirror: List<Long> = emptyList()

    // Where a command sent the engine, shown until the engine is heard
    // there, since the engine does it a moment later on its own thread.
    private class Pending(val key: Long, val ms: Long, val at: Long)

    private var pending: Pending? = null

    // Times the place was moved, for PlayerState.moves.
    private var moves = 0

    // After a jump, news of other songs starting is stale until this one
    // does (or a moment has passed).
    private var expecting: Long? = null
    private var expectingSince = 0L

    // The last position shown for the current entry, for the moment the
    // engine is already heard on the next one before its news arrives.
    private var lastShown = 0L

    // The output chosen (DEFAULT_OUTPUT follows the system), the devices
    // there are, and the one playing now.
    private var choice: String = device ?: DEFAULT_OUTPUT
    private var devices: List<OutputDevice> = emptyList()
    private var playingOn: OutputDevice? = null
    private val _deviceKey = MutableStateFlow<String?>(null)
    override val deviceKey: StateFlow<String?> = _deviceKey

    // Asks the engine for its devices off the caller's thread, since the
    // answer comes back from the engine's own thread.
    private val background = Executors.newSingleThreadExecutor { r -> Thread(r, "octo-player").apply { isDaemon = true } }

    private val _state = MutableStateFlow(PlayerState(volume = level, output = defaultOutput(), outputs = listOf(defaultOutput())))
    override val state: StateFlow<PlayerState> = _state

    init {
        engine.setListener(::onEvent)
        engine.setVolume(heardLevel())
        // A steady word of where playback is, which also catches a song
        // start whose own news never came (a seek before it was heard).
        engine.setPositionInterval(POSITION_EVERY_MS)
        if (device != null) engine.setOutputDevice(device)
        refreshDevices()
    }

    // ---- Time ----

    override fun positionMs(): Long = spot().second

    // The current entry's key and where it is, read together, so the two
    // always belong to the same song.
    fun spot(): Pair<Long?, Long> {
        val heard = engine.heard()
        synchronized(lock) {
            return queue.currentEntry?.key to positionLocked(heard)
        }
    }

    private fun positionLocked(heard: Heard): Long {
        run {
            val current = queue.currentEntry ?: return 0
            val duration = durationMs(heard)
            val at = pending
            if (at != null) {
                val waited = clock() - at.at
                val arrived = keyOfItem(heard.itemId) == at.key &&
                    heard.positionMs >= at.ms - HEARD_SLACK_MS &&
                    heard.positionMs <= at.ms + waited * speed + HEARD_SLACK_MS * 2
                if (arrived || waited > PENDING_GIVE_UP_MS) {
                    pending = null
                } else {
                    return clamp(at.ms, duration).also { lastShown = it }
                }
            }
            // The engine is heard on another song for a moment: its news
            // is on the way.
            if (keyOfItem(heard.itemId) != current.key) return lastShown
            return clamp(heard.positionMs.toLong(), duration).also { lastShown = it }
        }
    }

    private fun clamp(ms: Long, duration: Long) = if (duration > 0) ms.coerceIn(0, duration) else ms.coerceAtLeast(0)

    // How long the current song is: the length of its sound once the engine
    // has opened it, and the listed one until then (a song found online can
    // be listed with a guess, or with another copy's length). Positions come
    // from the engine's clock either way, so the switch moves nothing.
    private fun durationMs(heard: Heard = engine.heard()): Long {
        val current = queue.currentEntry ?: return 0
        val here = heard.takeIf { keyOfItem(it.itemId) == current.key }
        val engineMs = measured?.takeIf { it.first == current.key }?.second ?: here?.durationMs
        return playingLengthMs(knownLengthMs(current.song), engineMs, here?.positionMs?.toLong() ?: 0)
    }

    // Takes the engine's length of an entry's song. A listing more than a
    // second off is corrected for every entry of that song, and for the
    // rows that show it; the engine is handed the corrected entries, so the
    // song's other entries never report the old listing. Answers whether
    // the queue changed.
    private fun learnLength(key: Long?, engineMs: Long?): Boolean {
        val entry = queue.songs.firstOrNull { it.key == key } ?: return false
        val ms = lengths.learn(entry.song.id, knownLengthMs(entry.song), engineMs) ?: return false
        if (!queue.updateSong(entry.song.id) { it.withLengthMs(ms) }) return false
        val current = queue.currentEntry
        if (current != null && current.key in mirror) engine.replaceQueue(engineOrder().map { queueItem(it, sources) }, mirror.indexOf(current.key))
        return true
    }

    // ---- Transport ----

    override fun play(songs: List<Song>, start: Int, shuffle: Boolean, source: QueueSource) {
        synchronized(lock) {
            // A lineup of stations plays in its own order; the listener's
            // shuffle stays as it was for the songs played after it.
            val lineup = isLineup(songs)
            if (!lineup) this.shuffle = shuffle
            queue.replace(songs.map(lengths::applyTo), start, shuffle && !lineup, source)
            playing = queue.currentEntry != null
            problem = null
            load(startMs = 0, play = playing)
            publish()
        }
    }

    override fun resume() {
        synchronized(lock) {
            val current = queue.currentEntry ?: return
            if (playing) return
            playing = true
            if (isRadio(current.song.id)) {
                // A station joins what is on air now, from a fresh
                // connection, never from sound held since it stopped.
                problem = null
                load(startMs = 0, play = true)
            } else if (problem?.song?.id == current.song.id) {
                // The song that could not play is tried again from its
                // start, in an engine queue made afresh: the engine gave up
                // on it and would not try it again by itself.
                problem = null
                load(startMs = 0, play = true)
            } else {
                // At the very end of the last song, Play starts it over; the
                // engine does the same.
                if (engine.state() == PlaybackState.ENDED) setPending(current.key, 0)
                engine.play()
            }
            publish()
        }
    }

    override fun pause() {
        synchronized(lock) {
            if (!playing) return
            playing = false
            buffering = false
            if (isRadio(queue.currentEntry?.song?.id.orEmpty())) {
                // A station stops: its stream is let go, and what it named
                // is no longer on air.
                engine.stop()
                mirror = emptyList()
                streamTitle = null
            } else {
                engine.pause()
            }
            publish()
        }
    }

    override fun togglePlay() {
        if (state.value.playing) pause() else resume()
    }

    override fun next() {
        synchronized(lock) {
            if (queue.isLineup()) return step(forward = true)
            val next = queue.nextPosition(if (repeat == RepeatMode.One) RepeatMode.All else repeat) ?: return
            queue.moveTo(next)
            jump(play = playing)
            publish()
        }
    }

    override fun previous() {
        val at = positionMs()
        synchronized(lock) {
            val current = queue.currentEntry ?: return
            if (queue.isLineup()) return step(forward = false)
            val back = queue.previousPosition(if (repeat == RepeatMode.One) RepeatMode.All else repeat)
            if (isRadio(current.song.id)) {
                // A live stream cannot start over: back goes to the song before.
                if (back == null) return
                queue.moveTo(back)
                jump(play = playing)
            } else if (at > RESTART_AFTER_MS || back == null) {
                engine.seek(0)
                setPending(current.key, 0)
            } else {
                queue.moveTo(back)
                jump(play = playing)
            }
            publish()
        }
    }

    // Back or Next in a lineup: the station before or after, never round
    // from an end.
    private fun step(forward: Boolean) {
        val to = queue.lineupStep(forward) ?: return
        queue.moveTo(to)
        jump(play = playing)
        publish()
    }

    override fun seekTo(positionMs: Long) {
        synchronized(lock) {
            val current = queue.currentEntry ?: return
            // A live stream plays on from wherever its station is.
            if (isRadio(current.song.id)) return
            val target = clamp(positionMs, durationMs())
            engine.seek(target)
            setPending(current.key, target)
            publish()
        }
    }

    override fun skipTo(key: Long) {
        synchronized(lock) {
            if (!queue.jumpTo(key)) return
            playing = true
            jump(play = true)
            publish()
        }
    }

    // ---- The queue ----

    override fun playNext(songs: List<Song>, source: QueueSource) = changeQueue { queue.playNext(songs.map(lengths::applyTo), source) }

    override fun addToQueue(songs: List<Song>, source: QueueSource) = changeQueue { queue.add(songs.map(lengths::applyTo), source) }

    override fun insert(songs: List<Song>, before: Long?) = changeQueue { queue.insertBefore(songs.map(lengths::applyTo), before) }

    override fun moveUpcoming(from: Int, to: Int) = changeQueue { queue.moveUpcoming(from, to) }

    override fun move(keys: List<Long>, before: Long?) = changeQueue { queue.move(keys, before) }

    private fun changeQueue(change: () -> Unit) {
        synchronized(lock) {
            val wasEmpty = queue.currentEntry == null
            change()
            if (wasEmpty && queue.currentEntry != null) {
                // Songs put into an empty queue wait to be played.
                load(startMs = 0, play = false)
            } else {
                syncQueue()
            }
            publish()
        }
    }

    override fun remove(keys: List<Long>) = edited { queue.remove(keys) }

    override fun clearUpcoming() = edited { queue.clearUpcoming(); false }

    override fun removePlayed() = edited { queue.removePlayed(); false }

    override fun undo(): Boolean {
        var done = false
        edited { queue.undo().also { done = it != null } == true }
        return done
    }

    // An edit that may have changed the song playing: the engine moves to
    // the new one, or stops when there is none; otherwise it takes the
    // queue as it now is.
    private fun edited(change: () -> Boolean) {
        synchronized(lock) {
            if (change()) {
                if (queue.currentEntry == null) {
                    playing = false
                    load(startMs = 0, play = false)
                } else {
                    jump(play = playing)
                }
            } else {
                syncQueue()
            }
            publish()
        }
    }

    override fun clear() {
        synchronized(lock) {
            queue.clear()
            playing = false
            buffering = false
            stopAfter = false
            load(startMs = 0, play = false)
            publish()
        }
    }

    override fun setShuffle(on: Boolean) {
        synchronized(lock) {
            shuffle = on
            // A lineup keeps its order; the setting waits for songs.
            if (!queue.isLineup()) {
                queue.setShuffle(on)
                syncQueue()
            }
            publish()
        }
    }

    override fun setRepeat(mode: RepeatMode) {
        synchronized(lock) {
            repeat = mode
            val want = repeatForEngine()
            engineRepeat = want
            engine.setRepeat(want)
            publish()
        }
    }

    override fun setStopAfterCurrent(on: Boolean) {
        synchronized(lock) {
            stopAfter = on
            engine.setStopAfterCurrent(on)
            publish()
        }
    }

    override fun setVolume(volume: Float) {
        synchronized(lock) {
            level = volume.coerceIn(0f, 1f)
            engine.setVolume(heardLevel())
            publish()
        }
    }

    override fun setFade(fade: Float) {
        synchronized(lock) {
            val next = fade.coerceIn(0f, 1f)
            if (next == this.fade) return
            this.fade = next
            engine.setVolume(heardLevel())
            publish()
        }
    }

    // What the engine plays at: the volume as heard, times the fade.
    private fun heardLevel(): Float = loudness(level) * fade

    override fun selectOutput(id: String) {
        synchronized(lock) {
            choice = id
            engine.setOutputDevice(id.takeUnless { it == DEFAULT_OUTPUT })
            publish()
        }
    }

    // ---- Sound shaping ----

    override fun shape(eq: EqSettings, replayGain: ReplayGainSettings, dsp: DspSettings) {
        engine.setEq(eq)
        engine.setReplayGain(replayGain)
        engine.setDsp(dsp)
    }

    override fun setCrossfade(ms: Int) = engine.setCrossfade(ms)

    override fun setAutomix(settings: AutomixSettings) = engine.setAutomix(settings)

    override fun setSpeed(speed: Float, pitch: Float) {
        synchronized(lock) {
            this.speed = speed
            engine.setSpeed(speed, pitch)
            publish()
        }
    }

    override fun restore(saved: SavedQueue) {
        synchronized(lock) {
            shuffle = saved.shuffle
            queue.restore(saved.songs.map(lengths::applyTo), saved.order, saved.index, saved.shuffle, saved.sources)
            playing = false
            buffering = false
            stopAfter = false
            problem = null
            engine.setStopAfterCurrent(false)
            load(startMs = saved.positionMs.coerceAtLeast(0), play = false)
        }
        // Repeat goes to the engine as well, and publishes.
        setRepeat(saved.repeat)
    }

    // The repeat the engine plays by: the listener's, and off while a
    // station plays.
    private fun repeatForEngine(): EngineRepeat = when {
        isRadio(queue.currentEntry?.song?.id.orEmpty()) -> EngineRepeat.OFF
        repeat == RepeatMode.All -> EngineRepeat.ALL
        repeat == RepeatMode.One -> EngineRepeat.ONE
        else -> EngineRepeat.OFF
    }

    private fun syncRepeat() {
        val want = repeatForEngine()
        if (want == engineRepeat) return
        engineRepeat = want
        engine.setRepeat(want)
    }

    override fun close() {
        background.shutdownNow()
        engine.close()
    }

    // ---- Keeping the engine's queue in step ----

    // The engine's queue from scratch: every entry in play order, starting
    // at the current one.
    private fun load(startMs: Long, play: Boolean) {
        lastStarted = null
        val current = queue.currentEntry
        if (current == null) {
            mirror = emptyList()
            pending = null
            expecting = null
            engine.load(emptyList(), 0, 0, false)
            return
        }
        syncRepeat()
        val live = isRadio(current.song.id)
        // A station opened again names what is on air from scratch.
        if (live) streamTitle = null
        if (live && !play) {
            // A station waiting to be played holds no connection open: Play
            // opens it then.
            mirror = emptyList()
            pending = null
            expecting = null
            lastShown = 0
            engine.load(emptyList(), 0, 0, false)
            return
        }
        val ordered = engineOrder()
        mirror = ordered.map { it.key }
        // A live stream starts where its station is.
        val start = if (live) 0 else startMs
        engine.load(ordered.map { queueItem(it, sources) }, mirror.indexOf(current.key), start, play)
        expect(current.key)
        setPending(current.key, start)
        askProfiles()
    }

    // Moves the engine to the current entry: a skip within its queue when
    // it holds the entry, then its queue brought in line; a fresh load when
    // it does not.
    private fun jump(play: Boolean) {
        val current = queue.currentEntry ?: return load(0, false)
        val index = mirror.indexOf(current.key)
        if (index < 0) return load(startMs = 0, play = play)
        lastStarted = null
        syncRepeat()
        engine.skipTo(index)
        if (play) engine.play()
        expect(current.key)
        setPending(current.key, 0)
        syncQueue()
        askProfiles()
    }

    // Gives the engine the whole queue in play order, when it differs from
    // what it has. Only the whole queue will do: the songs before the
    // current one change too when the shuffle does, and repeat all goes
    // round to the first of them. The engine finds the song it plays in the
    // new list by its id, so it carries on even when it moved to the next
    // song a moment before the news of it reached here.
    private fun syncQueue() {
        val current = queue.currentEntry ?: return
        if (current.key !in mirror) return load(startMs = positionMsLocked(), play = playing)
        val ordered = engineOrder()
        val keys = ordered.map { it.key }
        if (keys == mirror) return
        engine.replaceQueue(ordered.map { queueItem(it, sources) }, keys.indexOf(current.key))
        mirror = keys
        askProfiles()
    }

    // The playing entry and the one after it get their profiles, so a
    // song's profile is usually there from when it is next.
    private fun askProfiles() {
        val profiles = profiles ?: return
        val current = queue.currentEntry ?: return
        val ordered = engineOrder()
        val at = ordered.indexOfFirst { it.key == current.key }
        profiles.follow(listOfNotNull(current, ordered.getOrNull(at + 1)))
    }

    // Every entry, in the order they play.
    private fun inPlayOrder(): List<QueueEntry> {
        val songs = queue.songs
        return queue.playOrder.map { songs[it] }
    }

    // What the engine holds: every entry in play order, or a station alone
    // while one plays, so a stream that fails stops there rather than
    // moving on by itself; Back and Next load the next one.
    private fun engineOrder(): List<QueueEntry> {
        val current = queue.currentEntry
        if (current != null && isRadio(current.song.id)) return listOf(current)
        return inPlayOrder()
    }

    private fun positionMsLocked(): Long = pending?.ms ?: lastShown

    private fun expect(key: Long) {
        expecting = key
        expectingSince = clock()
    }

    // A jump's song is awaited, and not for so long that it never came.
    private fun stillExpecting(): Boolean = expecting != null && clock() - expectingSince < EXPECT_MS

    private fun setPending(key: Long, ms: Long) {
        moves++
        pending = Pending(key, ms, clock())
        lastShown = ms
    }

    // ---- The engine's news ----

    private fun onEvent(event: EngineEvent) {
        var devicesMoved = false
        synchronized(lock) {
            when (event) {
                is EngineEvent.TrackStarted -> {
                    val key = keyOfItem(event.itemId)
                    val entry = queue.songs.firstOrNull { it.key == key }
                    val info = event.info
                    if (entry != null && info != null) decoded = entry.key to songFormatOf(info, entry.song)
                    if (entry != null) info?.durationMs?.toLong()?.let { measured = entry.key to it }
                    learnLength(key, info?.durationMs?.toLong())
                    started(key)
                }
                is EngineEvent.TrackEnded -> if (event.reason == EndReason.FINISHED) {
                    val key = keyOfItem(event.itemId)
                    if (queue.songs.any { it.key == key }) ended++
                    finished(key)
                }
                is EngineEvent.Buffering -> buffering = playing
                is EngineEvent.Ready -> buffering = false
                is EngineEvent.StateChanged -> when (event.state) {
                    PlaybackState.BUFFERING -> buffering = playing
                    else -> buffering = false
                }
                EngineEvent.QueueEnded -> {
                    playing = false
                    buffering = false
                    stopAfter = false
                }
                is EngineEvent.Error -> {
                    val failed = keyOfItem(event.itemId)?.let { key -> queue.songs.firstOrNull { it.key == key } }
                    problem = PlayProblem(plainWords(event.kind, failed?.song?.isExternal == true), failed?.song, event.message.takeIf(String::isNotBlank))
                    if (keyOfItem(event.itemId) == expecting) expecting = null
                }
                is EngineEvent.StreamTitle -> {
                    val key = keyOfItem(event.itemId) ?: return
                    if (queue.songs.none { it.key == key }) return
                    streamTitle = Triple(key, event.title, event.url)
                }
                is EngineEvent.Position -> {
                    val key = keyOfItem(event.itemId)
                    // The engine's length of the song heard, which a
                    // stream may only learn after it started. The decoder's
                    // word at the start, when it gave one, stands.
                    val heard = engine.heard().takeIf { keyOfItem(it.itemId) == key }
                    val corrected = learnLength(key, measured?.takeIf { it.first == key }?.second ?: heard?.durationMs)
                    when {
                        key == expecting -> expecting = null
                        // Heard on another song with no word of it
                        // starting, and nothing awaited (or the song a
                        // jump went for never came): follow it.
                        key != queue.currentEntry?.key && !stillExpecting() -> started(key)
                        corrected || (heard != null && durationMs(heard) != _state.value.durationMs) -> Unit
                        else -> return
                    }
                }
                // How the next song will follow, for checking blends in the field.
                is EngineEvent.TransitionPlanned -> {
                    System.err.println(event.reason)
                    return
                }
                is EngineEvent.DeviceChanged -> {
                    playingOn = event.device?.let { OutputDevice(it.id, it.name) }
                    deviceFormat = event.format?.let(::deviceFormatOf)
                    _deviceKey.value = event.device?.id
                    devicesMoved = true
                }
                else -> return
            }
            publish()
        }
        if (devicesMoved) refreshDevices()
    }

    // A song began to be heard.
    private fun started(key: Long?) {
        // News from a queue since replaced.
        if (key == null || queue.songs.none { it.key == key }) return
        val waiting = expecting
        if (waiting != null && key != waiting) {
            if (stillExpecting()) return
            // The song a jump went for never came: what is heard wins.
            expecting = null
        }
        if (key == waiting) expecting = null
        if (queue.currentEntry?.key != key) {
            queue.jumpTo(key)
            lastShown = 0
        } else if (key == lastStarted && !isRadio(queue.currentEntry?.song?.id.orEmpty())) {
            // The same entry started again by itself: repeat one. A live
            // stream starts again only to catch up with its station.
            rounds++
        }
        lastStarted = key
        if (pending?.key != key) pending = null
        problem = null
        askProfiles()
    }

    // A song played to its end. With stop-after-current, the engine is now
    // paused at the start of what follows.
    private fun finished(key: Long?) {
        if (!stopAfter || key != queue.currentEntry?.key) return
        stopAfter = false
        playing = false
        val next = if (repeat == RepeatMode.One) queue.current else queue.nextPosition(repeat)
        if (next != null) {
            queue.moveTo(next)
            queue.currentEntry?.let { setPending(it.key, 0) }
        }
    }

    private fun refreshDevices() {
        runCatching {
            background.execute {
                val listed = runCatching { engine.devices() }.getOrDefault(emptyList())
                val current = runCatching { engine.currentDevice() }.getOrNull()
                val format = runCatching { engine.outputFormat() }.getOrNull()
                synchronized(lock) {
                    devices = listed.map { OutputDevice(it.id, it.name) }
                    if (format != null) deviceFormat = deviceFormatOf(format)
                    if (current != null) {
                        playingOn = OutputDevice(current.id, current.name)
                        _deviceKey.value = current.id
                    }
                    publish()
                }
            }
        }
    }

    private fun defaultOutput(): OutputDevice {
        val name = playingOn?.takeIf { choice == DEFAULT_OUTPUT }?.name
        return OutputDevice(DEFAULT_OUTPUT, if (name != null) "System default ($name)" else "System default")
    }

    private fun publish() {
        val key = queue.currentEntry?.key
        if (key != roundsOf) {
            roundsOf = key
            rounds = 0
        }
        val outputs = listOf(defaultOutput()) + devices
        val said = streamTitle?.takeIf { it.first == key }
        val live = queue.liveNow(said?.second, said?.third)
        _state.value = PlayerState(
            queue = queue.songs,
            // A station shows what it has on air; only the current entry
            // carries it, so a saved queue keeps the station.
            current = queue.currentEntry?.let { if (live != null) it.copy(song = shownLive(it.song, live.shown)) else it },
            upcoming = queue.upcoming,
            played = queue.played,
            rounds = rounds,
            playing = playing,
            shuffle = shuffle,
            repeat = repeat,
            volume = level,
            durationMs = durationMs(),
            output = outputs.firstOrNull { it.id == choice } ?: outputs.first(),
            outputs = outputs,
            problem = problem,
            buffering = buffering,
            stopAfterCurrent = stopAfter,
            speed = speed,
            playingOn = playingOn,
            format = formatNow(),
            fade = fade,
            ended = ended,
            canUndo = queue.canUndo,
            moves = moves,
            live = live,
        )
    }

    // The current song's format, the decoder's once it started and the
    // library's until then, with the device's.
    private fun formatNow(): PlayFormat? {
        val current = queue.currentEntry
        val song = decoded?.takeIf { it.first == current?.key }?.second ?: current?.song?.let(::libraryFormat)
        if (song == null && deviceFormat == null) return null
        return PlayFormat(song, deviceFormat)
    }

    private companion object {
        // A jump's target is shown for at most this long if the engine is
        // never heard there (a song that fails to open, say).
        const val PENDING_GIVE_UP_MS = 3_000L
        const val HEARD_SLACK_MS = 150L
        const val EXPECT_MS = 3_000L
        const val POSITION_EVERY_MS = 250
    }
}

// The volume slider's 0 to 1 as a level: squared, so the slider's middle
// sounds like the middle rather than nearly full.
fun loudness(volume: Float): Float = volume.coerceIn(0f, 1f).let { it * it }

// Why a song would not play, in plain words, the same as the phone's. A
// song found online (`outside`) was never on the server, so a "not found"
// for it is the server not sending it.
fun plainWords(kind: ErrorKind, outside: Boolean = false): String = when (kind) {
    ErrorKind.NOT_FOUND -> if (outside) PlayFailure.Refused else PlayFailure.Missing
    ErrorKind.HTTP -> PlayFailure.Refused
    ErrorKind.NETWORK -> PlayFailure.Unreachable
    ErrorKind.UNSUPPORTED -> PlayFailure.Unsupported
    ErrorKind.DECODE -> PlayFailure.Damaged
    ErrorKind.DEVICE -> PlayFailure.Device
    else -> PlayFailure.Other
}.words
