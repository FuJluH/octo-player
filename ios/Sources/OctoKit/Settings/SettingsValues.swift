import Foundation

/// A choice kept by its name. Reading a name nothing answers to gives the choice's default.
public protocol StoredChoice: CaseIterable, Sendable, Equatable {
    var storedName: String { get }
}

extension StoredChoice {
    /// The choice saved under `name`, or `fallback` when nothing (or something unknown) is saved.
    public static func stored(_ name: String?, or fallback: Self) -> Self {
        allCases.first { $0.storedName == name } ?? fallback
    }
}

extension StoredChoice where Self: RawRepresentable, RawValue == String {
    public var storedName: String { rawValue }
}

extension KeyedDecodingContainer {
    /// A choice in a saved file, its default when the field is missing or names nothing known.
    func choice<T: StoredChoice>(_ key: Key, or fallback: T) -> T {
        T.stored((try? decodeIfPresent(String.self, forKey: key)) ?? nil, or: fallback)
    }

    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: Radio

/// The share of a radio kept for songs the library does not have, from the server's suggestions.
/// Balanced is the share Octo's Your Mix keeps.
public enum RadioDiscovery: String, StoredChoice, Codable {
    case libraryOnly = "LibraryOnly"
    case aLittle = "ALittle"
    case balanced = "Balanced"
    case lots = "Lots"
    case mostlyNew = "MostlyNew"

    public var share: Double {
        switch self {
        case .libraryOnly: 0
        case .aLittle: 0.15
        case .balanced: 0.35
        case .lots: 0.6
        case .mostlyNew: 0.85
        }
    }

    public var label: String {
        switch self {
        case .libraryOnly: "Only my library"
        case .aLittle: "A little"
        case .balanced: "Balanced"
        case .lots: "Lots"
        case .mostlyNew: "Mostly new"
        }
    }

    public var detail: String {
        switch self {
        case .libraryOnly: "Never a song from outside your library"
        case .aLittle: "About 1 song in 7 from outside your library"
        case .balanced: "About 1 song in 3 from outside your library"
        case .lots: "About 3 songs in 5 from outside your library"
        case .mostlyNew: "About 5 songs in 6 from outside your library"
        }
    }
}

/// How far down the best matches a pick may land, as a share of their total weight, and how many
/// of the library's matches stay in the running.
public enum RadioAdventure: String, StoredChoice, Codable {
    case focused = "Focused"
    case balanced = "Balanced"
    case wander = "Wander"

    public var reach: Double {
        switch self {
        case .focused: 0.2
        case .balanced: 0.5
        case .wander: 1.0
        }
    }

    public var keep: Double {
        switch self {
        case .focused: 0.5
        case .balanced: 1.0
        case .wander: 2.0
        }
    }

    public var label: String {
        switch self {
        case .focused: "Focused"
        case .balanced: "Balanced"
        case .wander: "Wander"
        }
    }

    public var detail: String {
        switch self {
        case .focused: "Only the closest matches"
        case .balanced: "Close matches, with some surprises"
        case .wander: "Deep cuts and further afield"
        }
    }
}

/// How far apart an album and an artist play, against the usual spacing, which grows with the
/// library. Another version of the same song always waits the usual spacing.
public enum RadioVariety: String, StoredChoice, Codable {
    case tight = "Tight"
    case normal = "Normal"
    case wide = "Wide"

    public var scale: Double {
        switch self {
        case .tight: 0.5
        case .normal: 1.0
        case .wide: 1.6
        }
    }

    public var label: String {
        switch self {
        case .tight: "Tight"
        case .normal: "Normal"
        case .wide: "Wide"
        }
    }

    public var detail: String {
        switch self {
        case .tight: "Artists and albums come back sooner"
        case .normal: "Spaced to suit your library's size"
        case .wide: "Artists and albums come back much later"
        }
    }
}

/// How a listener tunes Octo's radio.
public struct RadioTuning: Sendable, Equatable {
    public var discovery: RadioDiscovery
    public var adventure: RadioAdventure
    public var variety: RadioVariety
    public var favorites: Bool

