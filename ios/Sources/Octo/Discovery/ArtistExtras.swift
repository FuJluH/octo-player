import Foundation
import Observation
import OctoKit

/// An artist like the one on the page: in the library when `libraryId` is set, otherwise only on the
/// server, under `serverId`.
struct SimilarArtist: Sendable, Hashable {
    var name: String
    var artwork: String?
    var libraryId: String?
    var serverId: String
}

/// What the signed-in server adds to a library artist's page. Any part can be empty, and the page
/// shows only the parts that are not.
struct ArtistExtras: Sendable {
    var topSongs: [LibraryTrack] = []
    var about: String?
    var similar: [SimilarArtist] = []

    /// The extras as "Library songs only" shows them: top songs in the library, and similar artists
    /// the library has.
    func inLibraryOnly() -> ArtistExtras {
        ArtistExtras(topSongs: librarySongsOnly(topSongs, hide: true) { isFind($0.id) }, about: about,
                     similar: similar.filter { $0.libraryId != nil })
    }
}

/// Reads what the server knows about library artists: their top songs, a biography and artists like
/// them. Kept for as long as the app runs, per server and user, so going back to a page asks nothing
/// again. Nothing comes back without a server, or when it cannot be reached.
@MainActor
@Observable
final class ArtistExtrasSource {
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let discovery: Discovery
    @ObservationIgnored private var cache: [String: ArtistExtras] = [:]
    @ObservationIgnored private var extensions: [String: Set<String>] = [:]

    init(session: Session, library: Library, discovery: Discovery) {
        self.session = session
        self.library = library
        self.discovery = discovery
    }

    /// Drops what was kept for one artist, so the next read asks the server again.
    func forget(_ artistId: String) {
        for key in cache.keys where key.hasSuffix("|\(artistId)") { cache[key] = nil }
    }

    func forArtist(_ artist: LibraryArtist) async -> ArtistExtras? {
        guard let client = session.client, let sourceId = session.active?.sourceId else { return nil }
        let server = "\(client.credentials.username)@\(client.baseURL.absoluteString)"
        if let kept = cache["\(server)|\(artist.id)"] { return kept }
        let serverId = await serverArtistId(client, sourceId: sourceId, artist: artist)
        async let infoAnswer = Self.info(client, serverId)
        let byId = await extensionsOf(server, client).contains(topSongsByArtistId) ? serverId : nil
        let songs: [Song]? = (try? await client.topSongs(artist: artist.name, count: artistPageTopSongs, id: byId))
            .map { byId != nil ? $0 : ownSongs($0, artist: artist.name) }
        let info = await infoAnswer
        // Neither answered: the server could not be reached, so ask again next time.
        if info == nil && songs == nil { return nil }
        let extras = ArtistExtras(
            topSongs: Array(await discovery.resolve(songs ?? []).prefix(artistPageTopSongs)),
            about: info?.biography.flatMap(cleanBiography),
            similar: await similarArtists(sourceId, artist: artist, info: info))
        cache["\(server)|\(artist.id)"] = extras
        return extras
    }

    /// The artist's id on the server: the library's own when the artist came from it, the server's
    /// artist of the same name when the library merged them, or failing both, the one a search
    /// finds.
    private func serverArtistId(_ client: SubsonicClient, sourceId: String, artist: LibraryArtist) async -> String? {
        if let id = serverArtistIdOf(artist.id, sourceId: sourceId) { return id }
        let named = (try? await library.store.artistsNamed(sourceId, key: searchKey(artist.name))) ?? []
        for row in named {
            if let id = serverArtistIdOf(row.id, sourceId: sourceId), SongIdentity.sameArtistName(row.name, artist.name) { return id }
        }
        guard let found = try? await client.search(artist.name, artists: 5, albums: 0, songs: 0).artist else { return nil }
        return found.first { SongIdentity.sameArtistName($0.name, artist.name) }?.id
    }

    /// Artists like this one, each opening in the library when it is there.
    private func similarArtists(_ sourceId: String, artist: LibraryArtist, info: ServerArtistInfo?) async -> [SimilarArtist] {
        let others = (info?.similarArtist ?? []).filter { !$0.id.isEmpty && !SongIdentity.sameArtistName($0.name, artist.name) }
        if others.isEmpty { return [] }
        let keys = Array(Set(others.map { searchKey($0.name) }))
        var known: [String: LibraryArtist] = [:]
        for row in await library.artistsWithKeys(keys) where known[matchKey(row.name)] == nil { known[matchKey(row.name)] = row }
        var seen = Set<String>()
        return others.compactMap { other in
            let mine = known[matchKey(other.name)]
            let similar = SimilarArtist(name: mine?.name ?? other.name,
                                        artwork: mine?.artwork ?? onlineArtwork(sourceId, other.coverArt),
                                        libraryId: mine?.id, serverId: other.id)
            return seen.insert(similar.libraryId ?? similar.serverId).inserted ? similar : nil
        }
    }

    private nonisolated static func info(_ client: SubsonicClient, _ id: String?) async -> ServerArtistInfo? {
        guard let id else { return nil }
        return try? await client.artistInfo2(id: id)
    }

    private func extensionsOf(_ server: String, _ client: SubsonicClient) async -> Set<String> {
        if let known = extensions[server] { return known }
        let names = Set(((try? await client.extensionList()) ?? []).map { String($0.split(separator: ":").first ?? "") })
        extensions[server] = names
        return names
    }
}
