import Foundation
import Observation
import OctoKit

/// How many songs go in one star or unstar call, so the address stays short.
private let starBatch = 50

/// What keeping in step with each kept server remembers between launches: the stars and ratings
/// both sides last agreed on, plays waiting to be sent, and plays already sent. Each account's are
/// its own, by the kept server's id, since song ids only mean something on their server.
struct ListeningStore {
    private let prefs = Prefs("listening")

    func synced(_ account: String) -> Set<String> { prefs.strings("synced_stars", account) }
    func updateSynced(_ account: String, _ change: (Set<String>) -> Set<String>) {
        prefs.set(strings: change(synced(account)), "synced_stars", account)
    }

    func syncedRatings(_ account: String) -> [String: Int] { decodeRatings(prefs.strings("synced_ratings", account)) }
    func updateSyncedRatings(_ account: String, _ change: ([String: Int]) -> [String: Int]) {
        prefs.set(strings: encodeRatings(change(syncedRatings(account))), "synced_ratings", account)
    }

    func pending(_ account: String) -> [PendingPlay] { decodePending(prefs.strings("pending_plays", account)) }
    func addPending(_ account: String, _ play: PendingPlay) {
        prefs.set(strings: encodePending(pending(account).plusPlay(play)), "pending_plays", account)
    }

    /// A waiting play is done with: sent, or refused for good.
    func finishPending(_ account: String, _ play: PendingPlay, sent: Bool) {
        prefs.set(strings: encodePending(pending(account).filter { $0 != play }), "pending_plays", account)
        if sent { updateSent(account) { $0.plusSent(play.serverId, play.startedAt) } }
    }

    func sent(_ account: String) -> [String: SentPlays] { decodeSent(prefs.strings("sent_plays", account)) }
    func updateSent(_ account: String, _ change: ([String: SentPlays]) -> [String: SentPlays]) {
        prefs.set(strings: encodeSent(change(sent(account))), "sent_plays", account)
    }

    /// Forgets everything kept for a server taken off the list.
    func forget(_ account: String) { prefs.forgetAccount(account) }
}

/// Keeps what the listener does in step with the signed-in server: a heart stars the song's server
/// copy, a rating rates it, plays count on the server, and stars and ratings made elsewhere come
/// back. None of it ever holds up playback or shows an error; what fails is tried again later.
/// Each change is for the server in use when it was made, even when it is sent after a switch.
@MainActor
final class ListeningSync {
    private let session: Session
    private let library: Library
    let store = ListeningStore()
    /// One reconcile or send of each kind at a time.
    private let stars = SerialWork()
    private let plays = SerialWork()
    private let ratings = SerialWork()
    /// Plays still being noted, so a switch can wait for them.
    private var noting: [UUID: Task<Void, Never>] = [:]

    init(session: Session, library: Library, sync: ServerSync) {
        self.session = session
        self.library = library
        sync.afterSync("listening") { [weak self] in await self?.afterSync() }
        refreshSent()
    }

    /// The plays sent to the server in use, for counting the server's plays once.
    func refreshSent() {
        library.sentPlays = session.inUse.map { store.sent($0.account) } ?? [:]
    }

    /// Runs after each copy of the server's library: brings likes and stars together, rating
    /// with rating, notes which sent plays the server now counts, and sends plays that could not
    /// be sent before.
    func afterSync() async {
        guard let server = session.inUse else { return }
        guard let copies = try? await library.store.serverCopies(), !copies.isEmpty else { return }
        await stars.run { [weak self] in await self?.reconcile(server, copies) }
        await ratings.run { [weak self] in await self?.syncRatings(server) }
        var lastPlayed: [String: Int64?] = [:]
        for copy in copies { lastPlayed[copy.serverId] = copy.lastPlayedAt }
        store.updateSent(server.account) { $0.foldedInto(lastPlayed) }
        refreshSent()
        await plays.run { [weak self] in await self?.sendPending(server) }
    }

    /// A like changed on the phone. The song's server copies follow; a phone-only song has none.
    func likeChanged(_ trackId: String, liked: Bool) {
        guard let server = session.inUse else { return }
        Task {
            let ids = await serverIds(server, trackId)
            guard !ids.isEmpty else { return }
            await stars.run {
                let failure = await failureOf {
                    if liked { try await server.client.star(songIds: ids) } else { try await server.client.unstar(songIds: ids) }
                }
                if failure == nil { self.store.updateSynced(server.account) { liked ? $0.union(ids) : $0.subtracting(ids) } }
            }
        }
    }

    /// A rating changed on the phone. The song's server copies follow; when the server cannot take
    /// it now, the next sync sends it.
    func ratingChanged(_ trackId: String) {
        guard !isFind(trackId), let server = session.inUse else { return }
        Task {
            let ids = await serverIds(server, trackId)
            guard !ids.isEmpty else { return }
            await ratings.run {
                // The rating as it is now, so quick changes end on the last one.
                let rating = cleanRating(try? await self.library.store.rating(trackId))
                var sent = true
                for id in ids where await failureOf({ try await server.client.setRating(id, rating: rating) }) != nil { sent = false }
                if sent {
                    self.store.updateSyncedRatings(server.account) { before in
                        var next = before
                        for id in ids { next[id] = rating > 0 ? rating : nil }
                        return next
                    }
                }
            }
        }
    }

