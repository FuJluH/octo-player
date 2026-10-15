import Foundation
import Observation
import OctoKit

/// When a server's library was last copied, and how much came.
struct LastSync: Equatable {
    /// The kept server the copy was made for.
    var accountId: String
    var sourceId: String
    var at: Int64
    var songs: Int
    var albums: Int
}

/// A copy older than this is made again when the app starts.
private let staleMs: Int64 = 6 * 60 * 60 * 1000

/// Raised whenever a copy learns to keep something new from the server, so the next start copies
/// the library again whatever its age.
private let rowsVersion = 6

/// The account in use, as far as copying its library goes.
struct SyncAccount: Equatable {
    var id: String
    var sourceId: String
}

/// Keeps a copy of each kept server's library beside the phone's music: copied after signing in,
/// at app start when the last copy is old, and when asked. Only the server in use joins the
/// library; the others' copies wait for a switch, which then needs no new copy unless it is old.
/// Removing a server takes its copy away. Two accounts on one address share one copy, made again
/// when the other one is in use.
@MainActor
@Observable
final class ServerSync {
    private(set) var syncing = false
    /// Why the last copy failed, in words; nil once one works.
    private(set) var problem: String?
    /// The last copy of the server in use.
    private(set) var last: LastSync?

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let prefs = Prefs("server_sync")
    @ObservationIgnored private var job: Task<Void, Never>?
    @ObservationIgnored private var arriving: Task<Void, Never>?
    @ObservationIgnored private var watch: Watch<SyncAccount?>?
    @ObservationIgnored private var started = false
    /// What runs after each copy, in order: likes and plays, favorites, finds that arrived,
    /// playlists, downloads. Each part adds its own step when it starts.
    @ObservationIgnored private var steps: [(name: String, run: @MainActor () async -> Void)] = []

    init(session: Session, library: Library) {
        self.session = session
        self.library = library
    }

    /// The server in use, when one is signed in.
    var account: SyncAccount? {
        guard session.client != nil, let server = session.active, !server.signedOut else { return nil }
        return SyncAccount(id: server.id, sourceId: server.sourceId)
    }

    /// Adds a step that runs after every copy. Steps run in the order they were added.
    func afterSync(_ name: String, _ run: @escaping @MainActor () async -> Void) {
        steps.removeAll { $0.name == name }
        steps.append((name, run))
        steps.sort { Self.order($0.name) < Self.order($1.name) }
    }

    private static func order(_ name: String) -> Int {
        ["listening", "favorites", "finds", "playlists", "downloads"].firstIndex(of: name) ?? 99
    }

    func start() {
        guard !started else { return }
        started = true
        watch = Watch({ [weak self] in self?.account }) { [weak self] account in self?.arrive(account) }
        arrive(account)
    }

    private func arrive(_ account: SyncAccount?) {
        let previous = arriving
        arriving = Task { [weak self] in
            await previous?.value
            await self?.arrived(account)
        }
    }

    /// Another server (or none) is in use: a copy of the last one stops, the library becomes the
    /// new one's, and its copy is made again when old.
    private func arrived(_ account: SyncAccount?) async {
        job?.cancel()
        await job?.value
        problem = nil
        await dropUnkept()
        let want = account?.sourceId ?? ""
        library.serverInUse = account?.sourceId
        if prefs.string("library_server") != want {
            _ = try? await library.store.rebuild(serverInUse: account?.sourceId)
            prefs.set(want, "library_server")
        }
        library.ready = account?.id ?? phoneLibrary
        refreshLast()
        if let account, stale(account) { syncNow() }
    }

    /// Whether the server's copy should be made again: never made, made by an older version, old,
    /// or made for another account on the same address.
    private func stale(_ account: SyncAccount) -> Bool {
        guard let at = prefs.int64("synced_at", account.id) else { return true }
        return prefs.int("rows_version", account.id) != rowsVersion
            || prefs.string("copy_of", account.sourceId) != account.id
            || epochNowMs() - at > staleMs
    }

    /// Starts a copy unless one is already running.
    func syncNow() {
        guard job == nil else { return }
        job = Task { [weak self] in
            await self?.sync()
            self?.job = nil
        }
    }

    /// Starts a copy unless one is already running, and waits for it to end. Answers why it
    /// failed, in words, or nil when it worked.
    func syncNowAndWait() async -> String? {
        syncNow()
        await job?.value
        return problem
    }

    /// Copies the library afresh, stopping a copy already running: for when what the copy should
    /// hold has changed, like the chosen music folder.
    func syncAgain() {
        Task { [weak self] in
            guard let self else { return }
            self.job?.cancel()
            await self.job?.value
            self.syncNow()
        }
    }

    /// The music folder the library is limited to on this account, if one was chosen.
    func musicFolder(_ accountId: String) -> String? { prefs.string("music_folder", accountId) }

