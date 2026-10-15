import Foundation

/// The pages Settings opens, in the order the front page lists them.
public enum SettingsPage: String, CaseIterable, Sendable, Hashable, Codable {
    case playback = "Playback"
    case sound = "Sound"
    case radio = "Radio"
    case appearance = "Appearance"
    case library = "Library"
    case server = "Server"
    case streaming = "Streaming"
    case audioQuality = "AudioQuality"
    case lyrics = "Lyrics"
    case scrobbling = "Scrobbling"
    case backup = "Backup"
    case about = "About"

    public var title: String {
        switch self {
        case .playback: "Playback"
        case .sound: "Sound"
        case .radio: "Radio"
        case .appearance: "Appearance"
        case .library: "Library"
        case .server: "Server and sync"
        case .streaming: "Streaming and downloads"
        case .audioQuality: "Audio quality"
        case .lyrics: "Lyrics"
        case .scrobbling: "Scrobbling"
        case .backup: "Backup and restore"
        case .about: "About"
        }
    }
}

/// One setting as search finds it: the page it is on, the part of the page when there is one,
/// its title, a line about it, and other words people might look for it by. The id marks its
/// row, so search can point at it.
public struct SettingEntry: Sendable, Hashable, Identifiable {
    public let id: String
    public let page: SettingsPage
    public let title: String
    public let summary: String
    public let keywords: [String]
    public let section: String?

    public init(_ id: String, _ page: SettingsPage, _ title: String, _ summary: String = "", _ keywords: [String] = [],
                section: String? = nil) {
        self.id = id
        self.page = page
        self.title = title
        self.summary = summary
        self.keywords = keywords
        self.section = section
    }

    /// Where it lives, for a search result: "Appearance · Where it shows".
    public var place: String { [page.title, section].compactMap { $0 }.joined(separator: " · ") }
}

/// Every setting, written down once. The rows take their titles from here, so what search finds
/// is always what the page shows. The order breaks ties between equally good matches.
public enum SettingsIndex {
    // Playback
    public static let crossfade = SettingEntry("crossfade", .playback, "Crossfade", "Each song fades into the next",
                                               ["fade", "blend", "gapless", "transition", "mix"])
    public static let crossfadeLength = SettingEntry("crossfade_length", .playback, "Longest blend", "The most seconds two songs blend for",
                                                     ["fade", "seconds", "duration", "crossfade length"])
    public static let crossfadeCurve = SettingEntry("crossfade_curve", .playback, "Crossfade curve", "How the two volumes cross in a blend",
                                                    ["curve", "fade", "linear", "s-curve", "equal power", "logarithmic", "loudness", "dj", "overlap"])
    public static let smartTransitions = SettingEntry("smart_transitions", .playback, "Smart transitions", "Each blend starts where the songs meet best",
                                                      ["automix", "dj", "mix", "transition", "beat", "outro"])
    public static let filterSweeps = SettingEntry("filter_sweeps", .playback, "Filter sweeps", "Songs thin out as they cross",
                                                  ["filter", "sweep", "bass", "eq", "dj"])
    public static let matchTempo = SettingEntry("match_tempo", .playback, "Match tempo", "The next song nudges its speed to the beat",
                                                ["tempo", "bpm", "beat", "beatmatch", "speed"])
    public static let speed = SettingEntry("speed", .playback, "Speed", "How fast music plays, and its pitch",
                                           ["tempo", "pitch", "faster", "slower", "rate", "semitones"])
    public static let skipSilence = SettingEntry("skip_silence", .playback, "Skip silence", "Quiet stretches inside songs are skipped",
                                                 ["quiet", "gaps", "silent"])
    public static let autoplay = SettingEntry("autoplay", .playback, "Autoplay", "Similar songs keep playing when the queue ends",
                                              ["similar", "continue", "endless", "radio", "queue"])
    public static let resumeWired = SettingEntry("resume_wired", .playback, "Resume when headphones connect", "Plays again when a cable goes back in",
                                                 ["headphones", "cable", "wired", "usb", "plug"], section: "Headphones")
    public static let resumeBluetooth = SettingEntry("resume_bluetooth", .playback, "Resume when Bluetooth connects", "Plays again when Bluetooth reconnects",
                                                     ["bluetooth", "speaker", "car", "headphones"], section: "Headphones")
    public static let resumeAlways = SettingEntry("resume_always", .playback, "Always play on connect", "Plays on connect however the music stopped",
                                                  ["headphones", "bluetooth", "connect"], section: "Headphones")
    public static let castKeepPlaying = SettingEntry("cast_keep_playing", .playback, "Keep playing on the phone when casting ends", "Otherwise the music pauses",
                                                     ["cast", "casting", "airplay", "chromecast", "tv", "speaker", "disconnect", "resume", "phone"],
                                                     section: "Casting")