    public init(discovery: RadioDiscovery = .balanced, adventure: RadioAdventure = .balanced, variety: RadioVariety = .normal,
                favorites: Bool = false) {
        self.discovery = discovery
        self.adventure = adventure
        self.variety = variety
        self.favorites = favorites
    }

    /// How many songs to ask the server for: more when most of the radio is to come from outside
    /// the library, so the share can be reached.
    public var suggestions: Int { discovery.share > 0.5 ? 100 : 50 }
}

// MARK: Ambient glow

/// How strongly the artwork's colors show behind the pages.
public enum AmbientStrength: String, StoredChoice, Codable {
    case off = "Off"
    case subtle = "Subtle"
    case rich = "Rich"

    public var label: String { rawValue }

    public var detail: String {
        switch self {
        case .off: "The plain dark background everywhere."
        case .subtle: "A faint glow of the artwork's colors behind the pages."
        case .rich: "A fuller glow, still kept dark enough for text."
        }
    }

    /// How much of the color shows over the app's near-black background.
    public var glowAlpha: Double {
        switch self {
        case .off: 0
        case .subtle: 0.14
        case .rich: 0.24
        }
    }

    /// How much of the color tints the bar's glass: about half the page's.
    public var barTintAlpha: Double {
        switch self {
        case .off: 0
        case .subtle: 0.06
        case .rich: 0.10
        }
    }
}

/// The parts of the app that can wear the artwork's colors.
public enum AmbientArea: String, Sendable, CaseIterable {
    case home, library, search, settings
}

/// Where the ambient color shows, and how strongly.
public struct AmbientPrefs: Sendable, Equatable, Codable {
    public var strength: AmbientStrength = .subtle
    public var home = true
    public var library = true
    public var search = true
    public var settings = true
    /// A faint tint in the floating bar's glass.
    public var bar = true
    /// Album and artist pages glow with their own artwork, not the song on now.
    public var pageArtwork = true

    public init() {}

    public func shows(_ area: AmbientArea) -> Bool {
        guard strength != .off else { return false }
        switch area {
        case .home: return home
        case .library: return library
        case .search: return search
        case .settings: return settings
        }
    }

    public var tintsBar: Bool { strength != .off && bar }

    enum CodingKeys: String, CodingKey { case strength, home, library, search, settings, bar, pageArtwork }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strength = c.choice(.strength, or: .subtle)
        home = c.value(.home, or: true)
        library = c.value(.library, or: true)
        search = c.value(.search, or: true)
        settings = c.value(.settings, or: true)
        bar = c.value(.bar, or: true)
        pageArtwork = c.value(.pageArtwork, or: true)
    }
}

// MARK: Player background

/// What fills the full player behind the lyrics and controls.
public enum BackgroundMode: String, StoredChoice, Codable {
    /// The artwork torn into drifting copies, blurred into a slow wash of its colors.
    case immersive = "Default"
    /// The artwork, blurred and still.
    case artwork = "Artwork"
    /// A flat fill of the artwork's main color.
    case color = "Colour"
    /// The moving mesh of four colors.
    case classic = "Classic"

    public var label: String {
        switch self {
        case .immersive: "Immersive"
        case .artwork: "Artwork"
        case .color: "Color"
        case .classic: "Classic"
        }
    }

    public var detail: String {
        switch self {
        case .immersive: "The artwork torn into drifting layers, blurred into a slow wash of its colors."
        case .artwork: "The artwork, blurred and still."
        case .color: "A flat fill of the artwork's main color."
        case .classic: "Four of the artwork's colors, flowing into each other."
        }
    }

    /// Whether this background can drift at all.
    public var canMove: Bool { self == .immersive || self == .classic }
}

/// The player background's settings. The brightness cap, saturation and drift speed are
/// percentages, the contrast a factor, and the frame rate a limit.
public struct BackgroundPrefs: Sendable, Equatable, Codable {
    public static let brightnessCapRange = 20...100
    public static let saturationRange = 0...300
    public static let contrastRange: ClosedRange<Float> = 0.5...2
    public static let fpsChoices = [30, 60, 90, 120]
    public static let speedRange = 5...100

