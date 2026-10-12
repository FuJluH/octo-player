import Foundation
import Observation
import OctoKit
import Security

/// The ListenBrainz token, kept in the keychain under a key of its own, apart from the server
/// passwords, so signing out of a server keeps ListenBrainz connected. It stays on this phone: a
/// backup restored on another phone has no token, and the settings then say it needs attention.
private enum TokenVault {
    private static let service = "app.winters.octo.listenbrainz"
    private static let account = "token"

    static func save(_ token: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func forget() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}

/// Sends what is played on this phone to the listener's ListenBrainz profile, with or without a
/// server. Each counted play waits in a queue on the phone until ListenBrainz has it; sending never
/// holds up playback or shows a message, and what fails is tried again later.
@MainActor
@Observable
final class ListenBrainzSync {
    private(set) var prefs: ListenBrainzPrefs
    /// How many plays are waiting.
    private(set) var queued = 0

    /// The real length of a song once playing it found its listing wrong.
    @ObservationIgnored var realLength: (@MainActor (_ trackId: String, _ listedMs: Int64) -> Int64)?
    /// A song opened from a file outside the library: its title and artist, by its queue id.
    @ObservationIgnored var openedFile: (@MainActor (_ trackId: String) -> (title: String, artist: String)?)?

    @ObservationIgnored private let library: Library
    @ObservationIgnored private let connectivity: Connectivity
    @ObservationIgnored private let stored = Prefs("listenbrainz")
    @ObservationIgnored private let api: ListenBrainzApi
    @ObservationIgnored private let version: String
    @ObservationIgnored private let sending = SerialWork()
    @ObservationIgnored private var backoff = ListenBrainzBackoff()
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var queue: [Listen]?
    @ObservationIgnored private var started = false

    private static var queueFile: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("listenbrainz_queue.json")
    }

    init(library: Library, connectivity: Connectivity, version: String) {
        self.library = library
        self.connectivity = connectivity
        self.version = version
        api = ListenBrainzApi(client: ListenBrainzClient(userAgent: listenBrainzUserAgent(version: version)))
        prefs = ListenBrainzPrefs()
        prefs = readPrefs()
    }

    private func readPrefs() -> ListenBrainzPrefs {
        ListenBrainzPrefs(enabled: stored.bool("enabled") ?? false, user: stored.string("user"),
                          needsAttention: stored.bool("needs_attention") ?? false,
                          sendPlays: sendPlaysOf(stored.string("send_plays")), nowPlaying: stored.bool("now_playing") ?? true)
    }

    private func update(_ change: () -> Void) {
        change()
        prefs = readPrefs()
    }

    /// At app start: sends what waited from last time, and again whenever a connection comes back.
    func start() {
        guard !started else { return }
        started = true
        connectivity.onChange { [weak self] in
            guard let self, self.connectivity.online else { return }
            Task { await self.send(now: true) }
        }
        Task {
            _ = loadQueue()
            await send(now: true)
        }
    }

    // MARK: Settings

    /// Checks a pasted token and, when ListenBrainz takes it, keeps it and sends what is waiting.
    func connect(_ token: String) async -> TokenCheck {
        let clean = cleanListenBrainzToken(token)
        let check = (try? await api.validate(clean)) ?? .unreachable
        if case .valid(let user) = check {
            let letGo = connectingLetsQueueGo(previousUser: stored.string("user"), user: user)
            TokenVault.save(clean)
            update {
                stored.set(user, "user")
                stored.set(false, "needs_attention")
                stored.set(true, "enabled")
            }
            if letGo { writeQueue([]) }
            backoff.reset()
            Task { await send(now: true) }
        }
        return check
    }

    func disconnect() {
        Task {
            await sending.run {
                self.update {
                    self.stored.remove("user")
                    self.stored.remove("needs_attention")
                    self.stored.set(false, "enabled")
                }
                TokenVault.forget()
                self.writeQueue([])
            }
        }
    }

    func setEnabled(_ on: Bool) {
        update { stored.set(on, "enabled") }
        if on { Task { await send(now: true) } }
    }

    func setSendPlays(_ mode: SendPlays) { update { stored.set(mode.rawValue, "send_plays") } }

    func setNowPlaying(_ on: Bool) { update { stored.set(on, "now_playing") } }

    /// Puts back the choices from a backup in one go. Who is connected is left as it is.
    func restoreChoices(enabled: Bool, sendPlays: SendPlays, nowPlaying: Bool) {
        update {
            stored.set(enabled, "enabled")
            stored.set(sendPlays.rawValue, "send_plays")
            stored.set(nowPlaying, "now_playing")
        }
    }

