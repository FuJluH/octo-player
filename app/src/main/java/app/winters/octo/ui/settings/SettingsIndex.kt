package app.winters.octo.ui.settings

import app.winters.octo.discovery.LIBRARY_ONLY_SETTING
import app.winters.octo.playback.START_AFTER_SETTING
import app.winters.octo.radio.SONG_RADIO

import app.winters.octo.covers.PLAYLIST_COVERS_SETTING
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.catalog.searchKey
import kotlinx.serialization.Serializable

// The pages Settings opens, in the order the front page lists them.
@Serializable
enum class SettingsPage(val title: String) {
    Playback("Playback"),
    Sound("Sound"),
    Radio("Radio"),
    Appearance("Appearance"),
    Library("Library"),
    Server("Server and sync"),
    Streaming("Streaming and downloads"),
    AudioQuality("Audio quality"),
    Lyrics("Lyrics"),
    Scrobbling("Scrobbling"),
    Backup("Backup and restore"),
    About("About"),
}

// One setting as search finds it: the page it is on, the part of the page
// when there is one, its title, a line about it, and other words people
// might look for it by. The id marks its row, so search can point at it.
data class SettingEntry(
    val id: String,
    val page: SettingsPage,
    val title: String,
    val summary: String = "",
    val keywords: List<String> = emptyList(),
    val section: String? = null,
) {
    // Where it lives, for a search result: "Appearance · Where it shows".
    val place: String get() = listOfNotNull(page.title, section).joinToString(" · ")
}

// The Radio page's part for the stations on the air; the other is SONG_RADIO.
const val LIVE_RADIO = "Live radio"

// Every setting, written down once. The rows take their titles from here,
// so what search finds is always what the page shows.
object SettingsIndex {
    private val registered = mutableListOf<SettingEntry>()

    private fun add(
        id: String,
        page: SettingsPage,
        title: String,
        summary: String = "",
        keywords: List<String> = emptyList(),
        section: String? = null,
    ): SettingEntry = SettingEntry(id, page, title, summary, keywords, section).also { registered += it }

    // Playback
    val Crossfade = add(
        "crossfade", SettingsPage.Playback, "Crossfade", "Each song fades into the next",
        listOf("fade", "blend", "gapless", "transition", "mix"),
    )
    val CrossfadeLength = add(
        "crossfade_length", SettingsPage.Playback, "Longest blend", "The most seconds two songs blend for",
        listOf("fade", "seconds", "duration", "crossfade length"),
    )
    val CrossfadeCurve = add(
        "crossfade_curve", SettingsPage.Playback, "Crossfade curve", "How one song fades into the next",
        listOf("fade", "curve", "shape", "linear", "equal power", "s-curve", "logarithmic", "mix", "dj", "transition"),
    )
    val SmartTransitions = add(
        "smart_transitions", SettingsPage.Playback, "Smart transitions", "Each blend starts where the songs meet best",
        listOf("automix", "dj", "mix", "transition", "beat", "outro"),
    )
    val FilterSweeps = add(
        "filter_sweeps", SettingsPage.Playback, "Filter sweeps", "Songs thin out as they cross",
        listOf("filter", "sweep", "bass", "eq", "dj"),
    )
    val MatchTempo = add(
        "match_tempo", SettingsPage.Playback, "Match tempo", "The next song nudges its speed to the beat",
        listOf("tempo", "bpm", "beat", "beatmatch", "speed"),
    )
    val Speed = add(
        "speed", SettingsPage.Playback, "Speed", "How fast music plays, and its pitch",
        listOf("tempo", "pitch", "faster", "slower", "rate", "semitones"),
    )
    val SkipSilence = add(
        "skip_silence", SettingsPage.Playback, "Skip silence", "Quiet stretches inside songs are skipped",
        listOf("quiet", "gaps", "silent"),
    )
    val Autoplay = add(
        "autoplay", SettingsPage.Playback, "Autoplay", "Similar songs keep playing when the queue ends",
        listOf("similar", "continue", "endless", "radio", "queue"),
    )
    val ResumeWired = add(
        "resume_wired", SettingsPage.Playback, "Resume when headphones connect", "Plays again when a cable goes back in",
        listOf("headphones", "cable", "wired", "usb", "plug"), section = "Headphones",
    )
    val ResumeBluetooth = add(
        "resume_bluetooth", SettingsPage.Playback, "Resume when Bluetooth connects", "Plays again when Bluetooth reconnects",
        listOf("bluetooth", "speaker", "car", "headphones"), section = "Headphones",
    )
    val ResumeAlways = add(
        "resume_always", SettingsPage.Playback, "Always play on connect", "Plays on connect however the music stopped",
        listOf("headphones", "bluetooth", "connect"), section = "Headphones",
    )

