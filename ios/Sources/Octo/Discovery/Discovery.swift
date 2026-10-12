import Foundation
import Observation
import OctoKit

/// What a search of the library found, a few of each kind or one kind in full, and whether a
/// kind has more than shown, for its "See all".
struct LibraryResults: Sendable {
    var artists: [Artist] = []
    var albums: [Album] = []
    var songs: [Song] = []
    var playlists: [Playlist] = []
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

/// Where search reads the library from. The server's own library today; the phone's catalog,
/// which holds the phone's music and every server's together, takes its place.
@MainActor
protocol SearchLibrary: AnyObject {
    /// The library's artists, albums, songs and playlists whose search keys hold `folded`, up to
    /// `caps` of each and one more, to know whether a kind has more.
    func search(_ folded: String, caps: SearchCaps) async -> LibraryResults
}

/// The library as the signed-in server holds it: its search, less what it found online, and its
/// playlists. Nothing while signed out.
@MainActor
final class ServerLibrary: SearchLibrary {
    private let session: Session
    private var playlists: (server: String, at: Date, lists: [Playlist])?

    init(session: Session) { self.session = session }

    func search(_ folded: String, caps: SearchCaps) async -> LibraryResults {
        guard let client = session.client else { return LibraryResults() }
        var results = LibraryResults()
        if caps.artists > 0 || caps.albums > 0 || caps.songs > 0 {
            let found = (try? await client.search(
                folded,
                artists: caps.artists > 0 ? caps.artists + 1 : 0,
                albums: caps.albums > 0 ? caps.albums + 1 : 0,
                songs: caps.songs > 0 ? caps.songs + 1 : 0)) ?? SearchResult()
            let artists = found.artist.filter { !isOnlineId($0.id) }
            let albums = found.album.filter { !$0.isExternal }
            let songs = found.song.filter { !$0.isExternal }
            results.artists = Array(artists.prefix(caps.artists))
            results.albums = Array(albums.prefix(caps.albums))
            results.songs = Array(songs.prefix(caps.songs))
            results.moreArtists = artists.count > caps.artists
            results.moreAlbums = albums.count > caps.albums
            results.moreSongs = songs.count > caps.songs
        }
        if caps.playlists > 0 {
            let named = await ownPlaylists().filter { searchKey($0.name).contains(folded) }
            results.playlists = Array(named.prefix(caps.playlists))
            results.morePlaylists = named.count > caps.playlists
        }
        return results
    }

    /// The listener's own playlists, read again after a minute. Made for you lists are Home's.
    private func ownPlaylists() async -> [Playlist] {
        guard let client = session.client, let server = session.activeId else { return [] }
        if let kept = playlists, kept.server == server, Date().timeIntervalSince(kept.at) < 60 { return kept.lists }
        guard let lists = try? await client.playlists() else { return playlists?.server == server ? playlists?.lists ?? [] : [] }
        let own = lists.filter { $0.octoList == nil }
        playlists = (server, Date(), own)
        return own
    }
}

/// How long the chart is kept before the empty search asks for it again.
private let chartKeptSeconds: TimeInterval = 60 * 60
/// How long a server's list of charts, and one chart's songs, are kept.
private let chartChoicesKeptSeconds: TimeInterval = 24 * 60 * 60
private let chartSongsKeptSeconds: TimeInterval = 60 * 60

/// One page from the server of an album the library does not hold whole.
struct OnlineAlbumPage: Sendable {
    var album: Album
    var songs: [Song]
}

/// What the signed-in server offers beyond the library: songs, albums and artists found online,
/// ranked lists, charts and stations. Every call throws when the server cannot answer, and answers
/// nothing when no server is signed in.
@MainActor
@Observable
final class Discovery {
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let downloads: Downloads
    @ObservationIgnored let library: SearchLibrary

    @ObservationIgnored private var offered: [String: Bool] = [:]
    @ObservationIgnored private var chartsOfferedLive: [String: Bool] = [:]
    @ObservationIgnored private var chart: (server: String, at: Date, list: RankedSongs<Song>)?
    @ObservationIgnored private var choices: [String: (at: Date, value: ChartChoices)] = [:]
    @ObservationIgnored private var chartLists: [String: (at: Date, value: ChartList<Song>)] = [:]
    @ObservationIgnored private var albumTops: [String: [TopSongRef]] = [:]

    init(session: Session, downloads: Downloads, library: SearchLibrary? = nil) {
        self.session = session
        self.downloads = downloads
        self.library = library ?? ServerLibrary(session: session)
    }

