import Foundation
import Observation
import OctoKit

/// The library the pages read: the phone's music and the server in use, merged into one, in a
/// database on the phone. Every read is async and never throws; a page reads again when the
/// version of what it shows goes up:
///
///     .task(id: library.stamp(.library, .likes)) { songs = await library.likedTracks() }
///
/// Writes go through the stores that own them (likes, playlists, downloads), which keep the
/// server in step.
@MainActor
@Observable
final class Library {
    /// The database itself, for anything the reads below do not cover.
    @ObservationIgnored let store: CatalogStore

    /// Whose library is in place: a kept server's id, or `phoneLibrary` for the phone's music
    /// alone. Nil until the first is in place.
    var ready: String?

    /// Goes up by one whenever that part of the library changes.
    private(set) var libraryVersion = 0
    private(set) var likesVersion = 0
    private(set) var ratingsVersion = 0
    private(set) var playsVersion = 0
    private(set) var playlistsVersion = 0
    private(set) var findsVersion = 0
    private(set) var favoritesVersion = 0
    private(set) var pinsVersion = 0
    private(set) var downloadsVersion = 0
    private(set) var queueVersion = 0
    private(set) var sourcesVersion = 0

    /// The server source in use, when one is: its rows join the library.
    var serverInUse: String?

    /// What Octo sent the server of each song's plays, so its counts are not counted twice. Kept
    /// by the listening sync.
    var sentPlays: [String: SentPlays] = [:]

    init(store: CatalogStore) {
        self.store = store
        Task { [weak self] in
            await store.listen { change in
                Task { @MainActor in self?.bump(change) }
            }
        }
    }

    /// Opens the library database on the phone, or one in memory when the file cannot be opened.
    static func open() -> Library {
        let store = (try? CatalogStore(path: CatalogStore.defaultPath())) ?? (try! CatalogStore(path: ":memory:"))
        return Library(store: store)
    }

    private func bump(_ change: CatalogChange) {
        if change.contains(.library) { libraryVersion += 1 }
        if change.contains(.likes) { likesVersion += 1 }
        if change.contains(.ratings) { ratingsVersion += 1 }
        if change.contains(.plays) { playsVersion += 1 }
        if change.contains(.playlists) { playlistsVersion += 1 }
        if change.contains(.finds) { findsVersion += 1 }
        if change.contains(.favorites) { favoritesVersion += 1 }
        if change.contains(.pins) { pinsVersion += 1 }
        if change.contains(.downloads) { downloadsVersion += 1 }
        if change.contains(.queue) { queueVersion += 1 }
        if change.contains(.sources) { sourcesVersion += 1 }
    }

    /// One number that goes up whenever any of these parts changes, for `.task(id:)`.
    func stamp(_ kinds: CatalogChange...) -> Int {
        let all = kinds.reduce(CatalogChange()) { $0.union($1) }
        var total = 0
        if all.contains(.library) { total += libraryVersion }
        if all.contains(.likes) { total += likesVersion }
        if all.contains(.ratings) { total += ratingsVersion }
        if all.contains(.plays) { total += playsVersion }
        if all.contains(.playlists) { total += playlistsVersion }
        if all.contains(.finds) { total += findsVersion }
        if all.contains(.favorites) { total += favoritesVersion }
        if all.contains(.pins) { total += pinsVersion }
        if all.contains(.downloads) { total += downloadsVersion }
        if all.contains(.queue) { total += queueVersion }
        if all.contains(.sources) { total += sourcesVersion }
        return total
    }

    /// Runs a read, answering `fallback` when the database cannot.
    private func read<T: Sendable>(_ fallback: T, _ body: @Sendable (CatalogStore) async throws -> T) async -> T {
        (try? await body(store)) ?? fallback
    }

    // MARK: Songs, albums, artists

    func tracks() async -> [LibraryTrack] { await read([]) { try await $0.allTracks() } }
    func albums() async -> [LibraryAlbum] { await read([]) { try await $0.allAlbums() } }
    func artists() async -> [LibraryArtist] { await read([]) { try await $0.allArtists() } }

    func track(_ id: String) async -> LibraryTrack? { await read(nil) { try await $0.track(id) } }
    func album(_ id: String) async -> LibraryAlbum? { await read(nil) { try await $0.album(id) } }
    func artist(_ id: String) async -> LibraryArtist? { await read(nil) { try await $0.artist(id) } }

    /// Library songs by id, in the order asked; ids the library lacks are left out.
    func tracks(ids: [String]) async -> [LibraryTrack] { await read([]) { try await $0.tracks(ids: ids) } }