    val CastRenderers = add(
        "cast_renderers", SettingsPage.Playback, "Show TVs and speakers (DLNA)", "Smart TVs, receivers and streamers on the Wi-Fi",
        listOf("cast", "casting", "dlna", "upnp", "renderer", "tv", "speaker", "receiver", "streamer", "devices"), section = "Casting",
    )
    val CastKeepPlaying = add(
        "cast_keep_playing", SettingsPage.Playback, "Keep playing on the phone when casting ends", "Otherwise the music pauses",
        listOf("cast", "casting", "chromecast", "tv", "speaker", "disconnect", "resume", "phone"), section = "Casting",
    )

    // Radio: Octo's song radio, made from your music, and live radio, the
    // stations on the air
    val RadioDiscovery = add(
        "radio_discovery", SettingsPage.Radio, "Discovery", "How much of a song radio comes from outside your library",
        listOf("radio", "song radio", "start radio", "autoplay", "new music", "outside", "library only", "discover"), section = SONG_RADIO,
    )
    val RadioAdventure = add(
        "radio_adventure", SettingsPage.Radio, "Adventure", "How far a song radio strays from the song it started from",
        listOf("radio", "song radio", "start radio", "autoplay", "focused", "wander", "deep cuts", "similar"), section = SONG_RADIO,
    )
    val RadioVariety = add(
        "radio_variety", SettingsPage.Radio, "Artist variety", "How soon an artist or album comes back",
        listOf("radio", "song radio", "autoplay", "repeat", "spacing", "artist", "album"), section = SONG_RADIO,
    )
    val RadioFavorites = add(
        "radio_favorites", SettingsPage.Radio, "Favorites more often", "Hearted and 4 or 5 star songs come around more",
        listOf("radio", "song radio", "autoplay", "favorite", "hearted", "rating", "stars"), section = SONG_RADIO,
    )
    val LiveRadioNear = add(
        "live_radio_near", SettingsPage.Radio, "Find stations near you", "Live stations on the air around a place, to play or keep",
        listOf("live radio", "radio", "stations", "fm", "am", "local", "near me", "nearby", "internet radio", "location", "place", "kept"),
        section = LIVE_RADIO,
    )
    val RadioStations = add(
        "radio_stations", SettingsPage.Radio, "Stations on your server", "The live stations your server keeps, for everyone on it",
        listOf("live radio", "radio", "radio stations", "internet radio", "streams", "add a station", "server"), section = LIVE_RADIO,
    )

