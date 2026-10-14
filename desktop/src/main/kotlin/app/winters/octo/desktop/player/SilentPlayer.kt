package app.winters.octo.desktop.player

import app.winters.octo.playback.QueueSource
import app.winters.octo.playback.isRadio
import app.winters.octo.playback.RealLengths
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.random.Random

// A player with no sound, for tests and for a machine where the audio
// engine cannot load. It keeps the queue exactly as the engine's player
// does, and keeps time from a clock as if each song were playing, moving
// on at the end of each one.
class SilentPlayer(
    // Milliseconds from any fixed point; the tests pass their own.
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
    // Keeps time moving on its own when given; the tests call tick() instead.
    scope: CoroutineScope? = null,
    random: Random = Random.Default,
    volume: Float = 0.8f,
) : DesktopPlayer {
    private val queue = PlayQueue(random)
    private val lock = Any()
    private val system = OutputDevice(DEFAULT_OUTPUT, "System default")

    // Where the song was at `since`, and whether time runs from there.
    private var anchorMs = 0L
    // Times the place was moved, for PlayerState.moves.
    private var moves = 0
    private var since = clock()
    private var running = false
    private var shuffle = false
    private var repeat = RepeatMode.Off
    private var level = volume.coerceIn(0f, 1f)
    private var stopAfter = false
    // The sleep timer's fade, kept only to show: there is no sound.
    private var fade = 1f
    // Songs played to their end by themselves.
    private var ended = 0
    // Times round the current entry by repeat one, and which entry that is.
    private var rounds = 0
    private var roundsOf: Long? = null

    private val _state = MutableStateFlow(PlayerState(volume = level, output = system, outputs = listOf(system)))
    override val state: StateFlow<PlayerState> = _state

    // Nothing is measured without sound, so nothing is learned here.
    override val lengths = RealLengths()

    private val ticker: Job? = scope?.launch {
        while (isActive) {
            delay(TICK_MS)
            tick()
        }
    }

    // A live station's place is how long it has been listened to.
    override fun positionMs(): Long = synchronized(lock) {
        if (liveNow()) rawPosition() else rawPosition().coerceAtMost(durationMs().coerceAtLeast(0))
    }

    private fun liveNow(): Boolean = isRadio(queue.currentEntry?.song?.id.orEmpty())

    private fun rawPosition(): Long = if (running) anchorMs + (clock() - since) else anchorMs

    private fun durationMs(): Long = (queue.currentEntry?.song?.duration ?: 0) * 1000L

    // Moves on when the song has run out. The real engine hears this from
    // the audio; here the clock says so.
    fun tick() {
        synchronized(lock) {
            if (!running) return
            val duration = durationMs()
            // A song of unknown length never ends by itself.
            if (duration <= 0) return
            var over = rawPosition() - duration
            while (running && over >= 0) {
                val endedAt = clock() - over
                ended++
                if (stopAfter) {
                    // Paused at the start of what would play next, as the
                    // engine does; at the end of the queue it just ends.
                    stopAfter = false
                    val next = if (repeat == RepeatMode.One) queue.current else queue.nextPosition(repeat)
                    running = false
                    if (next != null) {
                        queue.moveTo(next)
                        anchorMs = 0
                    } else {
                        anchorMs = duration
                    }
                    publish()
                    return
                }
                if (repeat == RepeatMode.One) {
                    anchorMs = 0
                    since = endedAt
                    rounds++
                } else {
                    val next = queue.nextPosition(repeat)
                    if (next == null) {
                        running = false
                        anchorMs = duration
                        publish()
                        return
                    }
                    queue.moveTo(next)
                    anchorMs = 0
                    since = endedAt
                }
                val length = durationMs()
                if (length <= 0) break
                over = rawPosition() - length
            }
            publish()
        }
    }

    override fun play(songs: List<Song>, start: Int, shuffle: Boolean, source: QueueSource) {
        synchronized(lock) {
            // A lineup of stations plays in its own order.
            val lineup = isLineup(songs)
            if (!lineup) this.shuffle = shuffle
            queue.replace(songs, start, shuffle && !lineup, source)
            restartAt(0, play = queue.currentEntry != null)
        }
    }

    override fun resume() {
        synchronized(lock) {
            if (queue.currentEntry == null || running) return
            // A station starts afresh.
            if (liveNow()) return restartAt(0, play = true)
            // At the very end of the last song, Play starts it over.
            if (anchorMs >= durationMs() && durationMs() > 0) anchorMs = 0
            since = clock()
            running = true
            publish()
        }
    }

    override fun pause() {
        synchronized(lock) {
            if (!running) return
            anchorMs = rawPosition()
            running = false
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
            restartAt(0, play = running)
        }
    }

    override fun previous() {
        synchronized(lock) {
            if (queue.currentEntry == null) return
            if (queue.isLineup()) return step(forward = false)
            val back = queue.previousPosition(if (repeat == RepeatMode.One) RepeatMode.All else repeat)
            // A live stream cannot start over: back goes to the song before.
            if (liveNow()) {
                if (back != null) {
                    queue.moveTo(back)
                    restartAt(0, play = running)
                }
            } else if (rawPosition() > RESTART_AFTER_MS || back == null) {
                restartAt(0, play = running)
            } else {
                queue.moveTo(back)
                restartAt(0, play = running)
            }
        }
    }

    // Back or Next in a lineup, never round from an end.
    private fun step(forward: Boolean) {
        val to = queue.lineupStep(forward) ?: return
        queue.moveTo(to)
        restartAt(0, play = running)
    }

    override fun seekTo(positionMs: Long) {
        synchronized(lock) {
            if (queue.currentEntry == null || liveNow()) return
            restartAt(positionMs.coerceIn(0, durationMs().coerceAtLeast(0)), play = running)
        }
    }

    override fun skipTo(key: Long) {
        synchronized(lock) {
            if (queue.jumpTo(key)) restartAt(0, play = true)
        }
    }

    override fun playNext(songs: List<Song>, source: QueueSource) = putIn { queue.playNext(songs, source) }

    override fun addToQueue(songs: List<Song>, source: QueueSource) = putIn { queue.add(songs, source) }

    override fun insert(songs: List<Song>, before: Long?) = putIn { queue.insertBefore(songs, before) }

    // Songs put into an empty queue wait to be played.
    private fun putIn(change: () -> Unit) {
        synchronized(lock) {
            val wasEmpty = queue.currentEntry == null
            change()
            if (wasEmpty) restartAt(0, play = false) else publish()
        }
    }

    override fun moveUpcoming(from: Int, to: Int) {
        synchronized(lock) {
            queue.moveUpcoming(from, to)
            publish()
        }
    }

    override fun move(keys: List<Long>, before: Long?) {
        synchronized(lock) {
            queue.move(keys, before)
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

    // An edit that may have changed the song playing: the new one starts
    // from its beginning, playing if the old one was.
    private fun edited(change: () -> Boolean) {
        synchronized(lock) {
            if (change()) restartAt(0, play = running && queue.currentEntry != null) else publish()
        }
    }

    override fun clear() {
        synchronized(lock) {
            queue.clear()
            restartAt(0, play = false)
        }
    }

    override fun setShuffle(on: Boolean) {
        synchronized(lock) {
            shuffle = on
            if (!queue.isLineup()) queue.setShuffle(on)
            publish()
        }
    }

    override fun setRepeat(mode: RepeatMode) {
        synchronized(lock) {
            repeat = mode
            publish()
        }
    }

    override fun setVolume(volume: Float) {
        synchronized(lock) {
            level = volume.coerceIn(0f, 1f)
            publish()
        }
    }

    override fun selectOutput(id: String) {
        // One output only: this player makes no sound.
    }

    override fun setFade(fade: Float) {
        synchronized(lock) {
            this.fade = fade.coerceIn(0f, 1f)
            publish()
        }
    }

    override fun setStopAfterCurrent(on: Boolean) {
        synchronized(lock) {
            stopAfter = on
            publish()
        }
    }

    override fun restore(saved: SavedQueue) {
        synchronized(lock) {
            shuffle = saved.shuffle
            repeat = saved.repeat
            stopAfter = false
            queue.restore(saved.songs, saved.order, saved.index, saved.shuffle, saved.sources)
            restartAt(saved.positionMs.coerceIn(0, durationMs().coerceAtLeast(0)), play = false)
        }
    }

    override fun close() {
        ticker?.cancel()
    }

    private fun restartAt(position: Long, play: Boolean) {
        moves++
        anchorMs = position
        since = clock()
        running = play && queue.currentEntry != null
        publish()
    }

    private fun publish() {
        val key = queue.currentEntry?.key
        if (key != roundsOf) {
            roundsOf = key
            rounds = 0
        }
        val live = queue.liveNow(null, null)
        _state.value = PlayerState(
            queue = queue.songs,
            current = queue.currentEntry?.let { if (live != null) it.copy(song = shownLive(it.song, live.shown)) else it },
            upcoming = queue.upcoming,
            played = queue.played,
            rounds = rounds,
            playing = running,
            shuffle = shuffle,
            repeat = repeat,
            volume = level,
            durationMs = durationMs(),
            output = system,
            outputs = listOf(system),
            stopAfterCurrent = stopAfter,
            // The library's word only: nothing is decoded or played.
            format = queue.currentEntry?.song?.let(::libraryFormat)?.let { PlayFormat(it, null) },
            fade = fade,
            ended = ended,
            canUndo = queue.canUndo,
            moves = moves,
            live = live,
        )
    }

    private companion object {
        const val TICK_MS = 200L
    }
}