    public var mode: BackgroundMode = .immersive
    public var brightnessCap = 50
    public var saturation = 180
    public var contrast: Float = 1.3
    public var useBpm = true
    public var fps = 60
    /// How fast it drifts, as a share of the full pace.
    public var speed = 25

    public init() {}

    /// Held to the ranges the settings offer, for values read back.
    public func sane() -> BackgroundPrefs {
        var held = self
        held.brightnessCap = brightnessCap.clamped(to: Self.brightnessCapRange)
        held.saturation = saturation.clamped(to: Self.saturationRange)
        held.contrast = min(max(contrast, Self.contrastRange.lowerBound), Self.contrastRange.upperBound)
        held.fps = Self.fpsChoices.contains(fps) ? fps : 60
        held.speed = speed.clamped(to: Self.speedRange)
        return held
    }

    /// Whether the background is drawn from the prepared cover, so the adjustments apply.
    public var prepared: Bool { mode != .classic }

    enum CodingKeys: String, CodingKey { case mode, brightnessCap, saturation, contrast, useBpm, fps, speed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = c.choice(.mode, or: .immersive)
        brightnessCap = c.value(.brightnessCap, or: 50)
        saturation = c.value(.saturation, or: 180)
        contrast = c.value(.contrast, or: 1.3)
        useBpm = c.value(.useBpm, or: true)
        fps = c.value(.fps, or: 60)
        speed = c.value(.speed, or: 25)
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

// MARK: Streaming

/// Which copy plays when a song is on the phone and on the server.
public enum CopyPreference: String, StoredChoice, Codable {
    case phoneFirst = "PhoneFirst"
    case bestQuality = "BestQuality"

    public var label: String {
        switch self {
        case .phoneFirst: "Phone copy first"
        case .bestQuality: "Best quality"
        }
    }

    public var detail: String {
        switch self {
        case .phoneFirst: "Plays the phone's file, and streams only songs the phone lacks."
        case .bestQuality: "Plays whichever copy sounds better, even when that means streaming."
        }
    }
}

extension StreamQuality: StoredChoice {
    public static var allCases: [StreamQuality] { choices }

    /// The name a stream size is kept under.
    public var storedName: String {
        switch self {
        case .original: "Original"
        case .mp3(let kbps): "Kbps\(kbps)"
        }
    }

    public var kbps: Int? {
        switch self {
        case .original: nil
        case .mp3(let kbps): kbps
        }
    }

    /// As the settings show it: "Original" or "320 kbps".
    public var label: String { kbps.map { "\($0) kbps" } ?? "Original" }

    /// As the download quality shows it: "Original" or "320 kbps MP3".
    public var downloadLabel: String { kbps.map { "\($0) kbps MP3" } ?? "Original" }

    /// Original, as the pickers say it.
    public static let originalLabel = "Original (as the file is, FLAC stays FLAC)"
}

/// How much of a song is ready before it starts playing. A second is what players wait by default.
public enum StartAfter: String, StoredChoice, Codable {
    case instant = "Instant"
    case short = "Short"
    case steady = "Steady"
    case safe = "Safe"
    case long = "Long"

    public var ms: Int {
        switch self {
        case .instant: 250
        case .short: 1_000
        case .steady: 2_500
        case .safe: 5_000
        case .long: 10_000
        }
    }

    public var label: String {
        switch self {
        case .instant: "As soon as possible"
        case .short: "1 second"
        case .steady: "2.5 seconds"
        case .safe: "5 seconds"
        case .long: "10 seconds"
        }
    }

    public static let settingName = "Start playing after"
    public static let help = "Waits for this much audio before a song starts. Shorter starts faster on a slow connection; longer stutters less."
}

/// Where songs play from when a server is connected, and how big a stream is on Wi-Fi and on
/// mobile data.
public struct StreamPrefs: Sendable, Equatable, Codable {
    public var copies: CopyPreference = .phoneFirst
    public var wifi: StreamQuality = .original
    public var mobile: StreamQuality = .original
    public var startAfter: StartAfter = .short