    // Sound, which has a page of its own
    val SoundPerOutput = add(
        "sound_per_output", SettingsPage.Sound, "Sound for each output", "Headphones and speakers keep their own sound",
        listOf("bluetooth", "speaker", "device", "output"),
    )
    val Equalizer = add(
        "sound_equalizer", SettingsPage.Sound, "Equalizer", "Shape the sound, with presets",
        listOf("eq", "bass", "treble", "presets", "bands", "filters"),
    )
    val Loudness = add(
        "sound_loudness", SettingsPage.Sound, "Loudness", "Even out the volume between songs",
        listOf("volume", "levelling", "leveling", "normalize", "replaygain", "preamp"),
    )
    val Balance = add(
        "sound_balance", SettingsPage.Sound, "Balance", "Left and right",
        listOf("left", "right", "channel", "mono"),
    )
    val Crossfeed = add(
        "sound_crossfeed", SettingsPage.Sound, "Crossfeed", "Each ear hears a little of the other side, for headphones",
        listOf("headphones", "stereo", "speakers", "fatigue", "bs2b", "chu moy", "meier", "blend"),
    )
    val HeadphoneCorrection = add(
        "sound_correction", SettingsPage.Sound, "Headphone correction", "A correction for the headphones in use",
        listOf("headphones", "correction", "profile", "tuning"),
    )

    // Appearance
    val Ambient = add(
        "ambient", SettingsPage.Appearance, "Ambient color from the artwork", "The artwork's colors glowing behind the pages",
        listOf("glow", "background", "colours", "colors", "theme", "strength"),
    )
    val AmbientHome = add(
        "ambient_home", SettingsPage.Appearance, "Home", "The glow on the home page",
        listOf("glow"), section = "Where it shows",
    )
    val AmbientLibrary = add(
        "ambient_library", SettingsPage.Appearance, "Library", "The glow on library lists and pages",
        listOf("glow"), section = "Where it shows",
    )
    val AmbientSearch = add(
        "ambient_search", SettingsPage.Appearance, "Search", "The glow on the search page",
        listOf("glow"), section = "Where it shows",
    )
    val AmbientSettings = add(
        "ambient_settings", SettingsPage.Appearance, "Settings", "The glow on these pages",
        listOf("glow"), section = "Where it shows",
    )
    val AmbientBar = add(
        "ambient_bar", SettingsPage.Appearance, "Mini player and bar", "A trace of the song's color in the bar",
        listOf("glow", "bar", "tint"), section = "Where it shows",
    )
    val AmbientPageArtwork = add(
        "ambient_page_artwork", SettingsPage.Appearance, "Album and artist pages use their own artwork",
        "The glow follows the album or artist on the page",
        listOf("glow", "album", "artist", "cover"), section = "Where it shows",
    )
    val PlayerBackground = add(
        "immersive_background", SettingsPage.Appearance, "Player background", "What fills the player behind the lyrics",
        listOf("immersive", "wash", "artwork", "cover", "colour", "color", "blur", "classic", "mesh"), section = "Player",
    )
    val LiveBackground = add(
        "live_background", SettingsPage.Appearance, "Live background", "The player's background drifting slowly",
        listOf("player", "animated", "moving", "motion", "colours", "blur"), section = "Player",
    )
    val AnimatedArt = add(
        AnimatedArtSetting.PREF_KEY, SettingsPage.Appearance, AnimatedArtSetting.TITLE, AnimatedArtSetting.ABOUT,
        listOf("animated", "cover", "artwork", "video", "loop", "apple music", "album art", "full screen", "square"), section = "Player",
    )
    val BackgroundBrightnessCap = add(
        "immersive_bg_brightness_cap", SettingsPage.Appearance, "Brightness cap", "How bright the background may get, so words stay readable",
        listOf("background", "dim", "white", "readable"), section = "Player",
    )
    val BackgroundSaturation = add(
        "immersive_bg_saturation", SettingsPage.Appearance, "Saturation", "How vivid the background's colors are",
        listOf("background", "vivid", "colours", "color"), section = "Player",
    )
    val BackgroundContrast = add(
        "immersive_bg_contrast", SettingsPage.Appearance, "Contrast", "How far the background's light and dark parts are pushed apart",
        listOf("background"), section = "Player",
    )
    val BackgroundUseBpm = add(
        "immersive_bg_use_bpm", SettingsPage.Appearance, "Move with the beat", "The background drifts at the song's pace",
        listOf("bpm", "beats", "background", "motion"), section = "Player",
    )
    val BackgroundSpeed = add(
        "immersive_bg_speed", SettingsPage.Appearance, "Drift speed", "How fast the background moves",
        listOf("background", "slow", "fast", "motion", "speed", "ambience"), section = "Player",
    )
    val HomeSections = add(
        "home_sections", SettingsPage.Appearance, "Home sections", "The order of Home's shelves, and which ones show",
        listOf("home", "shelves", "sections", "order", "rearrange", "reorder", "move", "hide", "show", "layout", "customize", "edit home"),
        section = "Home",
    )
    val PlaylistCovers = add(
        "playlist_covers", SettingsPage.Appearance, PLAYLIST_COVERS_SETTING, "Designed covers, or the covers of their albums",
        listOf("playlist", "cover", "artwork", "mosaic", "picture", "designed"), section = "Playlists",
    )
    val AccentColor = add(
        "accent_color", SettingsPage.Appearance, "Accent color", "The color of selections, sliders, switches and buttons",
        listOf("accent", "color", "colour", "theme", "tint", "highlight", "palette", "album art", "cover", "personalize"), section = "Accent color",
    )
    val GlassTint = add(
        "accent_glass", SettingsPage.Appearance, "Color the glass", "The bar, glass buttons and sheets take the accent too",
        listOf("glass", "glaze", "frosted", "bar", "tint", "accent", "color", "colour", "theme"), section = "Accent color",
    )
    val ReduceMotion = add(
        "reduce_motion", SettingsPage.Appearance, "Reduce motion", "What moves only for show holds still",
        listOf("animation", "animations", "accessibility", "still", "calm", "motion sickness"), section = "Motion",
    )

