import Foundation
import Observation
import OctoKit

/// Liked songs. A change is saved on the phone first, then the song's server copies follow. Only a
/// song the library has can be liked: a find is not in the library.
@MainActor
@Observable
final class LikeStore {
    /// Every liked song, by library id.
    private(set) var liked: Set<String> = []

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let listening: ListeningSync
    @ObservationIgnored private var watch: Watch<Int>?

    init(library: Library, listening: ListeningSync) {
        self.library = library
        self.listening = listening
        watch = Watch({ [weak library] in library?.likesVersion ?? 0 }) { [weak self] _ in Task { await self?.reload() } }
        Task { await reload() }
    }

    private func reload() async { liked = await library.likedIds() }

    func isLiked(_ trackId: String) -> Bool { liked.contains(trackId) }

    func toggle(_ trackId: String) {
        Task {
            let store = library.store
            if (try? await store.isLiked(trackId)) == true {
                try? await store.unlike(trackId)
                listening.likeChanged(trackId, liked: false)
            } else {
                // A song the library does not have cannot be liked.
                guard let track = try? await store.track(trackId) else { return }
                try? await store.like(LikedTrack(trackId: trackId, relinkKey: track.relinkKey, likedAt: epochNowMs()))
                listening.likeChanged(trackId, liked: true)
            }
        }
    }

    /// Takes a like away. `removed` hears the like as it was, to put it back.
    func unlike(_ trackId: String, removed: @escaping @MainActor (LikedTrack) -> Void = { _ in }) {
        Task {
            let store = library.store
            guard let row = try? await store.likedRow(trackId) else { return }
            try? await store.unlike(trackId)
            listening.likeChanged(trackId, liked: false)
            removed(row)
        }
    }

    /// Puts a like back as it was, with its own time, so it keeps its place.
    func restore(_ row: LikedTrack) {
        Task {
            try? await library.store.like(row)
            listening.likeChanged(row.trackId, liked: true)
        }
    }
}

/// Rates library songs, 1 to 5 stars or 0 for none. The phone keeps the rating, the library
/// shows it at once, and the song's server copies follow. A song found online cannot be rated.
@MainActor
final class RatingStore {
    private let library: Library
    private let listening: ListeningSync

    init(library: Library, listening: ListeningSync) {
        self.library = library
        self.listening = listening
    }

    func rate(_ trackId: String, _ rating: Int) {
        guard !isFind(trackId) else { return }
        let stars = cleanRating(rating)
        Task {
            let store = library.store
            guard let track = try? await store.track(trackId) else { return }
            if stars == 0 {
                try? await store.unrate(trackId)
            } else {
                try? await store.rate(TrackRating(trackId: trackId, relinkKey: track.relinkKey, rating: stars, ratedAt: epochNowMs()))
            }
            try? await store.showRating(trackId, stars)
            // The server copies are noted as rated too, so a rebuild before the next sync still shows it.
            try? await store.setServerRating(trackId, stars)
            listening.ratingChanged(trackId)
        }
    }
}

/// The listener's playlists. Changes run on their own, so they finish even if the page that asked
/// for them closes. A playlist kept with the server sends each change there.
@MainActor
final class PlaylistStore {
    private let library: Library
    private let sync: PlaylistSync

    init(library: Library, sync: PlaylistSync) {
        self.library = library
        self.sync = sync
    }

    /// Makes a playlist, with the songs in it if any are given, and gives back the id it will have.
    @discardableResult
    func create(_ name: String, trackIds: [String] = []) -> String {
        let id = UUID().uuidString.lowercased()
        Task {
            let now = epochNowMs()
            let store = library.store
            try? await store.insertPlaylist(PlaylistRow(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: now, updatedAt: now))
            if !trackIds.isEmpty { _ = try? await store.addToPlaylist(id, tracks: await library.tracks(ids: trackIds), now: now) }
            sync.created(id)
        }
        return id
    }

