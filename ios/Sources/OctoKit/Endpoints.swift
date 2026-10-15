import Foundation

/// What the server is, after signing in.
public struct ServerProfile: Sendable, Equatable {
    public var info: ServerInfo
    /// OpenSubsonic extensions as "name:version" strings, the way the other apps keep them.
    public var extensions: [String]

    /// Octo calls itself Octo in `ping`, or lists its own extensions.
    public var isOcto: Bool {
        info.type?.caseInsensitiveCompare("octo") == .orderedSame || extensions.contains { $0.hasPrefix("octo") }
    }

    public func has(_ name: String) -> Bool { extensions.contains { $0.hasPrefix(name + ":") } }

    /// Whether the server lists an extension at this version.
    public func lists(_ name: String, version: Int = 1) -> Bool { extensions.contains("\(name):\(version)") }
}

/// How the app asks for a song's audio.
public enum StreamQuality: Sendable, Equatable, Hashable {
    /// The file as it is, when the phone can play it.
    case original
    /// MP3 at most this many kbps.
    case mp3(kbps: Int)

    public static let choices: [StreamQuality] = [.original, .mp3(kbps: 320), .mp3(kbps: 256), .mp3(kbps: 192), .mp3(kbps: 128)]
}

extension SubsonicClient {
    // Formats Apple's player opens as they are. Anything else (Ogg, Opus, WMA, APE, WavPack)
    // the server turns into MP3.
    static let playableSuffixes: Set<String> = ["mp3", "m4a", "mp4", "aac", "alac", "flac", "wav", "aif", "aiff", "caf"]

    /// Who the server is and what it can do. `ping` first: a wrong password fails here.
    public func profile() async throws -> ServerProfile {
        let info: ServerInfo = try await get("ping", key: nil)
        let extensions: [Extension] = info.openSubsonic
            ? ((try? await get("getOpenSubsonicExtensions", key: "openSubsonicExtensions")) ?? [])
            : []
        return ServerProfile(
            info: info,
            extensions: extensions.flatMap { e in e.versions.map { "\(e.name):\($0)" } }
        )
    }

    /// Who an API key belongs to.
    public func tokenInfo() async throws -> String {
        let body: TokenInfo = try await get("tokenInfo", key: "tokenInfo")
        return body.username
    }

    public func albumList(_ type: AlbumListType, size: Int = 30, offset: Int = 0) async throws -> [Album] {
        let list: AlbumListBody = try await get(
            "getAlbumList2", inFolder([("type", type.rawValue), ("size", "\(size)"), ("offset", "\(offset)")], nil),
            key: "albumList2")
        return list.album
    }

    public func album(_ id: String) async throws -> Album {
        var album: Album = try await get("getAlbum", [("id", id)], key: "album")
        // Octo's animated art comes with whole addresses, or not at all when it holds none.
        if let art = album.animatedArt?.resolved(on: baseURL) {
            album.animatedArt = art.isEmpty ? nil : art
        }
        return album
    }

    public func artists() async throws -> [Artist] {
        let body: ArtistsBody = try await get("getArtists", inFolder([], nil), key: "artists")
        return body.index.flatMap(\.artist)
    }

    public func artist(_ id: String) async throws -> Artist {
        try await get("getArtist", [("id", id)], key: "artist")
    }

    public func topSongs(artist name: String, count: Int = 10) async throws -> [Song] {
        let body: SongsBody = try await get("getTopSongs", [("artist", name), ("count", "\(count)")], key: "topSongs")
        return body.song
    }

    public func playlists() async throws -> [Playlist] {
        let body: PlaylistsBody = try await get("getPlaylists", key: "playlists")
        return body.playlist
    }

    public func playlist(_ id: String) async throws -> Playlist {
        try await get("getPlaylist", [("id", id)], key: "playlist")
    }

    public func search(_ query: String, artists: Int = 10, albums: Int = 20, songs: Int = 40) async throws -> SearchResult {
        try await get("search3", inFolder([
            ("query", query), ("artistCount", "\(artists)"), ("albumCount", "\(albums)"), ("songCount", "\(songs)"),
        ], nil), key: "searchResult3")
    }

    public func starred() async throws -> SearchResult {
        try await get("getStarred2", key: "starred2")
    }

    /// Radio from a song: Octo mixes the library with its own suggestions for a client that
    /// mixes them itself (`octoMix=client`); other servers answer with similar songs.
    public func radio(from songId: String, count: Int = 50) async throws -> [Song] {
        let body: SongsBody = try await get(
            "getSimilarSongs2", [("id", songId), ("count", "\(count)"), ("octoMix", "client")], key: "similarSongs2",
            timeout: 120)
        return body.song
    }

