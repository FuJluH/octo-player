import Foundation

// The server calls behind the library pages, and what they read beside the plain models.

/// What a song's listing says beyond `Song`: when it came in and was last played, how often,
/// the listener's rating, every genre, and the rest an OpenSubsonic server adds.
public struct SongExtras: Decodable, Sendable, Hashable {
    public var created: String?
    public var played: String?
    public var playCount: Int?
    public var userRating: Int?
    public var genres: [String]
    public var albumArtist: String?
    public var sortName: String?
    public var musicBrainzId: String?
    public var bpm: Int?
    public var comment: String?
    public var composer: String?
    public var isrc: [String]
    public var size: Int64?
    public var path: String?
    public var personal: Bool

    enum CodingKeys: String, CodingKey {
        case created, played, playCount, userRating, genres, albumArtists, displayAlbumArtist, sortName, musicBrainzId, bpm
        case comment, displayComposer, isrc, size, path, octoPersonal
    }

    private struct Named: Decodable { let name: String? }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        created = c.string(.created)
        played = c.string(.played)
        playCount = c.int(.playCount)
        userRating = c.int(.userRating)
        if let named = try? c.decodeIfPresent([Named].self, forKey: .genres) {
            genres = named.compactMap(\.name).filter { !$0.isEmpty }
        } else {
            genres = (try? c.decodeIfPresent([String].self, forKey: .genres)) ?? []
        }
        let albumArtists = (try? c.decodeIfPresent([Named].self, forKey: .albumArtists))?.compactMap(\.name) ?? []
        albumArtist = c.string(.displayAlbumArtist) ?? (albumArtists.isEmpty ? nil : albumArtists.joined(separator: ", "))
        sortName = c.string(.sortName)
        musicBrainzId = c.string(.musicBrainzId)
        bpm = c.int(.bpm)
        comment = c.string(.comment)
        composer = c.string(.displayComposer)
        if let many = try? c.decodeIfPresent([String].self, forKey: .isrc) {
            isrc = many
        } else {
            isrc = c.string(.isrc).map { [$0] } ?? []
        }
        size = c.int(.size).map(Int64.init)
        path = c.string(.path)
        personal = c.bool(.octoPersonal) ?? false
    }
}

/// A song as a library listing gives it: the song and what is said beside it.
public struct ListedSong: Decodable, Sendable {
    public var song: Song
    public var extras: SongExtras

    public init(from decoder: Decoder) throws {
        song = try Song(from: decoder)
        extras = try SongExtras(from: decoder)
    }
}

/// What an album's listing says beyond `Album`.
public struct AlbumExtras: Decodable, Sendable, Hashable {
    public var created: String?
    public var played: String?
    public var playCount: Int?
    public var releaseTypes: [String]
    public var sortName: String?
    public var discTitles: [Int: String]
    public var genres: [String]

    enum CodingKeys: String, CodingKey { case created, played, playCount, releaseTypes, sortName, discTitles, genres }

    private struct Named: Decodable { let name: String? }
    private struct DiscTitle: Decodable {
        let disc: Int?
        let title: String?
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        created = c.string(.created)
        played = c.string(.played)
        playCount = c.int(.playCount)
        if let many = try? c.decodeIfPresent([String].self, forKey: .releaseTypes) {
            releaseTypes = many
        } else {
            releaseTypes = c.string(.releaseTypes).map { [$0] } ?? []
        }
        sortName = c.string(.sortName)
        var titles: [Int: String] = [:]
        for disc in (try? c.decodeIfPresent([DiscTitle].self, forKey: .discTitles)) ?? [] {
            if let number = disc.disc, let title = disc.title, !title.isEmpty { titles[number] = title }
        }
        discTitles = titles
        if let named = try? c.decodeIfPresent([Named].self, forKey: .genres) {
            genres = named.compactMap(\.name)
        } else {
            genres = []
        }
    }
}

/// An album as a listing gives it, with its songs when the listing is `getAlbum`.
public struct ListedAlbum: Decodable, Sendable {
    public var album: Album
    public var extras: AlbumExtras
    public var songs: [ListedSong]

