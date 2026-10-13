package app.winters.octo.desktop.listening

import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.discovery.knownLengthMs
import app.winters.octo.playback.countsAsPlay
import app.winters.octo.playback.isRadio
import app.winters.octo.playback.msLeftToCount
import app.winters.octo.subsonic.Song

// A play that counted: the song, when it began (ms since 1970), how long
// it had been heard when it counted, and how long it is.
data class HeardPlay(val song: Song, val startedAt: Long, val heardMs: Long, val durationMs: Long)

// Counts how long each song is actually heard, pauses and waits for the
// network left out, and hands on a play the moment enough of it was heard
// (the phone's rule), or when it moves on if that moment was missed. Also
// says when each song first starts to be heard. Each time round a song on
// repeat is its own play. Live radio is never a play, nor announced.
// Fed every player state, and flushed at quit from another thread, so
// each step holds the counter's lock.
class PlayCounter(
    private val onStarted: (Song) -> Unit,
    private val onCounted: (HeardPlay) -> Unit,
    // Milliseconds from any fixed point, for how long a song was heard.
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
    // Milliseconds since 1970, for when a play began.
    private val wallClock: () -> Long = System::currentTimeMillis,
) {
    private var play: Pair<Long, Int>? = null
    private var song: Song? = null
    private var durationMs = 0L
    private var startedAt = 0L
    private var heardMs = 0L
    private var hearingSince: Long? = null
    private var announced = false

    // Whether this play was already handed on, the moment it counted.
    private var counted = false

    @Synchronized
    fun update(state: PlayerState) {
        val current = state.current?.takeUnless { isRadio(it.song.id) }
        val id = current?.let { it.key to state.rounds }
        if (id != play) {
            finish()
            play = id
            song = current?.song
            startedAt = wallClock()
            heardMs = 0
            announced = false
            counted = false
        }
        if (current == null) return
        // The player's length is the sound's own once it has opened.
        durationMs = state.durationMs.takeIf { it > 0 } ?: knownLengthMs(current.song)
        val hearing = state.playing && !state.buffering
        if (hearing && hearingSince == null) {
            hearingSince = clock()
            if (!announced) {
                announced = true
                onStarted(current.song)
            }
        } else if (!hearing) {
            stopClock()
        }
    }

    // How long until the song playing counts, while it is being heard and
    // has not counted yet; null otherwise.
    @Synchronized
    fun msUntilCounted(): Long? {
        if (counted || song == null) return null
        val since = hearingSince ?: return null
        return msLeftToCount(heardMs + (clock() - since), durationMs)
    }

    // Hands on the song playing the moment enough of it was heard, not when
    // it moves on, so the last song before a long pause or a shutdown is
    // neither held back nor lost. Once per play.
    @Synchronized
    fun check() {
        if (counted) return
        val heard = song ?: return
        val heardNow = heardMs + (hearingSince?.let { clock() - it } ?: 0)
        if (!countsAsPlay(heardNow, durationMs)) return
        counted = true
        onCounted(HeardPlay(heard, startedAt, heardNow, durationMs))
    }

    // Hands on the song playing now if it counts, and starts over: for
    // quitting, or signing out.
    @Synchronized
    fun flush() {
        finish()
        play = null
        song = null
    }

    private fun finish() {
        stopClock()
        val heard = song ?: return
        if (!counted && countsAsPlay(heardMs, durationMs)) onCounted(HeardPlay(heard, startedAt, heardMs, durationMs))
        song = null
        heardMs = 0
    }

    private fun stopClock() {
        hearingSince?.let { heardMs += clock() - it }
        hearingSince = null
    }
}