    // Radio: Octo's song radio, made from your music, and live radio, the stations on the air
    public static let radioDiscovery = SettingEntry("radio_discovery", .radio, "Discovery", "How much of a song radio comes from outside your library",
                                                    ["radio", "song radio", "start radio", "autoplay", "new music", "outside", "library only", "discover"],
                                                    section: RadioWords.songRadio)
    public static let radioAdventure = SettingEntry("radio_adventure", .radio, "Adventure", "How far a song radio strays from the song it started from",
                                                    ["radio", "song radio", "start radio", "autoplay", "focused", "wander", "deep cuts", "similar"],
                                                    section: RadioWords.songRadio)
    public static let radioVariety = SettingEntry("radio_variety", .radio, "Artist variety", "How soon an artist or album comes back",
                                                  ["radio", "song radio", "autoplay", "repeat", "spacing", "artist", "album"], section: RadioWords.songRadio)
    public static let radioFavorites = SettingEntry("radio_favorites", .radio, "Favorites more often", "Hearted and 4 or 5 star songs come around more",
                                                    ["radio", "song radio", "autoplay", "favorite", "hearted", "rating", "stars"], section: RadioWords.songRadio)
    public static let liveRadioNear = SettingEntry("live_radio_near", .radio, "Find stations near you",
                                                   "Live stations on the air around a place, to play or keep",
                                                   ["live radio", "radio", "stations", "fm", "am", "local", "near me", "nearby", "internet radio",
                                                    "location", "place", "kept"],
                                                   section: RadioWords.liveRadio)
    public static let radioStations = SettingEntry("radio_stations", .radio, "Stations on your server",
                                                   "The live stations your server keeps, for everyone on it",
                                                   ["live radio", "radio", "radio stations", "internet radio", "streams", "add a station", "server"],
                                                   section: RadioWords.liveRadio)

    // Sound, which has a page of its own
    public static let sound: [SettingEntry] = SoundSearchEntry.all.map { SettingEntry($0.id, .sound, $0.title, $0.summary, $0.keywords) }

