import Foundation
import OctoKit

/// The library's part of a backup: playlists made on the phone, likes, ratings, favorites, pins,
/// sort orders and each song's lyrics timing, read from the library and put back through the
/// same writes the pages use.
@MainActor
final class LibraryBackups: BackupLibrary {
    private unowned let actions: LibraryActions

    init(actions: LibraryActions) { self.actions = actions }

    private var state: LibraryState { actions.state }
    private var library: Library { state.library }

    private func key(_ track: LibraryTrack) -> SongKey {
        SongKey(relinkKey: track.relinkKey, title: track.title, artist: track.artist, album: track.album, durationMs: track.durationMs)
    }

    /// A song as the library last knew it; the texts are empty and the length 0 once it is gone.
    private func key(_ row: SongKeyRow) -> SongKey {
        SongKey(relinkKey: row.relinkKey, title: row.title ?? "", artist: row.artist ?? "", album: row.album ?? "",
                durationMs: row.durationMs ?? 0)
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

    func playlistRows() async -> [PlaylistRow] { (try? await library.store.playlists()) ?? [] }

    func phonePlaylists() async -> [PlaylistBackup] {
        let rows = ((try? await library.store.phonePlaylists()) ?? []).sorted { $0.createdAt < $1.createdAt }
        let songs = Dictionary(grouping: (try? await library.store.phonePlaylistSongKeys()) ?? []) { $0.playlistId ?? "" }
        return rows.map { row in PlaylistBackup(row.name, (songs[row.id] ?? []).map { key($0) }) }
    }

    func likes() async -> [SongKey] { ((try? await library.store.likedSongKeys()) ?? []).map { key($0) } }

    func ratings() async -> [RatedSong] {
        ((try? await library.store.ratedSongKeys()) ?? []).compactMap { row in row.rating.map { RatedSong(key(row), $0) } }
    }

    func favoriteAlbums() async -> [HeldKey] {
        let rows = ((try? await library.store.likedAlbumRows()) ?? []).sorted { $0.likedAt < $1.likedAt }
        let albums = await albumsById()
        return rows.map { albumKey($0.relinkKey, albums[$0.albumId]) }
    }

    func favoriteArtists() async -> [HeldKey] {
        let rows = ((try? await library.store.likedArtistRows()) ?? []).sorted { $0.likedAt < $1.likedAt }
        let artists = await artistsById()
        return rows.map { artistKey($0.relinkKey, artists[$0.artistId]) }
    }

    func pins() async -> [PinBackup] {
        let rows = (try? await library.store.pins()) ?? []
        let albums = await albumsById()
        let artists = await artistsById()
        let playlists = Dictionary((await playlistRows()).map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return rows.compactMap { pin in
            let item: HeldKey? = switch PinKind.of(pin.kind) {
            case .album: albumKey(pin.relinkKey, albums[pin.itemId])
            case .artist: artistKey(pin.relinkKey, artists[pin.itemId])
            case .playlist: playlists[pin.itemId].map { HeldKey(name: $0) }
            case nil: nil
            }
            return item.map { PinBackup(pin.kind, $0) }
        }
    }

    private func albumsById() async -> [String: LibraryAlbum] {
        Dictionary((await library.albums()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func artistsById() async -> [String: LibraryArtist] {
        Dictionary((await library.artists()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// An album by its kept key, with empty names when the library no longer has it.
    private func albumKey(_ relinkKey: String, _ album: LibraryAlbum?) -> HeldKey {
        HeldKey(relinkKey: relinkKey, name: album?.title ?? "", artist: album?.artist ?? "")
    }

    private func artistKey(_ relinkKey: String, _ artist: LibraryArtist?) -> HeldKey {
        HeldKey(relinkKey: relinkKey, name: artist?.name ?? "")
    }

    func sortOrders() async -> [String: String] { state.savedOrders() }

    /// Each moved song the library still has, with its timing.
    func lyricsOffsets() async -> [LyricsOffsetBackup] {
        let offsets = LyricsSongTiming.shared.offsets
        return await library.tracks(ids: Array(offsets.keys)).compactMap { track in
            offsets[track.id].map { LyricsOffsetBackup(key(track), Int64($0)) }
        }
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

    /// A playlist made by this restore may not be written yet, so it is pinned by its id alone.
    func pin(_ kind: PinKind, id: String) async { _ = await state.data.pins.pin(kind, id) }

    func restoreSortOrders(_ orders: [String: String]) async { state.restoreOrders(orders) }
}