    public init(copies: CopyPreference = .phoneFirst, wifi: StreamQuality = .original, mobile: StreamQuality = .original,
                startAfter: StartAfter = .short) {
        self.copies = copies
        self.wifi = wifi
        self.mobile = mobile
        self.startAfter = startAfter
    }

    enum CodingKeys: String, CodingKey { case copies, wifi, mobile, startAfter }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        copies = c.choice(.copies, or: .phoneFirst)
        wifi = c.choice(.wifi, or: .original)
        mobile = c.choice(.mobile, or: .original)
        startAfter = c.choice(.startAfter, or: .short)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(copies.storedName, forKey: .copies)
        try c.encode(wifi.storedName, forKey: .wifi)
        try c.encode(mobile.storedName, forKey: .mobile)
        try c.encode(startAfter.storedName, forKey: .startAfter)
    }
}

// MARK: Offline

/// How much room recently played server songs may take on the phone. Off keeps nothing.
public enum CacheSize: String, StoredChoice, Codable {
    case off = "Off"
    case gb1 = "Gb1"
    case gb2 = "Gb2"
    case gb5 = "Gb5"
    case gb10 = "Gb10"

    public var bytes: Int64 {
        switch self {
        case .off: 0
        case .gb1: 1 << 30
        case .gb2: 2 << 30
        case .gb5: 5 << 30
        case .gb10: 10 << 30
        }
    }

    /// As the settings show it: "Off" or "2 GB".
    public var label: String { self == .off ? "Off" : "\(bytes >> 30) GB" }
}

/// What to keep on the phone for playing without a connection.
public struct OfflinePrefs: Sendable, Equatable, Codable {
    /// The range each "songs ahead" count can be set to.
    public static let prefetchRange = 0...10

    public var cacheSize: CacheSize = .gb2
    public var prefetchWifi = 3
    public var prefetchMobile = 1
    public var downloadQuality: StreamQuality = .original
    public var wifiOnly = true
    /// Stream on Wi-Fi even when a downloaded copy is on the phone.
    public var streamOnWifi = false
    public var keepLiked = false
    /// Playlists whose songs are kept downloaded, by id (by name in a backup).
    public var keptPlaylists: [String] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case cacheSize, prefetchWifi, prefetchMobile, downloadQuality, wifiOnly, streamOnWifi, keepLiked, keptPlaylists
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cacheSize = c.choice(.cacheSize, or: .gb2)
        prefetchWifi = c.value(.prefetchWifi, or: 3)
        prefetchMobile = c.value(.prefetchMobile, or: 1)
        downloadQuality = c.choice(.downloadQuality, or: .original)
        wifiOnly = c.value(.wifiOnly, or: true)
        streamOnWifi = c.value(.streamOnWifi, or: false)
        keepLiked = c.value(.keepLiked, or: false)
        keptPlaylists = c.value(.keptPlaylists, or: [])
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cacheSize.storedName, forKey: .cacheSize)
        try c.encode(prefetchWifi, forKey: .prefetchWifi)
        try c.encode(prefetchMobile, forKey: .prefetchMobile)
        try c.encode(downloadQuality.storedName, forKey: .downloadQuality)
        try c.encode(wifiOnly, forKey: .wifiOnly)
        try c.encode(streamOnWifi, forKey: .streamOnWifi)
        try c.encode(keepLiked, forKey: .keepLiked)
        try c.encode(keptPlaylists, forKey: .keptPlaylists)
    }
}

// MARK: Player

/// How the player looks and plays. The defaults are what a new install gets.
public struct PlayerPrefs: Sendable, Equatable, Codable {
    /// The range the longest blend can be set to.
    public static let crossfadeSecondsRange = 2...16

