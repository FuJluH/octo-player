import Foundation

/// The backup format. Raised when a change means an older app would read a newer file wrongly;
/// an older file is always read.
public let backupVersion = 1

/// Marks a file as an Octo settings backup, so any other JSON is refused.
public let backupKind = "octo-settings"

/// A song as a backup names it, so it can be found again after a reinstall or in another
/// library: its relink key (album artist, album, disc, track, title and length), and its title,
/// artist, album and length on their own.
public struct SongKey: Codable, Sendable, Hashable {
    public var relinkKey = ""
    public var title = ""
    public var artist = ""
    public var album = ""
    public var durationMs: Int64 = 0

    public init(relinkKey: String = "", title: String = "", artist: String = "", album: String = "", durationMs: Int64 = 0) {
        self.relinkKey = relinkKey
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }

    enum CodingKeys: String, CodingKey { case relinkKey, title, artist, album, durationMs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relinkKey = c.value(.relinkKey, or: "")
        title = c.value(.title, or: "")
        artist = c.value(.artist, or: "")
        album = c.value(.album, or: "")
        durationMs = c.value(.durationMs, or: 0)
    }

    var json: OrderedJSON {
        .object([("relinkKey", .string(relinkKey)), ("title", .string(title)), ("artist", .string(artist)), ("album", .string(album)),
                 ("durationMs", .int(durationMs))])
    }
}

public struct RatedSong: Codable, Sendable, Equatable {
    public var song: SongKey
    public var rating: Int

    public init(_ song: SongKey, _ rating: Int) {
        self.song = song
        self.rating = rating
    }
}

public struct PlaylistBackup: Codable, Sendable, Equatable {
    public var name: String
    public var songs: [SongKey]

    public init(_ name: String, _ songs: [SongKey] = []) {
        self.name = name
        self.songs = songs
    }

    enum CodingKeys: String, CodingKey { case name, songs }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        songs = c.value(.songs, or: [])
    }
}

public struct PresetBackup: Codable, Sendable, Equatable {
    public var name: String
    public var gains: [Double]

    public init(_ name: String, _ gains: [Double]) {
        self.name = name
        self.gains = gains
    }
}

/// The sound settings: whether each output keeps its own, and every saved set by output ("all"
/// is the shared one).
public struct SoundBackup: Sendable, Equatable {
    public var perOutput = false
    public var profiles: [String: SoundSettings] = [:]

    public init(perOutput: Bool = false, profiles: [String: SoundSettings] = [:]) {
        self.perOutput = perOutput
        self.profiles = profiles
    }
}

/// Which folders are left out of the library, and what goes to the server.
public struct LibraryBackup: Codable, Sendable, Equatable {
    public var excludedFolders: [String] = []
    public var syncQueue = true
    public var newPlaylistsOnServer = false

    public init(excludedFolders: [String] = [], syncQueue: Bool = true, newPlaylistsOnServer: Bool = false) {
        self.excludedFolders = excludedFolders
        self.syncQueue = syncQueue
        self.newPlaylistsOnServer = newPlaylistsOnServer
    }

    enum CodingKeys: String, CodingKey { case excludedFolders, syncQueue, newPlaylistsOnServer }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        excludedFolders = c.value(.excludedFolders, or: [])
        syncQueue = c.value(.syncQueue, or: true)
        newPlaylistsOnServer = c.value(.newPlaylistsOnServer, or: false)
    }
}

/// A favorite or pinned album or artist as a backup names it: its relink key and its names. An
/// artist has no artist.
public struct HeldKey: Codable, Sendable, Hashable {
    public var relinkKey = ""
    public var name = ""
    public var artist = ""

    public init(relinkKey: String = "", name: String = "", artist: String = "") {
        self.relinkKey = relinkKey
        self.name = name
        self.artist = artist
    }

    enum CodingKeys: String, CodingKey { case relinkKey, name, artist }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relinkKey = c.value(.relinkKey, or: "")
        name = c.value(.name, or: "")
        artist = c.value(.artist, or: "")
    }

    var json: OrderedJSON { .object([("relinkKey", .string(relinkKey)), ("name", .string(name)), ("artist", .string(artist))]) }
}

/// Something pinned to Home, in row order. A playlist is named by its name.
public struct PinBackup: Codable, Sendable, Equatable {
    public var kind: String
    public var item: HeldKey

    public init(_ kind: String, _ item: HeldKey) {
        self.kind = kind
        self.item = item
    }
}

/// A song's lyrics moved earlier or later by hand.
public struct LyricsOffsetBackup: Codable, Sendable, Equatable {
    public var song: SongKey
    public var offsetMs: Int64

