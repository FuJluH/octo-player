import Foundation
import Observation
import OctoKit

/// What a search of the library found, a few of each kind or one kind in full, and whether a
/// kind has more than shown, for its "See all".
struct LibraryResults: Sendable {
    var artists: [LibraryArtist] = []
    var albums: [LibraryAlbum] = []
    var songs: [LibraryTrack] = []
    var playlists: [PlaylistSummary] = []
    var moreArtists = false
    var moreAlbums = false
    var moreSongs = false
    var morePlaylists = false
    /// Songs found online whose library song is among these songs, as the library knew when they
    /// were looked up. Those are left out of the songs not in the library, so no song is listed
    /// twice.
    var listedFinds: Set<String> = []

    var isEmpty: Bool { artists.isEmpty && albums.isEmpty && songs.isEmpty && playlists.isEmpty }
}

/// How long the chart is kept before the empty search asks for it again.
private let chartKeptSeconds: TimeInterval = 60 * 60
/// How long a server's list of charts, and one chart's songs, are kept.
private let chartChoicesKeptSeconds: TimeInterval = 24 * 60 * 60
private let chartSongsKeptSeconds: TimeInterval = 60 * 60
/// How many ids or keys one database lookup takes.
private let lookupChunk = 900

/// One page from the server of an album the library does not hold whole.
struct OnlineAlbumPage: Sendable {
    var album: Album
    var songs: [Song]
}

/// What the signed-in server offers beyond the library: songs, albums and artists found online,
/// ranked lists, charts and stations, each matched to the library. Every call throws when the
/// server cannot answer, and answers nothing when no server is signed in.
@MainActor
@Observable
final class Discovery {
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let downloads: Downloads
    @ObservationIgnored let library: Library

    @ObservationIgnored private var offered: [String: Bool] = [:]
    @ObservationIgnored private var chartsOfferedLive: [String: Bool] = [:]
    @ObservationIgnored private var chart: (server: String, at: Date, list: RankedSongs<Song>)?
    @ObservationIgnored private var choices: [String: (at: Date, value: ChartChoices)] = [:]
    @ObservationIgnored private var chartLists: [String: (at: Date, value: ChartList<Song>)] = [:]
    @ObservationIgnored private var albumTops: [String: [TopSongRef]] = [:]

    init(session: Session, downloads: Downloads, library: Library) {
        self.session = session
        self.downloads = downloads
        self.library = library
    }

    /// Whether a server is signed in, so there is anything to discover.
    var available: Bool { session.client != nil }

    /// Which kept server what is found comes from; nil with none signed in.
    var server: String? { session.client == nil ? nil : session.activeId }

    /// The source the signed-in server's music is kept under.
    var sourceId: String? { session.client == nil ? nil : session.active?.sourceId }

    // MARK: The library

    /// The library's artists, albums, songs and playlists whose search keys hold `folded`, up to
    /// `caps` of each, and whether each kind has more.
    func searchLibrary(_ folded: String, caps: SearchCaps) async -> LibraryResults {
        var results = LibraryResults()
        if caps.artists > 0 || caps.albums > 0 || caps.songs > 0 {
            let found = await library.search(folded, artists: caps.artists > 0 ? caps.artists + 1 : 0,
                                             albums: caps.albums > 0 ? caps.albums + 1 : 0, songs: caps.songs > 0 ? caps.songs + 1 : 0)
            results.artists = Array(found.artists.prefix(caps.artists))
            results.albums = Array(found.albums.prefix(caps.albums))
            results.songs = Array(found.tracks.prefix(caps.songs))
            results.moreArtists = found.artists.count > caps.artists
            results.moreAlbums = found.albums.count > caps.albums
            results.moreSongs = found.tracks.count > caps.songs
        }
        if caps.playlists > 0 {
            let named = await library.playlists().filter { searchKey($0.name).contains(folded) }
            results.playlists = Array(named.prefix(caps.playlists))
            results.morePlaylists = named.count > caps.playlists
        }
        return results
    }

    // MARK: Search

    /// Songs, albums and artists the server has beyond the library. Nil with no server.
    func search(_ query: String) async throws -> Discovered? {
        guard let client = session.client, let sourceId else { return nil }
        let found = try await client.search(query.trimmingCharacters(in: .whitespacesAndNewlines), artists: 10, albums: 20,
                                            songs: discoverSongs)
        let songs = await resolve(found.song).filter { isFind($0.id) }.map(\.asSong)
        // Octo counts how many songs of each album the library holds. One it holds every song of
        // is not a find; one it holds some of goes apart, saying how many.
        let albums = await notInLibrary(sourceId, found.album).filter { albumShare($0) != .whole }
        return Discovered(songs: songs, albums: albums.filter { albumShare($0) != .part }.map(counted),
                          artists: await artistsNotInLibrary(sourceId, found.artist),
                          partAlbums: albums.filter { albumShare($0) == .part }.map(counted))
    }

