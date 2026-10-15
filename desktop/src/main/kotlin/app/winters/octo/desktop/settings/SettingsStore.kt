package app.winters.octo.desktop.settings

import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.offline.KeepChoices
import app.winters.octo.playback.FadeCurve
import app.winters.octo.playback.StartAfter
import app.winters.octo.sound.SoundSettings
import app.winters.octo.desktop.system.SystemPrefs
import app.winters.octo.desktop.discord.DiscordPrefs
import app.winters.octo.desktop.hotkeys.HotkeyPrefs
import app.winters.octo.covers.PlaylistCoverStyle
import app.winters.octo.home.HOME_SECTIONS_KEY
import app.winters.octo.livelists.accountKey
import app.winters.octo.liveradio.LIVE_RADIUS_DEFAULT_INDEX
import app.winters.octo.liveradio.LivePlace
import app.winters.octo.liveradio.LiveSort
import app.winters.octo.server.serverName
import app.winters.octo.server.settleServers
import app.winters.octo.subsonic.AuthMode
import app.winters.octo.update.UpdatePrefs
import app.winters.octo.theme.AccentChoice
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream
import app.winters.octo.radio.RadioAdventure
import app.winters.octo.radio.RadioDiscovery
import app.winters.octo.radio.RadioTuning
import app.winters.octo.radio.RadioVariety
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

// Everything the desktop app remembers between runs, as one JSON file in
// the settings folder. Every field has a default, so a file from an older
// or newer version still reads. Passwords are never in here; they live in
// the system's password store.
@Serializable
data class AppSettings(
    val window: WindowSpot? = null,
    // Use the system's own title bar instead of the app's glass one.
    val systemTitleBar: Boolean = false,
    // The server in use, as Octo kept it before there could be several. It
    // is always a copy of the one `activeServer` names, so an older Octo
    // opened later still finds it.
    val server: SavedServer? = null,
    // Every server kept here, in the listener's order, and the id of the one
    // in use (none while signed out).
    val servers: List<SavedServer> = emptyList(),
    val activeServer: String? = null,
    val appearance: Appearance = Appearance(),
    val playback: PlaybackPrefs = PlaybackPrefs(),
    // How the Songs page is ordered, as the shared sort lists save it.
    val songSort: String? = null,
    // How the Albums page is ordered, the same way.
    val albumSort: String? = null,
    // The panel open on the right, by its tab: "queue", "lyrics", "info",
    // or none.
    val sidePanel: String? = null,
    // The playlists songs were added to lately, newest first, by id, for
    // "Add to last playlist" and the top of the playlist chooser.
    val recentPlaylists: List<String> = emptyList(),
    // The frame: sidebar and panel sizes, and what the sidebar shows.
    val frame: FramePrefs = FramePrefs(),
    // The last searches that led somewhere, newest first.
    val recentSearches: List<String> = emptyList(),
    // Each song table's columns and widths, by the table's name, and how
    // tall rows are everywhere.
    val tables: Map<String, TablePrefs> = emptyMap(),
    val density: String = "regular",
    // The equalizer, loudness and the rest of the Sound page.
    val sound: SoundPrefs = SoundPrefs(),
    // Where lyrics come from, and their timing.
    val lyrics: LyricsPrefs = LyricsPrefs(),
    // The tray, notifications and the mini player.
    val system: SystemPrefs = SystemPrefs(),
    // Telling the server what was played, and carrying the queue between devices.
    val listening: ListeningPrefs = ListeningPrefs(),
    // Showing the song playing in the listener's Discord status (off unless asked).
    val discord: DiscordPrefs = DiscordPrefs(),
    // Keys that work from any app (off unless asked), and the ones chosen.
    val hotkeys: HotkeyPrefs = HotkeyPrefs(),
    // Certificates the listener chose to trust although the system does
    // not, as SHA-256 fingerprints by host. Each counts only for its host.
    // Not secret: a fingerprint only names a certificate.
    val trustedCertificates: Map<String, String> = emptyMap(),
    // Looking for new versions of Octo, and how they are put in.
    val updates: UpdatePrefs = UpdatePrefs(),
    // Only songs in the library: albums, search, artists and radio leave
    // out songs found online.
    val libraryOnly: Boolean = false,
    // This install's id, made once, which its own server tells it apart
    // by. Empty until first needed.
    val deviceId: String = "",
    // Songs kept on this computer to play without a connection.
    val offline: OfflinePrefs = OfflinePrefs(),
    // Live radio near you: where, how far and in what order, and the
    // stations kept here.
    val liveRadio: LiveRadioPrefs = LiveRadioPrefs(),
    // The newest server release the listener chose Later for, by server id.
    val serverUpdateLater: Map<String, String> = emptyMap(),
)