    public init(_ song: SongKey, _ offsetMs: Int64) {
        self.song = song
        self.offsetMs = offsetMs
    }
}

/// Whether the screen stays on while lyrics show, each song's timing, how synced lyrics look,
/// and each sound output's timing by output key.
public struct LyricsBackup: Codable, Sendable, Equatable {
    public var keepScreenOn = true
    public var offsets: [LyricsOffsetBackup] = []
    public var look: LyricsLook?
    public var outputOffsets: [String: Int64] = [:]

    public init(keepScreenOn: Bool = true, offsets: [LyricsOffsetBackup] = [], look: LyricsLook? = nil, outputOffsets: [String: Int64] = [:]) {
        self.keepScreenOn = keepScreenOn
        self.offsets = offsets
        self.look = look
        self.outputOffsets = outputOffsets
    }

    enum CodingKeys: String, CodingKey { case keepScreenOn, offsets, look, outputOffsets }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keepScreenOn = c.value(.keepScreenOn, or: true)
        offsets = c.value(.offsets, or: [])
        look = (try? c.decodeIfPresent(LyricsLook.self, forKey: .look)) ?? nil
        outputOffsets = c.value(.outputOffsets, or: [:])
    }
}

/// What is kept on the phone for playing without a connection. Playlists kept downloaded are
/// named by their name, since restored playlists get new ids.
public typealias OfflineBackup = OfflinePrefs

/// The ListenBrainz choices. Who was connected, and how, is never in a backup.
public struct ListenBrainzBackup: Codable, Sendable, Equatable {
    public var enabled = false
    public var sendPlays: SendPlays = .all
    public var nowPlaying = true

    public init(enabled: Bool = false, sendPlays: SendPlays = .all, nowPlaying: Bool = true) {
        self.enabled = enabled
        self.sendPlays = sendPlays
        self.nowPlaying = nowPlaying
    }

    enum CodingKeys: String, CodingKey { case enabled, sendPlays, nowPlaying }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.value(.enabled, or: false)
        sendPlays = c.choice(.sendPlays, or: .all)
        nowPlaying = c.value(.nowPlaying, or: true)
    }
}

/// The server signed in to, for reference: its address and user name only.
public struct ServerBackup: Codable, Sendable, Equatable {
    public var address: String
    public var username: String

    public init(address: String, username: String) {
        self.address = address
        self.username = username
    }
}

/// Everything a backup holds. Every part is optional, so a backup from an older app with fewer
/// settings still reads. Some stored key names keep the other apps' British spelling.
public struct Backup: Sendable, Equatable {
    public var kind = backupKind
    public var version = backupVersion
    public var createdAt: Int64 = 0
    public var player: PlayerPrefs?
    public var streaming: StreamPrefs?
    public var sound: SoundBackup?
    public var presets: [PresetBackup] = []
    public var library: LibraryBackup?
    public var server: ServerBackup?
    public var playlists: [PlaylistBackup] = []
    public var likes: [SongKey] = []
    public var ratings: [RatedSong] = []
    public var favoriteAlbums: [HeldKey] = []
    public var favoriteArtists: [HeldKey] = []
    public var pins: [PinBackup] = []
    public var lyrics: LyricsBackup?
    public var offline: OfflineBackup?
    public var listenBrainz: ListenBrainzBackup?
    /// Home's shelves in order, a hidden one led by "-", as stored under `homeSectionsKey`.
    public var homeSections: String?
    /// The order each list was left in, by the list's name, as "<order>:asc" or "<order>:desc".
    public var sortOrders: [String: String] = [:]
    /// The live radio stations kept on the phone, newest first.
    public var keptStations: [LiveStation] = []

    public init() {}
}

/// What reading a picked file gave.
public enum BackupRead: Equatable, Sendable {
    case read(Backup)
    /// Not an Octo backup, or not readable at all.
    case notABackup
    /// Made by a newer Octo in a format this one does not know.
    case tooNew
}

public enum BackupFile {
    /// The largest backup read. Even a big library's backup is a few megabytes.
    public static let maxBytes = 32 * 1024 * 1024