    func rename(_ id: String, _ name: String) {
        Task {
            try? await library.store.renamePlaylist(id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), now: epochNowMs())
            sync.changed(id)
        }
    }

    func delete(_ id: String) {
        Task {
            let store = library.store
            guard let playlist = try? await store.playlist(id) else { return }
            try? await store.deletePlaylist(id)
            sync.deleted(playlist)
        }
    }

    /// Adds songs to the end. `added` hears the new rows, to take them back out.
    func add(_ id: String, trackIds: [String], added: @escaping @MainActor ([Int64]) -> Void = { _ in }) {
        Task {
            let rows = (try? await library.store.addToPlaylist(id, tracks: await songs(trackIds), now: epochNowMs())) ?? []
            sync.changed(id)
            if !rows.isEmpty { added(rows) }
        }
    }

    /// Takes a song out. `removed` hears the row as it was, to put it back.
    func remove(_ id: String, itemId: Int64, removed: @escaping @MainActor (PlaylistItem) -> Void = { _ in }) {
        Task {
            guard let row = try? await library.store.removeFromPlaylist(id, itemId: itemId, now: epochNowMs()) else { return }
            sync.changed(id)
            removed(row)
        }
    }

    /// Takes several songs out, one after another. `removed` hears the rows as they were, in the
    /// order they went, to put them back.
    func removeAll(_ id: String, itemIds: [Int64], removed: @escaping @MainActor ([PlaylistItem]) -> Void = { _ in }) {
        Task {
            let now = epochNowMs()
            var rows: [PlaylistItem] = []
            for itemId in itemIds {
                if let row = try? await library.store.removeFromPlaylist(id, itemId: itemId, now: now) { rows.append(row) }
            }
            guard !rows.isEmpty else { return }
            sync.changed(id)
            removed(rows)
        }
    }

    /// Puts songs taken out together back, the last taken out first, so each lands in its place.
    func restoreAll(_ id: String, rows: [PlaylistItem]) {
        Task {
            let now = epochNowMs()
            for row in rows.reversed() { try? await library.store.restoreToPlaylist(id, item: row, now: now) }
            sync.changed(id)
        }
    }

    /// Takes back an add: the rows it made go again.
    func removeRows(_ id: String, itemIds: [Int64]) {
        Task {
            try? await library.store.removeItemsFromPlaylist(id, itemIds: itemIds, now: epochNowMs())
            sync.changed(id)
        }
    }

    /// Puts a song taken out back in the place it had.
    func restore(_ id: String, row: PlaylistItem) {
        Task {
            try? await library.store.restoreToPlaylist(id, item: row, now: epochNowMs())
            sync.changed(id)
        }
    }

    /// Moves a song into the place of the one it was dropped on.
    func move(_ id: String, itemId: Int64, targetId: Int64) {
        Task {
            try? await library.store.moveInPlaylist(id, itemId: itemId, targetId: targetId, now: epochNowMs())
            sync.changed(id)
        }
    }

    /// Makes a playlist only on the phone on the server too, and keeps them in step.
    func saveToServer(_ id: String) { sync.saveToServer(id) }

    /// Brings in what changed in the server's playlists since the last look, at most once a minute.
    func freshen() { sync.freshen() }

    /// Songs by id for a playlist: library songs, and finds shaped like them.
    private func songs(_ ids: [String]) async -> [LibraryTrack] { await library.songs(ids: ids) }
}

/// Favorite albums and artists. A change is saved on the phone first, then the server's copy follows.
@MainActor
@Observable
final class FavoriteStore {
    private(set) var albums: Set<String> = []
    private(set) var artists: Set<String> = []

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let sync: FavoriteSync
    @ObservationIgnored private var watch: Watch<Int>?

    init(library: Library, sync: FavoriteSync) {
        self.library = library
        self.sync = sync
        watch = Watch({ [weak library] in library?.favoritesVersion ?? 0 }) { [weak self] _ in Task { await self?.reload() } }
        Task { await reload() }
    }

    private func reload() async {
        albums = await library.likedAlbumIds()
        artists = await library.likedArtistIds()
    }

    func ids(_ kind: FavoriteKind) -> Set<String> { kind == .album ? albums : artists }

    func toggle(_ kind: FavoriteKind, _ id: String) { set(kind, id, favorite: !ids(kind).contains(id)) }

    func set(_ kind: FavoriteKind, _ id: String, favorite: Bool) {
        Task {
            let store = library.store
            switch kind {
            case .album:
                if favorite {
                    guard let key = try? await store.albumKey(id) else { return }
                    try? await store.likeAlbums([LikedAlbumRow(albumId: id, relinkKey: key.searchKey, likedAt: epochNowMs())])
                } else {
                    try? await store.unlikeAlbum(id)
                }
            case .artist:
                if favorite {
                    guard let key = try? await store.artistKey(id) else { return }
                    try? await store.likeArtists([LikedArtistRow(artistId: id, relinkKey: key.searchKey, likedAt: epochNowMs())])
                } else {
                    try? await store.unlikeArtist(id)
                }
            }
            sync.changed(kind, id, liked: favorite)
        }
    }
}