// The Live radio page as the listener left it: what they typed in Where
// (a postal code, or a city with its state after a comma), the country
// (an ISO code, empty for this computer's own), the place it was found to
// be, the radius chosen (by its place in the list of choices) and the
// order. `kept` is the stations kept on this computer, as KeptStations
// writes them, so a station saved by a newer Octo never breaks this file.
@Serializable
data class LiveRadioPrefs(
    val where: String = "",
    val country: String = "",
    val place: LivePlace? = null,
    val radius: Int = LIVE_RADIUS_DEFAULT_INDEX,
    val sort: LiveSort = LiveSort.Distance,
    val kept: String = "",
)

// Where kept songs go (empty for the usual folder), and what is kept from
// each server, by its id.
@Serializable
data class OfflinePrefs(
    val folder: String = "",
    // How kept songs are fetched: the file as it is, or Opus at a lower
    // bitrate (a StreamQuality name), as the phone's download quality.
    val downloadQuality: String = "Original",
    val servers: Map<String, KeepChoices> = emptyMap(),
)

// A song table as the listener set it up: the columns shown, in order (by
// their names), and the widths of any they dragged, in dp. Empty means the
// table's own choice.
@Serializable
data class TablePrefs(
    val columns: List<String> = emptyList(),
    val widths: Map<String, Float> = emptyMap(),
)

// The frame around the page, as the listener left it.
@Serializable
data class FramePrefs(
    // The sidebar's width in dp, and whether it is folded to its icons.
    val sidebarWidth: Float = 240f,
    val sidebarRail: Boolean = false,
    // The side panel's width in dp.
    val panelWidth: Float = 328f,
    // Sidebar groups folded shut, by name ("library", "yours", "playlists").
    val foldedGroups: Set<String> = emptySet(),
    // Playlists kept at the top of the sidebar's list, by id, in order.
    val pinnedPlaylists: List<String> = emptyList(),
    // Whether the time on the right counts down (the time left) or shows
    // the song's length.
    val showTimeLeft: Boolean = true,
)

// What the server hears about listening here. Both are on unless switched
// off, as on the phone.
@Serializable
data class ListeningPrefs(
    // Plays count on the server, for play counts and recently played on
    // every app that uses it.
    val reportPlays: Boolean = true,
    // The queue is kept on the server, so another device can pick it up.
    val syncQueue: Boolean = true,
)

// Lyrics settings, by song id (the server's) and by output device id.
@Serializable
data class LyricsPrefs(
    // Whether the online lyrics library (LRCLIB) may be asked, as on the phone.
    val online: Boolean = true,
    // Fast singing blooms too, as on the phone (LyricsLook.bloomFast).
    val bloomFast: Boolean = true,
    // How much later than written each song's words are heard, in ms; kept
    // only for songs that were moved.
    val offsets: Map<String, Long> = emptyMap(),
    // The same for each output: a Bluetooth pair heard late, say.
    val outputOffsets: Map<String, Long> = emptyMap(),
    // Songs whose lyrics the listener hid, on a server that does not keep
    // that choice itself.
    val hidden: Set<String> = emptySet(),
    // Lyrics picked for a song from somewhere other than the server:
    // "online:<id>" for a copy in the online library, "file" for the song
    // file's own.
    val picks: Map<String, String> = emptyMap(),
)

