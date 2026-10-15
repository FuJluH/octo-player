import Foundation

// What the signed-in server offers beyond the library: songs, albums and artists found online,
// radio from any song, and stations. Songs come back shaped like library songs; one found online
// has an id starting "find:" and plays as a stream.

/// How many artists, albums and songs a search asks the server for. Octo holds back songs found
/// online when a search asks for 12 songs or fewer, so it always asks for more than that.
public let discoverySearchArtists = 10
public let discoverySearchAlbums = 20
public let discoverySearchSongs = 40

/// How many songs a radio plays after the one it started from.
public let discoveryRadioSongs = 50

/// An album on the server, not in the library. `ownedCount` is how many of its songs the library
/// holds, when Octo counted them.
public struct OnlineAlbum: Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String
    public var artistId: String?
    public var year: Int?
    public var songCount: Int
    public var artwork: String?
    public var ownedCount: Int?

    public init(id: String, title: String, artist: String, artistId: String?, year: Int?, songCount: Int, artwork: String?,
                ownedCount: Int? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artistId = artistId
        self.year = year
        self.songCount = songCount
        self.artwork = artwork
        self.ownedCount = ownedCount
    }

    /// A server album as a card shows it, with how much of it the library holds when the server
    /// found it online and counted.
    public init(_ album: Album, sourceId: String) {
        self.init(id: album.id, title: album.name, artist: album.artist, artistId: album.artistId, year: album.year,
                  songCount: album.songCount, artwork: onlineArtwork(sourceId, album.coverArt),
                  ownedCount: album.isExternal ? album.ownedCount : nil)
    }
}

public struct OnlineArtist: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var albumCount: Int
    public var artwork: String?

    public init(id: String, name: String, albumCount: Int, artwork: String?) {
        self.id = id
        self.name = name
        self.albumCount = albumCount
        self.artwork = artwork
    }

    public init(_ artist: Artist, sourceId: String) {
        self.init(id: artist.id, name: artist.name, albumCount: artist.albumCount, artwork: onlineArtwork(sourceId, artist.coverArt))
    }
}

/// A station the server runs, played as the list of songs it has lined up. A Made for you list or
/// a mix is shown and played the same way, with its song count, and `octoGroup` says what kind of
/// list Octo made it. An internet radio station added to the server has its stream instead.
public struct Station: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var artwork: String?
    public var songCount: Int?
    public var streamUrl: String?
    public var octoGroup: String?
    /// An internet radio station's website, when the server has one for it.
    public var homepage: String?

    public init(id: String, name: String, artwork: String?, songCount: Int? = nil, streamUrl: String? = nil, octoGroup: String? = nil,
                homepage: String? = nil) {
        self.id = id
        self.name = name
        self.artwork = artwork
        self.songCount = songCount
        self.streamUrl = streamUrl
        self.octoGroup = octoGroup
        self.homepage = homepage
    }

    /// One of the server's playlists Octo made, its cover drawn from its id when it has none of
    /// its own.
    public init(_ list: Playlist, sourceId: String) {
        self.init(id: list.id, name: list.name, artwork: ArtworkRef.server(sourceId: sourceId, coverId: list.coverArt ?? list.id).encode(),
                  songCount: list.songCount, octoGroup: list.octoGroup)
    }

    /// One of Octo's stations, its cover drawn from its id when it has none of its own.
    public init(_ station: RadioStation, sourceId: String) {
        self.init(id: station.id, name: station.name,
                  artwork: ArtworkRef.server(sourceId: sourceId, coverId: station.coverArt ?? station.id).encode())
    }
}