    /// A song started playing, so the server shows it as playing now.
    func nowPlaying(_ trackId: String) {
        guard let server = session.inUse else { return }
        Task {
            guard let id = await serverIds(server, trackId).first else { return }
            _ = await failureOf { try await server.client.scrobble(id, timeMs: epochNowMs(), submission: false) }
        }
    }

    /// A play counted. It waits in its server's queue until the server has it.
    func played(_ trackId: String, startedAt: Int64) {
        guard let server = session.inUse else { return }
        let key = UUID()
        noting[key] = Task { [weak self] in
            guard let self else { return }
            defer { self.noting[key] = nil }
            guard let id = await self.serverIds(server, trackId).first else { return }
            self.store.addPending(server.account, PendingPlay(serverId: id, startedAt: startedAt))
            await self.plays.run { await self.sendPending(server) }
        }
    }

    /// Waits until every play counted so far is noted for its server: before a switch, so the last
    /// song counts for the server it played from.
    func noted() async {
        for task in Array(noting.values) { await task.value }
    }

    private func reconcile(_ server: ServerInUse, _ copies: [ServerCopy]) async {
        // Without the server's stars as they are now, nothing can be decided.
        guard let starred = try? await server.client.starred().song else { return }
        let store = library.store
        let liked = Set((try? await store.likedIds()) ?? [])
        let plan = reconcileStars(copies, liked: liked, starred: Set(starred.map(\.id)), synced: self.store.synced(server.account))
        let starFailed = await inBatches(plan.star) { try await server.client.star(songIds: $0) }
        let unstarFailed = await inBatches(plan.unstar) { try await server.client.unstar(songIds: $0) }
        // A like from the server keeps the time it was starred there.
        var starredAt: [String: Int64] = [:]
        for song in starred { if let at = parseServerTime(song.starred) { starredAt[song.id] = at } }
        var likedAt: [String: Int64] = [:]
        for copy in copies {
            guard let at = starredAt[copy.serverId] else { continue }
            likedAt[copy.trackId] = min(likedAt[copy.trackId] ?? at, at)
        }
        let now = epochNowMs()
        let tracks = await library.tracks(ids: Array(plan.like))
        try? await store.likeAll(tracks.map { LikedTrack(trackId: $0.id, relinkKey: $0.relinkKey, likedAt: likedAt[$0.id] ?? now) })
        for id in plan.unlike { try? await store.unlike(id) }
        self.store.updateSynced(server.account) { _ in plan.settled(starFailed: starFailed, unstarFailed: unstarFailed) }
    }

    private func syncRatings(_ server: ServerInUse) async {
        let store = library.store
        let before = self.store.syncedRatings(server.account)
        var local: [String: Int] = [:]
        for row in (try? await store.ratings()) ?? [] { local[row.trackId] = cleanRating(row.rating) }
        let plan = reconcileRatings((try? await store.serverRatings()) ?? [], local: local, synced: before)
        var failed = Set<String>()
        for (song, send) in plan.send {
            for id in send.serverIds where await failureOf({ try await server.client.setRating(id, rating: send.rating) }) != nil {
                failed.insert(song)
            }
        }
        for (song, send) in plan.send where !failed.contains(song) { try? await store.setServerRating(song, send.rating) }
        let now = epochNowMs()
        var tracks: [String: LibraryTrack] = [:]
        for track in await library.tracks(ids: Array(plan.adopt.keys)) { tracks[track.id] = track }
        for (song, rating) in plan.adopt {
            if rating == 0 {
                try? await store.unrate(song)
            } else if let track = tracks[song] {
                try? await store.rate(TrackRating(trackId: song, relinkKey: track.relinkKey, rating: rating, ratedAt: now))
            }
        }
        // The library shows the rating both sides now have, or will once sent.
        var shown = plan.adopt
        for (song, send) in plan.send { shown[song] = send.rating }
        for (song, rating) in shown { try? await store.showRating(song, rating) }
        self.store.updateSyncedRatings(server.account) { _ in plan.settled(failed: failed, before: before) }
    }

    /// Sends the waiting plays oldest first, and stops at the first one the server cannot take now.
    private func sendPending(_ server: ServerInUse) async {
        for play in store.pending(server.account) {
            let failure = await failureOf { try await server.client.scrobble(play.serverId, timeMs: play.startedAt, submission: true) }
            // Cut short (the work was stopped): the play waits for the next send.
            if let failure, isCancellation(failure) || worthRetrying(failure) { break }
            store.finishPending(server.account, play, sent: failure == nil)
        }
        if session.inUse?.account == server.account { refreshSent() }
    }

    /// The ids that did not go through.
    private func inBatches(_ ids: Set<String>, _ call: @escaping @MainActor ([String]) async throws -> Void) async -> Set<String> {
        var failed = Set<String>()
        for batch in ids.sorted().catalogBatches(starBatch) where await failureOf({ try await call(batch) }) != nil {
            failed.formUnion(batch)
        }
        return failed
    }

    /// A song's copies on the server, the same one first every time. A find is a server song itself.
    private func serverIds(_ server: ServerInUse, _ trackId: String) async -> [String] {
        if isFind(trackId) { return [String(trackId.dropFirst(findPrefix.count))] }
        return await library.copies(trackId).filter { $0.sourceId == server.sourceId }.map(\.nativeId).sorted()
    }
}

extension Array {
    /// The list cut into runs of at most `size`.
    func catalogBatches(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