    private enum Keys: String, CodingKey { case song }

    public init(from decoder: Decoder) throws {
        album = try Album(from: decoder)
        extras = try AlbumExtras(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        songs = (try? c.decodeIfPresent([ListedSong].self, forKey: .song)) ?? []
    }
}

/// A playlist's listing with its dates.
public struct ListedPlaylist: Decodable, Sendable {
    public var playlist: Playlist
    public var created: String?
    public var changed: String?
    public var songs: [ListedSong]

    private enum Keys: String, CodingKey { case created, changed, entry }

    public init(from decoder: Decoder) throws {
        playlist = try Playlist(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        created = c.string(.created)
        changed = c.string(.changed)
        songs = (try? c.decodeIfPresent([ListedSong].self, forKey: .entry)) ?? []
    }
}

/// A genre as the server lists it.
public struct ListedGenre: Decodable, Sendable, Hashable {
    public var name: String
    public var songCount: Int
    public var albumCount: Int

    enum CodingKeys: String, CodingKey { case value, songCount, albumCount }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.string(.value) ?? ""
        songCount = c.int(.songCount) ?? 0
        albumCount = c.int(.albumCount) ?? 0
    }
}

/// What the server says about an artist: the biography and artists like them.
public struct ArtistAbout: Decodable, Sendable {
    public struct Similar: Decodable, Sendable, Hashable {
        public var id: String
        public var name: String
        public var coverArt: String?
        public var artistImageUrl: String?

        enum CodingKeys: String, CodingKey { case id, name, coverArt, artistImageUrl }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.string(.id) ?? ""
            name = c.string(.name) ?? ""
            coverArt = c.string(.coverArt)
            artistImageUrl = c.string(.artistImageUrl)
        }
    }

    public var biography: String?
    public var similarArtist: [Similar]

    enum CodingKeys: String, CodingKey { case biography, similarArtist }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        biography = c.string(.biography)
        similarArtist = (try? c.decodeIfPresent([Similar].self, forKey: .similarArtist)) ?? []
    }
}

/// A shared link the server made.
public struct ShareLink: Decodable, Sendable {
    public var id: String
    public var url: String

    enum CodingKeys: String, CodingKey { case id, url }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        url = c.string(.url) ?? ""
    }
}

/// A folder on the server, as its folder calls list it.
public struct ServerFolderRef: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var coverArt: String?
    public var songCount: Int?

    public init(id: String, name: String, coverArt: String? = nil, songCount: Int? = nil) {
        self.id = id
        self.name = name
        self.coverArt = coverArt
        self.songCount = songCount
    }
}

/// One folder's insides: the folders in it and its songs, in the server's order.
public struct ServerFolderListing: Sendable {
    public var folders: [ServerFolderRef]
    public var songs: [ListedSong]
}

/// What the server lets the signed-in user do to the library's files.
public struct FileActions: Decodable, Sendable, Equatable {
    public var enabled: Bool
    public var allowed: Bool
    public var dryRun: Bool
    public var actions: [String]
    public var keepDays: Int
    public var upgradeSource: String?
    public var admin: Bool

    enum CodingKeys: String, CodingKey { case enabled, allowed, dryRun, actions, keepDays, upgradeSource, admin }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = c.bool(.enabled) ?? false
        allowed = c.bool(.allowed) ?? false
        dryRun = c.bool(.dryRun) ?? true
        actions = (try? c.decodeIfPresent([String].self, forKey: .actions)) ?? []
        keepDays = c.int(.keepDays) ?? 0
        upgradeSource = c.string(.upgradeSource)
        admin = c.bool(.admin) ?? true
    }

    public init(enabled: Bool = false, allowed: Bool = false, dryRun: Bool = true, actions: [String] = [], keepDays: Int = 0,
                upgradeSource: String? = nil, admin: Bool = true) {
        self.enabled = enabled
        self.allowed = allowed
        self.dryRun = dryRun
        self.actions = actions
        self.keepDays = keepDays
        self.upgradeSource = upgradeSource
        self.admin = admin
    }

    private var real: Bool { enabled && allowed && admin && !dryRun }
    public var canRemove: Bool { real && actions.contains("remove") }
    public var canRestore: Bool { real && actions.contains("restore") }
    public var canEdit: Bool { real && actions.contains("retag") && actions.contains("undo") }
    public var canJoinAlbums: Bool { real && actions.contains("joinAlbum") }
    public var canLookUp: Bool { real && actions.contains("lookup") }
    public var canAddCover: Bool { real && actions.contains("cover") }
    public var canUpgrade: Bool { enabled && allowed && !dryRun && actions.contains("upgrade") }
}

