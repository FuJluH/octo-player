import Foundation
import OctoKit

/// Every change the library pages make: likes, ratings, favorites, pins and playlists.
@MainActor
protocol LibraryWrites: AnyObject {
    /// Likes or unlikes library songs; `at` keeps a like's own time when it is put back.
    func setLiked(_ tracks: [LibraryTrack], _ on: Bool, at: Int64?) async
    func setRating(_ track: LibraryTrack, _ rating: Int) async
    func setFavorite(album: LibraryAlbum, _ on: Bool) async
    func setFavorite(artist: LibraryArtist, _ on: Bool) async
    /// Pins at the end of Home's row; false when Home is full.
    func pin(kind: String, id: String, key: String) async -> Bool
    func unpin(kind: String, id: String) async
    func moveToFront(kind: String, id: String) async
    /// Makes a playlist with these songs, kept with the server in use; answers its id.
    func createPlaylist(name: String, tracks: [LibraryTrack]) async throws -> String?
    func renamePlaylist(_ id: String, name: String) async
    func deletePlaylist(_ id: String) async
    /// Makes a playlist's songs exactly these, in this order.
    func setPlaylistSongs(_ id: String, tracks: [LibraryTrack]) async
    func appendToPlaylist(_ id: String, tracks: [LibraryTrack]) async throws
}

/// Changes sent to the server in use, and kept in the library on the phone where it keeps that
/// kind of thing, so every page shows them at once. The server's copy of the library follows at
/// the next sync.
@MainActor
final class ServerFirstWrites: LibraryWrites {
    private unowned let state: LibraryState

    init(state: LibraryState) { self.state = state }

    private var library: Library { state.library }
    private var client: SubsonicClient? { state.session.client }

    private func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

    func setLiked(_ tracks: [LibraryTrack], _ on: Bool, at time: Int64?) async {
        var songs: [LibraryTrack] = []
        for track in tracks where !track.isFound { songs.append(await state.resolved(track)) }
        guard !songs.isEmpty else { return }
        let when = time ?? now()
        for track in songs {
            if on {
                try? await library.store.like(LikedTrack(trackId: track.id, relinkKey: track.relinkKey, likedAt: when))
            } else {
                try? await library.store.unlike(track.id)
            }
        }
        var ids: [String] = []
        for track in songs { if let id = await state.serverId(track) { ids.append(id) } }
        try? await client?.setStarred(on, songIds: ids)
    }

    func setRating(_ given: LibraryTrack, _ rating: Int) async {
        state.noteRating(given.id, rating)
        let track = await state.resolved(given)
        if rating > 0 {
            try? await library.store.rate(TrackRating(trackId: track.id, relinkKey: track.relinkKey, rating: rating, ratedAt: now()))
        } else {
            try? await library.store.unrate(track.id)
        }
        try? await library.store.setServerRating(track.id, rating)
        if let id = await state.serverId(track) { try? await client?.rate(songId: id, rating: rating) }
    }

    func setFavorite(album: LibraryAlbum, _ on: Bool) async {
        if on {
            try? await library.store.likeAlbums([LikedAlbumRow(albumId: album.id, relinkKey: album.searchKey, likedAt: now())])
        } else {
            try? await library.store.unlikeAlbum(album.id)
        }
        if isServerSource(album.sourceId) { try? await client?.setStarred(on, albumIds: [album.nativeId]) }
    }

    func setFavorite(artist: LibraryArtist, _ on: Bool) async {
        if on {
            try? await library.store.likeArtists([LikedArtistRow(artistId: artist.id, relinkKey: artist.searchKey, likedAt: now())])
        } else {
            try? await library.store.unlikeArtist(artist.id)
        }
        if isServerSource(artist.sourceId), artist.id.hasPrefix(artist.sourceId + ":") {
            try? await client?.setStarred(on, artistIds: [String(artist.id.dropFirst(artist.sourceId.count + 1))])
        }
    }

    func pin(kind: String, id: String, key: String) async -> Bool {
        (try? await library.store.pin(PinnedItem(kind: kind, itemId: id, relinkKey: key, position: 0))) ?? false
    }

    func unpin(kind: String, id: String) async {
        try? await library.store.unpin(kind: kind, itemId: id)
    }

    func moveToFront(kind: String, id: String) async {
        try? await library.store.moveToFront(kind: kind, itemId: id)
    }

    /// The server's id for a playlist kept with it.
    private func serverPlaylistId(_ id: String) async -> String? {
        await library.playlist(id)?.serverId
    }

    private func serverIds(_ tracks: [LibraryTrack]) async -> [String] {
        var ids: [String] = []
        for track in tracks where !track.isFound {
            if let id = await state.serverId(track) { ids.append(id) }
        }
        return ids
    }

    func createPlaylist(name: String, tracks: [LibraryTrack]) async throws -> String? {
        guard let client else { throw OctoError.server(code: 0, message: "No server signed in") }
        let made = try await client.makePlaylist(name: name, songIds: await serverIds(tracks))
        _ = await state.sync.syncNowAndWait()
        guard let made else { return nil }
        return await library.playlists().first { playlist in
            playlist.onServer && playlist.name == name
        }.map(\.id) ?? made
    }

    func renamePlaylist(_ id: String, name: String) async {
        try? await library.store.renamePlaylist(id, name: name, now: now())
        if let serverId = await serverPlaylistId(id) { try? await client?.changePlaylist(serverId, name: name) }
    }

    func deletePlaylist(_ id: String) async {
        let serverId = await serverPlaylistId(id)
        try? await library.store.deletePlaylist(id)
        if let serverId { try? await client?.removePlaylist(serverId) }
    }

    func setPlaylistSongs(_ id: String, tracks: [LibraryTrack]) async {
        guard let serverId = await serverPlaylistId(id) else { return }
        try? await client?.replacePlaylistSongs(serverId, songIds: await serverIds(tracks))
        state.sync.syncAgain()
    }

    func appendToPlaylist(_ id: String, tracks: [LibraryTrack]) async throws {
        guard let serverId = await serverPlaylistId(id), let client else { return }
        try await client.changePlaylist(serverId, add: await serverIds(tracks))
        state.sync.syncAgain()
    }
}
