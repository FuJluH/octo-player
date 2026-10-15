package app.winters.octo.player

import android.content.Context
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.floatPreferencesKey
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.winters.octo.ambient.AmbientArea
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.ambient.AmbientPrefs
import app.winters.octo.ambient.AmbientStrength
import app.winters.octo.playback.AutomixSettings
import app.winters.octo.playback.CopyPreference
import app.winters.octo.playback.FadeCurve
import app.winters.octo.playback.PITCH_RANGE_SEMITONES
import app.winters.octo.playback.Pace
import app.winters.octo.playback.StartAfter
import app.winters.octo.playback.StreamQuality
import app.winters.octo.playback.paceOf
import app.winters.octo.playback.snapSpeed
import app.winters.octo.player.immersive.BackgroundPrefs
import app.winters.octo.radio.RadioAdventure
import app.winters.octo.radio.RadioDiscovery
import app.winters.octo.radio.RadioTuning
import app.winters.octo.radio.RadioVariety
import app.winters.octo.theme.AccentChoice
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import javax.inject.Inject
import javax.inject.Singleton

// How the full player looks and plays. The defaults are what a new install
// gets. A backup saves all of it.
@Serializable
data class PlayerPrefs(
    // Whether the player's background moves, on phones that can draw it
    // moving. Off holds it still.
    val liveBackground: Boolean = true,
    // What the player's background is, and how it is drawn.
    val background: BackgroundPrefs = BackgroundPrefs(),
    // Songs blending into each other, and over how many seconds at most.
    // Smart transitions pick where and how each pair of songs meets (off
    // blends at the end of each song), filter sweeps thin the songs out as
    // they cross, and matching the tempo nudges the next song's speed.
    val crossfade: Boolean = false,
    val crossfadeSeconds: Int = 8,
    val smartTransitions: Boolean = true,
    val filterSweeps: Boolean = true,
    val matchTempo: Boolean = false,
    // The shape of the crossfade with smart transitions off; smart
    // transitions pick their own.
    val crossfadeCurve: FadeCurve = FadeCurve.EqualPower,
    // Looking lyrics up online when the server and the song's files have none.
    val lyricsOnline: Boolean = true,
    // How fast music plays, whether the voice keeps its pitch at other
    // speeds, and a pitch shift in semitones on top.
    val speed: Float = 1f,
    val keepPitch: Boolean = true,
    val pitchSemitones: Int = 0,
    // Quiet stretches inside songs are skipped.
    val skipSilence: Boolean = false,
    // Similar songs keep playing once the queue runs out.
    val autoplay: Boolean = true,
    // How Octo's radio is tuned (see RadioTuning).
    val radioDiscovery: RadioDiscovery = RadioDiscovery.Balanced,
    val radioAdventure: RadioAdventure = RadioAdventure.Balanced,
    val radioVariety: RadioVariety = RadioVariety.Normal,
    val radioFavorites: Boolean = false,
    // Carrying on when headphones come back: over a cable, over Bluetooth,
    // and whether to play on connect even when the music was not paused by
    // the headphones going.
    val resumeWired: Boolean = false,
    val resumeBluetooth: Boolean = false,
    val resumeAlways: Boolean = false,
    // The artwork's colours glowing behind the rest of the app.
    val ambient: AmbientPrefs = AmbientPrefs(),
    // What moves only for show holds still: the lyrics' ripple and bloom,
    // and the moving backgrounds.
    val reduceMotion: Boolean = false,
    // Casting: whether TVs and speakers found as media renderers (DLNA)
    // are offered, and whether music keeps playing on the phone when
    // casting ends by itself (otherwise it pauses).
    val castRenderers: Boolean = true,
    val castKeepPlaying: Boolean = false,
    // Only songs in the library: albums, search, artists and radio leave
    // out songs found online.
    val libraryOnly: Boolean = false,
    // The accent the app is drawn in, or the playing cover's.
    val accent: AccentChoice = AccentChoice.Octo,
    // Whether the glass (the bar, glazed buttons and sheets) takes the
    // accent too, or keeps Octo's blue gray.
    val glassTint: Boolean = false,
    // Where an album's animated art plays: in place of the cover, filling
    // the player, or nowhere. Kept by its key ("square", "full_screen",
    // "off"), as the other apps keep it.
    @Serializable(with = AnimatedArtByKey::class) val animatedArt: AnimatedArtSetting = AnimatedArtSetting.Default,
) {
    // What the player uses: the longest blend, or 0 for none.
    val crossfadeMs: Long get() = if (crossfade) crossfadeSeconds * 1_000L else 0

    // How the player plans the blends.
    val automix: AutomixSettings
        get() = AutomixSettings(
            maxOverlapMs = crossfadeMs,
            smart = smartTransitions,
            filterSweeps = filterSweeps,
            beatMatch = matchTempo,
            fadeCurve = crossfadeCurve,
        )

    // The speed and pitch the player is set to.
    val pace: Pace get() = paceOf(speed, keepPitch, pitchSemitones)

    // Whether speed and pitch are as they came.
    val paceIsDefault: Boolean get() = speed == 1f && keepPitch && pitchSemitones == 0

    // How radio and Autoplay pick their songs.
    val radioTuning: RadioTuning get() = RadioTuning(radioDiscovery, radioAdventure, radioVariety, radioFavorites)
}