/// How one file action went, as the server tells it.
public struct FileActionResult: Decodable, Sendable {
    public var id: String
    public var action: String
    public var state: String
    public var detail: String?

    enum CodingKeys: String, CodingKey { case id, action, state, detail }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        action = c.string(.action) ?? ""
        state = c.string(.state) ?? ""
        detail = c.string(.detail)
    }
}

/// The extension an Octo server lists when it can act on the library's files.
public let octoLibraryActions = "octoLibraryActions"

/// Reads an ISO date as the server writes it, in milliseconds since 1970.
public func serverDateMs(_ text: String?) -> Int64? {
    guard let text, !text.isEmpty else { return nil }
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = parser.date(from: text) { return Int64(date.timeIntervalSince1970 * 1_000) }
    parser.formatOptions = [.withInternetDateTime]
    if let date = parser.date(from: text) { return Int64(date.timeIntervalSince1970 * 1_000) }
    return nil
}

private struct ListedSongs: Decodable {
    let song: [ListedSong]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        song = (try? c.decodeIfPresent([ListedSong].self, forKey: AnyKey("song"))) ?? []
    }
}

private struct ListedAlbums: Decodable {
    let album: [ListedAlbum]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        album = (try? c.decodeIfPresent([ListedAlbum].self, forKey: AnyKey("album"))) ?? []
    }
}

private struct ListedPlaylists: Decodable {
    let playlist: [ListedPlaylist]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        playlist = (try? c.decodeIfPresent([ListedPlaylist].self, forKey: AnyKey("playlist"))) ?? []
    }
}

private struct Genres: Decodable {
    let genre: [ListedGenre]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        genre = (try? c.decodeIfPresent([ListedGenre].self, forKey: AnyKey("genre"))) ?? []
    }
}

private struct CreatedPlaylist: Decodable {
    let playlist: ListedPlaylist?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        playlist = try? c.decodeIfPresent(ListedPlaylist.self, forKey: AnyKey("playlist"))
    }
}

private struct Shares: Decodable {
    let share: [ShareLink]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        share = (try? c.decodeIfPresent([ShareLink].self, forKey: AnyKey("share"))) ?? []
    }
}

private struct StarredLists: Decodable {
    let song: [ListedSong]
    let album: [ListedAlbum]
    let artist: [Artist]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        song = (try? c.decodeIfPresent([ListedSong].self, forKey: AnyKey("song"))) ?? []
        album = (try? c.decodeIfPresent([ListedAlbum].self, forKey: AnyKey("album"))) ?? []
        artist = (try? c.decodeIfPresent([Artist].self, forKey: AnyKey("artist"))) ?? []
    }
}

/// The songs, albums and artists the listener hearted.
public struct StarredItems: Sendable {
    public var songs: [ListedSong]
    public var albums: [ListedAlbum]
    public var artists: [Artist]
}

/// A folder listing's raw children, split into folders and songs.
private struct DirectoryBody: Decodable {
    let children: [Child]

    struct Child: Decodable {
        let isDir: Bool
        let ref: ServerFolderRef?
        let song: ListedSong?