    /// Albums the library has neither from this server nor by the same name and artist from
    /// anywhere else.
    private func notInLibrary(_ sourceId: String, _ albums: [Album]) async -> [Album] {
        if albums.isEmpty { return [] }
        let ids = albums.map(\.id)
        let known = Set((try? await library.store.knownAlbums(sourceId, ids)) ?? [])
        let named = Set(await library.albumsWithKeys(albums.map { searchKey("\($0.name) \($0.artist)") })
            .map { discoveryNameKey($0.title) + "|" + discoveryNameKey($0.artist) })
        return albums.filter { !known.contains($0.id) && !named.contains(discoveryNameKey($0.name) + "|" + discoveryNameKey($0.artist)) }
    }

    private func artistsNotInLibrary(_ sourceId: String, _ artists: [Artist]) async -> [Artist] {
        if artists.isEmpty { return [] }
        let known = Set((try? await library.store.knownArtists(artists.map { "\(sourceId):\($0.id)" })) ?? [])
        let named = Set(await library.artistsWithKeys(artists.map { searchKey($0.name) }).map { discoveryNameKey($0.name) })
        return artists.filter { !known.contains("\(sourceId):\($0.id)") && !named.contains(discoveryNameKey($0.name)) }
    }

    /// An online album's owned count is kept only when the server marks the album external.
    private func counted(_ album: Album) -> Album {
        var shown = album
        if !album.isExternal { shown.ownedCount = nil }
        return shown
    }

    // MARK: Ranked lists

    /// Whether the server ranks songs: it lists octoTopSongs, or, running Octo, says so when asked.
    /// Kept only once the server itself said; a server out of reach is asked again next time.
    private func offersTopSongs() async -> Bool {
        guard let client = session.client, let server = session.activeId else { return false }
        if session.profile?.lists(octoTopSongs, version: 1) == true { return true }
        if !session.isOcto { return false }
        if let known = offered[server] { return known }
        guard let yes = await client.supportsIfKnown(octoTopSongs, version: 1) else { return false }
        offered[server] = yes
        return yes
    }

    /// An artist's top songs. `libraryId` is a library artist's id, which names the server's
    /// artist when it came from this server; `serverId` an artist the server found online.
    func artistTopSongs(name: String, libraryId: String?, serverId found: String?) async -> RankedSongs<Song>? {
        guard let client = session.client, let asked = session.activeId else { return nil }
        guard await offersTopSongs() else { return nil }
        let id = found ?? libraryId.flatMap { serverId(of: $0, sourceId: sourceId) }
        guard let list = try? await client.artistTopSongs(artist: name, id: id, count: searchTopSongs) else { return nil }
        guard session.activeId == asked else { return nil }
        return await ranked(list)
    }

    /// The chart of the moment, kept an hour per kept server.
    func popularChart() async -> RankedSongs<Song>? {
        guard let client = session.client, let asked = session.activeId else { return nil }
        if let kept = chart, kept.server == asked, Date().timeIntervalSince(kept.at) < chartKeptSeconds { return kept.list }
        guard await offersTopSongs() else { return nil }
        guard let list = try? await client.topChart(count: topChartSongs) else { return nil }
        // Another server in use by the time it came: not this one's chart.
        guard session.activeId == asked, let shown = await ranked(list) else { return nil }
        chart = (asked, Date(), shown)
        return shown
    }

    /// Whether the server offers the Charts page: octoTopSongs at version 2, or Octo saying so
    /// when asked.
    func offersCharts() async -> Bool {
        guard let client = session.client, let server = session.activeId else { return false }
        if chartsOffered(session.profile?.extensions ?? []) { return true }
        if !session.isOcto { return false }
        if let known = chartsOfferedLive[server] { return known }
        guard let yes = await client.supportsIfKnown(octoTopSongs, version: octoTopSongsCharts) else { return false }
        chartsOfferedLive[server] = yes
        return yes
    }

    /// The charts the server's country has, kept a day per server. Nil when it has none.
    func chartChoices() async -> ChartChoices? {
        guard let client = session.client, let asked = session.activeId else { return nil }
        if let kept = choices[asked], Date().timeIntervalSince(kept.at) < chartChoicesKeptSeconds { return kept.value }
        guard await offersCharts(), let value = try? await client.charts(), session.activeId == asked else { return nil }
        choices[asked] = (Date(), value)
        return value
    }