    // MARK: Plays

    /// A play counted. It waits in the queue until ListenBrainz has it.
    func played(_ trackId: String, startedAt: Int64) {
        Task {
            guard let listen = listenToQueue(prefs, await songOf(trackId), startedAtMs: startedAt) else { return }
            writeQueue(loadQueue().plusListen(listen))
            await send(now: false)
        }
    }

    /// A song started. ListenBrainz shows it as playing now; a failure here does not matter, as
    /// the next song replaces it.
    func nowPlaying(_ trackId: String) {
        Task {
            guard let listen = listenPlayingNow(prefs, await songOf(trackId), nowMs: epochNowMs()), let token = TokenVault.read() else { return }
            if (try? await api.playingNow(token, listen, clientVersion: version)) == .unauthorized {
                update { stored.set(true, "needs_attention") }
            }
        }
    }

    /// Sends the waiting plays, oldest first, in batches. `now` tries even while waiting after
    /// failures; a new play waits its turn.
    private func send(now: Bool) async {
        await sending.run { [weak self] in await self?.sendOnce(now: now) }
    }

    private func sendOnce(now: Bool) async {
        guard backoff.allowsSend(now: now, atMs: epochNowMs()), prefs.sends else { return }
        guard let token = TokenVault.read() else {
            // The saved token can no longer be opened, so it needs pasting again.
            update { stored.set(true, "needs_attention") }
            return
        }
        while true {
            let batch = nextBatch(loadQueue())
            if batch.isEmpty { return }
            let api = api
            let version = version
            let result = (try? await deliverListens(batch, submit: { @Sendable listens in
                try await api.submit(token, listens, clientVersion: version)
            }, remove: { @Sendable [weak self] done in
                await MainActor.run { self?.removeFromQueue(done) }
            })) ?? .failed
            switch backoff.heard(result, atMs: epochNowMs()) {
            case .goOn:
                continue
            case .needsAttention:
                update { stored.set(true, "needs_attention") }
                return
            case .retry(let afterMs):
                retryIn(afterMs)
                return
            }
        }
    }

    private func retryIn(_ delayMs: Int64) {
        retry?.cancel()
        retry = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delayMs))
            if Task.isCancelled { return }
            await self?.send(now: true)
        }
    }

    // MARK: The queue file

    private func loadQueue() -> [Listen] {
        if let queue { return queue }
        let read = decodeListenQueue(try? Data(contentsOf: Self.queueFile))
        queue = read
        queued = read.count
        return read
    }

    /// Takes sent (or refused) plays out of the queue.
    private func removeFromQueue(_ done: [Listen]) {
        writeQueue(loadQueue().removingListens(done))
    }

    private func writeQueue(_ next: [Listen]) {
        try? encodeListenQueue(next).write(to: Self.queueFile, options: .atomic)
        queue = next
        queued = next.count
    }

    // MARK: What played

    /// What the app knows about a song that played. Radio streams are left out; an opened file
    /// goes only with its title and artist, as one that never reaches the server.
    private func songOf(_ trackId: String) async -> PlayedSong? {
        guard var song = await listedSongOf(trackId) else { return nil }
        if let realLength { song.durationMs = realLength(trackId, song.durationMs) }
        return song
    }

    private func listedSongOf(_ trackId: String) async -> PlayedSong? {
        if trackId.hasPrefix("radio:") { return nil }
        if trackId.hasPrefix("file:") {
            guard let file = openedFile?(trackId) else { return nil }
            return PlayedSong(title: file.title, artist: file.artist, album: "", durationMs: 0, trackNumber: nil, reachesServer: false)
        }
        if isFind(trackId) {
            guard let find = await library.finds([trackId]).first else { return nil }
            return PlayedSong(title: find.title, artist: find.artist, album: find.album, durationMs: find.durationMs, trackNumber: nil,
                              reachesServer: true)
        }
        guard let track = await library.track(trackId) else { return nil }
        let copies = await library.copies(trackId)
        let details = songDetails(copies)
        return PlayedSong(title: track.title, artist: track.artist, album: track.album, durationMs: track.durationMs,
                          trackNumber: track.trackNo, reachesServer: playReachesServer(trackId, copySources: copies.map(\.sourceId)),
                          recordingMbid: details.mbRecordingId, releaseMbid: details.mbAlbumId,
                          releaseGroupMbid: details.mbReleaseGroupId, artistMbids: details.mbArtistIds)
    }
}