    public func randomSongs(count: Int = 50) async throws -> [Song] {
        let body: SongsBody = try await get("getRandomSongs", [("size", "\(count)")], key: "randomSongs")
        return body.song
    }

    /// Hearts a song. On Octo, hearting a song found online also brings it into the library.
    /// One song by its id.
    public func song(_ id: String) async throws -> Song {
        try await get("getSong", [("id", id)], key: "song")
    }

    public func star(songId: String) async throws { try await call("star", [("id", songId)]) }
    public func unstar(songId: String) async throws { try await call("unstar", [("id", songId)]) }
    public func star(albumId: String) async throws { try await call("star", [("albumId", albumId)]) }
    public func unstar(albumId: String) async throws { try await call("unstar", [("albumId", albumId)]) }

    /// Now playing (`submission` false) or a finished play (true). `time` is when it started.
    public func scrobble(_ songId: String, submission: Bool, at time: Date) async throws {
        try await call("scrobble", [
            ("id", songId), ("submission", submission ? "true" : "false"),
            ("time", "\(Int64(time.timeIntervalSince1970 * 1000))"),
        ])
    }

    /// The address the player streams a song from. Signed fresh each time.
    public func streamURL(for song: Song, quality: StreamQuality) -> URL {
        let suffix = song.suffix?.lowercased() ?? ""
        let playable = song.isExternal || suffix.isEmpty || Self.playableSuffixes.contains(suffix)
        switch quality {
        case .original where playable:
            return url("stream", [("id", song.id), ("format", "raw")])
        case .original:
            return url("stream", [("id", song.id), ("format", "mp3"), ("maxBitRate", "320"), ("estimateContentLength", "true")])
        case .mp3(let kbps):
            // A lossy file already under the cap goes as it is.
            if playable, let rate = song.bitRate, rate > 0, rate <= kbps, suffix != "flac", suffix != "wav", suffix != "alac" {
                return url("stream", [("id", song.id), ("format", "raw")])
            }
            return url("stream", [("id", song.id), ("format", "mp3"), ("maxBitRate", "\(kbps)"), ("estimateContentLength", "true")])
        }
    }

    /// A cover at one of the sizes the other apps ask for (150, 300, 600, 1200), so the
    /// server's own cache answers.
    public func coverURL(_ coverId: String, size: Int) -> URL {
        let step = [150, 300, 600, 1200].first { $0 >= size } ?? 1200
        return url("getCoverArt", [("id", coverId), ("size", "\(step)")])
    }
}

struct AlbumListBody: Decodable {
    let album: [Album]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        album = (try? c.decodeIfPresent([Album].self, forKey: AnyKey("album"))) ?? []
    }
}

struct ArtistsBody: Decodable {
    struct Index: Decodable {
        let artist: [Artist]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            artist = (try? c.decodeIfPresent([Artist].self, forKey: AnyKey("artist"))) ?? []
        }
    }
    let index: [Index]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        index = (try? c.decodeIfPresent([Index].self, forKey: AnyKey("index"))) ?? []
    }
}

struct SongsBody: Decodable {
    let song: [Song]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        song = (try? c.decodeIfPresent([Song].self, forKey: AnyKey("song"))) ?? []
    }
}

struct PlaylistsBody: Decodable {
    let playlist: [Playlist]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        playlist = (try? c.decodeIfPresent([Playlist].self, forKey: AnyKey("playlist"))) ?? []
    }
}

struct TokenInfo: Decodable {
    let username: String
}

/// One ranked song in a chart or an artist's top songs. A song the library has comes as the
/// library's song; any other is one found online, marked isExternal.
public struct TopSong: Decodable, Sendable, Identifiable {
    public var rank: Int
    public var plays: Int?
    public var inLibrary: Bool
    public var song: Song?
    public var id: String { song?.id ?? "rank-\(rank)" }

    enum CodingKeys: String, CodingKey { case rank, plays, inLibrary, song }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = c.int(.rank) ?? 0
        plays = c.int(.plays)
        inLibrary = c.bool(.inLibrary) ?? false
        song = try? c.decodeIfPresent(Song.self, forKey: .song)
    }
}

/// A ranked list: an artist's, or a chart with its name and country.
public struct TopSongs: Decodable, Sendable {
    public var artist: String?
    public var source: String
    public var chart: String?
    public var name: String?
    public var country: String?
    public var entry: [TopSong]

