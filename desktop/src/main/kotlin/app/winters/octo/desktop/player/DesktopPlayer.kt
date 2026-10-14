package app.winters.octo.desktop.player

import app.winters.octo.playback.NoSource
import app.winters.octo.playback.QueueSource
import app.winters.octo.playback.RealLengths
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.flow.StateFlow

// Where the sound goes: a sound card, headphones, a USB DAC.
data class OutputDevice(val id: String, val name: String)

// What the player is doing, for the screen. Position is not in here: it
// moves all the time, so it is read with positionMs() while drawing.
data class PlayerState(
    // Every entry in queue order.
    val queue: List<QueueEntry> = emptyList(),
    // The entry playing (or paused), if any.
    val current: QueueEntry? = null,
    // The entries still to come, in the order they will play.
    val upcoming: List<QueueEntry> = emptyList(),
    // The entries already played before the current one, in play order.
    val played: List<QueueEntry> = emptyList(),
    // How many times the current entry has started over by itself (repeat
    // one), so each time round counts as its own play.
    val rounds: Int = 0,
    val playing: Boolean = false,
    val shuffle: Boolean = false,
    val repeat: RepeatMode = RepeatMode.Off,
    // From 0 to 1.
    val volume: Float = 0.8f,
    val durationMs: Long = 0,
    // The output in use, and the ones there are.
    val output: OutputDevice? = null,
    val outputs: List<OutputDevice> = emptyList(),
    // Why the last song could not play, if it could not.
    val problem: PlayProblem? = null,
    // Waiting for sound (the network, or a song opening) while playing.
    val buffering: Boolean = false,
    // Pauses once the song playing ends, a single time.
    val stopAfterCurrent: Boolean = false,
    // How fast the music plays, 1 for as recorded. Lyrics follow it.
    val speed: Float = 1f,
    // The device sound goes to now; while following the system's default,
    // `output` is the default and this says which device that is.
    val playingOn: OutputDevice? = null,
    // The current song's format and the device's, for the player bar's
    // label and the Info panel (see formatLabel and outputSentence).
    val format: PlayFormat? = null,
    // The sleep timer's fade on top of the volume, from 1 (none) to 0.
    val fade: Float = 1f,
    // How many songs have played to their end by themselves since the
    // player started (not skipped), for the sleep timer to count.
    val ended: Int = 0,
    // Whether the last edit to the queue can be taken back (undo).
    val canUndo: Boolean = false,
    // Counts each time the place in the song was moved (a seek, a song
    // started over), so a paused song's place is read again only then.
    val moves: Int = 0,
    // While a live station plays: what it has on air and the stations Back
    // and Next step through. Its place (positionMs) is how long it has been
    // listened to since it started.
    val live: LiveNow? = null,
)

// Why a song could not play: in plain words for the listener, the song if
// it was one song's fault, and the engine's own words for the details.
data class PlayProblem(val words: String, val song: Song? = null, val detail: String? = null)

// A queue put aside to come back to: the songs in queue order, the queue
// positions in the order they play, which one is current and how far into
// it, and the shuffle and repeat it had.
data class SavedQueue(
    val songs: List<Song>,
    val order: List<Int>,
    val index: Int,
    val positionMs: Long = 0,
    val shuffle: Boolean = false,
    val repeat: RepeatMode = RepeatMode.Off,
    // Where each song came from, in the same order as `songs`, when known.
    val sources: List<QueueSource>? = null,
)

// What the desktop app needs from whatever plays its music. The screens
// only ever talk to this. EnginePlayer (audio/) plays through the Rust
// audio engine; SilentPlayer keeps time and the queue with no sound, for
// tests and machines where the engine cannot load. Both pass the same
// contract tests (DesktopPlayerContract).
interface DesktopPlayer : AutoCloseable {
    val state: StateFlow<PlayerState>

    // The real lengths of songs whose listing was wrong, learned by playing
    // them, for every row that shows a song's length.
    val lengths: RealLengths

    // Where the song is, in milliseconds, right now.
    fun positionMs(): Long

    // Replaces the queue and plays from `start`. Shuffled, that song plays
    // first and the rest in a random order. `source` is the list they came
    // from, for the queue's headings.
    // A lineup (every song a live station) plays in its own order, never
    // shuffled.
    fun play(songs: List<Song>, start: Int = 0, shuffle: Boolean = false, source: QueueSource = NoSource)

    // For a live station, joins what is on air now, afresh.
    fun resume()

    // For a live station, stops its stream.
    fun pause()

    fun togglePlay()

    // In a lineup, the next station; nothing after the last.
    fun next()

    // Back to the start of the song, or to the one before when it has only
    // just begun. In a lineup, the station before; nothing before the first.
    fun previous()

    fun seekTo(positionMs: Long)

    // Plays a queue entry now.
    fun skipTo(key: Long)

    // Puts songs right after the current one. They are the listener's own
    // unless a `source` says otherwise.
    fun playNext(songs: List<Song>, source: QueueSource = QueueSource.You)

    // Puts songs at the end of what is to come: the listener's own, or a
    // radio's or Autoplay's by `source`.
    fun addToQueue(songs: List<Song>, source: QueueSource = QueueSource.You)

    // Puts the listener's songs among those to come, just before the entry
    // `before` (at the end for null), as a drop into the queue does.
    fun insert(songs: List<Song>, before: Long?)

    // Moves a song still to come, counted from the first after the current.
    fun moveUpcoming(from: Int, to: Int)

    // Moves entries to play just before the entry `before` (last for null),
    // keeping their order; see PlayQueue.move.
    fun move(keys: List<Long>, before: Long?)

    fun remove(key: Long) = remove(listOf(key))

    // Takes entries out as one edit. When the one playing goes, the next
    // plays.
    fun remove(keys: List<Long>)

    // Takes out every song still to come; the one playing plays on.
    fun clearUpcoming()

    // Takes out the songs already played.
    fun removePlayed()

    // Takes back the most recent queue edit (a removal, a move, songs put
    // in by the listener), if nothing else changed the queue since.
    // Answers whether it did.
    fun undo(): Boolean

    // Empties the queue and stops.
    fun clear()

    fun setShuffle(on: Boolean)

    fun setRepeat(mode: RepeatMode)

    fun setVolume(volume: Float)

    // Plays to one of `outputs`, or follows the system's default with
    // DEFAULT_OUTPUT.
    fun selectOutput(id: String)

    // Pauses at the end of the song playing, once.
    fun setStopAfterCurrent(on: Boolean) {}

    // Turns the sound down by a factor on top of the volume, from 1 (as
    // set) to 0, for the sleep timer's fade. The volume the listener set
    // stays as it is.
    fun setFade(fade: Float)

    // Puts a saved queue back, paused where it was left.
    fun restore(saved: SavedQueue)
}

// The output that follows whatever the system uses.
const val DEFAULT_OUTPUT = "default"

// How far into a song "Previous" restarts it instead of going back.
const val RESTART_AFTER_MS = 3_000L
