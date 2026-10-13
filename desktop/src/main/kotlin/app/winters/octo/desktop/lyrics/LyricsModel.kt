package app.winters.octo.desktop.lyrics

import app.winters.octo.desktop.audio.isBluetoothOutput
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.OutputDevice
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.settings.currentOs
import app.winters.octo.playback.isRadio
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.math.BigDecimal
import kotlin.math.abs
import kotlin.math.roundToLong

// Lyrics timing, as on the phone. An offset says how much later than
// written the words are heard: at +500 a line written at 1:00.00 is sung
// at 1:00.50. A song's own offset and the output's add up.
const val TIMING_STEP_MS = 50L
const val TIMING_LIMIT_MS = 10_000L
const val OUTPUT_TIMING_LIMIT_MS = 2_000L

// A screen shows a frame about this many frames after it is drawn for.
const val SCREEN_FRAMES = 2

// Where in the song a line written at this time is heard.
fun heardAt(lyricsMs: Long, offsetMs: Long): Long = (lyricsMs + offsetMs).coerceAtLeast(0)

fun stepTiming(offsetMs: Long, steps: Int, limitMs: Long = TIMING_LIMIT_MS): Long =
    (offsetMs + steps * TIMING_STEP_MS).coerceIn(-limitMs, limitMs)

// How far ahead of the song the words are shown, so they are on the glass
// when the song is heard: the frames the screen takes at its refresh rate.
// Every output starts from this; its own setting moves it from there.
fun screenLeadMs(refreshHz: Float): Long {
    val hz = if (refreshHz.isFinite() && refreshHz >= 30f) refreshHz else 60f
    return -(SCREEN_FRAMES * 1000.0 / hz).roundToLong()
}

// Where an output's timing starts when the listener never set one: the
// words are mostly heard this much late, about 0.3 s on built-in speakers
// or a cable and 0.5 s over Bluetooth, which holds more sound back.
// Starting there leaves most listeners nothing to move.
const val WIRED_OUTPUT_TIMING_MS = -300L
const val BLUETOOTH_OUTPUT_TIMING_MS = -500L

fun automaticOutputTiming(bluetooth: Boolean): Long = if (bluetooth) BLUETOOTH_OUTPUT_TIMING_MS else WIRED_OUTPUT_TIMING_MS

// An output's timing, and whether it is the automatic one (never set by
// the listener) rather than one they set, 0 included.
data class OutputTiming(val ms: Long, val automatic: Boolean)

fun outputTimingOf(kept: Long?, bluetooth: Boolean): OutputTiming =
    kept?.let { OutputTiming(it, automatic = false) } ?: OutputTiming(automaticOutputTiming(bluetooth), automatic = true)

// What an output's timing applies to, and, while it is the automatic one,
// what that is.
fun outputTimingAbout(bluetooth: Boolean, automatic: Boolean): String = when {
    !automatic -> "For every song on this output."
    bluetooth -> "For every song on this output. Automatic: ${timingWords(BLUETOOTH_OUTPUT_TIMING_MS)}, the usual for Bluetooth."
    else -> "For every song on this output. Automatic: ${timingWords(WIRED_OUTPUT_TIMING_MS)}, the usual for speakers or a cable."
}

// The offset in words: "in time", "0.25 s later", "0.3 s earlier".
fun timingWords(offsetMs: Long): String {
    if (offsetMs == 0L) return "in time"
    val seconds = BigDecimal.valueOf(abs(offsetMs), 3).stripTrailingZeros().toPlainString()
    return if (offsetMs > 0) "$seconds s later" else "$seconds s earlier"
}

// The offset as a signed number of seconds: "0 s", "+0.75 s", "-1.5 s".
fun signedTiming(offsetMs: Long): String {
    if (offsetMs == 0L) return "0 s"
    val seconds = BigDecimal.valueOf(abs(offsetMs), 3).stripTrailingZeros().toPlainString()
    return if (offsetMs > 0) "+$seconds s" else "-$seconds s"
}

