import Foundation
import Observation
import OctoKit

/// What the server in use offers beyond the library: songs, albums and artists found online,
/// radio from any song, stations and Made for you lists. Songs come back shaped like library
/// songs: a song the library has is that library song (a phone copy plays instead of a stream),
/// anything else is a find ("find:<server id>"), kept in the library database. A find already
/// downloaded is the library song it became. Every call throws when the server cannot answer, and
/// answers nothing when no server is signed in.
@MainActor
final class ServerDiscovery {
    private let session: Session
    private let library: Library
    /// Which of Octo's radio sources suggested each song, as its last radio answer said.
    let suggested = Suggestions()

    init(session: Session, library: Library) {
        self.session = session
        self.library = library
    }

    /// The source of the server in use, while one is signed in.
    var sourceId: String? { session.inUse?.sourceId }

    /// Whether the signed-in server runs stations and Made for you lists, which only Octo does.
    var offersStations: Bool { session.inUse != nil && (session.active?.runsOcto == true || session.isOcto) }

    private func server() -> (client: SubsonicClient, sourceId: String)? {
        session.inUse.map { ($0.client, $0.sourceId) }
    }

    // MARK: Search, radio, stations

    /// What a search finds beyond the library: songs only as finds, albums and artists not in the
    /// library, and albums the library holds part of kept apart.
    func search(_ query: String) async throws -> Discovered? {
        guard let (client, sourceId) = server() else { return nil }
        let found = try await client.search(query.trimmingCharacters(in: .whitespacesAndNewlines), artists: discoverySearchArtists,
                                            albums: discoverySearchAlbums, songs: discoverySearchSongs)
        let songs = await resolveFromServer(found.song)
        let store = library.store
        let known = Set((try? await store.knownAlbums(sourceId, found.album.map(\.id))) ?? [])
        let named = (try? await store.albumsWithKeys(albumLookupKeys(found.album))) ?? []
        let albums = albumsNotInLibrary(found.album, known: known, library: named)
        let knownArtists = Set((try? await store.knownArtists(artistRowIds(found.artist, sourceId: sourceId))) ?? [])
        let namedArtists = (try? await store.artistsWithKeys(artistLookupKeys(found.artist))) ?? []
        let artists = artistsNotInLibrary(found.artist, sourceId: sourceId, known: knownArtists, library: namedArtists)
        return discovered(songs: songs, albums: albums, artists: artists, sourceId: sourceId)
    }

    /// The song first, then up to 50 songs like it, each once.
    func radio(_ seed: LibraryTrack, count: Int = discoveryRadioSongs) async throws -> [LibraryTrack] {
        guard let (client, _) = server() else { return [] }
        let copies = await library.copies(seed.id)
        guard let seedId = try await radioSeedId(seed, copies: copies, search: { @Sendable text in
            try await client.search(text, artists: 0, albums: 0, songs: discoverySearchSongs).song
        }) else { return [] }
        let similar = await resolveFromServer(try await client.radio(from: seedId, count: count))
        return radioSongs(seed: seed, similar: similar)
    }

    /// The stations Octo runs, and the internet radio stations added to it, which play their
    /// stream. Other servers list only internet radio, so nothing is shown for them.
    func stations() async throws -> [Station] {
        guard offersStations, let (client, sourceId) = server() else { return [] }
        return homeStations(try await client.stations(), sourceId: sourceId)
    }

    /// The lists Octo made for the listener and its mixes by Home's shelves, from one read of its
    /// playlists.
    func octoLists() async throws -> (madeForYou: [Station], mixes: [HomeSection: [Station]]) {
        guard offersStations, let (client, sourceId) = server() else { return ([], [:]) }
        let playlists = try await client.playlists()
        return (madeForYouLists(playlists, sourceId: sourceId),
                homeMixes(playlists, listener: client.credentials.username, sourceId: sourceId))
    }

    /// Octo's lists for the listener in their groups, from its playlists.
    func octoListGroups() async throws -> [(group: OctoListGroup, lists: [Playlist])] {
        guard offersStations, let (client, _) = server() else { return [] }
        return OctoKit.octoListGroups(try await client.playlists(), listener: client.credentials.username)
    }

    /// The songs a station, or a Made for you list, has lined up now.
    func stationSongs(_ id: String) async throws -> [LibraryTrack] {
        guard let (client, _) = server() else { return [] }
        return await resolveFromServer(try await client.playlist(id).entry)
    }

    /// More of a station's songs, past those already queued (`after`, by their library ids),
    /// resolved like the songs it has lined up. Nothing when no server is signed in.
    func moreStationSongs(_ id: String, after trackIds: [String]) async throws -> [LibraryTrack] {
        guard let (client, sourceId) = server() else { return [] }
        let after = await serverIds(trackIds, sourceId: sourceId)
        return await resolveFromServer(try await client.stationSongs(id: id, after: after).entry)
    }

    /// The server's own ids for library songs, in order: a find's own, else the id of the song's
    /// copy on this server. A song with no copy there is left out.
    private func serverIds(_ trackIds: [String], sourceId: String) async -> [String] {
        let copies = (try? await library.store.copies(of: trackIds.filter { !isFind($0) })) ?? []
        var native: [String: String] = [:]
        for copy in copies where copy.sourceId == sourceId && native[copy.mergedId] == nil { native[copy.mergedId] = copy.nativeId }
        return trackIds.compactMap { id in isFind(id) ? String(id.dropFirst(findPrefix.count)) : native[id] }
    }