// Where songs play from when a server is connected, and how big a stream
// is on Wi-Fi and on mobile data: Original (the file as it is) by default
// on both, a smaller MP3 when chosen.
@Serializable
data class StreamPrefs(
    val copies: CopyPreference = CopyPreference.PhoneFirst,
    val wifi: StreamQuality = StreamQuality.Original,
    val mobile: StreamQuality = StreamQuality.Original,
    // How much of a stream is ready before a song starts.
    val startAfter: StartAfter = StartAfter.Short,
)

// The Animated art choice written by its key, the same in every app's
// backups; one this app does not know reads as Square.
object AnimatedArtByKey : KSerializer<AnimatedArtSetting> {
    override val descriptor = PrimitiveSerialDescriptor("AnimatedArtSetting", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: AnimatedArtSetting) = encoder.encodeString(value.key)

    override fun deserialize(decoder: Decoder): AnimatedArtSetting = AnimatedArtSetting.fromKey(decoder.decodeString())
}

// The range the longest blend can be set to.
val CrossfadeSecondsRange = 2..16

private val Context.playerPrefs by preferencesDataStore("player")
private val LIVE_BACKGROUND = booleanPreferencesKey("live_background")
private val CROSSFADE = booleanPreferencesKey("crossfade")
private val CROSSFADE_SECONDS = intPreferencesKey("crossfade_seconds")
private val SMART_TRANSITIONS = booleanPreferencesKey("smart_transitions")
private val FILTER_SWEEPS = booleanPreferencesKey("filter_sweeps")
private val MATCH_TEMPO = booleanPreferencesKey("match_tempo")
private val CROSSFADE_CURVE = stringPreferencesKey("crossfade_curve")
private val LYRICS_ONLINE = booleanPreferencesKey("lyrics_online")
private val SPEED = floatPreferencesKey("speed")
private val KEEP_PITCH = booleanPreferencesKey("keep_pitch")
private val PITCH_SEMITONES = intPreferencesKey("pitch_semitones")
private val SKIP_SILENCE = booleanPreferencesKey("skip_silence")
private val AUTOPLAY = booleanPreferencesKey("autoplay")
private val RADIO_DISCOVERY = stringPreferencesKey("radio_discovery")
private val RADIO_ADVENTURE = stringPreferencesKey("radio_adventure")
private val RADIO_VARIETY = stringPreferencesKey("radio_variety")
private val RADIO_FAVORITES = booleanPreferencesKey("radio_favorites")
private val RESUME_WIRED = booleanPreferencesKey("resume_wired")
private val RESUME_BLUETOOTH = booleanPreferencesKey("resume_bluetooth")
private val RESUME_ALWAYS = booleanPreferencesKey("resume_always")
private val COPIES = stringPreferencesKey("copies")
private val AMBIENT_STRENGTH = stringPreferencesKey("ambient_strength")
private val AMBIENT_HOME = booleanPreferencesKey("ambient_home")
private val AMBIENT_LIBRARY = booleanPreferencesKey("ambient_library")
private val AMBIENT_SEARCH = booleanPreferencesKey("ambient_search")
private val AMBIENT_SETTINGS = booleanPreferencesKey("ambient_settings")
private val AMBIENT_BAR = booleanPreferencesKey("ambient_bar")
private val AMBIENT_PAGE_ARTWORK = booleanPreferencesKey("ambient_page_artwork")
internal val STREAM_WIFI = stringPreferencesKey("stream_wifi")
internal val STREAM_MOBILE = stringPreferencesKey("stream_mobile")
private val START_AFTER = stringPreferencesKey("start_after")
private val BACKGROUND_MODE = stringPreferencesKey("immersive_background")
private val BACKGROUND_BRIGHTNESS_CAP = intPreferencesKey("immersive_bg_brightness_cap")
private val BACKGROUND_SATURATION = intPreferencesKey("immersive_bg_saturation")
private val BACKGROUND_CONTRAST = floatPreferencesKey("immersive_bg_contrast")
private val BACKGROUND_USE_BPM = booleanPreferencesKey("immersive_bg_use_bpm")
private val BACKGROUND_FPS = intPreferencesKey("immersive_bg_fps")
private val BACKGROUND_SPEED = intPreferencesKey("immersive_bg_speed")
private val REDUCE_MOTION = booleanPreferencesKey("reduce_motion")
private val CAST_RENDERERS = booleanPreferencesKey("cast_renderers")
private val CAST_KEEP_PLAYING = booleanPreferencesKey("cast_keep_playing")
private val LIBRARY_ONLY = booleanPreferencesKey("library_only")
private val ACCENT = stringPreferencesKey("accent_color")
private val GLASS_TINT = booleanPreferencesKey("accent_glass")
internal val ANIMATED_ART = stringPreferencesKey(AnimatedArtSetting.PREF_KEY)