    // Appearance
    public static let ambient = SettingEntry("ambient", .appearance, "Ambient color from the artwork", "The artwork's colors glowing behind the pages",
                                             ["glow", "background", "colours", "colors", "theme", "strength"])
    public static let ambientHome = SettingEntry("ambient_home", .appearance, "Home", "The glow on the home page", ["glow"], section: "Where it shows")
    public static let ambientLibrary = SettingEntry("ambient_library", .appearance, "Library", "The glow on library lists and pages", ["glow"],
                                                    section: "Where it shows")
    public static let ambientSearch = SettingEntry("ambient_search", .appearance, "Search", "The glow on the search page", ["glow"], section: "Where it shows")
    public static let ambientSettings = SettingEntry("ambient_settings", .appearance, "Settings", "The glow on these pages", ["glow"], section: "Where it shows")
    public static let ambientBar = SettingEntry("ambient_bar", .appearance, "Mini player and bar", "A trace of the song's color in the bar",
                                                ["glow", "bar", "tint"], section: "Where it shows")
    public static let ambientPageArtwork = SettingEntry("ambient_page_artwork", .appearance, "Album and artist pages use their own artwork",
                                                        "The glow follows the album or artist on the page", ["glow", "album", "artist", "cover"],
                                                        section: "Where it shows")
    public static let homeSections = SettingEntry("home_sections", .appearance, "Home sections", "The order of Home's shelves, and which ones show",
                                                  ["home", "shelves", "sections", "order", "rearrange", "reorder", "move", "hide", "show", "layout",
                                                   "customize", "edit home"],
                                                  section: "Home")
    public static let playerBackground = SettingEntry("immersive_background", .appearance, "Player background", "What fills the player behind the lyrics",
                                                      ["immersive", "wash", "artwork", "cover", "colour", "color", "blur", "classic", "mesh"], section: "Player")
    public static let animatedArt = SettingEntry(AnimatedArtSetting.prefKey, .appearance, AnimatedArtSetting.title,
                                                 "Apple Music's animated album covers, on the player and album pages",
                                                 ["animated", "album art", "cover", "video", "loop", "apple music", "full screen", "canvas"],
                                                 section: "Player")
    public static let liveBackground = SettingEntry("live_background", .appearance, "Live background", "The player's background drifting slowly",
                                                    ["player", "animated", "moving", "motion", "colours", "blur"], section: "Player")
    public static let backgroundBrightnessCap = SettingEntry("immersive_bg_brightness_cap", .appearance, "Brightness cap",
                                                             "How bright the background may get, so words stay readable",
                                                             ["background", "dim", "white", "readable"], section: "Player")
    public static let backgroundSaturation = SettingEntry("immersive_bg_saturation", .appearance, "Saturation", "How vivid the background's colors are",
                                                          ["background", "vivid", "colours", "color"], section: "Player")
    public static let backgroundContrast = SettingEntry("immersive_bg_contrast", .appearance, "Contrast",
                                                        "How far the background's light and dark parts are pushed apart", ["background"], section: "Player")
    public static let backgroundUseBpm = SettingEntry("immersive_bg_use_bpm", .appearance, "Move with the beat", "The background drifts at the song's pace",
                                                      ["bpm", "beats", "background", "motion"], section: "Player")
    public static let backgroundSpeed = SettingEntry("immersive_bg_speed", .appearance, "Drift speed", "How fast the background moves",
                                                     ["background", "slow", "fast", "motion", "speed", "ambience"], section: "Player")
    public static let backgroundFps = SettingEntry("immersive_bg_fps", .appearance, "Frame rate", "How smoothly the background moves",
                                                   ["fps", "battery", "smooth", "background"], section: "Player")
    public static let playlistCovers = SettingEntry("playlist_covers", .appearance, PlaylistCoverStyle.settingName,
                                                    "Designed covers, or the covers of their albums",
                                                    ["playlist", "cover", "artwork", "mosaic", "picture", "designed"], section: "Playlists")
    public static let accentColor = SettingEntry("accent_color", .appearance, "Accent color", "The color of selections, sliders, switches and buttons",
                                                 ["accent", "color", "colour", "theme", "tint", "highlight", "palette", "album art", "cover",
                                                  "personalize"],
                                                 section: "Accent color")
    public static let glassTint = SettingEntry("accent_glass", .appearance, "Color the glass", "The bar, glass buttons and toasts take the accent too",
                                               ["glass", "glaze", "frosted", "bar", "tint", "accent", "color", "colour", "theme"], section: "Accent color")
    public static let reduceMotion = SettingEntry("reduce_motion", .appearance, "Reduce motion", "What moves only for show holds still",
                                                  ["animation", "animations", "accessibility", "still", "calm", "motion sickness"], section: "Motion")

    // Library
    public static let phoneAccess = SettingEntry("phone_access", .library, "Music access", "Whether Octo may read the music on this phone",
                                                 ["permission", "allow", "storage", "files"], section: "Music on this phone")
    public static let phoneSongs = SettingEntry("phone_songs", .library, "Songs", "How many songs are on this phone", ["count", "library"],
                                                section: "Music on this phone")
    public static let rescan = SettingEntry("rescan", .library, "Rescan", "Look for new music on this phone",
                                            ["scan", "refresh", "find", "update", "new music"], section: "Music on this phone")
    public static let libraryOnly = SettingEntry("library_only", .library, LibraryOnlyWords.setting,
                                                 "Leave songs found online out of albums, search, artists and radio",
                                                 ["outside", "online", "found", "hide", "only", "my songs", "not in library", "discover"],
                                                 section: "Songs found online")
    public static let musicFolders = SettingEntry("music_folders", .library, "Music folders", "Leave a folder's music out of your library",
                                                  ["folders", "exclude", "hide", "include", "podcasts", "recordings"])