    // Library
    val PhoneAccess = add(
        "phone_access", SettingsPage.Library, "Music access", "Whether Octo may read the music on this phone",
        listOf("permission", "allow", "storage", "files"), section = "Music on this phone",
    )
    val PhoneSongs = add(
        "phone_songs", SettingsPage.Library, "Songs", "How many songs are on this phone",
        listOf("count", "library"), section = "Music on this phone",
    )
    val Rescan = add(
        "rescan", SettingsPage.Library, "Rescan", "Look for new music on this phone",
        listOf("scan", "refresh", "find", "update", "new music"), section = "Music on this phone",
    )
    val LibraryOnly = add(
        "library_only", SettingsPage.Library, LIBRARY_ONLY_SETTING, "Leave songs found online out of albums, search, artists and radio",
        listOf("outside", "online", "found", "hide", "only", "my songs", "not in library", "discover"), section = "Songs found online",
    )
    val MusicFolders = add(
        "music_folders", SettingsPage.Library, "Music folders", "Leave a folder's music out of your library",
        listOf("folders", "exclude", "hide", "include", "podcasts", "recordings"),
    )

    // Server and sync
    val ConnectServer = add(
        "connect_server", SettingsPage.Server, "Connect a server", "Add the music on your own server",
        listOf("sign in", "login", "add server", "account"),
    )
    val YourServers = add(
        "your_servers", SettingsPage.Server, "Your servers", "The servers kept on this phone, and the one in use",
        listOf("servers", "switch server", "several servers", "accounts", "sign out", "remove server", "in use"),
        section = "Your servers",
    )
    val AddServer = add(
        "add_server", SettingsPage.Server, "Add a server", "Keep another server here and switch to it in one tap",
        listOf("add server", "another server", "second server", "new server", "account"),
        section = "Your servers",
    )
    val ServerAddress = add(
        "server_address", SettingsPage.Server, "Address", "Where the server is",
        listOf("server", "url", "host"), section = "Connection",
    )
    val ServerConnection = add(
        "server_connection", SettingsPage.Server, "Connection", "Whether you are connected at home or away",
        listOf("home", "away", "network", "local"), section = "Connection",
    )
    val ServerUser = add(
        "server_user", SettingsPage.Server, "User", "Who is signed in",
        listOf("account", "username", "login"), section = "Connection",
    )
    val ServerMusicFolder = add(
        "server_music_folder", SettingsPage.Server, "Music folder", "Limit the library to one of the server's folders",
        listOf("server folder", "library folder", "limit"), section = "Connection",
    )
    val EditConnection = add(
        "edit_connection", SettingsPage.Server, "Edit connection", "Change the address or sign-in",
        listOf("change server", "password", "address", "sign in"), section = "Connection",
    )
    val ChangePassword = add(
        "change_password", SettingsPage.Server, "Change password", "Set a new password for your account on the server",
        listOf("password", "account", "security", "sign in"), section = "Connection",
    )
    val ServerKind = add(
        "server_kind", SettingsPage.Server, "Server", "What the server is, and what it offers",
        listOf("version", "navidrome", "octo", "subsonic", "about"), section = "Server",
    )
    val ServerAnswer = add(
        "server_answer", SettingsPage.Server, "Response time", "How quickly the server answers",
        listOf("speed", "ping", "latency", "slow"), section = "Server",
    )
    val ServerScan = add(
        "server_scan", SettingsPage.Server, "Its folders", "When the server last looked for new music",
        listOf("scan", "last scan", "new music"), section = "Server",
    )
    val OctoAdmin = add(
        "octo_admin", SettingsPage.Server, "Octo admin", "What Octo is doing: services, stations and downloads",
        listOf("admin", "health", "services", "stations"), section = "Connection",
    )
    val Import = add(
        "import", SettingsPage.Server, "Import", "Your music from another service, a file or a list, and fetching what is missing",
        listOf(
            "import", "get my music", "move", "transfer", "spotify", "apple music", "youtube music", "amazon music", "tidal", "deezer",
            "qobuz", "soundcloud", "pandora", "youtube", "tunemymusic", "playlists", "liked", "file", "csv", "paste", "missing", "download",
        ),
        section = "Connection",
    )
    val Family = add(
        "family", SettingsPage.Server, "Family", "Your plan, requests and devices, and the family's",
        listOf("family", "members", "requests", "devices", "approve", "plan", "storage"), section = "Connection",
    )
    val SignInElsewhere = add(
        "sign_in_elsewhere", SettingsPage.Server, "Sign in on another device", "A QR code your phone or computer scans to sign in with your login",
        listOf("qr", "scan", "another device", "phone", "computer", "sign in", "login"), section = "Connection",
    )
    val LastSynced = add(
        "last_synced", SettingsPage.Server, "Last synced", "When the server's library was last copied",
        listOf("sync", "updated"), section = "Sync",
    )
    val SyncNow = add(
        "sync_now", SettingsPage.Server, "Sync now", "Copy the server's library again",
        listOf("sync", "refresh", "update"), section = "Sync",
    )
    val QueueSync = add(
        "queue_sync", SettingsPage.Server, "Sync play queue with the server", "Pick up where another device left off",
        listOf("queue", "resume", "other device", "continue"), section = "Sync",
    )
    val PlaylistsToServer = add(
        "playlists_to_server", SettingsPage.Server, "Save new playlists to the server", "Playlists you make here are made there too",
        listOf("playlists", "upload", "sync"), section = "Sync",
    )
    val Shares = add(
        "shares", SettingsPage.Server, "Shared links", "Links to songs and albums you shared",
        listOf("share", "links"), section = "On the server",
    )
    val ScanServer = add(
        "scan_server", SettingsPage.Server, "Scan library now", "Ask the server to look for new music",
        listOf("scan", "refresh", "new music"), section = "On the server",
    )
    val ListeningNow = add(
        "listening_now", SettingsPage.Server, "Listening now", "Who else is playing music from the server",
        listOf("others", "users", "now playing"),
    )
    val Disconnect = add(
        "disconnect", SettingsPage.Server, "Sign out", "Sign out of the server in use, which stays in your list",
        listOf("sign out", "log out", "disconnect"),
    )