    /// The file name a backup is offered under: "Octo backup 2026-10-11.json".
    public static func suggestedName(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "Octo backup %04d-%02d-%02d.json", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: Writing

    public static func encode(_ backup: Backup) -> String {
        var top: [(String, OrderedJSON?)] = [
            ("kind", .string(backup.kind)),
            ("version", .int(Int64(backup.version))),
            ("createdAt", .int(backup.createdAt)),
            ("player", backup.player.map(playerJSON)),
            ("streaming", backup.streaming.map(streamJSON)),
            ("sound", backup.sound.map(soundJSON)),
            ("presets", .array(backup.presets.map { .object([("name", .string($0.name)), ("gains", .array($0.gains.map { .double($0) }))]) })),
            ("library", backup.library.map { library in
                .object([("excludedFolders", .strings(library.excludedFolders)), ("syncQueue", .bool(library.syncQueue)),
                         ("newPlaylistsOnServer", .bool(library.newPlaylistsOnServer))])
            }),
            ("server", backup.server.map { .object([("address", .string($0.address)), ("username", .string($0.username))]) }),
            ("playlists", .array(backup.playlists.map { .object([("name", .string($0.name)), ("songs", .array($0.songs.map(\.json)))]) })),
            ("likes", .array(backup.likes.map(\.json))),
            ("ratings", .array(backup.ratings.map { .object([("song", $0.song.json), ("rating", .int(Int64($0.rating)))]) })),
            ("favouriteAlbums", .array(backup.favoriteAlbums.map(\.json))),
            ("favouriteArtists", .array(backup.favoriteArtists.map(\.json))),
            ("pins", .array(backup.pins.map { .object([("kind", .string($0.kind)), ("item", $0.item.json)]) })),
            ("lyrics", backup.lyrics.map(lyricsJSON)),
            ("offline", backup.offline.map(offlineJSON)),
            ("listenBrainz", backup.listenBrainz.map {
                .object([("enabled", .bool($0.enabled)), ("sendPlays", .string($0.sendPlays.storedName)), ("nowPlaying", .bool($0.nowPlaying))])
            }),
            ("homeSections", backup.homeSections.map { .string($0) }),
        ]
        top.append(("sortOrders", sortOrdersJSON(backup.sortOrders)))
        top.append(("keptStations", .array(backup.keptStations.map(liveStationJSON))))
        return OrderedJSON.fields(top).pretty()
    }

    /// Each list's order in the order the lists come in, any list this app does not have last.
    static func sortOrdersJSON(_ orders: [String: String]) -> OrderedJSON {
        let lists = SortList.allCases.map(\.key)
        func place(_ key: String) -> Int { lists.firstIndex(of: key) ?? lists.count }
        let ordered = orders.sorted { a, b in place(a.key) != place(b.key) ? place(a.key) < place(b.key) : a.key < b.key }
        return .object(ordered.map { ($0.key, .string($0.value)) })
    }

    /// A kept station in the shape the other apps keep it, without a distance.
    static func liveStationJSON(_ s: LiveStation) -> OrderedJSON {
        .object([("uuid", .string(s.uuid)), ("name", .string(s.name)), ("streamUrl", .string(s.streamUrl)),
                 ("favicon", .string(s.favicon)), ("codec", .string(s.codec)), ("bitrate", .int(Int64(s.bitrate))),
                 ("hls", .bool(s.hls)), ("country", .string(s.country)), ("countryCode", .string(s.countryCode)),
                 ("state", .string(s.state)), ("tags", .strings(s.tags)), ("clicks", .int(Int64(s.clicks)))])
    }

    static func playerJSON(_ p: PlayerPrefs) -> OrderedJSON {
        let b = p.background
        let a = p.ambient
        return .object([
            ("liveBackground", .bool(p.liveBackground)),
            ("background", .object([
                ("mode", .string(b.mode.storedName)), ("brightnessCap", .int(Int64(b.brightnessCap))), ("saturation", .int(Int64(b.saturation))),
                ("contrast", .double(Double(String(b.contrast)) ?? Double(b.contrast))), ("useBpm", .bool(b.useBpm)),
                ("fps", .int(Int64(b.fps))), ("speed", .int(Int64(b.speed))),
            ])),
            ("crossfade", .bool(p.crossfade)), ("crossfadeSeconds", .int(Int64(p.crossfadeSeconds))),
            ("crossfadeCurve", .string(p.crossfadeCurve.storedName)),
            ("smartTransitions", .bool(p.smartTransitions)), ("filterSweeps", .bool(p.filterSweeps)), ("matchTempo", .bool(p.matchTempo)),
            ("lyricsOnline", .bool(p.lyricsOnline)), ("speed", .double(Double(String(p.speed)) ?? Double(p.speed))),
            ("keepPitch", .bool(p.keepPitch)), ("pitchSemitones", .int(Int64(p.pitchSemitones))), ("skipSilence", .bool(p.skipSilence)),
            ("autoplay", .bool(p.autoplay)), ("radioDiscovery", .string(p.radioDiscovery.storedName)),
            ("radioAdventure", .string(p.radioAdventure.storedName)), ("radioVariety", .string(p.radioVariety.storedName)),
            ("radioFavorites", .bool(p.radioFavorites)), ("resumeWired", .bool(p.resumeWired)), ("resumeBluetooth", .bool(p.resumeBluetooth)),
            ("resumeAlways", .bool(p.resumeAlways)),
            ("ambient", .object([
                ("strength", .string(a.strength.storedName)), ("home", .bool(a.home)), ("library", .bool(a.library)), ("search", .bool(a.search)),
                ("settings", .bool(a.settings)), ("bar", .bool(a.bar)), ("pageArtwork", .bool(a.pageArtwork)),
            ])),
            ("reduceMotion", .bool(p.reduceMotion)), ("castRenderers", .bool(p.castRenderers)), ("castKeepPlaying", .bool(p.castKeepPlaying)),
            ("libraryOnly", .bool(p.libraryOnly)), ("accent", .string(p.accent.storedName)), ("glassTint", .bool(p.glassTint)),
            ("animatedArt", .string(p.animatedArt.storedName)),
        ])
    }

    static func streamJSON(_ s: StreamPrefs) -> OrderedJSON {
        .object([("copies", .string(s.copies.storedName)), ("wifi", .string(s.wifi.storedName)), ("mobile", .string(s.mobile.storedName)),
                 ("startAfter", .string(s.startAfter.storedName))])
    }

    static func lyricsJSON(_ l: LyricsBackup) -> OrderedJSON {
        .fields([
            ("keepScreenOn", .bool(l.keepScreenOn)),
            ("offsets", .array(l.offsets.map { .object([("song", $0.song.json), ("offsetMs", .int($0.offsetMs))]) })),
            ("look", l.look.map { look in
                .object([("style", .string(look.style.rawValue)), ("emphasis", .int(Int64(look.emphasis))), ("glow", .int(Int64(look.glow))),
                         ("lift", .int(Int64(look.lift))), ("speed", .int(Int64(look.speed))), ("inactiveScale", .int(Int64(look.inactiveScale))),
                         ("fade", .int(Int64(look.fade))), ("cascade", .int(Int64(look.cascade))), ("keepCompleted", .bool(look.keepCompleted)),
                         ("arc", .bool(look.arc)), ("bloomFast", .bool(look.bloomFast))])
            }),
            ("outputOffsets", .object(l.outputOffsets.sorted { $0.key < $1.key }.map { ($0.key, .int($0.value)) })),
        ])
    }

    static func offlineJSON(_ o: OfflineBackup) -> OrderedJSON {
        .object([("cacheSize", .string(o.cacheSize.storedName)), ("prefetchWifi", .int(Int64(o.prefetchWifi))),
                 ("prefetchMobile", .int(Int64(o.prefetchMobile))), ("downloadQuality", .string(o.downloadQuality.storedName)),
                 ("wifiOnly", .bool(o.wifiOnly)), ("streamOnWifi", .bool(o.streamOnWifi)), ("keepLiked", .bool(o.keepLiked)),
                 ("keptPlaylists", .strings(o.keptPlaylists.sorted()))])
    }

    /// One output's sound as the other apps write it: enum names capitalized, no filter ids.
    static func soundJSON(_ sound: SoundBackup) -> OrderedJSON {
        .object([
            ("perOutput", .bool(sound.perOutput)),
            ("profiles", .object(sound.profiles.sorted { $0.key < $1.key }.map { ($0.key, settingsJSON($0.value)) })),
        ])
    }

    static func filterJSON(_ f: EqFilter) -> OrderedJSON {
        .object([("type", .string(f.type.rawValue)), ("frequency", .double(f.frequency)), ("gainDb", .double(f.gainDb)),
                 ("q", .double(f.q)), ("enabled", .bool(f.enabled))])
    }

    static func settingsJSON(_ s: SoundSettings) -> OrderedJSON {
        .fields([
            ("eqEnabled", .bool(s.eqEnabled)), ("mode", .string(s.mode.rawValue)),
            ("graphicGains", .array(s.graphicGains.map { .double($0) })), ("filters", .array(s.filters.map(filterJSON))),
            ("preset", s.preset.map { .string($0) }), ("preampDb", .double(s.preampDb)), ("autoPreamp", .bool(s.autoPreamp)),
            ("correction", s.correction.map { c in
                .object([("name", .string(c.name)), ("source", .string(c.source)), ("preampDb", .double(c.preampDb)),
                         ("filters", .array(c.filters.map(filterJSON)))])
            }),
            ("replayGain", .string(s.replayGain.rawValue)), ("replayGainPreampDb", .double(s.replayGainPreampDb)),
            ("replayGainFallbackDb", .double(s.replayGainFallbackDb)), ("preventClipping", .bool(s.preventClipping)),
            ("limiter", .bool(s.limiter)), ("balance", .double(s.balance)), ("mono", .bool(s.mono)),
            ("crossfeed", .object([
                ("on", .bool(s.crossfeed.on)), ("preset", .string(s.crossfeed.preset.rawValue)),
                ("cutHz", .int(Int64(s.crossfeed.cutHz))), ("feedDb", .double(s.crossfeed.feedDb)),
            ])),
        ])
    }

    // MARK: Reading

    /// Reads a file's bytes as UTF-8, bytes that are not UTF-8 read as U+FFFD.
    public static func decode(_ data: Data) -> BackupRead {
        decode(String(decoding: data, as: UTF8.self))
    }

    /// Reads a backup the way the other Octo apps do: a file that is not JSON, not an object, or
    /// has a field of the wrong kind anywhere is not a backup; a null or a choice this app does
    /// not know takes the default; fields this app does not know are passed over.
    public static func decode(_ text: String) -> BackupRead {
        let clean = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        guard let parsed = try? OrderedJSON.parse(clean), case .object = parsed,
              case .object(let fields)? = try? BackupShape.backup.normalized(parsed)
        else { return .notABackup }
        let read = Fields(fields)
        if (read["kind"]?.text ?? backupKind) != backupKind { return .notABackup }
        let version = read["version"]?.whole.map { Int($0) } ?? backupVersion
        if version > backupVersion { return .tooNew }
        return .read(backup(from: read, version: version))
    }

    /// An object's fields by key, once each.
    struct Fields {
        private let values: [String: OrderedJSON]

        init(_ pairs: [(String, OrderedJSON)]) { values = Dictionary(pairs, uniquingKeysWith: { _, last in last }) }

        subscript(_ key: String) -> OrderedJSON? { values[key] }
    }

    static func backup(from o: Fields, version: Int) -> Backup {
        var b = Backup()
        b.version = version
        b.createdAt = o["createdAt"]?.whole ?? 0
        b.player = part(o["player"], PlayerPrefs.self)
        b.streaming = part(o["streaming"], StreamPrefs.self)
        if case .object(let sound)? = o["sound"] { b.sound = soundBackup(Fields(sound)) }
        if case .array(let presets)? = o["presets"] {
            b.presets = presets.compactMap { item -> PresetBackup? in
                guard case .object(let pairs) = item else { return nil }
                let fields = Fields(pairs)
                guard let name = fields["name"]?.text else { return nil }
                guard case .array(let gains)? = fields["gains"] else { return PresetBackup(name, []) }
                return PresetBackup(name, gains.compactMap(\.decimal))
            }
        }
        b.library = part(o["library"], LibraryBackup.self)
        b.server = part(o["server"], ServerBackup.self)
        b.playlists = part(o["playlists"], [PlaylistBackup].self) ?? []
        b.likes = part(o["likes"], [SongKey].self) ?? []
        b.ratings = part(o["ratings"], [RatedSong].self) ?? []
        b.favoriteAlbums = part(o["favouriteAlbums"], [HeldKey].self) ?? []
        b.favoriteArtists = part(o["favouriteArtists"], [HeldKey].self) ?? []
        b.pins = part(o["pins"], [PinBackup].self) ?? []
        b.lyrics = part(o["lyrics"], LyricsBackup.self)
        b.offline = part(o["offline"], OfflinePrefs.self)
        b.listenBrainz = part(o["listenBrainz"], ListenBrainzBackup.self)
        b.homeSections = o["homeSections"]?.text
        if case .object(let orders)? = o["sortOrders"] {
            for (list, order) in orders { if let order = order.text { b.sortOrders[list] = order } }
        }
        b.keptStations = part(o["keptStations"], [LiveStation].self) ?? []
        return b
    }

    /// One part of a checked backup, read by its own decoder. Null is no part.
    private static func part<T: Decodable>(_ value: OrderedJSON?, _ type: T.Type) -> T? {
        guard let value else { return nil }
        if case .null = value { return nil }
        let decoder = JSONDecoder()
        decoder.userInfo[unknownChoicesTakeDefaults] = true
        return try? decoder.decode(T.self, from: Data(value.pretty().utf8))
    }

    static func soundBackup(_ o: Fields) -> SoundBackup {
        var profiles: [String: SoundSettings] = [:]
        if case .object(let saved)? = o["profiles"] {
            for (key, value) in saved {
                if let settings = part(value, SoundSettings.self) { profiles[key] = settings }
            }
        }
        var perOutput = false
        if case .bool(let on)? = o["perOutput"] { perOutput = on }
        return SoundBackup(perOutput: perOutput, profiles: profiles)
    }

    /// A server address with nothing but where it is: no user name or password written into it,
    /// no query and no fragment.
    public static func plainAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        func cut(_ text: String) -> String {
            String(text.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        }
        guard let parts = URLComponents(string: trimmed) else { return cut(address).trimmingCharacters(in: .whitespaces) }
        guard let host = parts.host, !host.isEmpty else {
            let before = cut(address)
            let after = before.range(of: "@", options: .backwards).map { String(before[$0.upperBound...]) } ?? before
            return after.trimmingCharacters(in: .whitespaces)
        }
        let port = parts.port.map { ":\($0)" } ?? ""
        var text = "\(parts.scheme ?? "https")://\(host)\(port)\(parts.percentEncodedPath)"
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }
}

// MARK: Matching a backup against this library

/// A library song as the finder sees it.
public struct BackupTrack: Sendable, Equatable {
    public var id: String
    public var relinkKey: String
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int64