/// Albums, artists and playlists pinned to the front of Home, in the order they were pinned
/// unless moved. Home holds at most `pinLimit`.
@MainActor
@Observable
final class PinStore {
    /// The pins Home can show now, in row order.
    private(set) var shown: [PinnedItem] = []

    @ObservationIgnored private let library: Library
    @ObservationIgnored private var watch: Watch<Int>?

    init(library: Library) {
        self.library = library
        watch = Watch({ [weak library] in library?.stamp(.pins, .library, .playlists) ?? 0 }) { [weak self] _ in
            Task { await self?.reload() }
        }
        Task { await reload() }
    }

    private func reload() async { shown = await library.shownPins() }

    func isPinned(_ kind: PinKind, _ id: String) -> Bool { shown.contains { $0.kind == kind.rawValue && $0.itemId == id } }

    /// Pins at the end of the row. False when Home is full.
    func pin(_ kind: PinKind, _ id: String) async -> Bool {
        let store = library.store
        let relinkKey: String
        switch kind {
        case .album:
            guard let key = try? await store.albumKey(id) else { return false }
            relinkKey = key.searchKey
        case .artist:
            guard let key = try? await store.artistKey(id) else { return false }
            relinkKey = key.searchKey
        case .playlist:
            // A playlist's id never changes.
            relinkKey = id
        }
        return (try? await store.pin(PinnedItem(kind: kind.rawValue, itemId: id, relinkKey: relinkKey, position: 0))) ?? false
    }

    func unpin(_ kind: PinKind, _ id: String) async { try? await library.store.unpin(kind: kind.rawValue, itemId: id) }

    func moveToFront(_ kind: PinKind, _ id: String) async { try? await library.store.moveToFront(kind: kind.rawValue, itemId: id) }
}

/// Plays: a song began, or one counted. Each play is kept on the phone and handed to the server
/// and ListenBrainz.
@MainActor
final class PlayStore {
    private let library: Library
    private let listening: ListeningSync
    /// The real length of a song once playing it found its listing wrong.
    var realLength: (@MainActor (_ trackId: String, _ listedMs: Int64) -> Int64)?

    init(library: Library, listening: ListeningSync) {
        self.library = library
        self.listening = listening
    }

    /// A song began to play.
    func started(_ trackId: String) {
        listening.nowPlaying(trackId)
        Task {
            if let song = await playedSong(trackId) { ListenBrainzSync.shared.nowPlaying(song) }
        }
    }

    /// A song stopped or ended after `playedMs` heard of `durationMs`: kept when it counts as a play.
    func record(_ trackId: String, startedAt: Int64, playedMs: Int64, durationMs: Int64) {
        guard PlayRules.countsAsPlay(played: Double(playedMs) / 1000, duration: Double(durationMs) / 1000) else { return }
        Task {
            let store = library.store
            let key = (try? await store.track(trackId))?.relinkKey ?? ""
            try? await store.addPlay(PlayEvent(trackId: trackId, relinkKey: key, startedAt: startedAt, playedMs: playedMs, durationMs: durationMs))
        }
        listening.played(trackId, startedAt: startedAt)
        Task {
            if let song = await playedSong(trackId) {
                ListenBrainzSync.shared.played(song, startedAt: Date(timeIntervalSince1970: Double(startedAt) / 1000))
            }
        }
    }

    /// What the library knows about a song that played, for ListenBrainz: its details from every
    /// copy, and whether the server hears the play. Nil for anything not in the library or the
    /// finds (radio streams, opened files).
    func playedSong(_ trackId: String) async -> PlayedSong? {
        var song: PlayedSong
        if isFind(trackId) {
            guard let find = await library.finds([trackId]).first else { return nil }
            song = PlayedSong(find.title, find.artist, find.album, durationMs: find.durationMs, trackNumber: nil, reachesServer: true)
        } else {
            guard let track = await library.track(trackId) else { return nil }
            let copies = await library.copies(trackId)
            let details = songDetails(copies)
            song = PlayedSong(track.title, track.artist, track.album, durationMs: track.durationMs, trackNumber: track.trackNo,
                              reachesServer: playReachesServer(isFind: false, copySources: copies.map(\.sourceId)),
                              recordingMbid: details.mbRecordingId, releaseMbid: details.mbAlbumId,
                              releaseGroupMbid: details.mbReleaseGroupId, artistMbids: details.mbArtistIds)
        }
        if let realLength { song.durationMs = realLength(trackId, song.durationMs) }
        return song
    }
}