    // Server and sync
    public static let connectServer = SettingEntry("connect_server", .server, "Connect a server", "Add the music on your own server",
                                                   ["sign in", "login", "add server", "account"])
    public static let yourServers = SettingEntry("your_servers", .server, "Your servers", "The servers kept on this phone, and the one in use",
                                                 ["servers", "switch server", "several servers", "accounts", "sign out", "remove server", "in use"],
                                                 section: "Your servers")
    public static let addServer = SettingEntry("add_server", .server, "Add a server", "Keep another server here and switch to it in one tap",
                                               ["add server", "another server", "second server", "new server", "account"], section: "Your servers")
    public static let serverAddress = SettingEntry("server_address", .server, "Address", "Where the server is", ["server", "url", "host"],
                                                   section: "Connection")
    public static let serverConnection = SettingEntry("server_connection", .server, "Connection", "Whether you are connected at home or away",
                                                      ["home", "away", "network", "local"], section: "Connection")
    public static let serverUser = SettingEntry("server_user", .server, "User", "Who is signed in", ["account", "username", "login"], section: "Connection")
    public static let serverMusicFolder = SettingEntry("server_music_folder", .server, "Music folder", "Limit the library to one of the server's folders",
                                                       ["server folder", "library folder", "limit"], section: "Connection")
    public static let editConnection = SettingEntry("edit_connection", .server, "Edit connection", "Change the address or sign-in",
                                                    ["change server", "password", "address", "sign in"], section: "Connection")
    public static let changePassword = SettingEntry("change_password", .server, "Change password", "Set a new password for your account on the server",
                                                    ["password", "account", "security", "sign in"], section: "Connection")
    public static let serverKind = SettingEntry("server_kind", .server, "Server", "What the server is, and what it offers",
                                                ["version", "navidrome", "octo", "subsonic", "about"], section: "Server")
    public static let serverAnswer = SettingEntry("server_answer", .server, "Response time", "How quickly the server answers",
                                                  ["speed", "ping", "latency", "slow"], section: "Server")
    public static let serverScan = SettingEntry("server_scan", .server, "Its folders", "When the server last looked for new music",
                                                ["scan", "last scan", "new music"], section: "Server")
    public static let octoAdmin = SettingEntry("octo_admin", .server, "Octo admin", "What Octo is doing: services, stations and downloads",
                                               ["admin", "health", "services", "stations"], section: "Connection")
    public static let importMusic = SettingEntry("import", .server, "Import",
                                                 "Your music from another service, a file or a list, and fetching what is missing",
                                                 ["import", "get my music", "move", "transfer", "spotify", "apple music", "youtube music", "amazon music",
                                                  "tidal", "deezer", "qobuz", "soundcloud", "pandora", "youtube", "tunemymusic", "playlists", "liked", "file",
                                                  "csv", "paste", "missing", "download"],
                                                 section: "Connection")
    public static let family = SettingEntry("family", .server, "Family", "Your plan, requests and devices, and the family's",
                                            ["family", "members", "requests", "devices", "approve", "plan", "storage"], section: "Connection")
    public static let signInElsewhere = SettingEntry("sign_in_elsewhere", .server, "Sign in on another device",
                                                     "A QR code your phone or computer scans to sign in with your login",
                                                     ["qr", "scan", "another device", "phone", "computer", "sign in", "login"], section: "Connection")
    public static let lastSynced = SettingEntry("last_synced", .server, "Last synced", "When the server's library was last copied", ["sync", "updated"],
                                                section: "Sync")
    public static let syncNow = SettingEntry("sync_now", .server, "Sync now", "Copy the server's library again", ["sync", "refresh", "update"],
                                             section: "Sync")
    public static let queueSync = SettingEntry("queue_sync", .server, "Sync play queue with the server", "Pick up where another device left off",
                                               ["queue", "resume", "other device", "continue"], section: "Sync")
    public static let playlistsToServer = SettingEntry("playlists_to_server", .server, "Save new playlists to the server",
                                                       "Playlists you make here are made there too", ["playlists", "upload", "sync"], section: "Sync")
    public static let shares = SettingEntry("shares", .server, "Shared links", "Links to songs and albums you shared", ["share", "links"],
                                            section: "On the server")
    public static let scanServer = SettingEntry("scan_server", .server, "Scan library now", "Ask the server to look for new music",
                                                ["scan", "refresh", "new music"], section: "On the server")
    public static let listeningNow = SettingEntry("listening_now", .server, "Listening now", "Who else is playing music from the server",
                                                  ["others", "users", "now playing"])
    public static let disconnect = SettingEntry("disconnect", .server, "Sign out", "Sign out of the server in use, which stays in your list",
                                                ["sign out", "log out", "disconnect"])