        private enum Keys: String, CodingKey { case isDir, id, title, name, coverArt, songCount }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            isDir = c.bool(.isDir) ?? false
            if isDir, let id = c.string(.id) {
                ref = ServerFolderRef(id: id, name: c.string(.title) ?? c.string(.name) ?? "", coverArt: c.string(.coverArt),
                                      songCount: c.int(.songCount))
                song = nil
            } else {
                ref = nil
                song = try? ListedSong(from: decoder)
            }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        children = (try? c.decodeIfPresent([Child].self, forKey: AnyKey("child"))) ?? []
    }
}

private struct IndexesBody: Decodable {
    let folders: [ServerFolderRef]
    let songs: [ListedSong]

    private struct Index: Decodable {
        let artist: [Ref]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            artist = (try? c.decodeIfPresent([Ref].self, forKey: AnyKey("artist"))) ?? []
        }
    }

    private struct Ref: Decodable {
        let ref: ServerFolderRef?
        private enum Keys: String, CodingKey { case id, name, coverArt }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            ref = c.string(.id).map { ServerFolderRef(id: $0, name: c.string(.name) ?? "", coverArt: c.string(.coverArt)) }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        let indexes = (try? c.decodeIfPresent([Index].self, forKey: AnyKey("index"))) ?? []
        let loose = (try? DirectoryBody(from: decoder))?.children ?? []
        folders = indexes.flatMap { $0.artist.compactMap(\.ref) } + loose.compactMap(\.ref)
        songs = loose.compactMap(\.song)
    }
}

extension SubsonicClient {
    /// One page of every song on the server: an empty search matches everything on servers that
    /// allow it; others answer with nothing.
    public func songPage(size: Int, offset: Int) async throws -> [ListedSong] {
        let body: ListedSongs = try await get("search3", [
            ("query", ""), ("artistCount", "0"), ("albumCount", "0"), ("songCount", "\(size)"), ("songOffset", "\(offset)"),
        ], key: "searchResult3")
        return body.song
    }

    /// Every song on the server, a page at a time; album by album when the empty search finds
    /// nothing. Songs listed twice are kept once and songs outside the library are left out.
    public func everySong(albums: [ListedAlbum], page: Int = 500) async throws -> [ListedSong] {
        var all: [ListedSong] = []
        while true {
            let next = try await songPage(size: page, offset: all.count)
            all += next
            if next.count < page { break }
        }
        if all.isEmpty {
            for album in albums {
                if let full = try? await listedAlbum(album.album.id) { all += full.songs }
            }
        }
        var seen = Set<String>()
        return all.filter { !$0.song.isExternal && seen.insert($0.song.id).inserted }
    }

    /// Every album on the server, a page at a time, each once.
    public func everyAlbum(page: Int = 500) async throws -> [ListedAlbum] {
        var all: [ListedAlbum] = []
        while true {
            let body: ListedAlbums = try await get(
                "getAlbumList2", [("type", "alphabeticalByName"), ("size", "\(page)"), ("offset", "\(all.count)")], key: "albumList2")
            all += body.album
            if body.album.count < page { break }
        }
        var seen = Set<String>()
        return all.filter { seen.insert($0.album.id).inserted }
    }

    /// Albums of one kind of list, with what their listing says.
    public func listedAlbums(_ type: String, size: Int, offset: Int = 0, extra: [(String, String)] = []) async throws -> [ListedAlbum] {
        let body: ListedAlbums = try await get(
            "getAlbumList2", [("type", type), ("size", "\(size)"), ("offset", "\(offset)")] + extra, key: "albumList2")
        return body.album
    }

    /// One album with its songs and what their listings say.
    public func listedAlbum(_ id: String) async throws -> ListedAlbum {
        try await get("getAlbum", [("id", id)], key: "album")
    }

    public func listedPlaylists() async throws -> [ListedPlaylist] {
        let body: ListedPlaylists = try await get("getPlaylists", key: "playlists")
        return body.playlist
    }

    public func listedPlaylist(_ id: String) async throws -> ListedPlaylist {
        try await get("getPlaylist", [("id", id)], key: "playlist")
    }

    public func starredItems() async throws -> StarredItems {
        let body: StarredLists = try await get("getStarred2", key: "starred2")
        return StarredItems(songs: body.song, albums: body.album, artists: body.artist)
    }