// The refresh rate of the main screen, for the screen lead.
fun screenRefreshHz(): Float = runCatching {
    java.awt.GraphicsEnvironment.getLocalGraphicsEnvironment().defaultScreenDevice.displayMode.refreshRate.toFloat()
}.getOrDefault(60f)

// The lyrics of the song playing now, fetched once per song however many
// views show them (the side panel and the full player), and again when
// the listener chose other lyrics, hid them or showed them again.
class LyricsModel(
    private val player: DesktopPlayer,
    val sources: LyricsSources,
    private val settings: SettingsStore,
    scope: CoroutineScope,
    // Whether an output is Bluetooth, asked of the system.
    private val route: (OutputDevice?) -> Boolean = { isBluetoothOutput(it, currentOs()) },
) {
    // The song, and its lyrics once found (null while looking).
    data class Shown(val song: Song?, val answer: LyricsAnswer?)

    private val _state = MutableStateFlow(Shown(null, null))
    val state: StateFlow<Shown> = _state

    // Whether the output playing now is Bluetooth, for its automatic
    // timing; found out again whenever the output changes.
    private val _bluetooth = MutableStateFlow(false)
    val bluetooth: StateFlow<Boolean> = _bluetooth

    init {
        @OptIn(ExperimentalCoroutinesApi::class)
        scope.launch {
            player.state.map { it.playingOn }
                .distinctUntilChanged()
                .mapLatest { device -> withContext(Dispatchers.IO) { route(device) } }
                .collect { _bluetooth.value = it }
        }
        @OptIn(ExperimentalCoroutinesApi::class)
        scope.launch {
            // By id: the same song with its length corrected is not a new song.
            combine(player.state.map { it.current?.song }.distinctUntilChanged { a, b -> a?.id == b?.id }, sources.revisions) { song, revisions ->
                song to (song?.let { revisions[it.id] } ?: 0)
            }
                .distinctUntilChanged()
                .mapLatest { (song, _) ->
                    if (song == null) return@mapLatest Shown(null, LyricsAnswer.None)
                    // Live radio has no lyrics to follow.
                    if (isRadio(song.id)) return@mapLatest Shown(song, LyricsAnswer.None)
                    _state.value = Shown(song, null)
                    Shown(song, sources.answerFor(song))
                }
                // An answer that lands just as the song changes belongs to
                // the old song; it is never shown over the new one.
                .collect { shown -> if (shown.song?.id == player.state.value.current?.song?.id) _state.value = shown }
        }
    }

    // ---- Timing ----

    fun songOffset(songId: String): Long = settings.current.lyrics.offsets[songId] ?: 0L

    fun outputOffset(device: String?): Long = outputTiming(device).ms

    // The output's timing: the one set for it, or the automatic one.
    fun outputTiming(device: String?): OutputTiming =
        outputTimingOf(device?.let { settings.current.lyrics.outputOffsets[it] }, _bluetooth.value)

    fun stepSong(songId: String, steps: Int) = settings.update { s ->
        val moved = stepTiming(s.lyrics.offsets[songId] ?: 0L, steps)
        val offsets = if (moved == 0L) s.lyrics.offsets - songId else s.lyrics.offsets + (songId to moved)
        s.copy(lyrics = s.lyrics.copy(offsets = offsets))
    }

    // Moves an output's timing from where it is now, its automatic one at
    // first, and keeps it, 0 included.
    fun stepOutput(device: String, steps: Int) {
        val bluetooth = _bluetooth.value
        settings.update { s ->
            val moved = stepTiming(s.lyrics.outputOffsets[device] ?: automaticOutputTiming(bluetooth), steps, OUTPUT_TIMING_LIMIT_MS)
            s.copy(lyrics = s.lyrics.copy(outputOffsets = s.lyrics.outputOffsets + (device to moved)))
        }
    }

    // Back to the output's automatic timing.
    fun resetOutput(device: String) = settings.update { s ->
        s.copy(lyrics = s.lyrics.copy(outputOffsets = s.lyrics.outputOffsets - device))
    }
}