// A saved choice, or the default when nothing (or something unknown) is saved.
private inline fun <reified T : Enum<T>> choice(name: String?, default: T): T =
    enumValues<T>().firstOrNull { it.name == name } ?: default

// The Animated art choice as stored, by its key; Square when nothing (or
// something unknown) is stored.
internal fun animatedArtOf(stored: Preferences): AnimatedArtSetting = AnimatedArtSetting.fromKey(stored[ANIMATED_ART])

// The streaming choices as stored, each one not stored yet at its default.
internal fun streamPrefsOf(stored: Preferences): StreamPrefs {
    val defaults = StreamPrefs()
    return StreamPrefs(
        copies = choice(stored[COPIES], defaults.copies),
        wifi = choice(stored[STREAM_WIFI], defaults.wifi),
        mobile = choice(stored[STREAM_MOBILE], defaults.mobile),
        startAfter = choice(stored[START_AFTER], defaults.startAfter),
    )
}

@Singleton
class PlayerSettings @Inject constructor(@ApplicationContext private val context: Context) {
    val prefs: Flow<PlayerPrefs> = context.playerPrefs.data.map { stored ->
        val defaults = PlayerPrefs()
        PlayerPrefs(
            liveBackground = stored[LIVE_BACKGROUND] ?: defaults.liveBackground,
            background = BackgroundPrefs(
                mode = choice(stored[BACKGROUND_MODE], defaults.background.mode),
                brightnessCap = stored[BACKGROUND_BRIGHTNESS_CAP] ?: defaults.background.brightnessCap,
                saturation = stored[BACKGROUND_SATURATION] ?: defaults.background.saturation,
                contrast = stored[BACKGROUND_CONTRAST] ?: defaults.background.contrast,
                useBpm = stored[BACKGROUND_USE_BPM] ?: defaults.background.useBpm,
                fps = stored[BACKGROUND_FPS] ?: defaults.background.fps,
                speed = stored[BACKGROUND_SPEED] ?: defaults.background.speed,
            ).sane(),
            crossfade = stored[CROSSFADE] ?: defaults.crossfade,
            crossfadeSeconds = (stored[CROSSFADE_SECONDS] ?: defaults.crossfadeSeconds).coerceIn(CrossfadeSecondsRange),
            smartTransitions = stored[SMART_TRANSITIONS] ?: defaults.smartTransitions,
            filterSweeps = stored[FILTER_SWEEPS] ?: defaults.filterSweeps,
            matchTempo = stored[MATCH_TEMPO] ?: defaults.matchTempo,
            crossfadeCurve = choice(stored[CROSSFADE_CURVE], defaults.crossfadeCurve),
            lyricsOnline = stored[LYRICS_ONLINE] ?: defaults.lyricsOnline,
            speed = snapSpeed(stored[SPEED] ?: defaults.speed),
            keepPitch = stored[KEEP_PITCH] ?: defaults.keepPitch,
            pitchSemitones = (stored[PITCH_SEMITONES] ?: defaults.pitchSemitones)
                .coerceIn(-PITCH_RANGE_SEMITONES, PITCH_RANGE_SEMITONES),
            skipSilence = stored[SKIP_SILENCE] ?: defaults.skipSilence,
            autoplay = stored[AUTOPLAY] ?: defaults.autoplay,
            radioDiscovery = choice(stored[RADIO_DISCOVERY], defaults.radioDiscovery),
            radioAdventure = choice(stored[RADIO_ADVENTURE], defaults.radioAdventure),
            radioVariety = choice(stored[RADIO_VARIETY], defaults.radioVariety),
            radioFavorites = stored[RADIO_FAVORITES] ?: defaults.radioFavorites,
            resumeWired = stored[RESUME_WIRED] ?: defaults.resumeWired,
            resumeBluetooth = stored[RESUME_BLUETOOTH] ?: defaults.resumeBluetooth,
            resumeAlways = stored[RESUME_ALWAYS] ?: defaults.resumeAlways,
            ambient = AmbientPrefs(
                strength = choice(stored[AMBIENT_STRENGTH], defaults.ambient.strength),
                home = stored[AMBIENT_HOME] ?: defaults.ambient.home,
                library = stored[AMBIENT_LIBRARY] ?: defaults.ambient.library,
                search = stored[AMBIENT_SEARCH] ?: defaults.ambient.search,
                settings = stored[AMBIENT_SETTINGS] ?: defaults.ambient.settings,
                bar = stored[AMBIENT_BAR] ?: defaults.ambient.bar,
                pageArtwork = stored[AMBIENT_PAGE_ARTWORK] ?: defaults.ambient.pageArtwork,
            ),
            reduceMotion = stored[REDUCE_MOTION] ?: defaults.reduceMotion,
            castRenderers = stored[CAST_RENDERERS] ?: defaults.castRenderers,
            castKeepPlaying = stored[CAST_KEEP_PLAYING] ?: defaults.castKeepPlaying,
            libraryOnly = stored[LIBRARY_ONLY] ?: defaults.libraryOnly,
            accent = choice(stored[ACCENT], defaults.accent),
            glassTint = stored[GLASS_TINT] ?: defaults.glassTint,
            animatedArt = animatedArtOf(stored),
        )
    }

