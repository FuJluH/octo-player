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
            extensions: extensions.flatMap { e in e.versions.isEmpty ? ["\(e.name):1"] : e.versions.map { "\(e.name):\($0)" } }
        )
    }

    public func albumList(_ type: AlbumListType, size: Int = 30, offset: Int = 0) async throws -> [Album] {
        let list: AlbumListBody = try await get(
            "getAlbumList2", [("type", type.rawValue), ("size", "\(size)"), ("offset", "\(offset)")], key: "albumList2")
        return list.album
    }

    public func album(_ id: String) async throws -> Album {
        try await get("getAlbum", [("id", id)], key: "album")
    }

    public func artists() async throws -> [Artist] {
        let body: ArtistsBody = try await get("getArtists", key: "artists")
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
        try await get("search3", [
            ("query", query), ("artistCount", "\(artists)"), ("albumCount", "\(albums)"), ("songCount", "\(songs)"),
        ], key: "searchResult3")
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
