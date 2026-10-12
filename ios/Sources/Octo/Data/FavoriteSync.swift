import Foundation
import OctoKit

/// How many albums or artists go in one star or unstar call.
private let favoriteBatch = 50

/// Keeps favorite albums and artists in step with stars on the signed-in server, the way the
/// listening sync does for liked songs: a favorite made on the phone stars the server's copy, and
/// stars made elsewhere come back as favorites after each sync. Albums and artists only on the
/// phone stay local. Nothing here shows an error; a change that fails to send is tried again
/// shortly, and the next sync catches whatever is still left.
@MainActor
final class FavoriteSync {
    private let session: Session
    private let library: Library
    private let prefs = Prefs("favourite_stars")
    private let lock = SerialWork()

    init(session: Session, library: Library, sync: ServerSync) {
        self.session = session
        self.library = library
        sync.afterSync("favorites") { [weak self] in await self?.afterSync() }
    }

    /// The server album or artist ids both sides last agreed were starred, per account and kind.
    private func synced(_ account: String, _ kind: FavoriteKind) -> Set<String> { prefs.strings(name(kind), account) }

    private func updateSynced(_ account: String, _ kind: FavoriteKind, _ change: (Set<String>) -> Set<String>) {
        prefs.set(strings: change(synced(account, kind)), name(kind), account)
    }

    private func name(_ kind: FavoriteKind) -> String { kind == .album ? "synced_albums" : "synced_artists" }

    /// Forgets everything kept for a server taken off the list.
    func forget(_ account: String) { prefs.forgetAccount(account) }

    /// Runs after each sync of the server's library.
    func afterSync() async {
        guard let server = session.inUse else { return }
        // Without the server's stars as they are now, nothing can be decided.
        guard let starred = try? await server.client.starred() else { return }
        await lock.run { [weak self] in
            guard let self else { return }
            let albums = await self.copies(server, .album)
            if !albums.isEmpty {
                var times: [String: Int64?] = [:]
                for album in starred.album { times[album.id] = parseServerTime(album.starred) }
                await self.reconcile(server, .album, albums, await self.likedIds(.album), times)
            }
            let artists = await self.copies(server, .artist)
            if !artists.isEmpty {
                var times: [String: Int64?] = [:]
                for artist in starred.artist { times[artist.id] = parseServerTime(artist.starred) }
                await self.reconcile(server, .artist, artists, await self.likedIds(.artist), times)
            }
        }
    }

    /// A favorite changed on the phone. The server's copies follow at once; a try that fails is
    /// made again a few times, then left to the next sync.
    func changed(_ kind: FavoriteKind, _ libraryId: String, liked: Bool) {
        Task { [weak self] in
            guard let self else { return }
            if await self.sendChange(kind, libraryId, liked) { return }
            for wait in favoriteRetryWaits {
                try? await Task.sleep(for: .milliseconds(wait))
                if await self.sendChange(kind, libraryId, liked) { return }
            }
        }
    }

    /// One try at sending a change. True when nothing is left to send.
    private func sendChange(_ kind: FavoriteKind, _ libraryId: String, _ liked: Bool) async -> Bool {
        // No server at all means nothing to send.
        guard let server = session.inUse else { return session.active == nil || session.active?.signedOut == true }
        let done = Outcome()
        await lock.run { [weak self] in
            guard let self else { return }
            let likedNow = await self.likedIds(kind).contains(libraryId)
            let ids = idsToSend(await self.copies(server, kind), libraryId: libraryId, liked: liked, likedNow: likedNow)
            if ids.isEmpty {
                done.value = true
                return
            }
            let sent = await failureOf { try await self.call(server, kind, star: liked, ids) } == nil
            if sent { self.updateSynced(server.account, kind) { liked ? $0.union(ids) : $0.subtracting(ids) } }
            done.value = sent
        }
        return done.value
    }

    /// The server call that stars or unstars albums or artists, each by its own parameter.
    private func call(_ server: ServerInUse, _ kind: FavoriteKind, star: Bool, _ ids: [String]) async throws {
        switch (kind, star) {
        case (.album, true): try await server.client.star(albumIds: ids)
        case (.album, false): try await server.client.unstar(albumIds: ids)
        case (.artist, true): try await server.client.star(artistIds: ids)
        case (.artist, false): try await server.client.unstar(artistIds: ids)
        }
    }

    private func likedIds(_ kind: FavoriteKind) async -> Set<String> {
        kind == .album ? await library.likedAlbumIds() : await library.likedArtistIds()
    }

    private func reconcile(_ server: ServerInUse, _ kind: FavoriteKind, _ copies: [ServerCopy], _ liked: Set<String>,
                           _ starredAt: [String: Int64?]) async {
        let plan = reconcileStars(copies, liked: liked, starred: Set(starredAt.keys), synced: synced(server.account, kind))
        var starFailed = Set<String>()
        for batch in plan.star.sorted().catalogBatches(favoriteBatch)
        where await failureOf({ try await self.call(server, kind, star: true, batch) }) != nil {
            starFailed.formUnion(batch)
        }
        var unstarFailed = Set<String>()
        for batch in plan.unstar.sorted().catalogBatches(favoriteBatch)
        where await failureOf({ try await self.call(server, kind, star: false, batch) }) != nil {
            unstarFailed.formUnion(batch)
        }
        // A favorite from the server keeps the time it was starred there.
        var likedAt: [String: Int64] = [:]
        for copy in copies {
            guard let at = starredAt[copy.serverId] ?? nil else { continue }
            likedAt[copy.trackId] = min(likedAt[copy.trackId] ?? at, at)
        }
        let now = epochNowMs()
        let store = library.store
        switch kind {
        case .album:
            var rows: [LikedAlbumRow] = []
            for id in plan.like.sorted() {
                if let key = try? await store.albumKey(id) { rows.append(LikedAlbumRow(albumId: id, relinkKey: key.searchKey, likedAt: likedAt[id] ?? now)) }
            }
            try? await store.likeAlbums(rows)
            for id in plan.unlike { try? await store.unlikeAlbum(id) }
        case .artist:
            var rows: [LikedArtistRow] = []
            for id in plan.like.sorted() {
                if let key = try? await store.artistKey(id) { rows.append(LikedArtistRow(artistId: id, relinkKey: key.searchKey, likedAt: likedAt[id] ?? now)) }
            }
            try? await store.likeArtists(rows)
            for id in plan.unlike { try? await store.unlikeArtist(id) }
        }
        updateSynced(server.account, kind) { _ in plan.settled(starFailed: starFailed, unstarFailed: unstarFailed) }
    }

    /// The library's albums or artists and their copies on the signed-in server.
    private func copies(_ server: ServerInUse, _ kind: FavoriteKind) async -> [ServerCopy] {
        let store = library.store
        let counts = kind == .album
            ? ((try? await store.serverAlbumCounts(server.sourceId)) ?? [])
            : ((try? await store.serverArtistCounts(server.sourceId)) ?? [])
        return serverCopiesOf(counts, sourceId: server.sourceId)
    }
}

/// How one piece of serial work came out, read once it has run.
@MainActor
private final class Outcome {
    var value = false
}