    enum CodingKeys: String, CodingKey { case artist, source, chart, name, country, entry }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = c.string(.artist)
        source = c.string(.source) ?? ""
        chart = c.string(.chart)
        name = c.string(.name)
        country = c.string(.country)
        entry = (try? c.decodeIfPresent([TopSong].self, forKey: .entry)) ?? []
    }

    public var songs: [Song] { entry.compactMap(\.song) }
}

/// An internet radio station. On Octo each station is also a read-only playlist of its songs.
public struct RadioStation: Decodable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var streamUrl: String?
    public var coverArt: String?
    public var homePageUrl: String?

    enum CodingKeys: String, CodingKey { case id, name, streamUrl, coverArt, homePageUrl }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        streamUrl = c.string(.streamUrl)
        coverArt = c.string(.coverArt)
        homePageUrl = c.string(.homePageUrl)
    }
}

struct StationsBody: Decodable {
    let internetRadioStation: [RadioStation]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        internetRadioStation = (try? c.decodeIfPresent([RadioStation].self, forKey: AnyKey("internetRadioStation"))) ?? []
    }
}

/// The chart ids getTopChart takes: the overall chart, Best New Songs, Trending; any other is
/// an Apple genre's number.
public enum Charts {
    public static let overall = "34"
    public static let newSongs = "new"
    public static let trending = "trending"
}

extension SubsonicClient {
    /// A chart from Octo (octoTopSongs; version 2 takes a chart id).
    public func topChart(count: Int = 20, chart: String? = nil) async throws -> TopSongs {
        var params = [("count", "\(count)")]
        if let chart { params.append(("chart", chart)) }
        return try await get("getTopChart", params, key: "topSongs")
    }

    /// The most played songs of an artist, ranked by the server's source.
    public func artistTopSongs(artist: String, id: String?, count: Int = 20) async throws -> TopSongs {
        var params = [("artist", artist), ("count", "\(count)")]
        if let id { params.append(("id", id)) }
        return try await get("getArtistTopSongs", params, key: "topSongs")
    }

    /// Octo builds its stations the first time they are asked for after it starts, so this may
    /// take minutes.
    public func stations() async throws -> [RadioStation] {
        let body: StationsBody = try await get("getInternetRadioStations", key: "internetRadioStations", timeout: 180)
        return body.internetRadioStation
    }
}

/// One line of lyrics; `start` is in milliseconds when the lyrics are synced.
public struct LyricsLine: Decodable, Sendable, Equatable {
    public var start: Int?
    public var value: String

    enum CodingKeys: String, CodingKey { case start, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.int(.start)
        value = c.string(.value) ?? ""
    }

    public init(start: Int? = nil, value: String = "") {
        self.start = start
        self.value = value
    }
}

/// A song's lyrics as an OpenSubsonic server sends them (songLyrics). There can be several:
/// synced and plain, other languages, and with version 2 a translation or pronunciation beside
/// the main one.
public struct StructuredLyrics: Decodable, Sendable, Equatable {
    public var lang: String?
    public var synced: Bool
    /// Milliseconds the words show sooner than their stamps say. It follows the LRC offset tag:
    /// above zero, the words come sooner. A fraction is rounded to the nearest millisecond, a
    /// half up.
    public var offset: Int
    public var line: [LyricsLine]
    public var displayArtist: String?
    public var displayTitle: String?
    /// "main", "translation" or "pronunciation". Missing means main.
    public var kind: String?
    /// Who sings, when the lines are split between voices.
    public var agents: [LyricsAgent]
    /// Word timings, one or more per line, matched to a line by its index.
    public var cueLine: [CueLine]