    val streamPrefs: Flow<StreamPrefs> = context.playerPrefs.data.map(::streamPrefsOf)

    suspend fun setLiveBackground(on: Boolean) {
        context.playerPrefs.edit { it[LIVE_BACKGROUND] = on }
    }

    // The player's background settings, all at once.
    suspend fun setBackground(prefs: BackgroundPrefs) {
        context.playerPrefs.edit { it.putBackground(prefs.sane()) }
    }

    suspend fun setCrossfade(on: Boolean) {
        context.playerPrefs.edit { it[CROSSFADE] = on }
    }

    suspend fun setCrossfadeSeconds(seconds: Int) {
        context.playerPrefs.edit { it[CROSSFADE_SECONDS] = seconds.coerceIn(CrossfadeSecondsRange) }
    }

    suspend fun setSmartTransitions(on: Boolean) {
        context.playerPrefs.edit { it[SMART_TRANSITIONS] = on }
    }

    suspend fun setFilterSweeps(on: Boolean) {
        context.playerPrefs.edit { it[FILTER_SWEEPS] = on }
    }

    suspend fun setMatchTempo(on: Boolean) {
        context.playerPrefs.edit { it[MATCH_TEMPO] = on }
    }

    suspend fun setCrossfadeCurve(curve: FadeCurve) {
        context.playerPrefs.edit { it[CROSSFADE_CURVE] = curve.name }
    }