    public var liveBackground = true
    public var background = BackgroundPrefs()
    public var crossfade = false
    public var crossfadeSeconds = 8
    /// The curve of the crossfade while smart transitions are off.
    public var crossfadeCurve: FadeCurve = .equalPower
    public var smartTransitions = true
    public var filterSweeps = true
    public var matchTempo = false
    public var lyricsOnline = true
    public var speed: Float = 1
    public var keepPitch = true
    public var pitchSemitones = 0
    public var skipSilence = false
    public var autoplay = true
    public var radioDiscovery: RadioDiscovery = .balanced
    public var radioAdventure: RadioAdventure = .balanced
    public var radioVariety: RadioVariety = .normal
    public var radioFavorites = false
    public var resumeWired = false
    public var resumeBluetooth = false
    public var resumeAlways = false
    public var ambient = AmbientPrefs()
    public var reduceMotion = false
    public var castRenderers = true
    public var castKeepPlaying = false
    public var libraryOnly = false
    /// The accent the app is drawn in, or the playing cover's.
    public var accent: AccentChoice = .octo
    /// Whether Octo's glass takes the accent too, or stays Apple's own.
    public var glassTint = false
    /// How an album's animated art shows.
    public var animatedArt: AnimatedArtSetting = .standard

    public init() {}

    /// The longest blend the player uses, or 0 for none.
    public var crossfadeMs: Int { crossfade ? crossfadeSeconds * 1_000 : 0 }

    /// The speed and pitch the player is set to.
    public var pace: Pace { Pace.of(speed: speed, keepPitch: keepPitch, semitones: pitchSemitones) }

    /// Whether speed and pitch are as they came.
    public var paceIsDefault: Bool { speed == 1 && keepPitch && pitchSemitones == 0 }

    /// How radio and Autoplay pick their songs.
    public var radioTuning: RadioTuning {
        RadioTuning(discovery: radioDiscovery, adventure: radioAdventure, variety: radioVariety, favorites: radioFavorites)
    }

    /// Held to the ranges the settings offer: the blend length, the speed's steps, the pitch and
    /// the background's values.
    public func sane() -> PlayerPrefs {
        var held = self
        held.background = background.sane()
        held.crossfadeSeconds = crossfadeSeconds.clamped(to: Self.crossfadeSecondsRange)
        held.speed = Pace.snapSpeed(speed)
        held.pitchSemitones = pitchSemitones.clamped(to: -Pace.pitchRangeSemitones...Pace.pitchRangeSemitones)
        return held
    }

    enum CodingKeys: String, CodingKey {
        case liveBackground, background, crossfade, crossfadeSeconds, crossfadeCurve, smartTransitions, filterSweeps, matchTempo, lyricsOnline,
             speed, keepPitch, pitchSemitones, skipSilence, autoplay, radioDiscovery, radioAdventure, radioVariety, radioFavorites,
             resumeWired, resumeBluetooth, resumeAlways, ambient, reduceMotion, castRenderers, castKeepPlaying, libraryOnly, accent, glassTint,
             animatedArt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlayerPrefs()
        liveBackground = c.value(.liveBackground, or: d.liveBackground)
        background = c.value(.background, or: d.background)
        crossfade = c.value(.crossfade, or: d.crossfade)
        crossfadeSeconds = c.value(.crossfadeSeconds, or: d.crossfadeSeconds)
        crossfadeCurve = c.choice(.crossfadeCurve, or: d.crossfadeCurve)
        smartTransitions = c.value(.smartTransitions, or: d.smartTransitions)
        filterSweeps = c.value(.filterSweeps, or: d.filterSweeps)
        matchTempo = c.value(.matchTempo, or: d.matchTempo)
        lyricsOnline = c.value(.lyricsOnline, or: d.lyricsOnline)
        speed = c.value(.speed, or: d.speed)
        keepPitch = c.value(.keepPitch, or: d.keepPitch)
        pitchSemitones = c.value(.pitchSemitones, or: d.pitchSemitones)
        skipSilence = c.value(.skipSilence, or: d.skipSilence)
        autoplay = c.value(.autoplay, or: d.autoplay)
        radioDiscovery = c.choice(.radioDiscovery, or: d.radioDiscovery)
        radioAdventure = c.choice(.radioAdventure, or: d.radioAdventure)
        radioVariety = c.choice(.radioVariety, or: d.radioVariety)
        radioFavorites = c.value(.radioFavorites, or: d.radioFavorites)
        resumeWired = c.value(.resumeWired, or: d.resumeWired)
        resumeBluetooth = c.value(.resumeBluetooth, or: d.resumeBluetooth)
        resumeAlways = c.value(.resumeAlways, or: d.resumeAlways)
        ambient = c.value(.ambient, or: d.ambient)
        reduceMotion = c.value(.reduceMotion, or: d.reduceMotion)
        castRenderers = c.value(.castRenderers, or: d.castRenderers)
        castKeepPlaying = c.value(.castKeepPlaying, or: d.castKeepPlaying)
        libraryOnly = c.value(.libraryOnly, or: d.libraryOnly)
        accent = c.choice(.accent, or: d.accent)
        glassTint = c.value(.glassTint, or: d.glassTint)
        animatedArt = c.choice(.animatedArt, or: d.animatedArt)
    }
}