// The Sound page's settings. With `perOutput` on, every output (a sound
// card, headphones, a USB DAC) keeps its own set, by its device id, as on
// the phone; otherwise the shared set under SHARED_SOUND is used everywhere.
@Serializable
data class SoundPrefs(
    val perOutput: Boolean = false,
    val profiles: Map<String, SoundSettings> = emptyMap(),
    // Curves for the ten bands the listener saved under a name.
    val presets: List<SavedCurve> = emptyList(),
)

@Serializable
data class SavedCurve(val name: String, val gains: List<Float>)

const val SHARED_SOUND = "all"

// Where the window was and how big, in density-independent pixels, and
// whether it filled the screen.
@Serializable
data class WindowSpot(
    val x: Float,
    val y: Float,
    val width: Float,
    val height: Float,
    val maximized: Boolean = false,
)

// The server signed in to, without its password. The values of its extra
// headers are secrets too, so only their names are kept here.
@Serializable
data class SavedServer(
    val address: String,
    val username: String,
    val authMode: AuthMode = AuthMode.Token,
    val serverType: String? = null,
    val serverVersion: String? = null,
    val openSubsonic: Boolean = false,
    // The OpenSubsonic extensions it listed, as "name:version".
    val extensions: List<String> = emptyList(),
    // An address used instead while it answers, on the home network.
    val home: String? = null,
    val headerNames: List<String> = emptyList(),
    // Whether the password is kept in the system's store, or only while
    // the app is open.
    val rememberSignIn: Boolean = true,
    // Which server this is, for its password and its own folder of plays,
    // queue and live lists: the account's key from when it was first kept,
    // which is also the folder older versions of Octo made for it. It stays
    // when the address is edited.
    val id: String = "",
    // The name the listener gave it; none shows its host.
    val label: String = "",
    // Signed out: still in the list, its password forgotten.
    val signedOut: Boolean = false,
)

// The server's id, or the one it would get, for a server kept by an older
// version of Octo.
val SavedServer.key: String get() = id.ifEmpty { accountKey(username, address) }

// What the server is called in the app: its label, else its host.
val SavedServer.name: String get() = serverName(label, address)

private fun SavedServer.withId(): SavedServer = if (id.isEmpty()) copy(id = key) else this

// The servers as read from the file, in one shape: each with its id, and the
// one in use named by `activeServer`. `server` has the last word, since an
// older Octo writes only that: a file from before the list becomes a list of
// one, a server an older Octo signed in to since is added (or brought up to
// date) and made the one in use, and one it signed out of leaves none in use.
internal fun AppSettings.settledServers(): AppSettings {
    val (list, kept) = settleServers(
        servers.map { it.withId() },
        server?.withId(),
        id = { it.id },
        same = { a, b -> a.username == b.username && a.address == b.address },
        adopt = { legacy, same -> if (same == null) legacy else legacy.copy(id = same.id, label = legacy.label.ifEmpty { same.label }, signedOut = false) },
    )
    return copy(servers = list, activeServer = kept?.id, server = kept)
}

// The settings as they are written: `server` a copy of the one in use.
internal fun AppSettings.mirrored(): AppSettings {
    val active = activeServer?.let { id -> servers.firstOrNull { it.id == id } }
    return if (active == server && (active != null || activeServer == null)) this else copy(server = active, activeServer = active?.id)
}