    suspend fun setLyricsOnline(on: Boolean) {
        context.playerPrefs.edit { it[LYRICS_ONLINE] = on }
    }

    suspend fun setSpeed(speed: Float) {
        context.playerPrefs.edit { it[SPEED] = snapSpeed(speed) }
    }

    suspend fun setKeepPitch(on: Boolean) {
        context.playerPrefs.edit { it[KEEP_PITCH] = on }
    }

    suspend fun setPitchSemitones(semitones: Int) {
        context.playerPrefs.edit { it[PITCH_SEMITONES] = semitones.coerceIn(-PITCH_RANGE_SEMITONES, PITCH_RANGE_SEMITONES) }
    }

    // Normal speed and pitch again.
    suspend fun resetPace() {
        context.playerPrefs.edit {
            it.remove(SPEED)
            it.remove(KEEP_PITCH)
            it.remove(PITCH_SEMITONES)
        }
    }

    suspend fun setSkipSilence(on: Boolean) {
        context.playerPrefs.edit { it[SKIP_SILENCE] = on }
    }

    suspend fun setAutoplay(on: Boolean) {
        context.playerPrefs.edit { it[AUTOPLAY] = on }
    }

    suspend fun setRadioDiscovery(discovery: RadioDiscovery) {
        context.playerPrefs.edit { it[RADIO_DISCOVERY] = discovery.name }
    }

    suspend fun setRadioAdventure(adventure: RadioAdventure) {
        context.playerPrefs.edit { it[RADIO_ADVENTURE] = adventure.name }
    }

    suspend fun setRadioVariety(variety: RadioVariety) {
        context.playerPrefs.edit { it[RADIO_VARIETY] = variety.name }
    }

    suspend fun setRadioFavorites(on: Boolean) {
        context.playerPrefs.edit { it[RADIO_FAVORITES] = on }
    }

    suspend fun setResumeWired(on: Boolean) {
        context.playerPrefs.edit { it[RESUME_WIRED] = on }
    }

    suspend fun setResumeBluetooth(on: Boolean) {
        context.playerPrefs.edit { it[RESUME_BLUETOOTH] = on }
    }

    suspend fun setResumeAlways(on: Boolean) {
        context.playerPrefs.edit { it[RESUME_ALWAYS] = on }
    }

    suspend fun setAmbientStrength(strength: AmbientStrength) {
        context.playerPrefs.edit { it[AMBIENT_STRENGTH] = strength.name }
    }

    suspend fun setAmbientArea(area: AmbientArea, on: Boolean) {
        val key = when (area) {
            AmbientArea.Home -> AMBIENT_HOME
            AmbientArea.Library -> AMBIENT_LIBRARY
            AmbientArea.Search -> AMBIENT_SEARCH
            AmbientArea.Settings -> AMBIENT_SETTINGS
        }
        context.playerPrefs.edit { it[key] = on }
    }

    suspend fun setAmbientBar(on: Boolean) {
        context.playerPrefs.edit { it[AMBIENT_BAR] = on }
    }

    suspend fun setAmbientPageArtwork(on: Boolean) {
        context.playerPrefs.edit { it[AMBIENT_PAGE_ARTWORK] = on }
    }

    suspend fun setReduceMotion(on: Boolean) {
        context.playerPrefs.edit { it[REDUCE_MOTION] = on }
    }

    suspend fun setCastRenderers(on: Boolean) {
        context.playerPrefs.edit { it[CAST_RENDERERS] = on }
    }

    suspend fun setCastKeepPlaying(on: Boolean) {
        context.playerPrefs.edit { it[CAST_KEEP_PLAYING] = on }
    }

    suspend fun setLibraryOnly(on: Boolean) {
        context.playerPrefs.edit { it[LIBRARY_ONLY] = on }
    }

    suspend fun setAccent(accent: AccentChoice) {
        context.playerPrefs.edit { it[ACCENT] = accent.name }
    }

    suspend fun setGlassTint(on: Boolean) {
        context.playerPrefs.edit { it[GLASS_TINT] = on }
    }

