import Foundation
import Observation
import OctoKit

/// Controls for the signed-in server beyond its library: whether the user is an admin, a library
/// scan, shared links, who else is listening, and radio stations. What the server refuses is
/// remembered for the run.
@MainActor
@Observable
final class ServerControls {
    /// Whether the user is an admin, asked once per server in use; false while asking or on failure.
    private(set) var isAdmin = false
    private(set) var scan: ServerScanState = .idle
    /// Whether the server in use shares links, until it refuses.
    var sharing: Bool { session.inUse.map { !notSharing.contains($0.account) } ?? false }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let sync: ServerSync
    @ObservationIgnored private var notSharing = Set<String>()
    /// Stations each kept server refused to change, by its id and theirs.
    @ObservationIgnored private var readOnly: [String: Set<String>] = [:]
    @ObservationIgnored private var scanning: Task<Void, Never>?
    @ObservationIgnored private var watch: Watch<String?>?

    init(session: Session, library: Library, sync: ServerSync) {
        self.session = session
        self.library = library
        self.sync = sync
        watch = Watch({ [weak session] in session?.inUse?.account }) { [weak self] _ in self?.serverChanged() }
        serverChanged()
    }

    private func serverChanged() {
        isAdmin = false
        scanning?.cancel()
        scanning = nil
        scan = .idle
        guard let server = session.inUse else { return }
        Task {
            let name = server.username
            guard !name.isEmpty, let user = try? await server.client.user(name) else { return }
            if session.inUse?.account == server.account { isAdmin = user.adminRole }
        }
    }

    // MARK: Scanning

    /// Starts a library scan and follows it every 2 s; once it ends the library is copied again.
    /// Tapping again while one runs does nothing.
    func startScan() {
        guard scanning == nil, let server = session.inUse else { return }
        scanning = Task { [weak self] in
            guard let self else { return }
            defer { self.scanning = nil }
            do {
                let first = try await server.client.serverStartScan()
                var poll = ServerScanPoll(started: first.scanning)
                self.scan = .scanning(count: first.count)
                while true {
                    try await Task.sleep(for: .milliseconds(serverScanPollMs))
                    let status = try await server.client.serverScanStatus()
                    if poll.isDone(scanning: status.scanning) { break }
                    self.scan = .scanning(count: status.count)
                }
                self.scan = .finished
                self.sync.syncNow()
            } catch {
                if isCancellation(error) { return }
                self.scan = .failed(message: serverScanFailedWords(error))
            }
        }
    }

    // MARK: Sharing

    /// The server's id for a library song, for sharing: the lowest among its copies there.
    func shareableSongId(_ trackId: String) async -> String? {
        guard let server = session.inUse else { return nil }
        if isFind(trackId) { return String(trackId.dropFirst(findPrefix.count)) }
        return serverSongId(copies: await library.copies(trackId), serverInUse: server.sourceId)
    }

    /// The server album a library album is, for sharing: the one most of its songs came from.
    func shareableAlbumId(_ albumId: String) async -> String? {
        guard let server = session.inUse else { return nil }
        let ids = (try? await library.store.albumTrackIds(albumId)) ?? []
        let copies = (try? await library.store.copies(of: ids)) ?? []
        return serverAlbumId(copies: copies, serverInUse: server.sourceId)
    }

    /// The signed-in user's shares. A server that refuses is marked as not sharing for the run.
    func shares() async throws -> [ServerShare] {
        guard let server = session.inUse else { return [] }
        return try await guarded(server) { try await server.client.serverShares() }
    }

    /// Makes a link to songs or an album that lasts as chosen.
    func createShare(_ ids: [String], description: String? = nil, expiry: ShareExpiry) async throws -> ServerShare? {
        guard let server = session.inUse else { return nil }
        return try await guarded(server) {
            try await server.client.serverCreateShare(ids, description: description, expiresAtMs: shareExpiresAt(expiry, now: epochNowMs()))
        }
    }

    func deleteShare(_ id: String) async throws {
        guard let server = session.inUse else { return }
        try await guarded(server) { try await server.client.serverDeleteShare(id) }
    }

    private func guarded<T>(_ server: ServerInUse, _ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch {
            if sharingUnavailable(error) { notSharing.insert(server.account) }
            throw error
        }
    }

    // MARK: Others listening

    /// Who is listening now: other people, and this account on other players.
    func othersListening() async throws -> [ServerNowPlaying] {
        guard let server = session.inUse else { return [] }
        return OctoKit.othersListening(try await server.client.serverNowPlaying(), username: server.username, user: \.username,
                                       player: \.playerName)
    }

    // MARK: Stations

    /// Whether a station can be changed: not one Octo makes itself, and not one the server refused.
    func canEdit(_ station: RadioStation) -> Bool {
        guard let server = session.inUse else { return false }
        return !looksGenerated(station, isOcto: server.isOcto) && !(readOnly[server.account] ?? []).contains(station.id)
    }

    func stations() async throws -> [ServerStationDetails] {
        try await session.inUse?.client.serverStationDetails() ?? []
    }

    func createStation(streamUrl: String, name: String, homepageUrl: String?) async throws {
        try await session.inUse?.client.serverCreateStation(streamUrl: streamUrl, name: name, homepageUrl: homepageUrl)
    }

    func updateStation(_ id: String, streamUrl: String, name: String, homepageUrl: String?) async throws {
        guard let server = session.inUse else { return }
        try await stationChange(server, id) { try await server.client.serverUpdateStation(id, streamUrl: streamUrl, name: name, homepageUrl: homepageUrl) }
    }

    func deleteStation(_ id: String) async throws {
        guard let server = session.inUse else { return }
        try await stationChange(server, id) { try await server.client.serverDeleteStation(id) }
    }

    private func stationChange(_ server: ServerInUse, _ id: String, _ call: () async throws -> Void) async throws {
        do {
            try await call()
        } catch {
            if stationChangeRefused(error) { readOnly = markingReadOnly(readOnly, account: server.account, stations: [id]) }
            throw error
        }
    }
}