    // Streaming and downloads, with Audio quality written among them as it always was
    public static let copies = SettingEntry("copies", .streaming, "When a song is on the phone and the server", "Which copy plays",
                                            ["phone copy", "best quality", "duplicate", "prefer"], section: "Streaming")
    public static let accountHome = SettingEntry("account_home", .audioQuality, "At home", "Your account's quality on your home network, for every app",
                                                 ["quality", "bitrate", "family", "home", "account"], section: "Your account")
    public static let accountAway = SettingEntry("account_away", .audioQuality, "Away from home", "Your account's quality anywhere else, for every app",
                                                 ["quality", "bitrate", "family", "away", "data saver", "account"], section: "Your account")
    public static let deviceQuality = SettingEntry("device_quality", .audioQuality, "This phone follows", "Your account's choice, or this app's",
                                                   ["quality", "device", "family", "app"], section: "Quality on this device")
    public static let streamWifi = SettingEntry("stream_wifi", .audioQuality, "Streaming on Wi-Fi", "This app's quality over Wi-Fi",
                                                ["quality", "bitrate", "kbps", "streaming", "wifi"], section: "This app")
    public static let startAfter = SettingEntry("start_after", .streaming, StartAfter.settingName, "How much of a song is ready before it starts",
                                                ["buffer", "preload", "start", "slow", "wait", "stutter"], section: "Streaming")
    public static let streamMobile = SettingEntry("stream_mobile", .audioQuality, "Streaming on mobile data", "This app's quality over mobile data",
                                                  ["quality", "bitrate", "kbps", "cellular", "data saver", "streaming", "mobile"], section: "This app")
    public static let cacheSize = SettingEntry("cache_size", .streaming, "Cache size", "Room for songs played lately, to play without a connection",
                                               ["storage", "offline", "space"], section: "Cache")
    public static let fetchWifi = SettingEntry("fetch_wifi", .streaming, "Fetch ahead on Wi-Fi", "Songs ahead in the queue saved while one plays",
                                               ["prefetch", "preload", "next songs", "offline"], section: "Cache")
    public static let fetchMobile = SettingEntry("fetch_mobile", .streaming, "Fetch ahead on mobile data", "Songs ahead saved on mobile data",
                                                 ["prefetch", "preload", "cellular"], section: "Cache")
    public static let clearCache = SettingEntry("clear_cache", .streaming, "Clear cache", "Free the room the cache takes",
                                                ["free space", "storage", "delete"], section: "Cache")
    public static let downloadQuality = SettingEntry("download_quality", .streaming, "Download quality", "The file downloads come as",
                                                     ["bitrate", "kbps", "offline"], section: "Downloads")
    public static let wifiOnly = SettingEntry("wifi_only", .streaming, "Download on Wi-Fi only", "Downloads wait for Wi-Fi", ["mobile data", "cellular"],
                                              section: "Downloads")
    public static let keepLiked = SettingEntry("keep_liked", .streaming, "Keep Liked songs downloaded", "Liked songs follow your likes offline",
                                               ["offline", "likes", "auto download"], section: "Downloads")
    public static let streamOnWifi = SettingEntry("stream_on_wifi", .streaming, "Prefer streaming on Wi-Fi", "Stream even when a song is downloaded",
                                                  ["downloaded", "stream"], section: "Downloads")
    public static let downloadedMusic = SettingEntry("downloaded_music", .streaming, "Downloaded music", "What is downloaded, and how much room it takes",
                                                     ["downloads", "offline", "manage"], section: "Downloads")