    // Streaming and downloads
    val Copies = add(
        "copies", SettingsPage.Streaming, "When a song is on the phone and the server", "Which copy plays",
        listOf("phone copy", "best quality", "duplicate", "prefer"), section = "Streaming",
    )
    // Audio quality
    val AccountHome = add(
        "account_home", SettingsPage.AudioQuality, "At home", "Your account's quality on your home network, for every app",
        listOf("quality", "bitrate", "family", "home", "account"), section = "Your account",
    )
    val AccountAway = add(
        "account_away", SettingsPage.AudioQuality, "Away from home", "Your account's quality anywhere else, for every app",
        listOf("quality", "bitrate", "family", "away", "data saver", "account"), section = "Your account",
    )
    val DeviceQuality = add(
        "device_quality", SettingsPage.AudioQuality, "This phone follows", "Your account's choice, or this app's",
        listOf("quality", "device", "family", "app"), section = "Quality on this device",
    )
    val StreamWifi = add(
        "stream_wifi", SettingsPage.AudioQuality, "Streaming on Wi-Fi", "This app's quality over Wi-Fi",
        listOf("quality", "bitrate", "kbps", "streaming", "wifi"), section = "This app",
    )
    val StartAfter = add(
        "start_after", SettingsPage.Streaming, START_AFTER_SETTING, "How much of a song is ready before it starts",
        listOf("buffer", "preload", "start", "slow", "wait", "stutter"), section = "Streaming",
    )
    val StreamMobile = add(
        "stream_mobile", SettingsPage.AudioQuality, "Streaming on mobile data", "This app's quality over mobile data",
        listOf("quality", "bitrate", "kbps", "cellular", "data saver", "streaming", "mobile"), section = "This app",
    )
    val CacheSize = add(
        "cache_size", SettingsPage.Streaming, "Cache size", "Room for songs played lately, to play without a connection",
        listOf("storage", "offline", "space"), section = "Cache",
    )
    val FetchWifi = add(
        "fetch_wifi", SettingsPage.Streaming, "Fetch ahead on Wi-Fi", "Songs ahead in the queue saved while one plays",
        listOf("prefetch", "preload", "next songs", "offline"), section = "Cache",
    )
    val FetchMobile = add(
        "fetch_mobile", SettingsPage.Streaming, "Fetch ahead on mobile data", "Songs ahead saved on mobile data",
        listOf("prefetch", "preload", "cellular"), section = "Cache",
    )
    val ClearCache = add(
        "clear_cache", SettingsPage.Streaming, "Clear cache", "Free the room the cache takes",
        listOf("free space", "storage", "delete"), section = "Cache",
    )
    val DownloadQuality = add(
        "download_quality", SettingsPage.Streaming, "Download quality", "The file downloads come as",
        listOf("bitrate", "kbps", "offline"), section = "Downloads",
    )
    val WifiOnly = add(
        "wifi_only", SettingsPage.Streaming, "Download on Wi-Fi only", "Downloads wait for Wi-Fi",
        listOf("mobile data", "cellular"), section = "Downloads",
    )
    val KeepLiked = add(
        "keep_liked", SettingsPage.Streaming, "Keep Liked songs downloaded", "Liked songs follow your likes offline",
        listOf("offline", "likes", "auto download"), section = "Downloads",
    )
    val StreamOnWifi = add(
        "stream_on_wifi", SettingsPage.Streaming, "Prefer streaming on Wi-Fi", "Stream even when a song is downloaded",
        listOf("downloaded", "stream"), section = "Downloads",
    )
    val DownloadedMusic = add(
        "downloaded_music", SettingsPage.Streaming, "Downloaded music", "What is downloaded, and how much room it takes",
        listOf("downloads", "offline", "manage"), section = "Downloads",
    )