// MARK: Library

/// Whether Octo may read the music on this phone.
public enum PhoneAccess: Sendable, Equatable {
    case granted, notAsked, denied, deniedForever

    /// The word on the access row while access is missing.
    public var buttonLabel: String { self == .deniedForever ? "Open settings" : "Allow access" }
}

/// A top-level folder of the phone's music, how many songs it holds, and whether it counts.
public struct MusicFolder: Sendable, Equatable, Hashable {
    public var name: String
    public var songs: Int
    public var included: Bool

    public init(_ name: String, songs: Int, included: Bool) {
        self.name = name
        self.songs = songs
        self.included = included
    }
}

/// The switch that keeps songs found online out of sight, its words the same on every app.
public enum LibraryOnlyWords {
    public static let setting = "Library songs only"
    public static let help = "Shows only songs in your library: albums, search, artists and radio leave out outside songs."
    public static let onlyMySongs = "Only my songs"
}

/// The songs to show: all of them, or with `hide` only those `outside` does not mark, in order.
public func librarySongsOnly<T>(_ songs: [T], hide: Bool, outside: (T) -> Bool) -> [T] {
    hide ? songs.filter { !outside($0) } : songs
}

// MARK: Playlists

/// What a playlist's picture is: artwork designed for it, or the covers of its first albums.
public enum PlaylistCoverStyle: String, StoredChoice, Codable {
    case designed = "Designed"
    case mosaic = "Mosaic"

    public static let settingName = "Playlist covers"

    public var label: String {
        switch self {
        case .designed: "Designed"
        case .mosaic: "Album mosaic"
        }
    }

    public var help: String {
        switch self {
        case .designed: "Each playlist's name on painted artwork picked by its music. Easy to tell apart at a glance, even in a long list."
        case .mosaic: "The covers of the first albums on it. Handy when you know a playlist by its music."
        }
    }
}

// MARK: Scrobbling

/// Which plays are sent: all of them, or only those the server never hears, so a server that
/// passes its own plays on does not count them twice.
public enum SendPlays: String, StoredChoice, Codable {
    case all = "All"
    case phoneOnly = "PhoneOnly"

    public var label: String {
        switch self {
        case .all: "All songs"
        case .phoneOnly: "Only songs on this phone"
        }
    }

    public var detail: String {
        switch self {
        case .all: "Every song you play here"
        case .phoneOnly: "Songs your server also has are left out"
        }
    }
}

/// The ListenBrainz settings. `user` is who the saved token belongs to, or nil when none is saved.
public struct ListenBrainzPrefs: Sendable, Equatable {
    public var enabled = false
    public var user: String?
    public var needsAttention = false
    public var sendPlays: SendPlays = .all
    public var nowPlaying = true

    public init(enabled: Bool = false, user: String? = nil, needsAttention: Bool = false, sendPlays: SendPlays = .all,
                nowPlaying: Bool = true) {
        self.enabled = enabled
        self.user = user
        self.needsAttention = needsAttention
        self.sendPlays = sendPlays
        self.nowPlaying = nowPlaying
    }

    public var connected: Bool { user != nil }

    /// Plays are kept while switched on and connected, even while the token needs attention.
    public var keepsPlays: Bool { enabled && connected }

    public var sends: Bool { keepsPlays && !needsAttention }
}

// MARK: Server

/// Where the server is reached from, when it has a home address.
public enum ServerPlace: Sendable, Equatable {
    case home, away
}
