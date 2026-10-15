import Foundation

/// How many songs or albums each request asks for when reading everything.
public let libraryPage = 500

/// How many albums are asked for at once when songs are read album by album.
private let albumsAtOnce = 4

extension SubsonicClient {
    /// Every album, a page in alphabetical order, in one music folder when one is chosen.
    public func fullAlbumPage(size: Int, offset: Int, folder: String? = nil) async throws -> [ServerAlbum] {
        let body = try await get(
            "getAlbumList2", inFolder([("type", "alphabeticalByName"), ("size", "\(size)"), ("offset", "\(offset)")], folder),
            key: nil, as: Lenient<AlbumList2Key, FullAlbumList>.self, timeout: 120)
        return body.value?.album ?? []
    }

    /// One album with its songs, as fully as the server says.
    public func fullAlbum(_ id: String) async throws -> ServerAlbum {
        try await get("getAlbum", [("id", id)], key: "album", timeout: 60)
    }

    /// One song, as fully as the server says.
    public func fullSong(_ id: String) async throws -> ServerSong {
        try await get("getSong", [("id", id)], key: "song")
    }

    /// Every artist the server lists.
    public func fullArtists(folder: String? = nil) async throws -> [ServerArtist] {
        let body = try await get("getArtists", inFolder([], folder), key: nil, as: Lenient<ArtistsKey, FullArtists>.self,
                                 timeout: 120)
        return body.value?.index.flatMap(\.artist) ?? []
    }

    /// A page of every song: an empty search, which most servers answer with everything.
    public func songPage(size: Int, offset: Int, folder: String? = nil) async throws -> [ServerSong] {
        let body = try await get("search3", inFolder([
            ("query", ""), ("artistCount", "0"), ("albumCount", "0"), ("songCount", "\(size)"), ("songOffset", "\(offset)"),
        ], folder), key: nil, as: Lenient<SearchResult3Key, FullSearch>.self, timeout: 120)
        return body.value?.song ?? []
    }

    /// The params with the music folder asked for, else the one the client is limited to, when
    /// there is one.
    func inFolder(_ params: [(String, String)], _ folder: String?) -> [(String, String)] {
        guard let folder = folder ?? musicFolderId else { return params }
        return params + [("musicFolderId", folder)]
    }

    /// Reads the whole library in pages. Songs come from an empty search where the server allows
    /// one, and otherwise album by album. Anything listed twice is kept once, and songs the server
    /// marks as outside the library are left out. Albums, artists and songs are read side by side.
    public func readLibrary(page: Int = libraryPage, folder: String? = nil) async throws -> ServerLibrary {
        async let albumsRead = Self.pages(page) { offset in try await self.fullAlbumPage(size: page, offset: offset, folder: folder) }
        async let artistsRead = fullArtists(folder: folder)
        let listed = try await Self.pages(page) { offset in try await self.songPage(size: page, offset: offset, folder: folder) }
        var seenAlbums = Set<String>()
        let albums = try await albumsRead.filter { seenAlbums.insert($0.id).inserted }
        let read = listed.isEmpty ? try await songsByAlbum(albums) : listed
        var seenSongs = Set<String>()
        let songs = read.filter { !$0.isExternal && seenSongs.insert($0.id).inserted }
        var seenArtists = Set<String>()
        let artists = try await artistsRead.filter { seenArtists.insert($0.id).inserted }
        return ServerLibrary(songs, albums, artists)
    }

    /// Asks for page after page until one comes back short.
    static func pages<T: Sendable>(_ size: Int, _ fetch: @Sendable (Int) async throws -> [T]) async throws -> [T] {
        var all: [T] = []
        while true {
            let page = try await fetch(all.count)
            all += page
            if page.count < size { return all }
        }
    }

    private func songsByAlbum(_ albums: [ServerAlbum]) async throws -> [ServerSong] {
        var songs: [ServerSong] = []
        for start in stride(from: 0, to: albums.count, by: albumsAtOnce) {
            let batch = albums[start..<min(start + albumsAtOnce, albums.count)].map(\.id)
            let found = try await withThrowingTaskGroup(of: (Int, [ServerSong]).self) { group in
                for (index, id) in batch.enumerated() {
                    group.addTask {
                        // An album removed since the list was read is simply skipped.
                        do {
                            return (index, try await self.fullAlbum(id).song)
                        } catch OctoError.notFound {
                            return (index, [])
                        }
                    }
                }
                var parts = [[ServerSong]](repeating: [], count: batch.count)
                for try await (index, part) in group { parts[index] = part }
                return parts.flatMap { $0 }
            }
            songs += found
        }
        return songs
    }
}

struct FullAlbumList: Decodable {
    let album: [ServerAlbum]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        album = (try? c.decodeIfPresent([ServerAlbum].self, forKey: AnyKey("album"))) ?? []
    }
}

struct FullArtists: Decodable {
    struct Index: Decodable {
        let artist: [ServerArtist]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: AnyKey.self)
            artist = (try? c.decodeIfPresent([ServerArtist].self, forKey: AnyKey("artist"))) ?? []
        }
    }
    let index: [Index]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        index = (try? c.decodeIfPresent([Index].self, forKey: AnyKey("index"))) ?? []
    }
}

struct FullSearch: Decodable {
    let artist: [ServerArtist]
    let album: [ServerAlbum]
    let song: [ServerSong]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        artist = (try? c.decodeIfPresent([ServerArtist].self, forKey: AnyKey("artist"))) ?? []
        album = (try? c.decodeIfPresent([ServerAlbum].self, forKey: AnyKey("album"))) ?? []
        song = (try? c.decodeIfPresent([ServerSong].self, forKey: AnyKey("song"))) ?? []
    }
}

/// The name an answer's payload goes under.
protocol PayloadName { static var name: String { get } }

enum AlbumList2Key: PayloadName { static let name = "albumList2" }
enum ArtistsKey: PayloadName { static let name = "artists" }
enum SearchResult3Key: PayloadName { static let name = "searchResult3" }

/// A payload that may be missing from an answer, read as nil rather than an error.
struct Lenient<Name: PayloadName, T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        value = try? c.decodeIfPresent(T.self, forKey: AnyKey(Name.name))
    }
}