    // Lyrics
    val LyricsOnline = add(
        "lyrics_online", SettingsPage.Lyrics, "Find lyrics online", "Look lyrics up when your music has none",
        listOf("internet", "lookup", "synced", "words"),
    )
    val LyricsScreenOn = add(
        "lyrics_screen_on", SettingsPage.Lyrics, "Keep the screen on", "While lyrics show in the player",
        listOf("screen", "timeout", "awake", "display"),
    )
    val LyricsStyle = add(
        "lyrics_style", SettingsPage.Lyrics, "Lyrics style", "Flowing, or the classic view",
        listOf("look", "flowing", "classic", "animation", "synced", "karaoke"), section = "Synced lyrics",
    )
    val LyricsEmphasis = add(
        "lyrics_fx_emphasis", SettingsPage.Lyrics, "Emphasis", "How much long notes swell letter by letter",
        listOf("bloom", "held notes", "letters", "swell"), section = "Look",
    )
    val LyricsGlow = add(
        "lyrics_fx_glow", SettingsPage.Lyrics, "Glow", "How strongly long notes glow",
        listOf("shine", "bloom", "light"), section = "Look",
    )
    val LyricsLift = add(
        "lyrics_fx_lift", SettingsPage.Lyrics, "Lift", "How far sung words rise and bob",
        listOf("rise", "bob", "bounce"), section = "Look",
    )
    val LyricsMotionSpeed = add(
        "lyrics_fx_speed", SettingsPage.Lyrics, "Motion speed", "How quickly lines move into place",
        listOf("springs", "faster", "slower", "animation"), section = "Look",
    )
    val LyricsInactiveScale = add(
        "lyrics_fx_inactive_scale", SettingsPage.Lyrics, "Inactive line size", "How big the lines not being sung are",
        listOf("scale", "size", "smaller", "other lines"), section = "Look",
    )
    val LyricsFade = add(
        "lyrics_fx_fade", SettingsPage.Lyrics, "Fill softness", "How soft the edge of the word fill is",
        listOf("wipe", "gradient", "edge", "soft", "sweep"), section = "Look",
    )
    val LyricsCascade = add(
        "lyrics_fx_cascade", SettingsPage.Lyrics, "Ripple", "How far apart lines start moving",
        listOf("cascade", "stagger", "wave"), section = "Look",
    )
    val LyricsKeepCompleted = add(
        "lyrics_keep_completed", SettingsPage.Lyrics, "Keep sung lines visible", "Lines already sung stay faintly on screen",
        listOf("history", "past", "completed", "previous"), section = "Look",
    )
    val LyricsBloomFast = add(
        "lyrics_bloom_fast", SettingsPage.Lyrics, "Bloom fast singing", "A word held long for its line swells and glows too",
        listOf("glow", "bloom", "rap", "fast", "swell", "emphasis"), section = "Look",
    )
    val LyricsArc = add(
        "lyrics_arc", SettingsPage.Lyrics, "Curved lyrics", "The lines bend around a drum",
        listOf("arc", "curve", "3d", "perspective", "wheel"), section = "Look",
    )
    val LyricsOutputTiming = add(
        "lyrics_output_timing", SettingsPage.Lyrics, "Lyrics timing on this output", "Words earlier or later on this speaker or headphones",
        listOf("sync", "delay", "latency", "bluetooth", "earbuds", "offset", "late", "early", "behind"), section = "Timing",
    )

