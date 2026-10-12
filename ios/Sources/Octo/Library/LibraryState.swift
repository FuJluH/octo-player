import Foundation
import Observation
import OctoKit

/// What the library pages keep beside the library itself: the order each list was left in, the
/// playlists added to lately, what the server lets this user do to its files, and the listener's
/// likes, favorites, pins and ratings as the stores hold them.
@MainActor
@Observable
final class LibraryState {
    /// The order each list was last left in.
    private(set) var orders: [SortList: ListOrder] = [:]
    /// The playlists added to lately, newest first.
    private(set) var recentPlaylists: [String] = []
    /// Ratings set here, shown at once until the library has them.
    private(set) var ratings: [String: Int] = [:]
    /// The playlists to add to, as the library last listed them.
    private(set) var playlists: [PlaylistSummary] = []
    /// Every rated library song's rating, by id.
    private(set) var rated: [String: Int] = [:]
    /// Library songs in the family member's own library on the server in use, and whether that
    /// server marks any.
    private(set) var personalIds: Set<String> = []
    private(set) var marksPersonal = false

    @ObservationIgnored let data: DataServices
    @ObservationIgnored let session: Session
    /// Fixes and deletes on the server's files.
    @ObservationIgnored let files: LibraryFiles
    /// Library songs by the id their plain song has, for the selection bar.
    @ObservationIgnored private var bySongId: [String: LibraryTrack] = [:]
    @ObservationIgnored private var server: String?

    init(data: DataServices, session: Session) {
        self.data = data
        self.session = session
        files = LibraryFiles(session: session, library: data.library, sync: data.serverSync)
        for list in SortList.allCases { orders[list] = list.decode(UserDefaults.standard.string(forKey: Self.orderKey(list))) }
    }

    var library: Library { data.library }
    var sync: ServerSync { data.serverSync }
    var offline: OfflineDownloads { data.offline }

    /// Whether the phone has a connection.
    var online: Bool { data.connectivity.online }

    /// Every liked song, by library id.
    var likedIds: Set<String> { data.likes.liked }
    var favoriteAlbumIds: Set<String> { data.favorites.albums }
    var favoriteArtistIds: Set<String> { data.favorites.artists }
    /// Home's pins, in row order.
    var pins: [PinnedItem] { data.pins.shown }

    /// Reads again what goes with the server in use, when another comes into use.
    func serverChanged() async {
        guard session.activeId != server else { return }
        server = session.activeId
        ratings = [:]
        recentPlaylists = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    }

    private var recentKey: String { Self.recentPlaylistsKey(session.activeId ?? "phone") }

    private static func recentPlaylistsKey(_ account: String) -> String { "playlists.recent.\(account)" }

    /// Forgets the playlists added to lately on a server taken off the list.
    static func forgetRecent(_ account: String) {
        UserDefaults.standard.removeObject(forKey: recentPlaylistsKey(account))
    }

    /// Whether the server in use can make shared links.
    var canShare: Bool { data.controls.sharing }

    /// What the server lets this user do to the library's files; nil when it offers nothing.
    var fileActions: FileActions? { files.actions }

    // MARK: Orders

    func order(_ list: SortList) -> ListOrder { orders[list] ?? list.defaultOrder }

    func setOrder(_ list: SortList, _ order: ListOrder) {
        orders[list] = order
        UserDefaults.standard.set(list.encode(order), forKey: Self.orderKey(list))
    }

    private static func orderKey(_ list: SortList) -> String { "sort.\(list.key)" }

    /// The orders chosen so far, by list name, for a backup. Lists never reordered, or holding an
    /// order they no longer offer, are left out.
    func savedOrders() -> [String: String] {
        var saved: [String: String] = [:]
        for list in SortList.allCases {
            if let text = UserDefaults.standard.string(forKey: Self.orderKey(list)) { saved[list.key] = text }
        }
        var out: [String: String] = [:]
        for (list, order) in restorableOrders(saved) { out[list.key] = list.encode(order) }
        return out
    }

    /// Puts back the orders from a backup; lists this app does not have are left as they are.
    func restoreOrders(_ saved: [String: String]) {
        for (list, order) in restorableOrders(saved) { setOrder(list, order) }
    }

    /// Reads again what the menus need at once: the playlists, the ratings and the member's own
    /// songs.
    func refreshCaches() async {
        playlists = await library.playlists()
        let ratedRows = (try? await library.store.tracks(sql: "SELECT t.*, NULL AS heading FROM track t WHERE t.rating > 0")) ?? []
        var byId: [String: Int] = [:]
        for row in ratedRows { byId[row.track.id] = row.track.rating }
        for rating in (try? await library.store.ratings()) ?? [] { byId[rating.trackId] = rating.rating }
        rated = byId
        ratings = ratings.filter { byId[$0.key] != $0.value }
        if let server = library.serverInUse {
            personalIds = (try? await library.store.personalTrackIds(server)) ?? []
            marksPersonal = (try? await library.store.marksPersonal(server)) ?? false
        } else {
            personalIds = []
            marksPersonal = false
        }
    }