    public func genreList() async throws -> [ListedGenre] {
        let body: Genres = try await get("getGenres", key: "genres")
        return body.genre
    }

    /// An artist's biography and artists like them.
    public func artistAbout(_ id: String, similar: Int = 20) async throws -> ArtistAbout {
        try await get("getArtistInfo2", [("id", id), ("count", "\(similar)")], key: "artistInfo2")
    }

    /// Stars songs, albums or artists for the signed-in user. Several go in one call.
    public func setStarred(_ on: Bool, songIds: [String] = [], albumIds: [String] = [], artistIds: [String] = []) async throws {
        let params = songIds.map { ("id", $0) } + albumIds.map { ("albumId", $0) } + artistIds.map { ("artistId", $0) }
        guard !params.isEmpty else { return }
        try await call(on ? "star" : "unstar", params)
    }

    /// Rates a song for the signed-in user, 1 to 5 stars; 0 takes the rating off.
    public func rate(songId: String, rating: Int) async throws {
        try await call("setRating", [("id", songId), ("rating", "\(min(max(rating, 0), 5))")])
    }

    /// Makes a playlist with these songs in this order, and answers with it as the server now
    /// has it, when it says.
    public func makePlaylist(name: String, songIds: [String]) async throws -> ListedPlaylist? {
        let body: CreatedPlaylist = try await get("createPlaylist", [("name", name)] + songIds.map { ("songId", $0) }, key: nil)
        return body.playlist
    }

    /// Makes a playlist's songs exactly these, in this order.
    public func replacePlaylistSongs(_ id: String, songIds: [String]) async throws {
        try await call("createPlaylist", [("playlistId", id)] + songIds.map { ("songId", $0) })
    }

    /// Changes a playlist's name, takes songs out by their place and adds songs to the end.
    public func changePlaylist(_ id: String, name: String? = nil, add: [String] = [], removeAt: [Int] = []) async throws {
        var params: [(String, String)] = [("playlistId", id)]
        if let name { params.append(("name", name)) }
        params += add.map { ("songIdToAdd", $0) }
        params += removeAt.map { ("songIndexToRemove", "\($0)") }
        try await call("updatePlaylist", params)
    }

    public func removePlaylist(_ id: String) async throws {
        try await call("deletePlaylist", [("id", id)])
    }

    /// Makes a public link to songs or an album. `expiresAtMs` nil never expires.
    public func makeShareLink(ids: [String], description: String?, expiresAtMs: Int64?) async throws -> ShareLink {
        var params = ids.map { ("id", $0) }
        if let description { params.append(("description", description)) }
        if let expiresAtMs { params.append(("expires", "\(expiresAtMs)")) }
        let body: Shares = try await get("createShare", params, key: "shares")
        guard let share = body.share.first else { throw OctoError.server(code: 0, message: "The server made no share") }
        return share
    }

    /// The server's folders from the top: its music folders' indexes, then loose songs.
    public func folderTop() async throws -> ServerFolderListing {
        let body: IndexesBody = try await get("getIndexes", key: "indexes")
        return ServerFolderListing(folders: body.folders, songs: body.songs)
    }

    /// One folder on the server and what it holds.
    public func folder(_ id: String) async throws -> ServerFolderListing {
        let body: DirectoryBody = try await get("getMusicDirectory", [("id", id)], key: "directory")
        return ServerFolderListing(folders: body.children.compactMap(\.ref), songs: body.children.compactMap(\.song))
    }

    /// What the signed-in user may do to the library's files.
    public func fileActions() async throws -> FileActions {
        try await get("getLibraryActions", key: "libraryActions")
    }

    /// Asks the server to act on one library song's file: "remove" moves it into the server's
    /// trash, "upgrade" queues a look for a lossless copy.
    public func fileAction(_ id: String, action: String, with extra: [(String, String)] = []) async throws -> FileActionResult {
        try await get("libraryAction", [("id", id), ("action", action)] + extra, key: "libraryAction")
    }
}
