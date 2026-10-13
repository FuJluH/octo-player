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

/// What the signed-in server offers beyond the library: songs, albums and artists found online,
/// ranked lists, charts and stations, each matched to the library. What the server finds is read
/// through `ServerDiscovery`; the ranked lists and charts are kept here. Every call throws when the
/// server cannot answer, and answers nothing when no server is signed in.
@MainActor
@Observable
final class Discovery {
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let online: ServerDiscovery
    @ObservationIgnored let library: Library

    @ObservationIgnored private var offered: [String: Bool] = [:]
    @ObservationIgnored private var chartsOfferedLive: [String: Bool] = [:]
    @ObservationIgnored private var chart: (server: String, at: Date, list: RankedSongs<Song>)?
    @ObservationIgnored private var choices: [String: (at: Date, value: ChartChoices)] = [:]
    @ObservationIgnored private var chartLists: [String: (at: Date, value: ChartList<Song>)] = [:]
    @ObservationIgnored private var albumTops: [String: [TopSongRef]] = [:]

    init(session: Session, online: ServerDiscovery, library: Library) {
        self.session = session
        self.online = online
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
    func search(_ query: String) async throws -> Discovered? { try await online.search(query) }

    // MARK: Ranked lists

    /// Whether the server ranks songs: it lists octoTopSongs, or, running Octo, says so when asked.
    /// Kept only once the server itself said; a server out of reach is asked again next time.
    private func offersTopSongs() async -> Bool {
        guard let client = session.client, let server = session.active?.sourceId else { return false }
        if session.extensions.contains("\(octoTopSongs):1") { return true }
        if !session.runsOcto { return false }
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
        guard let client = session.client, let server = session.active?.sourceId else { return false }
        if chartsOffered(session.extensions) { return true }
        if !session.runsOcto { return false }
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
        let tracks = await online.resolveInPlace(entries.compactMap(\.song)).map { $0?.asSong }
        let songs = rankTracks(entries, tracks, id: \.id)
        let shown = ChartList(chart: id, name: list.name, source: list.source, country: list.country, songs: songs)
        chartLists[key] = (Date(), shown)
        return shown
    }

    /// The server's songs as the app shows them, each in its place.
    private func ranked(_ list: TopSongs) async -> RankedSongs<Song>? {
        let entries = list.entry.filter { $0.song != nil }
        let tracks = await online.resolveInPlace(entries.compactMap(\.song)).map { $0?.asSong }
        let songs = rankTracks(entries, tracks, id: \.id)
        return songs.isEmpty ? nil : RankedSongs(artist: list.artist, source: list.source, songs: songs)
    }

    // MARK: Stations

    /// The kept server whose stations Home shows: the one signed in to, while it runs Octo.
    var stationsFrom: String? { online.offersStations ? session.activeId : nil }

    /// The stations the server runs: only Octo's.
    func stations() async throws -> [Station] { try await online.stations() }

    /// The lists Octo made for the listener and its mixes by Home's shelves, from its playlists.
    func octoLists() async throws -> (madeForYou: [Station], mixes: [HomeSection: [Station]]) { try await online.octoLists() }

    /// Octo's lists for the listener in their groups; nothing on a server that does not run Octo.
    func octoListGroups() async throws -> [(group: OctoListGroup, lists: [Playlist])] { try await online.octoListGroups() }

    /// Server lists found gone on their own pages, so Home can drop them.
    private(set) var goneLists: Set<String> = []

    /// A server list answered that it is gone.
    func listGone(_ id: String) { goneLists.insert(id) }

    /// The songs a station, or a Made for you list, has lined up now.
    func stationSongs(_ id: String) async throws -> [Song] { try await online.stationSongs(id).map(\.asSong) }

    // MARK: Pages

    /// An album the server found, with its songs in the server's order.
    func album(_ id: String) async throws -> OnlineAlbumPage? { try await online.album(id) }

    /// An artist the server found, with the albums it lists.
    func artist(_ id: String) async throws -> OnlineArtistPage? { try await online.artist(id) }

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

    /// Songs from the server as the app shows them, in the order sent, each once: a library song as
    /// it is in the library, anything else as a find.
    func resolve(_ songs: [Song]) async -> [LibraryTrack] { await online.resolveFromServer(songs) }
}