@Serializable
data class Appearance(
    // A soft wash of the playing song's colours behind the window.
    val ambientGlow: Boolean = true,
    // How strong that wash is, from 0 to 1.
    val glowStrength: Float = 0.5f,
    // Less motion everywhere: the full player's background holds still and
    // lyrics move without springs or blooms.
    val calmMotion: Boolean = false,
    // The full player's moving background.
    val wash: WashPrefs = WashPrefs(),
    // What the window's colours are, when on: the glow across the top, or
    // the full player's wash behind everything.
    val ambience: AmbienceStyle = AmbienceStyle.Glow,
    // How the immersive colours move behind the pages.
    val ambienceMotion: AmbienceMotion = AmbienceMotion.Gentle,
    // How big the words are, as a percentage, or 0 for the system's own
    // text size.
    val textSize: Int = 0,
    // Playlists' pictures: designed for each one, or their album mosaics.
    val playlistCovers: PlaylistCoverStyle = PlaylistCoverStyle.Designed,
    // Home's shelves in order, a hidden one led by "-", as the phone keeps
    // them; null for the usual order, all shown.
    @SerialName(HOME_SECTIONS_KEY) val homeSections: String? = null,
    // The accent the app is drawn in, or the playing cover's.
    val accent: AccentChoice = AccentChoice.Octo,
    // Animated album covers on Octo servers that offer them: "square" in
    // place of the cover, "full_screen" behind the player, or "off"
    // (AnimatedArtSetting's keys; anything else reads as the default).
    @SerialName(AnimatedArtSetting.PREF_KEY) val animatedArt: String = AnimatedArtSetting.Default.key,
)

// The Animated art choice.
val Appearance.animatedArtSetting: AnimatedArtSetting get() = AnimatedArtSetting.fromKey(animatedArt)

// The window's colours: the playing cover blurred into a glow across the
// top, or the full player's moving wash of it behind the whole window.
@Serializable
enum class AmbienceStyle { Glow, Immersive }

// How the immersive colours move behind the pages: not at all, slowly, or
// at the full player's own pace.
@Serializable
enum class AmbienceMotion { Still, Gentle, Full }

// The full player's background, as the phone's settings have it: whether
// it moves, how fast it drifts (a share of the full pace), whether it
// follows the song's tempo, the frame rate it is held to, and how the
// cover is prepared (a cap on brightness and the saturation, both in
// percent, and the contrast as a factor).
@Serializable
data class WashPrefs(
    val moving: Boolean = true,
    val speed: Int = 25,
    val useBpm: Boolean = true,
    val fps: Int = 60,
    val brightnessCap: Int = 50,
    val saturation: Int = 180,
    val contrast: Float = 1.3f,
)

// Playback settings, read by the audio engine's player.
@Serializable
data class PlaybackPrefs(
    val volume: Float = 0.8f,
    // The longest blend, 2 to 16 seconds; 0 is off. Albums played in order
    // stay gapless.
    val crossfadeSeconds: Int = 0,
    // Each blend starts where the music allows rather than at the very end
    // of the song; with it, filter sweeps over both songs and, when asked
    // for, the next song's speed nudged to the beat.
    val smartTransitions: Boolean = true,
    val filterSweeps: Boolean = true,
    val matchTempo: Boolean = false,
    // The shape of the crossfade with smart transitions off; smart
    // transitions pick their own.
    val crossfadeCurve: FadeCurve = FadeCurve.EqualPower,
    // The device picked in the output menu, or null to follow the system.
    val outputDevice: String? = null,
    // How fast music plays (0.5 to 2), whether the voice keeps its pitch at
    // other speeds, and a pitch shift in semitones on top, as on the phone.
    val speed: Float = 1f,
    val keepPitch: Boolean = true,
    val pitchSemitones: Int = 0,
    // When the queue runs out, songs like the last one keep playing. On by
    // default, as on the phone.
    val autoplay: Boolean = true,
    // How songs stream when this app picks the quality: the file as it is,
    // or Opus at a lower bitrate (a StreamQuality name); and how much of a
    // stream is ready before it starts.
    val streamQuality: String = "Original",
    val startAfter: StartAfter = StartAfter.Short,
    // How Octo's radio is tuned (see RadioTuning).
    val radioDiscovery: RadioDiscovery = RadioDiscovery.Balanced,
    val radioAdventure: RadioAdventure = RadioAdventure.Balanced,
    val radioVariety: RadioVariety = RadioVariety.Normal,
    val radioFavorites: Boolean = false,
) {
    // How radio and Autoplay pick their songs.
    val radioTuning: RadioTuning get() = RadioTuning(radioDiscovery, radioAdventure, radioVariety, radioFavorites)
}