/// The stations Home shows, from the server's internet radio stations. Octo's own carry their id
/// as their cover and play the songs they have lined up; any other plays its stream, like on the
/// Radio stations screen. An added station with no stream has nothing to play and is left off.
public func homeStations(_ stations: [RadioStation], sourceId: String) -> [Station] {
    stations.compactMap { station in
        if looksGenerated(station, isOcto: true) { return Station(station, sourceId: sourceId) }
        let stream = (station.streamUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stream.isEmpty else { return nil }
        var added = Station(station, sourceId: sourceId)
        added.streamUrl = stream
        let site = (station.homePageUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if site.lowercased().hasPrefix("http://") || site.lowercased().hasPrefix("https://") { added.homepage = site }
        return added
    }
}

/// Octo's own stations among those Home shows, for its Radio shelf: the ones that play the songs
/// they have lined up and keep going.
public func octoRadio(_ stations: [Station]) -> [Station] { stations.filter(stationHasPlayButton) }

/// The internet radio stations added to the server among those Home shows, for its Live radio
/// shelf: the ones that play a stream.
public func internetRadio(_ stations: [Station]) -> [Station] { stations.filter { !stationHasPlayButton($0) } }

/// What a search found beyond the library. `partAlbums` are albums the library holds some of the
/// songs of, kept apart from those it holds none of, so the "Not in your library" title is never
/// over one that partly is.
public struct Discovered: Sendable, Hashable {
    public var songs: [LibraryTrack]
    public var albums: [OnlineAlbum]
    public var artists: [OnlineArtist]
    public var partAlbums: [OnlineAlbum]

    public init(songs: [LibraryTrack], albums: [OnlineAlbum], artists: [OnlineArtist], partAlbums: [OnlineAlbum] = []) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
        self.partAlbums = partAlbums
    }

    public var isEmpty: Bool { notInLibraryEmpty && partAlbums.isEmpty }

    /// Nothing to list under "Not in your library".
    public var notInLibraryEmpty: Bool { songs.isEmpty && albums.isEmpty && artists.isEmpty }
}

public struct OnlineAlbumPage: Sendable, Hashable {
    public var album: OnlineAlbum
    public var songs: [LibraryTrack]

    public init(album: OnlineAlbum, songs: [LibraryTrack]) {
        self.album = album
        self.songs = songs
    }
}

public struct OnlineArtistPage: Sendable, Hashable {
    public var artist: OnlineArtist
    public var albums: [OnlineAlbum]

    public init(artist: OnlineArtist, albums: [OnlineAlbum]) {
        self.artist = artist
        self.albums = albums
    }
}

// MARK: Octo only

/// Whether the server is Octo: its status page answered at sign-in (`probed`), it calls itself
/// Octo, or it lists an Octo extension. The status page only answers at home, so away from home
/// the extensions are what tell.
public func isOctoServer(probed: Bool, serverType: String?, extensions: some Sequence<String>) -> Bool {
    probed || serverType?.lowercased() == "octo" || extensions.contains { $0.hasPrefix("octo") }
}

extension StoredServer {
    /// Whether this server is Octo, which alone runs stations, makes Made for you lists and lists
    /// songs outside the library on a library album.
    public var runsOcto: Bool { isOctoServer(probed: isOcto, serverType: serverType, extensions: extensions) }
}

// MARK: Made for you

/// The lists Octo made for the listener (Liked Songs, New Releases, Rediscover, Deep Cuts), in
/// that order, from the server's playlists. Only an Octo server that makes them marks a playlist
/// so; any other has none.
public func madeForYouLists(_ playlists: [Playlist], sourceId: String) -> [Station] {
    func rank(_ kind: String?) -> Int { kind.flatMap { octoListKinds.firstIndex(of: $0) } ?? octoListKinds.count }
    return playlists.enumerated()
        .filter { $0.element.octoList != nil }
        .sorted { a, b in
            let ra = rank(a.element.octoList), rb = rank(b.element.octoList)
            return ra != rb ? ra < rb : a.offset < b.offset
        }
        .map { _, list in Station(list, sourceId: sourceId) }
}

// MARK: Search

/// The key an album is known by across sources: its title and its artist.
public func albumNameKey(_ title: String, _ artist: String) -> String { matchKey(title) + "|" + matchKey(artist) }

/// The search keys to look up library albums by, one for each server album.
public func albumLookupKeys(_ albums: [Album]) -> [String] { albums.map { searchKey("\($0.name) \($0.artist)") } }

/// The search keys to look up library artists by, one for each server artist.
public func artistLookupKeys(_ artists: [Artist]) -> [String] { artists.map { searchKey($0.name) } }

/// The ids the library keeps a server's artists under, "<source>:<server id>".
public func artistRowIds(_ artists: [Artist], sourceId: String) -> [String] { artists.map { "\(sourceId):\($0.id)" } }

/// Albums the library has neither from this server (`known`, by the server's ids) nor by the same
/// name and artist from anywhere else (`library`, the library albums found by `albumLookupKeys`).
public func albumsNotInLibrary(_ albums: [Album], known: Set<String>, library: [LibraryAlbum]) -> [Album] {
    if albums.isEmpty { return [] }
    let named = Set(library.map { albumNameKey($0.title, $0.artist) })
    return albums.filter { !known.contains($0.id) && !named.contains(albumNameKey($0.name, $0.artist)) }
}

/// Artists the library has neither from this server (`known`, by `artistRowIds`) nor by the same
/// name from anywhere else (`library`, the library artists found by `artistLookupKeys`).
public func artistsNotInLibrary(_ artists: [Artist], sourceId: String, known: Set<String>, library: [LibraryArtist]) -> [OnlineArtist] {
    if artists.isEmpty { return [] }
    let named = Set(library.map { matchKey($0.name) })
    return artists
        .filter { !known.contains("\(sourceId):\($0.id)") && !named.contains(matchKey($0.name)) }
        .map { OnlineArtist($0, sourceId: sourceId) }
}

/// What a search found beyond the library. `songs` are the songs it found, resolved in order: only
/// finds are listed, as library songs show with the library. `albums` are those not in the library
/// (see `albumsNotInLibrary`): Octo counts how many songs of each the library holds, so one it
/// holds every song of is left out (its songs are in the library) and one it holds some of goes
/// apart, saying how many.
public func discovered(songs: [LibraryTrack], albums: [Album], artists: [OnlineArtist], sourceId: String) -> Discovered {
    let shown = albums.filter { albumShare($0) != .whole }
    let part = shown.filter { albumShare($0) == .part }
    let none = shown.filter { albumShare($0) != .part }
    return Discovered(
        songs: songs.filter { isFind($0.id) },
        albums: none.map { OnlineAlbum($0, sourceId: sourceId) },
        artists: artists,
        partAlbums: part.map { OnlineAlbum($0, sourceId: sourceId) }
    )
}

// MARK: Radio

/// The server's id for a radio seed that needs no search: a find's own id, else the id of the
/// song's copy on a server (`copies`, every copy of the song). Nil for a song only on the phone.
public func knownSeedId(_ track: LibraryTrack, copies: [SourceTrack]) -> String? {
    if isFind(track.id) { return String(track.id.dropFirst(findPrefix.count)) }
    return copies.first { $0.sourceId.hasPrefix("server:") }?.nativeId
}

/// What to search the server for to find a song only on the phone. The search asks for no artists,
/// no albums and `discoverySearchSongs` songs.
public func seedSearch(_ track: LibraryTrack) -> String { "\(track.artist) \(track.title)" }

/// The song the server found for one only on the phone: the same recording when the server has
/// it, or else the same song in another version.
public func seedIdAmong(_ found: [Song], for track: LibraryTrack) -> String? {
    (found.first { sameRecording($0.title, $0.artist ?? "", track.title, track.artist) }
        ?? found.first { sameSongAnyVersion($0.title, $0.artist ?? "", track.title, track.artist) })?.id
}

/// The server's id for a song a radio starts from: a find's own, a library song's server copy, or,
/// for a song only on the phone, the same song as the server knows it, found with `search`. Nil
/// when the server has none or cannot answer; only a stop is passed on.
public func radioSeedId(_ track: LibraryTrack, copies: [SourceTrack],
                        search: (String) async throws -> [Song]) async throws -> String? {
    if let known = knownSeedId(track, copies: copies) { return known }
    let found: [Song]
    do {
        found = try await search(seedSearch(track))
    } catch {
        if isCancellation(error) { throw error }
        return nil
    }
    return seedIdAmong(found, for: track)
}

/// A radio's songs: the song it started from first, then the songs like it, each once.
public func radioSongs(seed: LibraryTrack, similar: [LibraryTrack]) -> [LibraryTrack] {
    var seen = Set<String>()
    return ([seed] + similar).filter { seen.insert($0.id).inserted }
}

// MARK: A library album on the server

/// Which of the server's album rows a library album is, from its songs' copies (`copies`, every
/// copy of its songs): the one on `sourceId` most of them came from, the first seen on a tie. Nil
/// when none came from it. Only an Octo server lists the songs of it the library lacks, as finds
/// in the server's order.
public func serverAlbumRow(_ copies: [SourceTrack], sourceId: String) -> String? {
    var counts: [String: Int] = [:]
    var order: [String] = []
    for copy in copies where copy.sourceId == sourceId {
        if counts[copy.albumId] == nil { order.append(copy.albumId) }
        counts[copy.albumId, default: 0] += 1
    }
    var best: String?
    var most = 0
    for albumId in order where (counts[albumId] ?? 0) > most {
        best = albumId
        most = counts[albumId] ?? 0
    }
    return best
}

// MARK: Suggested by

/// Radio answers remembered for "Suggested by" before the oldest are dropped, and how long one is
/// believed: a later radio may suggest the song again from another source, and an old answer
/// would name the wrong one.
public let suggestionsKept = 5_000
public let suggestionLifetimeMs: Int64 = 12 * 60 * 60 * 1000

/// Which source suggested each track, newest last: past the cap the oldest answers go, and one
/// older than its lifetime is forgotten, so the song info never names a source from a radio long
/// gone. Kept while the app runs, not saved. Safe across threads.
public final class Suggestions: @unchecked Sendable {
    private let kept: Int
    private let lifetimeMs: Int64
    private let now: @Sendable () -> Int64
    private let lock = NSLock()
    private var entries: [String: (by: String, at: Int64)] = [:]
    /// Ids from the oldest answer to the newest.
    private var order: [String] = []

    public init(kept: Int = suggestionsKept, lifetimeMs: Int64 = suggestionLifetimeMs,
                now: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }) {
        self.kept = kept
        self.lifetimeMs = lifetimeMs
        self.now = now
    }

    /// Notes which source suggested each id (`suggestionsOf`). A song suggested again moves to the
    /// newest end.
    public func putAll(_ sources: [String: String]) {
        let at = now()
        lock.lock()
        defer { lock.unlock() }
        for (id, by) in sources.sorted(by: { $0.key < $1.key }) {
            if entries[id] != nil, let index = order.firstIndex(of: id) { order.remove(at: index) }
            entries[id] = (by, at)
            order.append(id)
        }
        let over = order.count - kept
        if over > 0 {
            for id in order.prefix(over) { entries[id] = nil }
            order.removeFirst(over)
        }
    }

    public subscript(id: String) -> String? {
        let time = now()
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[id] else { return nil }
        if time - entry.at <= lifetimeMs { return entry.by }
        entries[id] = nil
        if let index = order.firstIndex(of: id) { order.remove(at: index) }
        return nil
    }
}
