import Foundation
import OctoKit

/// The library's part of a backup: playlists made on the phone, likes, ratings, favorites, pins
/// and sort orders, read from the library and put back through the same writes the pages use.
@MainActor
final class LibraryBackups: BackupLibrary {
    private unowned let actions: LibraryActions

    init(actions: LibraryActions) { self.actions = actions }

    private var state: LibraryState { actions.state }
    private var library: Library { state.library }

    private func key(_ track: LibraryTrack) -> SongKey {
        SongKey(relinkKey: track.relinkKey, title: track.title, artist: track.artist, album: track.album, durationMs: track.durationMs)
    }

    func tracks() async -> [BackupTrack] {
        await library.tracks().map {
            BackupTrack(id: $0.id, relinkKey: $0.relinkKey, title: $0.title, artist: $0.artist, album: $0.album, durationMs: $0.durationMs)
        }
    }

    func albums() async -> [NamedItem] {
        await library.albums().map { NamedItem(id: $0.id, relinkKey: $0.searchKey, name: $0.title, artist: $0.artist) }
    }

    func artists() async -> [NamedItem] {
        await library.artists().map { NamedItem(id: $0.id, relinkKey: $0.searchKey, name: $0.name) }
    }

    func playlistNames() async -> [String] { await library.playlists().map(\.name) }

    func phonePlaylists() async -> [PlaylistBackup] {
        let rows = ((try? await library.store.phonePlaylists()) ?? []).sorted { $0.createdAt < $1.createdAt }
        var out: [PlaylistBackup] = []
        for row in rows {
            out.append(PlaylistBackup(row.name, await library.playlistTracks(row.id).map { key($0.track) }))
        }
        return out
    }

    func likes() async -> [SongKey] { await library.likedTracks().map(key) }

    func ratings() async -> [RatedSong] {
        let rated = (try? await library.store.ratings()) ?? []
        let tracks = Dictionary((await library.tracks(ids: rated.map(\.trackId))).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return rated.filter { $0.rating > 0 }.map { rating in
            if let track = tracks[rating.trackId] { return RatedSong(key(track), rating.rating) }
            return RatedSong(SongKey(relinkKey: rating.relinkKey), rating.rating)
        }
    }

    func favoriteAlbums() async -> [HeldKey] {
        await library.likedAlbums().map { HeldKey(relinkKey: $0.album.searchKey, name: $0.album.title, artist: $0.album.artist) }
    }

    func favoriteArtists() async -> [HeldKey] {
        await library.likedArtists().map { HeldKey(relinkKey: $0.artist.searchKey, name: $0.artist.name) }
    }

    func pins() async -> [PinBackup] {
        var out: [PinBackup] = []
        let playlists = await library.playlists()
        for pin in await library.shownPins() {
            switch pin.kind {
            case "album":
                if let album = await library.album(pin.itemId) {
                    out.append(PinBackup(pin.kind, HeldKey(relinkKey: pin.relinkKey, name: album.title, artist: album.artist)))
                }
            case "artist":
                if let artist = await library.artist(pin.itemId) {
                    out.append(PinBackup(pin.kind, HeldKey(relinkKey: pin.relinkKey, name: artist.name)))
                }
            default:
                if let playlist = playlists.first(where: { $0.id == pin.itemId }) {
                    out.append(PinBackup(pin.kind, HeldKey(relinkKey: pin.relinkKey, name: playlist.name)))
                }
            }
        }
        return out
    }

    func sortOrders() async -> [String: String] { state.savedOrders() }

    /// Each song's lyrics timing, by the song's key, for songs the library still has.
    func lyricsOffsets() async -> [LyricsOffsetBackup] {
        let offsets = LyricsSongTiming.shared.offsets
        let tracks = Dictionary((await library.tracks(ids: Array(offsets.keys))).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return offsets.sorted { $0.key < $1.key }.compactMap { id, ms in
            tracks[id].map { LyricsOffsetBackup(key($0), Int64(ms)) }
        }
    }

    func playlistNamesById() async -> [String: String] {
        Dictionary((await library.playlists()).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    func makePlaylist(_ name: String, trackIds: [String]) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return state.data.playlists.create(trimmed, trackIds: trackIds)
    }

    func isLiked(_ trackId: String) async -> Bool { (try? await library.store.isLiked(trackId)) ?? false }

    func like(_ trackId: String) async {
        guard !(await isLiked(trackId)), await library.track(trackId) != nil else { return }
        state.data.likes.toggle(trackId)
    }

    func rate(_ trackId: String, stars: Int) async { state.data.ratings.rate(trackId, stars) }

    func favoriteAlbumIds() async -> Set<String> { await library.likedAlbumIds() }
    func favoriteArtistIds() async -> Set<String> { await library.likedArtistIds() }

    func favorite(album id: String) async { state.data.favorites.set(.album, id, favorite: true) }

    func favorite(artist id: String) async { state.data.favorites.set(.artist, id, favorite: true) }

    func pin(_ kind: PinKind, id: String) async {
        switch kind {
        case .album, .artist:
            _ = await state.data.pins.pin(kind, id)
        case .playlist:
            let playlist = await library.playlists().first { $0.name.caseInsensitiveCompare(id) == .orderedSame || $0.id == id }
            guard let playlist else { return }
            _ = await state.data.pins.pin(.playlist, playlist.id)
        }
    }

    func restoreSortOrders(_ orders: [String: String]) async { state.restoreOrders(orders) }

    /// Puts one song's lyrics timing back: held to the song limit, and not kept at 0.
    func setLyricsOffset(_ trackId: String, ms: Int64) async {
        LyricsSongTiming.shared.set(trackId, Int(ms))
    }
}