private val json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    prettyPrint = true
    coerceInputValues = true
}

// Reads and writes the settings file. A write goes to a temporary file
// first, is flushed to the disk, and then replaces the old one in a single
// move, so neither a crash nor a power cut leaves half a file. A file that
// is not valid settings is set aside, never deleted, and the app starts
// from the defaults.
//
// With `writeDelayMs`, changes are kept in memory at once and written a
// moment later, together, off the caller's thread: a slider dragged for a
// second is one write, not sixty. Whatever is waiting is written when the
// app ends.
class SettingsStore(private val file: File, private val writeDelayMs: Long = 0) {
    private val lock = Any()
    private val _state = MutableStateFlow(read().settledServers())

    val state: StateFlow<AppSettings> = _state

    val current: AppSettings get() = _state.value

    // The settings changed since the file was last written, if any.
    private var unsaved: AppSettings? = null
    private val writer = if (writeDelayMs > 0) {
        Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "octo-settings").apply { isDaemon = true } }
    } else {
        null
    }

    init {
        if (writer != null) Runtime.getRuntime().addShutdownHook(Thread({ flush() }, "octo-settings-exit"))
    }

    fun update(change: (AppSettings) -> AppSettings) {
        synchronized(lock) {
            val before = _state.value
            val changed = change(before)
            // A change to `server` alone is read the way an older Octo's is.
            val alone = changed.server != before.server && changed.servers == before.servers && changed.activeServer == before.activeServer
            val next = if (alone) changed.settledServers() else changed.mirrored()
            if (next == before) return
            _state.value = next
            if (writer == null) {
                write(next)
                return
            }
            val waiting = unsaved != null
            unsaved = next
            if (!waiting) writer.schedule(::flush, writeDelayMs, TimeUnit.MILLISECONDS)
        }
    }

    // Writes what is waiting now. A write that fails is tried again later.
    fun flush() {
        synchronized(lock) {
            val settings = unsaved ?: return
            if (write(settings)) {
                unsaved = null
            } else {
                runCatching { writer?.schedule(::flush, RETRY_MS, TimeUnit.MILLISECONDS) }
            }
        }
    }

    private fun read(): AppSettings {
        if (!file.exists()) return AppSettings()
        // Another program (a sync tool, a virus scanner) can hold the file
        // for a moment; that is not a broken file.
        var text: String? = null
        for (attempt in 1..READ_ATTEMPTS) {
            text = try {
                file.readText()
            } catch (e: IOException) {
                if (attempt < READ_ATTEMPTS) Thread.sleep(RETRY_READ_MS)
                null
            }
            if (text != null) break
        }
        if (text == null) return AppSettings()
        return try {
            json.decodeFromString(AppSettings.serializer(), text)
        } catch (e: SerializationException) {
            setAside()
            AppSettings()
        } catch (e: IllegalArgumentException) {
            setAside()
            AppSettings()
        }
    }

    private fun setAside() {
        val aside = File(file.parentFile, file.nameWithoutExtension + ".unreadable-" + System.currentTimeMillis() + ".json")
        runCatching { Files.move(file.toPath(), aside.toPath()) }
    }

    // True once the file holds these settings.
    private fun write(settings: AppSettings): Boolean {
        return try {
            file.parentFile?.mkdirs()
            val temp = File(file.parentFile, file.name + ".tmp")
            FileOutputStream(temp).use { out ->
                out.write(json.encodeToString(AppSettings.serializer(), settings).toByteArray(Charsets.UTF_8))
                out.fd.sync()
            }
            try {
                Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            } catch (e: IOException) {
                Files.move(temp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
            true
        } catch (e: IOException) {
            // The settings stay in memory; the next write tries again.
            false
        }
    }

    companion object {
        const val FILE_NAME = "settings.json"

        // How long the app waits to write changes, so a drag is one write.
        const val APP_WRITE_DELAY_MS = 400L
        private const val RETRY_MS = 2_000L
        private const val READ_ATTEMPTS = 3
        private const val RETRY_READ_MS = 150L
    }
}