    /// An album's songs in album order.
    func albumTracks(_ albumId: String) async -> [LibraryTrack] { await read([]) { try await $0.albumTracks(albumId) } }

    /// An artist's albums, newest first.
    func artistAlbums(_ artistId: String) async -> [LibraryAlbum] { await read([]) { try await $0.artistAlbums(artistId) } }

    /// An artist's songs: once any were played, the most played first, the rest album by album.
    func artistTracks(_ artistId: String) async -> [LibraryTrack] {
        let tracks = await read([]) { try await $0.artistTracks(artistId) }
        return artistSongOrder(tracks, played: await playedTracks())
    }

    /// The newest albums, by when they were added.
    func recentAlbums(limit: Int = 20) async -> [LibraryAlbum] { await read([]) { try await $0.recentAlbums(limit: limit) } }

    func genres() async -> [GenreSummary] { await read([]) { try await $0.genres() } }
    func genreAlbums(_ name: String) async -> [LibraryAlbum] { await read([]) { try await $0.genreAlbums(name) } }
    func genreTrackIds(_ name: String) async -> [String] { await read([]) { try await $0.genreTrackIds(name) } }

    /// Every song's album and artist in album order, for playing whole lists of albums or artists.
    func trackPlaces() async -> [TrackPlace] { await read([]) { try await $0.trackPlaces() } }

    // MARK: Search

    struct Found: Sendable {
        var artists: [LibraryArtist] = []
        var albums: [LibraryAlbum] = []
        var tracks: [LibraryTrack] = []
    }

    /// Library items whose search key holds the text, each kind A to Z. The text is folded the
    /// way search keys are; under 2 characters finds nothing.
    func search(_ text: String, artists: Int = 10, albums: Int = 20, songs: Int = 40) async -> Found {
        let query = searchKey(text)
        guard query.count >= 2 else { return Found() }
        return await read(Found()) { store in
            Found(artists: try await store.searchArtists(query, limit: artists),
                  albums: try await store.searchAlbums(query, limit: albums),
                  tracks: try await store.searchTracks(query, limit: songs))
        }
    }

    /// Exact search-key lookups, for telling whether something is already in the library.
    func tracksWithKeys(_ keys: [String]) async -> [LibraryTrack] { await read([]) { try await $0.tracksWithKeys(keys) } }
    func albumsWithKeys(_ keys: [String]) async -> [LibraryAlbum] { await read([]) { try await $0.albumsWithKeys(keys) } }
    func artistsWithKeys(_ keys: [String]) async -> [LibraryArtist] { await read([]) { try await $0.artistsWithKeys(keys) } }

    // MARK: Counts

    /// Every song in the library, phone and server together.
    func trackCount() async -> Int { await read(0) { try await $0.libraryTrackCount() } }
    func albumCount() async -> Int { await read(0) { try await $0.albumCount() } }
    func artistCount() async -> Int { await read(0) { try await $0.artistCount() } }
    func likedCount() async -> Int { await read(0) { try await $0.likedCount() } }

    // MARK: Favorites

    /// Liked songs the library still has, newest like first.
    func likedTracks() async -> [LibraryTrack] { await read([]) { try await $0.likedTracks() } }
    func likedIds() async -> Set<String> { Set(await read([]) { try await $0.likedIds() }) }
    /// Favorite albums the library still has, newest first.
    func likedAlbums() async -> [LikedAlbum] {
        await read([]) { try await $0.likedAlbums() }.sorted { $0.likedAt > $1.likedAt }
    }
    func likedArtists() async -> [LikedArtist] {
        await read([]) { try await $0.likedArtists() }.sorted { $0.likedAt > $1.likedAt }
    }
    func likedAlbumIds() async -> Set<String> { Set(await read([]) { try await $0.likedAlbumIds() }) }
    func likedArtistIds() async -> Set<String> { Set(await read([]) { try await $0.likedArtistIds() }) }

    /// Pins on Home whose album, artist or playlist the library still has, at most `pinLimit`.
    func shownPins() async -> [PinnedItem] { Array(await read([]) { try await $0.shownPins() }.prefix(pinLimit)) }

    // MARK: Listening

    /// Every played song, the phone's plays and the server's counted together.
    func playedTracks() async -> [PlayedTrack] {
        let sent = sentPlays
        return await read([]) { store in withServerPlays(try await store.playedTracks(), try await store.serverPlayedTracks(), sent) }
    }

    /// Every album with a played song, at its latest play on the phone or the server.
    func playedAlbums() async -> [PlayedAlbum] {
        await read([]) { store in withServerAlbumPlays(try await store.playedAlbums(), try await store.serverPlayedAlbums()) }
    }