    // Lyrics
    public static let lyricsOnline = SettingEntry("lyrics_online", .lyrics, "Find lyrics online", "Look lyrics up when your music has none",
                                                  ["internet", "lookup", "synced", "words"])
    public static let lyricsScreenOn = SettingEntry("lyrics_screen_on", .lyrics, "Keep the screen on", "While lyrics show in the player",
                                                    ["screen", "timeout", "awake", "display"])
    public static let lyricsStyle = SettingEntry("lyrics_style", .lyrics, "Lyrics style", "Flowing, or the classic view",
                                                 ["look", "flowing", "classic", "animation", "synced", "karaoke"], section: "Synced lyrics")
    public static let lyricsEmphasis = SettingEntry("lyrics_fx_emphasis", .lyrics, "Emphasis", "How much long notes swell letter by letter",
                                                    ["bloom", "held notes", "letters", "swell"], section: "Look")
    public static let lyricsGlow = SettingEntry("lyrics_fx_glow", .lyrics, "Glow", "How strongly long notes glow", ["shine", "bloom", "light"], section: "Look")
    public static let lyricsLift = SettingEntry("lyrics_fx_lift", .lyrics, "Lift", "How far sung words rise and bob", ["rise", "bob", "bounce"], section: "Look")
    public static let lyricsMotionSpeed = SettingEntry("lyrics_fx_speed", .lyrics, "Motion speed", "How quickly lines move into place",
                                                       ["springs", "faster", "slower", "animation"], section: "Look")
    public static let lyricsInactiveScale = SettingEntry("lyrics_fx_inactive_scale", .lyrics, "Inactive line size", "How big the lines not being sung are",
                                                         ["scale", "size", "smaller", "other lines"], section: "Look")
    public static let lyricsFade = SettingEntry("lyrics_fx_fade", .lyrics, "Fill softness", "How soft the edge of the word fill is",
                                                ["wipe", "gradient", "edge", "soft", "sweep"], section: "Look")
    public static let lyricsCascade = SettingEntry("lyrics_fx_cascade", .lyrics, "Ripple", "How far apart lines start moving",
                                                   ["cascade", "stagger", "wave"], section: "Look")
    public static let lyricsKeepCompleted = SettingEntry("lyrics_keep_completed", .lyrics, "Keep sung lines visible", "Lines already sung stay faintly on screen",
                                                         ["history", "past", "completed", "previous"], section: "Look")
    public static let lyricsArc = SettingEntry("lyrics_arc", .lyrics, "Curved lyrics", "The lines bend around a drum",
                                               ["arc", "curve", "3d", "perspective", "wheel"], section: "Look")
    public static let lyricsBloomFast = SettingEntry("lyrics_bloom_fast", .lyrics, "Bloom fast singing",
                                                     "Notes held out among quick singing bloom too",
                                                     ["bloom", "rap", "fast", "held", "notes", "emphasis"], section: "Look")
    public static let lyricsOutputTiming = SettingEntry("lyrics_output_timing", .lyrics, "Lyrics timing on this output",
                                                        "Words earlier or later on this speaker or headphones",
                                                        ["sync", "delay", "latency", "bluetooth", "earbuds", "offset", "late", "early", "behind"],
                                                        section: "Timing")

    // Scrobbling
    public static let listenBrainz = SettingEntry("listenbrainz", .scrobbling, "ListenBrainz", "Add the songs you play to your profile",
                                                  ["scrobble", "history", "stats", "profile", "token"])
    public static let sendPlays = SettingEntry("send_plays", .scrobbling, "Send plays of", "All songs, or only songs on this phone",
                                               ["phone only", "all songs", "counted twice"])
    public static let nowPlaying = SettingEntry("now_playing", .scrobbling, "Show what I'm playing now", "Your profile shows the song while it plays",
                                                ["now playing", "profile", "status"])
    public static let scrobblingDisconnect = SettingEntry("scrobbling_disconnect", .scrobbling, "Disconnect", "Stop sending plays and forget the token",
                                                          ["sign out", "remove", "listenbrainz"])

    // Backup and restore
    public static let saveBackup = SettingEntry("save_backup", .backup, "Save a backup", "Your settings, playlists, likes and favorites in a file",
                                                ["export", "file", "save settings"])
    public static let restoreBackup = SettingEntry("restore_backup", .backup, "Restore from a backup", "Put them back from a file",
                                                   ["import", "file", "new phone"])

    // About
    public static let version = SettingEntry("version", .about, "Version", "Which Octo this is", ["about", "build", "update"])
    public static let whatsNew = SettingEntry("whats_new", .about, "What's new", "The latest additions, in plain words",
                                              ["changes", "changelog", "release notes", "updates"])
    public static let checkUpdates = SettingEntry("check_updates", .about, "Check for updates automatically", "Looks for a new version of Octo every few hours",
                                                  ["update", "new version", "upgrade", "auto update"], section: "Updates")
    public static let earlyVersions = SettingEntry("early_versions", .about, "Try early versions", "New versions before they're finished",
                                                   ["beta", "pre-release", "prerelease", "preview", "update"], section: "Updates")
    public static let checkNow = SettingEntry("check_now", .about, "Check now", "Look for a new version of Octo", ["update", "new version", "upgrade"],
                                              section: "Updates")

