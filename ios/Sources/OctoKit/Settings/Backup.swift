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
    /// The order each list was left in, by the list's name, as "<order>:asc" or "<order>:desc".
    public var sortOrders: [String: String] = [:]

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
        ]
        top.append(("sortOrders", .object(backup.sortOrders.sorted { $0.key < $1.key }.map { ($0.key, .string($0.value)) })))
        return OrderedJSON.fields(top).pretty()
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
            ("libraryOnly", .bool(p.libraryOnly)),
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
                         ("arc", .bool(look.arc))])
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
        .object([("type", .string(capitalized(f.type.rawValue))), ("frequency", .double(f.frequency)), ("gainDb", .double(f.gainDb)),
                 ("q", .double(f.q)), ("enabled", .bool(f.enabled))])
    }

    static func settingsJSON(_ s: SoundSettings) -> OrderedJSON {
        .fields([
            ("eqEnabled", .bool(s.eqEnabled)), ("mode", .string(capitalized(s.mode.rawValue))),
            ("graphicGains", .array(s.graphicGains.map { .double($0) })), ("filters", .array(s.filters.map(filterJSON))),
            ("preset", s.preset.map { .string($0) }), ("preampDb", .double(s.preampDb)), ("autoPreamp", .bool(s.autoPreamp)),
            ("correction", s.correction.map { c in
                .object([("name", .string(c.name)), ("source", .string(c.source)), ("preampDb", .double(c.preampDb)),
                         ("filters", .array(c.filters.map(filterJSON)))])
            }),
            ("replayGain", .string(capitalized(s.replayGain.rawValue))), ("replayGainPreampDb", .double(s.replayGainPreampDb)),
            ("replayGainFallbackDb", .double(s.replayGainFallbackDb)), ("preventClipping", .bool(s.preventClipping)),
            ("limiter", .bool(s.limiter)), ("balance", .double(s.balance)), ("mono", .bool(s.mono)),
        ])
    }

    static func capitalized(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }

    // MARK: Reading

    public static func decode(_ data: Data) -> BackupRead {
        guard var text = String(data: data, encoding: .utf8) else { return .notABackup }
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        return decode(text)
    }

    public static func decode(_ text: String) -> BackupRead {
        let clean = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        guard let object = try? JSONSerialization.jsonObject(with: Data(clean.utf8)) as? [String: Any] else { return .notABackup }
        let kind = object["kind"] as? String ?? backupKind
        if object["kind"] != nil, object["kind"] as? String == nil { return .notABackup }
        if kind != backupKind { return .notABackup }
        let version = (object["version"] as? NSNumber)?.intValue ?? backupVersion
        if version > backupVersion { return .tooNew }
        return .read(backup(from: object, version: version))
    }

    static func backup(from o: [String: Any], version: Int) -> Backup {
        var b = Backup()
        b.version = version
        b.createdAt = (o["createdAt"] as? NSNumber)?.int64Value ?? 0
        b.player = part(o["player"], PlayerPrefs.self)
        b.streaming = part(o["streaming"], StreamPrefs.self)
        if let sound = o["sound"] as? [String: Any] { b.sound = soundBackup(sound) }
        b.presets = (o["presets"] as? [[String: Any]] ?? []).compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            return PresetBackup(name, (item["gains"] as? [NSNumber] ?? []).map(\.doubleValue))
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
        b.sortOrders = o["sortOrders"] as? [String: String] ?? [:]
        return b
    }

    private static func part<T: Decodable>(_ value: Any?, _ type: T.Type) -> T? {
        guard let value, !(value is NSNull), JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func soundBackup(_ o: [String: Any]) -> SoundBackup {
        var profiles: [String: SoundSettings] = [:]
        for (key, value) in o["profiles"] as? [String: Any] ?? [:] {
            if let settings = value as? [String: Any] { profiles[key] = soundSettings(settings) }
        }
        return SoundBackup(perOutput: o["perOutput"] as? Bool ?? false, profiles: profiles)
    }

    /// Sound settings from the other apps' shape, each field its default when missing or unknown.
    static func soundSettings(_ o: [String: Any]) -> SoundSettings {
        var s = SoundSettings()
        func lower(_ key: String) -> String? { (o[key] as? String).map { $0.prefix(1).lowercased() + $0.dropFirst() } }
        func double(_ key: String) -> Double? { (o[key] as? NSNumber)?.doubleValue }
        if let on = o["eqEnabled"] as? Bool { s.eqEnabled = on }
        if let mode = lower("mode").flatMap(EqMode.init(rawValue:)) { s.mode = mode }
        if let gains = o["graphicGains"] as? [NSNumber], gains.count == s.graphicGains.count { s.graphicGains = gains.map(\.doubleValue) }
        if let filters = o["filters"] as? [[String: Any]] { s.filters = filters.compactMap(filter) }
        if o.keys.contains("preset") { s.preset = o["preset"] as? String } else { s.preset = "Flat" }
        if let db = double("preampDb") { s.preampDb = db }
        if let auto = o["autoPreamp"] as? Bool { s.autoPreamp = auto }
        if let c = o["correction"] as? [String: Any], let name = c["name"] as? String {
            s.correction = HeadphoneCorrection(name: name, source: c["source"] as? String ?? "",
                                               preampDb: (c["preampDb"] as? NSNumber)?.doubleValue ?? 0,
                                               filters: (c["filters"] as? [[String: Any]] ?? []).compactMap(filter))
        }
        if let mode = lower("replayGain").flatMap(ReplayGainMode.init(rawValue:)) { s.replayGain = mode }
        if let db = double("replayGainPreampDb") { s.replayGainPreampDb = db }
        if let db = double("replayGainFallbackDb") { s.replayGainFallbackDb = db }
        if let on = o["preventClipping"] as? Bool { s.preventClipping = on }
        if let on = o["limiter"] as? Bool { s.limiter = on }
        if let b = double("balance") { s.balance = min(max(b, -1), 1) }
        if let on = o["mono"] as? Bool { s.mono = on }
        return s
    }

    static func filter(_ o: [String: Any]) -> EqFilter? {
        guard let frequency = (o["frequency"] as? NSNumber)?.doubleValue else { return nil }
        let type = (o["type"] as? String).map { $0.prefix(1).lowercased() + $0.dropFirst() }.flatMap(FilterType.init(rawValue:)) ?? .peak
        return EqFilter(type: type, frequency: frequency, gainDb: (o["gainDb"] as? NSNumber)?.doubleValue ?? 0,
                        q: (o["q"] as? NSNumber)?.doubleValue ?? 1.41, enabled: o["enabled"] as? Bool ?? true)
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
            backup.sortOrders.isEmpty ? nil : "sort orders",
        ].compactMap { $0 }
        if !settings.isEmpty { lines.append("Settings: " + settings.joined(separator: ", ")) }
        if let sound = backup.sound {
            let outputs = sound.profiles.keys.filter { $0 != "all" }.count
            if sound.perOutput && outputs > 0 { lines.append(plural(outputs, "output with its own sound", "outputs with their own sound")) }
        }
        if !backup.presets.isEmpty { lines.append(plural(backup.presets.count, "equalizer preset", "equalizer presets")) }
        if !backup.playlists.isEmpty {
            lines.append(plural(backup.playlists.count, "playlist", "playlists") + ", "
                + plural(backup.playlists.reduce(0) { $0 + $1.songs.count }, "song", "songs"))
        }
        if !backup.likes.isEmpty { lines.append(plural(backup.likes.count, "liked song", "liked songs")) }
        if !backup.ratings.isEmpty { lines.append(plural(backup.ratings.count, "rating", "ratings")) }
        if !backup.favoriteAlbums.isEmpty { lines.append(plural(backup.favoriteAlbums.count, "favorite album", "favorite albums")) }
        if !backup.favoriteArtists.isEmpty { lines.append(plural(backup.favoriteArtists.count, "favorite artist", "favorite artists")) }
        if !backup.pins.isEmpty { lines.append(plural(backup.pins.count, "pin on Home", "pins on Home")) }
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
        let g = SettingsSummaries.grouped
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