    /// An album found online, with its songs.
    func album(_ id: String) async throws -> OnlineAlbumPage? {
        guard let (client, sourceId) = server() else { return nil }
        let album = try await client.album(id)
        let info = OnlineAlbum(id: album.id, title: album.name, artist: album.artist, artistId: album.artistId, year: album.year,
                               songCount: album.songCount, artwork: onlineArtwork(sourceId, album.coverArt))
        return OnlineAlbumPage(album: info, songs: await resolveFromServer(album.song))
    }

    /// An artist found online, with their albums.
    func artist(_ id: String) async throws -> OnlineArtistPage? {
        guard let (client, sourceId) = server() else { return nil }
        let artist = try await client.artist(id)
        return OnlineArtistPage(artist: OnlineArtist(id: artist.id, name: artist.name, albumCount: artist.albumCount,
                                                     artwork: onlineArtwork(sourceId, artist.coverArt)),
                                albums: artist.album.map { OnlineAlbum($0, sourceId: sourceId) })
    }

    /// A library album as the server lists it now, found from its songs (`trackIds`): the songs
    /// the server sent, and each resolved to the library song it is or a find, in the server's
    /// order. Nil when no Octo server is signed in (only Octo lists songs outside the library) or
    /// none of the songs came from it.
    func libraryAlbum(_ trackIds: [String]) async throws -> (sent: [Song], resolved: [LibraryTrack])? {
        guard offersStations, let (client, sourceId) = server() else { return nil }
        let copies = (try? await library.store.copies(of: trackIds)) ?? []
        guard let row = serverAlbumRow(copies, sourceId: sourceId), let native = try await library.store.albumNativeId(row) else {
            return nil
        }
        let sent = try await client.album(native).song
        return (sent, await resolveFromServer(sent))
    }

    /// Which of Octo's radio sources suggested a song, for its info sheet.
    func suggestedBy(_ trackId: String) -> String? { suggested[trackId] }

    // MARK: Resolving server songs

    /// Songs from the server in use as the app shows them, in the order sent, each once. Nothing
    /// when no server is signed in.
    func resolveFromServer(_ songs: [Song]) async -> [LibraryTrack] {
        var seen = Set<String>()
        return await resolveInPlace(songs).compactMap { $0 }.filter { seen.insert($0.id).inserted }
    }

    /// One id for each song sent, in the same order with repeats kept: the library song it is, or
    /// a find. For lists that must keep every entry, like a playlist.
    func idsFromServer(_ songs: [Song]) async -> [String] {
        guard let sourceId else { return [] }
        return await resolveEach(sourceId, songs).map(\.id)
    }

    /// The same, one for each song sent and in its place, nil where a library song is gone: for
    /// lists whose places mean something, like a ranking.
    func resolveInPlace(_ songs: [Song]) async -> [LibraryTrack?] {
        guard let sourceId, !songs.isEmpty else { return [] }
        let each = await resolveEach(sourceId, songs)
        var adopted: [String] = []
        var inLibrary: [String] = []
        for resolved in each {
            switch resolved {
            case .inLibrary(let id): inLibrary.append(id)
            case .found(let song): if !song.adoptedId.isEmpty { adopted.append(song.adoptedId) }
            }
        }
        var tracks: [String: LibraryTrack] = [:]
        for track in await library.tracks(ids: inLibrary + adopted) { tracks[track.id] = track }
        let present = Set(tracks.keys)
        let shown: [LibraryTrack?] = each.map { resolved in
            switch asAdopted(resolved, library: present) {
            case .inLibrary(let id): tracks[id]
            case .found(let song): song.asTrack
            }
        }
        suggested.putAll(suggestionsOf(shown.map { $0?.id }, songs))
        return shown
    }

    /// What each song sent is, in order, with the finds among them kept.
    func resolveEach(_ sourceId: String, _ songs: [Song]) async -> [Resolved] {
        guard !songs.isEmpty else { return [] }
        let store = library.store
        let ids = distinct(songs.map(\.id))
        var links: [String: String] = [:]
        for link in (try? await store.libraryLinks(sourceId, ids)) ?? [] { links[link.serverId] = link.trackId }
        let unlinked = songs.filter { links[$0.id] == nil }
        let keys = distinct(unlinked.flatMap { titleKeys($0.title) })
        let candidates = keys.isEmpty ? [] : ((try? await store.tracksWithKeys(keys)) ?? [])
        let resolved = resolveSongs(songs, sourceId: sourceId, links: links, library: candidates, now: epochNowMs())
        // Finds as stored, so a length learned from playing one shows.
        var seen = Set<String>()
        let finds = resolved.compactMap { item -> OnlineSong? in
            if case .found(let song) = item, seen.insert(song.id).inserted { return song }
            return nil
        }
        var kept: [String: OnlineSong] = [:]
        for song in (try? await store.keepFinds(finds)) ?? finds { kept[song.id] = song }
        return resolved.map { item in
            if case .found(let song) = item, let stored = kept[song.id] { return .found(stored) }
            return item
        }
    }
}
