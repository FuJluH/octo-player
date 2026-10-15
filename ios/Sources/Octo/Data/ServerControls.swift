import Foundation
import Observation
import OctoKit

/// Controls for the signed-in server beyond its library: whether the user is an admin, a library
/// scan, shared links, who else is listening, and radio stations. What the server refuses is
/// remembered for the run.
@MainActor
@Observable
final class ServerControls {
    /// Whether the user is an admin, asked on each sign-in; false while asking or on failure.
    private(set) var isAdmin = false
    private(set) var scan: ServerScanState = .idle
    /// Whether the server in use shares links, until it refuses.
    var sharing: Bool { session.inUse.map { !notSharing.contains($0.account) } ?? false }

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let sync: ServerSync
    private var notSharing = Set<String>()
    /// Stations each kept server refused to change, by its id and theirs.
    @ObservationIgnored private var readOnly: [String: Set<String>] = [:]
    @ObservationIgnored private var scanning: Task<Void, Never>?
    @ObservationIgnored private var watch: Watch<SignedInUser?>?
    /// Each library song's server id for sharing, once looked up; dropped when the server or the
    /// library changes.
    @ObservationIgnored private var shareLookups: [String: ShareLookup] = [:]
    /// Goes up whenever the looked-up ids are dropped, so the menus that read them ask again.
    private var shareLookupEpoch = 0
    @ObservationIgnored private var copiesWatch: Watch<Int>?

    /// Who is signed in where: another kept server, or another user on the same one, is a new
    /// sign-in.
    struct SignedInUser: Equatable {
        let account: String
        let username: String
    }

    init(session: Session, library: Library, sync: ServerSync) {
        self.session = session
        self.library = library
        self.sync = sync
        watch = Watch({ [weak session] in session?.inUse.map { SignedInUser(account: $0.account, username: $0.username) } }) { [weak self] _ in
            self?.serverChanged()
        }
        copiesWatch = Watch({ [weak library] in library?.stamp(.library, .sources) ?? 0 }) { [weak self] _ in self?.dropShareLookups() }
        serverChanged()
    }

    private func serverChanged() {
        dropShareLookups()
        isAdmin = false
        scanning?.cancel()
        scanning = nil
        scan = .idle
        guard let server = session.inUse else { return }
        Task {
            let name = server.username
            guard !name.isEmpty, let user = try? await server.client.user(name) else { return }
            if let now = session.inUse, now.account == server.account, now.username == name { isAdmin = user.adminRole }
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

    /// The server's id for a library song, for sharing, as far as it is known now: nil until it
    /// has been looked up, and when the song has no copy on the server in use. Asking starts the
    /// look-up; the answer reaches whoever asked through observation.
    func knownShareableSongId(_ trackId: String) -> String? {
        _ = shareLookupEpoch
        let lookup: ShareLookup
        if let known = shareLookups[trackId] {
            lookup = known
        } else {
            lookup = ShareLookup()
            shareLookups[trackId] = lookup
            let epoch = shareLookupEpoch
            Task { [weak self] in
                guard let self else { return }
                let id = await self.shareableSongId(trackId)
                guard self.shareLookupEpoch == epoch else { return }
                lookup.answer = .some(id)
            }
        }
        return lookup.answer ?? nil
    }

    private func dropShareLookups() {
        guard !shareLookups.isEmpty else { return }
        shareLookups = [:]
        shareLookupEpoch += 1
    }

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

    /// Makes a link to songs or an album that lasts as chosen. With no server signed in it fails
    /// as a server refusal would.
    func createShare(_ ids: [String], description: String? = nil, expiry: ShareExpiry) async throws -> ServerShare {
        guard let server = session.inUse else { throw OctoError.server(code: 0, message: noServerSignedIn) }
        return try await guarded(server) {
            try await server.client.serverCreateShare(ids, description: description, expiresAtMs: shareExpiresAt(expiry, now: epochNowMs()))
        }
    }

    /// Deletes a link. A refusal here never marks the server as not sharing.
    func deleteShare(_ id: String) async throws {
        guard let server = session.inUse else { return }
        try await server.client.serverDeleteShare(id)
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

    /// The same, for a station read with all its details.
    func canEdit(stationId: String, coverArt: String?) -> Bool {
        guard let server = session.inUse else { return false }
        return !looksGenerated(stationId: stationId, coverArt: coverArt, isOcto: server.isOcto)
            && !(readOnly[server.account] ?? []).contains(stationId)
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

/// What sharing says when no server is signed in.
let noServerSignedIn = "No server signed in"

/// One song's server id for sharing: nil while it is looked up, then the answer, which is
/// itself nil when the server in use has no copy.
@MainActor
@Observable
final class ShareLookup {
    var answer: String?? = nil
}