    /// Every setting, in the order written.
    public static let all: [SettingEntry] = [
        crossfade, crossfadeLength, crossfadeCurve, smartTransitions, filterSweeps, matchTempo, speed, skipSilence, autoplay,
        resumeWired, resumeBluetooth, resumeAlways, castKeepPlaying,
        radioDiscovery, radioAdventure, radioVariety, radioFavorites, liveRadioNear, radioStations,
    ] + sound + [
        ambient, ambientHome, ambientLibrary, ambientSearch, ambientSettings, ambientBar, ambientPageArtwork, homeSections,
        playerBackground, animatedArt, liveBackground, backgroundBrightnessCap, backgroundSaturation, backgroundContrast, backgroundUseBpm,
        backgroundSpeed, backgroundFps, playlistCovers, accentColor, glassTint, reduceMotion,
        phoneAccess, phoneSongs, rescan, libraryOnly, musicFolders,
        connectServer, yourServers, addServer, serverAddress, serverConnection, serverUser, serverMusicFolder, editConnection,
        changePassword, serverKind, serverAnswer, serverScan, octoAdmin, importMusic, family, signInElsewhere, lastSynced, syncNow,
        queueSync, playlistsToServer, shares, scanServer, listeningNow, disconnect,
        copies, accountHome, accountAway, deviceQuality, streamWifi, startAfter, streamMobile, cacheSize, fetchWifi, fetchMobile,
        clearCache, downloadQuality, wifiOnly, keepLiked, streamOnWifi, downloadedMusic,
        lyricsOnline, lyricsScreenOn, lyricsStyle, lyricsEmphasis, lyricsGlow, lyricsLift, lyricsMotionSpeed, lyricsInactiveScale,
        lyricsFade, lyricsCascade, lyricsKeepCompleted, lyricsArc, lyricsBloomFast, lyricsOutputTiming,
        listenBrainz, sendPlays, nowPlaying, scrobblingDisconnect,
        saveBackup, restoreBackup,
        version, whatsNew, checkUpdates, earlyVersions, checkNow,
    ]

    public static func byId(_ id: String) -> SettingEntry? { all.first { $0.id == id } }
}

/// How well a setting matches, best first: the title begins with what was typed, every word is
/// in the title, the title and other words together cover it, or only the line about it does.
private enum SettingMatch: Int, Comparable {
    case titleStart, title, keywords, summary

    static func < (a: SettingMatch, b: SettingMatch) -> Bool { a.rawValue < b.rawValue }
}

/// Lowercase, accents and punctuation gone, runs of spaces made one, so "wifi" finds "Wi-Fi".
public func settingsNormalized(_ text: String) -> String {
    var kept = String.UnicodeScalarView()
    for scalar in searchKey(text).unicodeScalars {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
            kept.append(scalar)
        default:
            if scalar.properties.isWhitespace { kept.append(" ") }
        }
    }
    return String(kept).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
}

/// A typed word is found in some text when a word there starts with it, or anywhere inside it
/// once it is three letters or more.
private func found(_ word: String, in text: String) -> Bool {
    if text.isEmpty { return false }
    if text.hasPrefix(word) || text.contains(" " + word) { return true }
    return word.count >= 3 && text.contains(word)
}

/// The settings that match what was typed, best first. Every typed word must be found somewhere.
/// Ties keep the order the settings are written in.
public func searchSettings(_ query: String, in entries: [SettingEntry] = SettingsIndex.all) -> [SettingEntry] {
    let typed = settingsNormalized(query)
    if typed.isEmpty { return [] }
    let words = typed.split(separator: " ").map(String.init)
    let matched: [(SettingEntry, SettingMatch)] = entries.compactMap { entry in
        let title = settingsNormalized(entry.title)
        let other = settingsNormalized((entry.keywords + [entry.page.title] + [entry.section].compactMap { $0 }).joined(separator: " "))
        let summary = settingsNormalized(entry.summary)
        let match: SettingMatch
        if title.hasPrefix(typed) {
            match = .titleStart
        } else if words.allSatisfy({ found($0, in: title) }) {
            match = .title
        } else if words.allSatisfy({ found($0, in: title) || found($0, in: other) }) {
            match = .keywords
        } else if words.allSatisfy({ found($0, in: title) || found($0, in: other) || found($0, in: summary) }) {
            match = .summary
        } else {
            return nil
        }
        return (entry, match)
    }
    // A stable sort: equal matches keep the written order.
    return matched.enumerated()
        .sorted { a, b in a.element.1 != b.element.1 ? a.element.1 < b.element.1 : a.offset < b.offset }
        .map(\.element.0)
}