    // Scrobbling
    val ListenBrainz = add(
        "listenbrainz", SettingsPage.Scrobbling, "ListenBrainz", "Add the songs you play to your profile",
        listOf("scrobble", "history", "stats", "profile", "token"),
    )
    val SendPlays = add(
        "send_plays", SettingsPage.Scrobbling, "Send plays of", "All songs, or only songs on this phone",
        listOf("phone only", "all songs", "counted twice"),
    )
    val NowPlaying = add(
        "now_playing", SettingsPage.Scrobbling, "Show what I'm playing now", "Your profile shows the song while it plays",
        listOf("now playing", "profile", "status"),
    )
    val ScrobblingDisconnect = add(
        "scrobbling_disconnect", SettingsPage.Scrobbling, "Disconnect", "Stop sending plays and forget the token",
        listOf("sign out", "remove", "listenbrainz"),
    )

    // Backup and restore
    val SaveBackup = add(
        "save_backup", SettingsPage.Backup, "Save a backup", "Your settings, playlists, likes and favorites in a file",
        listOf("export", "file", "save settings"),
    )
    val RestoreBackup = add(
        "restore_backup", SettingsPage.Backup, "Restore from a backup", "Put them back from a file",
        listOf("import", "file", "new phone"),
    )

    // About
    val Version = add(
        "version", SettingsPage.About, "Version", "Which Octo this is",
        listOf("about", "build", "update"),
    )
    val WhatsNew = add(
        "whats_new", SettingsPage.About, "What's new", "The latest additions, in plain words",
        listOf("changes", "changelog", "release notes", "updates"),
    )
    val CheckUpdates = add(
        "check_updates", SettingsPage.About, "Check for updates automatically", "Looks for a new version of Octo every few hours",
        listOf("update", "new version", "upgrade", "auto update"), section = "Updates",
    )
    val InstallUpdates = add(
        "install_updates", SettingsPage.About, "Install updates", "Ask me, or when I leave Octo",
        listOf("update", "install", "automatic", "upgrade"), section = "Updates",
    )
    val EarlyVersions = add(
        "early_versions", SettingsPage.About, "Try early versions", "New versions before they're finished",
        listOf("beta", "pre-release", "prerelease", "preview", "update"), section = "Updates",
    )
    val CheckNow = add(
        "check_now", SettingsPage.About, "Check now", "Look for a new version of Octo",
        listOf("update", "new version", "upgrade"), section = "Updates",
    )