    /// A chart's songs, kept an hour per server and chart. Nil when it could not be read.
    func chart(_ id: String) async -> ChartList<Song>? {
        guard let client = session.client, let asked = session.activeId else { return nil }
        let key = "\(asked)|\(id)"
        if let kept = chartLists[key], Date().timeIntervalSince(kept.at) < chartSongsKeptSeconds { return kept.value }
        guard await offersCharts(), let list = try? await client.topChart(count: chartSongs(id), chart: id) else { return nil }
        // Another server in use by the time it came: not this one's chart.
        guard session.activeId == asked else { return nil }
        let entries = list.entry.filter { $0.song != nil }
        let tracks = await resolveInPlace(entries.compactMap(\.song)).map { $0?.asSong }
        let songs = rankTracks(entries, tracks, id: \.id)
        let shown = ChartList(chart: id, name: list.name, source: list.source, country: list.country, songs: songs)
        chartLists[key] = (Date(), shown)
        return shown
    }

    /// The server's songs as the app shows them, each in its place.
    private func ranked(_ list: TopSongs) async -> RankedSongs<Song>? {
        let entries = list.entry.filter { $0.song != nil }
        let tracks = await resolveInPlace(entries.compactMap(\.song)).map { $0?.asSong }
        let songs = rankTracks(entries, tracks, id: \.id)
        return songs.isEmpty ? nil : RankedSongs(artist: list.artist, source: list.source, songs: songs)
    }

    // MARK: Pages

    /// An album the server found, with its songs in the server's order.
    func album(_ id: String) async throws -> OnlineAlbumPage? {
        guard let client = session.client else { return nil }
        let album = try await client.album(id)
        return OnlineAlbumPage(album: album, songs: await resolve(album.song).map(\.asSong))
    }

    /// An artist the server found, with the albums it lists.
    func artist(_ id: String) async throws -> Artist? {
        guard let client = session.client else { return nil }
        return try await client.artist(id)
    }

    /// The artist's top songs, for marking an album's main song: kept for the app's run per user,
    /// server and artist; nothing when it cannot be reached (asked again then).
    func artistTopRefs(_ artist: String) async -> [TopSongRef] {
        guard !artist.trimmingCharacters(in: .whitespaces).isEmpty, let client = session.client else { return [] }
        let key = "\(client.credentials.username)@\(client.baseURL.absoluteString)|\(SongIdentity.key(artist))"
        if let kept = albumTops[key] { return kept }
        guard let songs = try? await client.topSongs(artist: artist, count: albumHighlightRanked) else { return [] }
        let refs = songs.map { TopSongRef(id: $0.id, title: $0.title, artist: $0.byline) }
        albumTops[key] = refs
        return refs
    }

    // MARK: Resolving

    /// Songs from the server as the app shows them, in the order sent: a library song as it is in
    /// the library, anything else as a find. A find already downloaded is the library song it
    /// became. Repeats are dropped by id.
    func resolve(_ songs: [Song]) async -> [LibraryTrack] {
        var seen = Set<String>()
        return await resolveInPlace(songs).compactMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    /// The same, one for each song sent and in its place, nil where a library song is gone.
    func resolveInPlace(_ songs: [Song]) async -> [LibraryTrack?] {
        guard let sourceId, !songs.isEmpty else { return [] }
        let ids = Array(Set(songs.map(\.id)))
        var links: [String: String] = [:]
        for link in (try? await library.store.libraryLinks(sourceId, ids)) ?? [] { links[link.serverId] = link.trackId }
        let unlinked = songs.filter { links[$0.id] == nil }
        let keys = Array(Set(unlinked.flatMap { titleKeys($0.title) }))
        var candidates: [LibraryTrack] = []
        for start in stride(from: 0, to: keys.count, by: lookupChunk) {
            candidates += await library.tracksWithKeys(Array(keys[start..<min(start + lookupChunk, keys.count)]))
        }
        var each = resolveSongs(songs, sourceId: sourceId, links: links, library: candidates, now: msSince1970())
        // Finds as stored, so a length learned from playing one shows.
        var foundRows: [OnlineSong] = []
        var foundSeen = Set<String>()
        for case .found(let row) in each where foundSeen.insert(row.id).inserted { foundRows.append(row) }
        if let kept = try? await library.store.keepFinds(foundRows) {
            let byId = Dictionary(kept.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            each = each.map { resolved in
                if case .found(let row) = resolved, let stored = byId[row.id] { return .found(stored) }
                return resolved
            }
        }
        var wanted: [String] = []
        for resolved in each {
            switch resolved {
            case .inLibrary(let trackId): wanted.append(trackId)
            case .found(let row): if !row.adoptedId.isEmpty { wanted.append(row.adoptedId) }
            }
        }
        let tracks = await library.tracks(ids: Array(Set(wanted)))
        let byId = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let inLibrary = Set(byId.keys)
        return each.map { resolved in
            switch asAdopted(resolved, library: inLibrary) {
            case .inLibrary(let trackId): byId[trackId]
            case .found(let row): row.asTrack
            }
        }
    }
}