    /// Limits the library to one music folder (nil for all), and copies it again.
    func chooseMusicFolder(_ folderId: String?, for accountId: String) {
        prefs.set(folderId, "music_folder", accountId)
        if accountId == account?.id { syncAgain() }
    }

    /// Stops a copy of the server being signed out of. Its copy stays for signing in again.
    func stopCopy() async {
        job?.cancel()
        await job?.value
    }

    /// After a kept server is taken off the list: its copy goes (unless another kept account
    /// shares the address), and its record with it.
    func forget(_ accountId: String) async {
        for name in ["synced_at", "songs", "albums", "rows_version", "source_id", "music_folder"] { prefs.remove(name, accountId) }
        await dropUnkept()
        refreshLast()
    }

    /// Puts one song from the server into the library at once, with the rest of its album as the
    /// server has it now, ahead of the next full copy: for a download that just finished. Answers
    /// the library song it became, or nil when the server could not give it.
    func takeInSong(_ serverId: String) async -> String? {
        guard let account, let client = session.client else { return nil }
        let sourceId = account.sourceId
        guard let song = try? await client.fullSong(serverId) else { return nil }
        var album: ServerAlbum?
        if let albumId = song.albumId, !albumId.isEmpty { album = try? await client.fullAlbum(albumId) }
        var seen = Set<String>()
        let songs = ((album?.song ?? []) + [song]).filter { seen.insert($0.id).inserted }
        let rows = buildServerCatalog(sourceId, ServerLibrary(songs, album.map { [$0] } ?? [], []))
        let store = library.store
        do {
            // Only what the library does not have yet goes in; the next full copy puts everything right.
            let have = Set(try await store.libraryLinks(sourceId, songs.map(\.id)).map(\.serverId))
            let tracks = rows.tracks.filter { !have.contains($0.nativeId) }
            if !tracks.isEmpty {
                let albums = Set(try await store.knownAlbums(sourceId, rows.albums.map(\.nativeId)))
                let artists = Set(try await store.knownArtists(rows.artists.map(\.id)))
                try await store.insertSourceRows(tracks: tracks, albums: rows.albums.filter { !albums.contains($0.nativeId) },
                                                 artists: rows.artists.filter { !artists.contains($0.id) })
                try await store.rebuild(serverInUse: sourceId)
            }
            return try await store.libraryLinks(sourceId, [serverId]).first?.trackId
        } catch {
            return nil
        }
    }

    private func sync() async {
        guard let account, let client = session.client else { return }
        let sourceId = account.sourceId
        let folder = musicFolder(account.id)
        syncing = true
        defer { syncing = false }
        do {
            let read = try await client.readLibrary(folder: folder)
            try Task.checkCancellation()
            let catalog = await Task.detached(priority: .utility) { buildServerCatalog(sourceId, read) }.value
            try Task.checkCancellation()
            try await library.store.replaceSource(sourceId, tracks: catalog.tracks, albums: catalog.albums, artists: catalog.artists)
            try await library.store.rebuild(serverInUse: sourceId)
            for step in steps {
                if Task.isCancelled { break }
                await step.run()
            }
            // A copy cut short saves nothing of itself, so it is made again.
            try Task.checkCancellation()
            prefs.set(sourceId, "source_id", account.id)
            prefs.set(epochNowMs(), "synced_at", account.id)
            prefs.set(catalog.tracks.count, "songs", account.id)
            prefs.set(catalog.albums.count, "albums", account.id)
            prefs.set(rowsVersion, "rows_version", account.id)
            prefs.set(account.id, "copy_of", sourceId)
            problem = nil
            refreshLast()
        } catch let error where isCancellation(error) {
            // A copy stopped says nothing.
        } catch {
            problem = userMessage(error)
        }
    }

    /// Removes the music of every server no longer kept. A signed-out server is still kept, so
    /// signing in again needs no new copy.
    private func dropUnkept() async {
        let kept = Set(session.servers.map(\.sourceId))
        let store = library.store
        let gone = ((try? await store.sourceIds()) ?? []).filter { isServerSource($0) && !kept.contains($0) }
        for source in gone {
            try? await store.deleteSource(source)
            prefs.remove("copy_of", source)
        }
        // Playlists kept with a server that is gone stay, only on the phone.
        try? await store.unlinkServersExcept(Array(kept))
    }

    private func refreshLast() {
        guard let account, let sourceId = prefs.string("source_id", account.id), let at = prefs.int64("synced_at", account.id) else {
            last = nil
            return
        }
        last = LastSync(accountId: account.id, sourceId: sourceId, at: at, songs: prefs.int("songs", account.id) ?? 0, albums: prefs.int("albums", account.id) ?? 0)
    }
}