    /// Whether a server is signed in, so there is anything to discover.
    var available: Bool { session.client != nil }

    /// Which kept server what is found comes from; nil with none signed in.
    var server: String? { session.client == nil ? nil : session.activeId }

    // MARK: Search

    /// Songs, albums and artists the server has beyond the library. Nil with no server.
    func search(_ query: String) async throws -> Discovered? {
        guard let client = session.client else { return nil }
        let found = try await client.search(query.trimmingCharacters(in: .whitespacesAndNewlines), artists: 10, albums: 20,
                                            songs: discoverSongs)
        let adoptions = downloads.adoptions ?? [:]
        let libraryAlbums = found.album.filter { !$0.isExternal }
        let libraryArtists = found.artist.filter { !isOnlineId($0.id) }
        return discovered(from: found, libraryAlbums: libraryAlbums, libraryArtists: libraryArtists) {
            $0.isExternal && adoptions[$0.id] == nil
        }
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
    func artistTopSongs(name: String, libraryId: String?, serverId: String?) async -> RankedSongs<Song>? {
        guard let client = session.client, let asked = session.activeId else { return nil }
        guard await offersTopSongs() else { return nil }
        let id = serverId ?? libraryId
        guard let list = try? await client.artistTopSongs(artist: name, id: id, count: searchTopSongs) else { return nil }
        guard session.activeId == asked else { return nil }
        return ranked(list)
    }

    /// The chart of the moment, kept an hour per kept server.
    func popularChart() async -> RankedSongs<Song>? {
        guard let client = session.client, let asked = session.activeId else { return nil }
        if let kept = chart, kept.server == asked, Date().timeIntervalSince(kept.at) < chartKeptSeconds { return kept.list }
        guard await offersTopSongs() else { return nil }
        guard let list = try? await client.topChart(count: topChartSongs) else { return nil }
        // Another server in use by the time it came: not this one's chart.
        guard session.activeId == asked, let shown = ranked(list) else { return nil }
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
        let key = "(asked)|(id)"
        if let kept = chartLists[key], Date().timeIntervalSince(kept.at) < chartSongsKeptSeconds { return kept.value }
        guard await offersCharts(), let list = try? await client.topChart(count: chartSongs(id), chart: id) else { return nil }
        // Another server in use by the time it came: not this one's chart.
        guard session.activeId == asked else { return nil }
        let entries = list.entry.filter { $0.song != nil }
        let songs = rankTracks(entries, resolveInPlace(entries.compactMap(\.song)), id: \.id)
        let shown = ChartList(chart: id, name: list.name, source: list.source, country: list.country, songs: songs)
        chartLists[key] = (Date(), shown)
        return shown
    }

    /// The server's songs as the app shows them, each in its place.
    private func ranked(_ list: TopSongs) -> RankedSongs<Song>? {
        let entries = list.entry.filter { $0.song != nil }
        let songs = rankTracks(entries, resolveInPlace(entries.compactMap(\.song)), id: \.id)
        return songs.isEmpty ? nil : RankedSongs(artist: list.artist, source: list.source, songs: songs)
    }

    // MARK: Pages

    /// An album the server found, with its songs in the server's order.
    func album(_ id: String) async throws -> OnlineAlbumPage? {
        guard let client = session.client else { return nil }
        let album = try await client.album(id)
        return OnlineAlbumPage(album: album, songs: resolve(album.song))
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
        let key = "(client.credentials.username)@(client.baseURL.absoluteString)|(SongIdentity.key(artist))"
        if let kept = albumTops[key] { return kept }
        guard let songs = try? await client.topSongs(artist: artist, count: albumHighlightRanked) else { return [] }
        let refs = songs.map { TopSongRef(id: $0.id, title: $0.title, artist: $0.byline) }
        albumTops[key] = refs
        return refs
    }

    // MARK: Resolving

    /// Songs from the server as the app shows them, in the order sent: a library song as it is, a
    /// find already downloaded as the library song it became when known, anything else as a find.
    /// Repeats are dropped by id.
    func resolve(_ songs: [Song]) -> [Song] {
        var seen = Set<String>()
        return resolveInPlace(songs).compactMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    /// The same, one for each song sent and in its place.
    func resolveInPlace(_ songs: [Song]) -> [Song?] {
        let adoptions = downloads.adoptions ?? [:]
        return songs.map { song in
            guard song.isExternal, let id = adoptions[song.id], let library = downloads.lastSeenLibrarySong(id) else { return song }
            return library
        }
    }
}