    public init(id: String, relinkKey: String, title: String, artist: String, album: String, durationMs: Int64) {
        self.id = id
        self.relinkKey = relinkKey
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
    }
}

/// An album or artist name as the library matches it: case, accents, punctuation, spacing and
/// bracketed extras ignored, "&" read as "and".
public func libraryMatchKey(_ name: String) -> String {
    SongIdentity.key(name.replacingOccurrences(of: #"\s*[(\[][^)\]]*[)\]]"#, with: " ", options: .regularExpression))
}

/// Finds songs named in a backup in this library: by relink key first, then by title (with its
/// kind of recording), artist and album, then as the same song by the same artist, of about the
/// same length when both lengths are known.
public final class SongFinder {
    private let byRelink: [String: [BackupTrack]]
    private let byWhole: [String: [BackupTrack]]
    private let byTitle: TitleIndex<BackupTrack>

    public init(_ library: [BackupTrack]) {
        byRelink = Dictionary(grouping: library.filter { !$0.relinkKey.isEmpty }, by: \.relinkKey)
        byWhole = Dictionary(grouping: library) { Self.wholeKey($0.title, $0.artist, $0.album) }
        byTitle = TitleIndex(library, title: \.title, artist: \.artist)
    }

    public func find(_ song: SongKey) -> String? {
        if !song.relinkKey.isEmpty, let hit = byRelink[song.relinkKey]?.first { return hit.id }
        if song.title.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        if let same = byWhole[Self.wholeKey(song.title, song.artist, song.album)], !same.isEmpty {
            return Self.closest(same, song.durationMs).id
        }
        if song.artist.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        let candidates = byTitle.candidates(song.title, song.artist).filter {
            sameSong(song.title, song.artist, song.durationMs, $0.title, $0.artist, $0.durationMs)
        }
        return candidates.isEmpty ? nil : Self.closest(candidates, song.durationMs).id
    }

    static func wholeKey(_ title: String, _ artist: String, _ album: String) -> String {
        "\(SongIdentity.songKeys(artist, title).title)|\(libraryMatchKey(artist))|\(libraryMatchKey(album))"
    }

    static func closest(_ tracks: [BackupTrack], _ durationMs: Int64) -> BackupTrack {
        if durationMs <= 0 { return tracks[0] }
        return tracks.min { abs($0.durationMs - durationMs) < abs($1.durationMs - durationMs) } ?? tracks[0]
    }
}

/// A library album or artist as the finder sees it. An artist has no artist.
public struct NamedItem: Sendable, Equatable {
    public var id: String
    public var relinkKey: String
    public var name: String
    public var artist: String

    public init(id: String, relinkKey: String, name: String, artist: String = "") {
        self.id = id
        self.relinkKey = relinkKey
        self.name = name
        self.artist = artist
    }
}

/// Finds albums or artists named in a backup in this library: by relink key first, then by name
/// (and artist, for an album). When several match, the smallest id wins, so the choice is the
/// same every time.
public final class NameFinder {
    private let byRelink: [String: [NamedItem]]
    private let byName: [String: [NamedItem]]

    public init(_ library: [NamedItem]) {
        byRelink = Dictionary(grouping: library.filter { !$0.relinkKey.isEmpty }, by: \.relinkKey)
        byName = Dictionary(grouping: library) { Self.nameKey($0.name, $0.artist) }
    }

    public func find(_ key: HeldKey) -> String? {
        if !key.relinkKey.isEmpty, let ids = byRelink[key.relinkKey]?.map(\.id), let first = ids.min() { return first }
        if key.name.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        return byName[Self.nameKey(key.name, key.artist)]?.map(\.id).min()
    }

    static func nameKey(_ name: String, _ artist: String) -> String { "\(libraryMatchKey(name))|\(libraryMatchKey(artist))" }
}

/// What can be pinned to Home.
public enum PinKind: String, Sendable, Equatable {
    case album, artist, playlist

    public static func of(_ name: String) -> PinKind? { PinKind(rawValue: name) }
}

/// A pin to add on restore: an album or artist by its library id, or a playlist by its name.
public struct PinPlan: Sendable, Hashable {
    public var kind: PinKind
    public var target: String
}

/// One playlist to make on restore: its name, the songs found, and how many the backup had.
public struct PlaylistPlan: Sendable, Equatable {
    public var name: String
    public var trackIds: [String]
    public var total: Int
}

/// What restoring would do with this library.
public struct RestorePlan: Sendable, Equatable {
    public var playlists: [PlaylistPlan] = []
    public var skippedPlaylists: [String] = []
    public var likes: [String] = []
    public var likesTotal = 0
    public var ratings: [String: Int] = [:]
    public var ratingsTotal = 0
    public var favoriteAlbums: [String] = []
    public var favoriteAlbumsTotal = 0
    public var favoriteArtists: [String] = []
    public var favoriteArtistsTotal = 0
    public var pins: [PinPlan] = []
    public var pinsTotal = 0
    public var lyricsOffsets: [String: Int64] = [:]
    public var lyricsOffsetsTotal = 0
    /// Playlists to keep downloaded, by name, and how many the backup named.
    public var keptPlaylists: [String] = []
    public var keptPlaylistsTotal = 0

    public init() {}

    public var playlistSongs: Int { playlists.reduce(0) { $0 + $1.trackIds.count } }
    public var playlistSongsTotal: Int { playlists.reduce(0) { $0 + $1.total } }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

public enum BackupPlanner {
    public static func plan(_ backup: Backup, library: [BackupTrack], existingPlaylists: [String], albums: [NamedItem] = [],
                            artists: [NamedItem] = []) -> RestorePlan {
        let finder = SongFinder(library)
        let albumFinder = NameFinder(albums)
        let artistFinder = NameFinder(artists)
        let taken = Set(existingPlaylists.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        let skipped = backup.playlists.filter { taken.contains($0.name.trimmingCharacters(in: .whitespaces).lowercased()) }
        let wanted = backup.playlists.filter { !taken.contains($0.name.trimmingCharacters(in: .whitespaces).lowercased()) }
        // Playlists here after the restore: those already here and those it makes.
        let playlistNames = taken.union(wanted.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        var plan = RestorePlan()
        plan.playlists = wanted.map {
            PlaylistPlan(name: $0.name.trimmingCharacters(in: .whitespaces), trackIds: $0.songs.compactMap(finder.find), total: $0.songs.count)
        }
        plan.skippedPlaylists = skipped.map(\.name)
        plan.likes = backup.likes.compactMap(finder.find).uniqued()
        plan.likesTotal = backup.likes.count
        for rated in backup.ratings where (1...5).contains(rated.rating) {
            if let id = finder.find(rated.song) { plan.ratings[id] = rated.rating }
        }
        plan.ratingsTotal = backup.ratings.count
        plan.favoriteAlbums = backup.favoriteAlbums.compactMap(albumFinder.find).uniqued()
        plan.favoriteAlbumsTotal = backup.favoriteAlbums.count
        plan.favoriteArtists = backup.favoriteArtists.compactMap(artistFinder.find).uniqued()
        plan.favoriteArtistsTotal = backup.favoriteArtists.count
        plan.pins = backup.pins.compactMap { pin -> PinPlan? in
            switch PinKind.of(pin.kind) {
            case .album: albumFinder.find(pin.item).map { PinPlan(kind: .album, target: $0) }
            case .artist: artistFinder.find(pin.item).map { PinPlan(kind: .artist, target: $0) }
            case .playlist:
                playlistNames.contains(pin.item.name.trimmingCharacters(in: .whitespaces).lowercased())
                    ? PinPlan(kind: .playlist, target: pin.item.name.trimmingCharacters(in: .whitespaces)) : nil
            case nil: nil
            }
        }.uniqued()
        plan.pinsTotal = backup.pins.count
        for moved in backup.lyrics?.offsets ?? [] {
            if let id = finder.find(moved.song) { plan.lyricsOffsets[id] = moved.offsetMs }
        }
        plan.lyricsOffsetsTotal = backup.lyrics?.offsets.count ?? 0
        var keptSeen = Set<String>()
        plan.keptPlaylists = (backup.offline?.keptPlaylists ?? []).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { playlistNames.contains($0.lowercased()) && keptSeen.insert($0.lowercased()).inserted }
        plan.keptPlaylistsTotal = backup.offline?.keptPlaylists.count ?? 0
        return plan
    }

    /// What a backup holds, a line each, for showing before it is restored.
    public static func describe(_ backup: Backup) -> [String] {
        var lines: [String] = []
        let settings = [
            backup.player != nil ? "player" : nil,
            backup.streaming != nil ? "streaming" : nil,
            backup.sound != nil ? "sound" : nil,
            backup.library != nil ? "library" : nil,
            backup.lyrics != nil ? "lyrics" : nil,
            backup.offline != nil ? "cache and downloads" : nil,
            backup.listenBrainz != nil ? "scrobbling" : nil,
            backup.homeSections != nil ? "home sections" : nil,
            backup.sortOrders.isEmpty ? nil : "sort orders",
        ].compactMap { $0 }
        if !settings.isEmpty { lines.append("Settings: " + settings.joined(separator: ", ")) }
        lines += SoundBackupWords.lines(perOutput: backup.sound?.perOutput ?? false, profiles: backup.sound?.profiles,
                                        presets: backup.presets.map { EqPreset(name: $0.name, gains: $0.gains) })
        if !backup.playlists.isEmpty {
            lines.append(plural(backup.playlists.count, "playlist", "playlists") + ", "
                + plural(backup.playlists.reduce(0) { $0 + $1.songs.count }, "song", "songs"))
        }
        if !backup.likes.isEmpty { lines.append(plural(backup.likes.count, "liked song", "liked songs")) }
        if !backup.ratings.isEmpty { lines.append(plural(backup.ratings.count, "rating", "ratings")) }
        if !backup.favoriteAlbums.isEmpty { lines.append(plural(backup.favoriteAlbums.count, "favorite album", "favorite albums")) }
        if !backup.favoriteArtists.isEmpty { lines.append(plural(backup.favoriteArtists.count, "favorite artist", "favorite artists")) }
        if !backup.pins.isEmpty { lines.append(plural(backup.pins.count, "pin on Home", "pins on Home")) }
        if !backup.keptStations.isEmpty { lines.append(plural(backup.keptStations.count, "kept radio station", "kept radio stations")) }
        if let offsets = backup.lyrics?.offsets, !offsets.isEmpty { lines.append("Lyrics timing for " + plural(offsets.count, "song", "songs")) }
        if let outputs = backup.lyrics?.outputOffsets, !outputs.isEmpty {
            lines.append("Lyrics timing for " + plural(outputs.count, "sound output", "sound outputs"))
        }
        if let kept = backup.offline?.keptPlaylists, !kept.isEmpty {
            lines.append(plural(kept.count, "playlist kept downloaded", "playlists kept downloaded"))
        }
        if backup.listenBrainz?.enabled == true { lines.append("ListenBrainz: connect again to send plays.") }
        if let server = backup.server { lines.append("Server: \(server.address) as \(server.username). Sign in again to use it.") }
        return lines
    }

    /// How much of a backup this library has, a line each, like "Playlists: 331 of 340 songs found".
    public static func describe(_ plan: RestorePlan) -> [String] {
        let g: (Int) -> String = { SettingsSummaries.grouped($0) }
        var lines: [String] = []
        if !plan.playlists.isEmpty {
            lines.append("Playlists: \(g(plan.playlistSongs)) of \(plural(plan.playlistSongsTotal, "song", "songs")) found")
        }
        if !plan.skippedPlaylists.isEmpty { lines.append("Already here, left as they are: " + plan.skippedPlaylists.joined(separator: ", ")) }
        if plan.likesTotal > 0 { lines.append("Likes: \(g(plan.likes.count)) of \(g(plan.likesTotal)) found") }
        if plan.ratingsTotal > 0 { lines.append("Ratings: \(g(plan.ratings.count)) of \(g(plan.ratingsTotal)) found") }
        if plan.favoriteAlbumsTotal > 0 { lines.append("Favorite albums: \(g(plan.favoriteAlbums.count)) of \(g(plan.favoriteAlbumsTotal)) found") }
        if plan.favoriteArtistsTotal > 0 {
            lines.append("Favorite artists: \(g(plan.favoriteArtists.count)) of \(g(plan.favoriteArtistsTotal)) found")
        }
        if plan.pinsTotal > 0 { lines.append("Pins: \(g(plan.pins.count)) of \(g(plan.pinsTotal)) found") }
        if plan.lyricsOffsetsTotal > 0 { lines.append("Lyrics timing: \(g(plan.lyricsOffsets.count)) of \(g(plan.lyricsOffsetsTotal)) songs found") }
        if plan.keptPlaylistsTotal > 0 {
            lines.append("Kept downloaded: \(g(plan.keptPlaylists.count)) of \(plural(plan.keptPlaylistsTotal, "playlist", "playlists")) found")
        }
        return lines
    }

    static func plural(_ count: Int, _ one: String, _ many: String) -> String {
        SettingsSummaries.count(count, one: one, many: many)
    }
}