    /// A library song as a plain server song shows it, before the library is asked: enough for
    /// its row and its menu. Anything that changes it reads the library's own row first.
    func provisional(_ song: Song) -> LibraryTrack {
        let onPhone = song.id.hasPrefix(deviceSource + ":")
        let source = onPhone ? deviceSource : library.serverInUse ?? ""
        let id = libraryId(song) ?? song.id
        let native = isFind(id) ? String(id.dropFirst(findPrefix.count)) : Octo.serverId(of: id, sourceId: source) ?? song.id
        let prefixed: (String?) -> String = { id in
            guard let id, !id.isEmpty else { return "" }
            return id.hasPrefix(source + ":") ? id : "\(source):\(id)"
        }
        let art = artworkOf(cover: song.coverArt, source: source, online: song.isExternal)
        return LibraryTrack(
            id: id, sourceId: source, nativeId: native, title: song.title,
            searchKey: searchKey(song.title), sortKey: sortKey(song.title), artist: song.artist ?? song.byline,
            artistId: song.isExternal ? "" : prefixed(song.artistId), album: song.album ?? "",
            albumId: song.isExternal ? "" : prefixed(song.albumId), trackNo: song.track.flatMap { $0 > 0 ? $0 : nil },
            discNo: song.discNumber.flatMap { $0 > 0 ? $0 : nil }, year: song.year,
            durationMs: Int64(song.duration) * 1_000, addedAt: 0,
            mimeType: mimeTypeOf(contentType: song.contentType, suffix: song.suffix), artwork: art, onPhone: onPhone,
            rating: 0, explicit: song.explicitStatus.map { $0 == "explicit" })
    }

    /// The library's own row for a song, when it has one.
    func resolved(_ track: LibraryTrack) async -> LibraryTrack {
        if !track.relinkKey.isEmpty || track.isFound { return track }
        return await library.track(track.id) ?? track
    }

    /// Where a collection stands on Home.
    func pinSpot(kind: String, id: String) -> PinSpot {
        OctoKit.pinSpot(pins.map { "\($0.kind)|\($0.itemId)" }, "\(kind)|\(id)")
    }

    /// The library id a plain song has here. A song that carries one already (as the queue's do)
    /// keeps it.
    func libraryId(_ song: Song) -> String? {
        if isServerSource(song.id) || song.id.hasPrefix(deviceSource + ":") || isFind(song.id) { return song.id }
        if song.isExternal { return findId(song.id) }
        return library.serverInUse.map { "\($0):\(song.id)" }
    }

    // MARK: Picking songs

    /// Songs of a list as the selection bar takes them, keyed by `key` (a playlist row, or the
    /// song's id). The bar's songs are found again by `tracks(for:)`.
    func pickables(_ tracks: [LibraryTrack], key: (LibraryTrack) -> String = \.id) -> [Pickable] {
        tracks.map { track in
            let song = track.queueSong
            bySongId[song.id] = track
            return Pickable(key: key(track), song: song)
        }
    }

    func pickables(_ rows: [PlaylistTrack]) -> [Pickable] {
        rows.map { row in
            let song = row.track.queueSong
            bySongId[song.id] = row.track
            return Pickable(key: String(row.itemId), song: song)
        }
    }

    /// The library songs the selection bar's songs are.
    func tracks(for songs: [Song]) -> [LibraryTrack] { songs.map { bySongId[$0.id] ?? provisional($0) } }

    // MARK: Ratings

    func rating(of track: LibraryTrack) -> Int { ratings[track.id] ?? rated[track.id] ?? track.rating }

    func noteRating(_ trackId: String, _ rating: Int) { ratings[trackId] = rating }

    // MARK: Downloads to the phone

    /// A library song's download: how far along, and whether it was asked for by hand.
    func kept(_ trackId: String) -> (status: DownloadStatus, byHand: Bool)? {
        guard let row = offline.byTrack[trackId] else { return nil }
        return (row.state, row.reasons.contains(DownloadReasons.manual))
    }

    /// Whether the song plays without a connection: on the phone, or downloaded.
    func isDownloaded(_ track: LibraryTrack) -> Bool { data.marks.isDownloaded(track) }

    /// With no connection, a song that cannot play.
    func isOutOfReach(_ track: LibraryTrack) -> Bool { data.marks.isOutOfReach(track) }

    // MARK: Playlists

    /// The playlist added to last, while it is still there.
    var lastPlaylist: PlaylistSummary? {
        recentPlaylists.first.flatMap { id in playlists.first { $0.id == id } }
    }

    /// Every playlist shown with this server, the three added to most recently first.
    var pickablePlaylists: [PlaylistSummary] { recentFirst(playlists, recent: recentPlaylists, id: \.id) }

    func markRecent(_ id: String) {
        recentPlaylists = OctoKit.recentPlaylists(recentPlaylists, adding: id)
        UserDefaults.standard.set(recentPlaylists, forKey: recentKey)
    }

    func playlistTracks(_ id: String) async -> [PlaylistTrack] { await library.playlistTracks(id) }

    // MARK: Songs of collections

    /// The songs of a collection in play order: an album's in album order; an artist's album by
    /// album (newest year first, then title key), each in album order; a playlist's in its order.
    func songs(of target: CollectionTarget) async -> [LibraryTrack] {
        switch target {
        case .album(let id):
            return await library.albumTracks(id)
        case .artist(let id):
            let albums = await library.artistAlbums(id).sorted { a, b in
                let ya = a.year ?? 0, yb = b.year ?? 0
                return ya != yb ? ya > yb : a.sortKey < b.sortKey
            }
            var out: [LibraryTrack] = []
            for album in albums { out += await library.albumTracks(album.id) }
            return out
        case .playlist(let id):
            return await playlistTracks(id).map(\.track)
        }
    }

    /// The server's id for a library song: its own row's, or its copy on the server in use.
    func serverId(_ track: LibraryTrack) async -> String? {
        if let id = track.serverSongId { return id }
        guard let server = library.serverInUse else { return nil }
        return serverSongId(copies: await library.copies(track.id), serverInUse: server)
    }

}

/// What a collection menu or a list of collections is about.
enum CollectionTarget: Hashable {
    case album(String)
    case artist(String)
    case playlist(String)
}