    enum CodingKeys: String, CodingKey { case lang, synced, offset, line, displayArtist, displayTitle, kind, agents, cueLine }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lang = c.string(.lang)
        synced = c.bool(.synced) ?? false
        if let whole = try? c.decodeIfPresent(Int.self, forKey: .offset) {
            offset = whole
        } else if let ms = try? c.decodeIfPresent(Double.self, forKey: .offset), ms.isFinite {
            offset = roundToLong(ms)
        } else {
            offset = c.int(.offset) ?? 0
        }
        line = (try? c.decodeIfPresent([LyricsLine].self, forKey: .line)) ?? []
        displayArtist = c.string(.displayArtist)
        displayTitle = c.string(.displayTitle)
        kind = c.string(.kind)
        agents = (try? c.decodeIfPresent([LyricsAgent].self, forKey: .agents)) ?? []
        cueLine = (try? c.decodeIfPresent([CueLine].self, forKey: .cueLine)) ?? []
    }

    public init(
        lang: String? = "und",
        synced: Bool = false,
        line: [LyricsLine] = [],
        displayArtist: String? = nil,
        displayTitle: String? = nil,
        offset: Int = 0,
        kind: String? = nil,
        agents: [LyricsAgent] = [],
        cueLine: [CueLine] = []
    ) {
        self.lang = lang
        self.synced = synced
        self.line = line
        self.displayArtist = displayArtist
        self.displayTitle = displayTitle
        self.offset = offset
        self.kind = kind
        self.agents = agents
        self.cueLine = cueLine
    }

    /// The line sung at `seconds`, for synced lyrics: the last one that has started.
    public func lineIndex(at seconds: Double) -> Int? {
        guard synced else { return nil }
        let ms = Int(seconds * 1000) + offset
        let found = line.map { LyricLine(startMs: $0.start ?? .max, text: $0.value) }.lineAt(ms)
        return found >= 0 ? found : nil
    }
}

/// One voice in lyrics split between voices.
public struct LyricsAgent: Decodable, Sendable, Equatable {
    public var id: String
    /// "main", "voice" (another singer), "bg" (backing vocals) or "group".
    public var role: String
    public var name: String?

    enum CodingKeys: String, CodingKey { case id, role, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        role = c.string(.role) ?? "main"
        name = c.string(.name)
    }

    public init(id: String = "", role: String = "main", name: String? = nil) {
        self.id = id
        self.role = role
        self.name = name
    }
}

/// The word timings of one lyric line, or of one voice in it.
public struct CueLine: Decodable, Sendable, Equatable {
    public var index: Int
    public var agentId: String?
    public var start: Int?
    public var end: Int?
    public var value: String
    public var cue: [Cue]

    enum CodingKeys: String, CodingKey { case index, agentId, start, end, value, cue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = c.int(.index) ?? 0
        agentId = c.string(.agentId)
        start = c.int(.start)
        end = c.int(.end)
        value = c.string(.value) ?? ""
        cue = (try? c.decodeIfPresent([Cue].self, forKey: .cue)) ?? []
    }

    public init(index: Int = 0, agentId: String? = nil, start: Int? = nil, end: Int? = nil, value: String = "", cue: [Cue] = []) {
        self.index = index
        self.agentId = agentId
        self.start = start
        self.end = end
        self.value = value
        self.cue = cue
    }
}

/// One timed word or syllable. Its place in the cue line's value is given in UTF-8 bytes, both
/// ends included, not in characters.
public struct Cue: Decodable, Sendable, Equatable {
    public var start: Int
    public var end: Int?
    public var value: String
    public var byteStart: Int
    public var byteEnd: Int

    enum CodingKeys: String, CodingKey { case start, end, value, byteStart, byteEnd }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = c.int(.start) ?? 0
        end = c.int(.end)
        value = c.string(.value) ?? ""
        byteStart = c.int(.byteStart) ?? 0
        byteEnd = c.int(.byteEnd) ?? 0
    }

    public init(start: Int = 0, end: Int? = nil, value: String = "", byteStart: Int = 0, byteEnd: Int = 0) {
        self.start = start
        self.end = end
        self.value = value
        self.byteStart = byteStart
        self.byteEnd = byteEnd
    }
}

struct LyricsListBody: Decodable {
    let structuredLyrics: [StructuredLyrics]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        structuredLyrics = (try? c.decodeIfPresent([StructuredLyrics].self, forKey: AnyKey("structuredLyrics"))) ?? []
    }
}

extension SubsonicClient {
    /// A song's lyrics as plain lines: the main lyrics, synced ones first and word-timed ones
    /// before those, with the offset already in every start.
    public func lyrics(songId: String) async throws -> StructuredLyrics? {
        try await songLyrics(songId: songId, language: nil).map(StructuredLyrics.init(lyrics:))
    }

    /// A song's lyrics from the server, word cues, backing vocals and voices included, with a
    /// translation into `language` beside each line when the server has one and the song is
    /// sung in another language. Nil when the server has nothing to show.
    public func songLyrics(songId: String, language: String?) async throws -> Lyrics? {
        let body: LyricsListBody = try await get("getLyricsBySongId", [("id", songId)], key: "lyricsList")
        return serverLyrics(body.structuredLyrics, language: language)
    }

    public func createPlaylist(name: String, songIds: [String]) async throws {
        try await call("createPlaylist", [("name", name)] + songIds.map { ("songId", $0) })
    }
}