    suspend fun setAnimatedArt(setting: AnimatedArtSetting) {
        context.playerPrefs.edit { it[ANIMATED_ART] = setting.key }
    }

    // Everything at once, for a backup.
    suspend fun snapshot(): Pair<PlayerPrefs, StreamPrefs> = prefs.first() to streamPrefs.first()

    // Puts back every setting from a backup in one go.
    suspend fun restore(player: PlayerPrefs, stream: StreamPrefs) {
        context.playerPrefs.edit {
            it[LIVE_BACKGROUND] = player.liveBackground
            it.putBackground(player.background.sane())
            it[CROSSFADE] = player.crossfade
            it[CROSSFADE_SECONDS] = player.crossfadeSeconds.coerceIn(CrossfadeSecondsRange)
            it[SMART_TRANSITIONS] = player.smartTransitions
            it[FILTER_SWEEPS] = player.filterSweeps
            it[MATCH_TEMPO] = player.matchTempo
            it[CROSSFADE_CURVE] = player.crossfadeCurve.name
            it[LYRICS_ONLINE] = player.lyricsOnline
            it[SPEED] = snapSpeed(player.speed)
            it[KEEP_PITCH] = player.keepPitch
            it[PITCH_SEMITONES] = player.pitchSemitones.coerceIn(-PITCH_RANGE_SEMITONES, PITCH_RANGE_SEMITONES)
            it[SKIP_SILENCE] = player.skipSilence
            it[AUTOPLAY] = player.autoplay
            it[RADIO_DISCOVERY] = player.radioDiscovery.name
            it[RADIO_ADVENTURE] = player.radioAdventure.name
            it[RADIO_VARIETY] = player.radioVariety.name
            it[RADIO_FAVORITES] = player.radioFavorites
            it[RESUME_WIRED] = player.resumeWired
            it[RESUME_BLUETOOTH] = player.resumeBluetooth
            it[RESUME_ALWAYS] = player.resumeAlways
            it[AMBIENT_STRENGTH] = player.ambient.strength.name
            it[AMBIENT_HOME] = player.ambient.home
            it[AMBIENT_LIBRARY] = player.ambient.library
            it[AMBIENT_SEARCH] = player.ambient.search
            it[AMBIENT_SETTINGS] = player.ambient.settings
            it[AMBIENT_BAR] = player.ambient.bar
            it[AMBIENT_PAGE_ARTWORK] = player.ambient.pageArtwork
            it[REDUCE_MOTION] = player.reduceMotion
            it[CAST_RENDERERS] = player.castRenderers
            it[CAST_KEEP_PLAYING] = player.castKeepPlaying
            it[LIBRARY_ONLY] = player.libraryOnly
            it[ACCENT] = player.accent.name
            it[GLASS_TINT] = player.glassTint
            it[ANIMATED_ART] = player.animatedArt.key
            it[COPIES] = stream.copies.name
            it[STREAM_WIFI] = stream.wifi.name
            it[STREAM_MOBILE] = stream.mobile.name
            it[START_AFTER] = stream.startAfter.name
        }
    }

    suspend fun setCopies(preference: CopyPreference) {
        context.playerPrefs.edit { it[COPIES] = preference.name }
    }

    suspend fun setStreamWifi(quality: StreamQuality) {
        context.playerPrefs.edit { it[STREAM_WIFI] = quality.name }
    }

    suspend fun setStreamMobile(quality: StreamQuality) {
        context.playerPrefs.edit { it[STREAM_MOBILE] = quality.name }
    }

    suspend fun setStartAfter(startAfter: StartAfter) {
        context.playerPrefs.edit { it[START_AFTER] = startAfter.name }
    }
}

private fun MutablePreferences.putBackground(prefs: BackgroundPrefs) {
    this[BACKGROUND_MODE] = prefs.mode.name
    this[BACKGROUND_BRIGHTNESS_CAP] = prefs.brightnessCap
    this[BACKGROUND_SATURATION] = prefs.saturation
    this[BACKGROUND_CONTRAST] = prefs.contrast
    this[BACKGROUND_USE_BPM] = prefs.useBpm
    this[BACKGROUND_FPS] = prefs.fps
    this[BACKGROUND_SPEED] = prefs.speed
}