    /// The most played songs, as the Home shelf shows them.
    func mostPlayedTracks(limit: Int = 20) async -> [LibraryTrack] { byPlayCount(await playedTracks(), limit: limit) }

    /// The albums played most recently, as the Home shelf shows them.
    func recentlyPlayedAlbums(limit: Int = 20) async -> [LibraryAlbum] { byLatestPlay(await playedAlbums(), limit: limit) }

    /// The latest plays, newest first, the phone's and the server's last plays together.
    func history(limit: Int = 200) async -> [HistoryPlay] {
        await read([]) { store in recentHistory(try await store.recentPlays(limit: limit), try await store.serverPlayedTracks(), limit: limit) }
    }

    /// The latest plays under a heading per day.
    func historyDays(limit: Int = 200) async -> [HistoryDay] {
        OctoKit.historyDays(await history(limit: limit), now: Int64(Date().timeIntervalSince1970 * 1000), zone: .current)
    }

    /// The most played songs over a range.
    func mostPlayed(_ range: HistoryRange, limit: Int = 100) async -> [PlayedTrack] {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let since = rangeStart(range, now: now, zone: .current)
        let sent = sentPlays
        return await read([]) { store in
            let local = if let since { try await store.playedTracks(since: since) } else { try await store.playedTracks() }
            return OctoKit.mostPlayed(local, try await store.serverPlayedTracks(), sent, since: since, limit: limit)
        }
    }

    /// Home's rediscovery shelves: albums not played lately, never finished, never played, at
    /// most 20 each, from the phone's plays and the server's together.
    func rediscovery() async -> Rediscovery<LibraryAlbum> {
        let albums = await albums()
        let played = await playedTracks()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return await Task.detached(priority: .utility) { homeRediscovery(albums, played: played, now: now) }.value
    }

    /// Albums by how often their songs were played, never-played ones left out.
    func mostPlayedAlbums(limit: Int = rediscoveryShelf) async -> [LibraryAlbum] {
        let albums = await albums()
        let played = await playedTracks()
        return await Task.detached(priority: .utility) {
            OctoKit.mostPlayedAlbums(albums, of: albumListening(albums, played: played), limit: limit)
        }.value
    }

    // MARK: Playlists

    /// The playlists shown now: the phone's own and the server-in-use's, the one changed last first.
    func playlists() async -> [PlaylistSummary] {
        let server = serverInUse
        return await read([]) { try await $0.playlistSummaries(serverInUse: server) }
    }

    func playlist(_ id: String) async -> PlaylistRow? { await read(nil) { try await $0.playlist(id) } }

    /// A playlist's songs in play order, finds shaped like library songs, each with its row id.
    func playlistTracks(_ id: String) async -> [PlaylistTrack] { await read([]) { try await $0.playlistTracks(id) } }

    /// Which of these songs each playlist already has.
    func playlistHoldings(_ trackIds: [String]) async -> [PlaylistHolding] { await read([]) { try await $0.playlistHoldings(trackIds) } }

    // MARK: Songs found online

    /// Finds by id ("find:<server id>").
    func finds(_ ids: [String]) async -> [OnlineSong] { await read([]) { try await $0.finds(ids) } }

    /// Each find now in the library, by its id, and the library song it became.
    func adoptions() async -> [String: String] {
        let rows = await read([]) { try await $0.requestedFinds() }
        var adopted: [String: String] = [:]
        for row in rows where !row.adoptedId.isEmpty { adopted[row.id] = row.adoptedId }
        return adopted
    }

    /// Songs by id as rows show them: library songs, and finds shaped like them (a find already
    /// downloaded shows as the library song it became). Unknown ids are left out.
    func songs(ids: [String]) async -> [LibraryTrack] {
        let library = await tracks(ids: ids.filter { !isFind($0) })
        let finds = await finds(ids.filter(isFind))
        let adopted = await tracks(ids: finds.map(\.adoptedId).filter { !$0.isEmpty })
        var byId: [String: LibraryTrack] = [:]
        for track in library + adopted { byId[track.id] = track }
        var findById: [String: LibraryTrack] = [:]
        for find in finds { findById[find.id] = byId[find.adoptedId] ?? find.asTrack }
        return ids.compactMap { isFind($0) ? findById[$0] : byId[$0] }
    }

    // MARK: Copies

    /// Every copy of a library song, from every source that has it.
    func copies(_ trackId: String) async -> [SourceTrack] { await read([]) { try await $0.copies(trackId) } }

    /// What the library knows about a song from all its copies, for the info sheet.
    func details(_ trackId: String) async -> SongDetails { songDetails(await copies(trackId)) }
}