    val all: List<SettingEntry> get() = registered

    fun byId(id: String): SettingEntry? = registered.firstOrNull { it.id == id }
}

// How well a setting matches, best first: the title begins with what was
// typed, every word is in the title, the title and other words together
// cover it, or only the line about it does.
private enum class Match { TitleStart, Title, Keywords, Summary }

// Lowercase, accents and punctuation gone, so "wifi" finds "Wi-Fi".
internal fun normalized(text: String): String =
    searchKey(text).filter { it.isLetterOrDigit() || it.isWhitespace() }.replace(Regex("\\s+"), " ").trim()

// A typed word is found in some text when a word there starts with it, or
// anywhere inside it once it is three letters or more.
private fun found(word: String, text: String): Boolean {
    if (text.isEmpty()) return false
    if (text.startsWith(word) || text.contains(" $word")) return true
    return word.length >= 3 && text.contains(word)
}

// The settings that match what was typed, best first. Every typed word must
// be found somewhere. Ties keep the order the settings are written in.
fun searchSettings(query: String, entries: List<SettingEntry> = SettingsIndex.all): List<SettingEntry> {
    val typed = normalized(query)
    if (typed.isEmpty()) return emptyList()
    val words = typed.split(' ')
    return entries.mapNotNull { entry ->
        val title = normalized(entry.title)
        val other = normalized((entry.keywords + entry.page.title + listOfNotNull(entry.section)).joinToString(" "))
        val summary = normalized(entry.summary)
        val match = when {
            title.startsWith(typed) -> Match.TitleStart
            words.all { found(it, title) } -> Match.Title
            words.all { found(it, title) || found(it, other) } -> Match.Keywords
            words.all { found(it, title) || found(it, other) || found(it, summary) } -> Match.Summary
            else -> return@mapNotNull null
        }
        entry to match
    }.sortedBy { it.second }.map { it.first }
}
