import Foundation
import Network
import Observation
import OctoKit

/// Sends what is played on this phone to the listener's ListenBrainz profile, with or without a
/// server. Each counted play waits in a queue on the phone until ListenBrainz has it; sending
/// never holds up playback or shows a message, and what fails is tried again later.
@MainActor
@Observable
final class ListenBrainzSync {
    static let shared = ListenBrainzSync()

    /// How many plays are waiting.
    private(set) var queued = 0

    @ObservationIgnored private let settings = AppSettings.shared
    @ObservationIgnored private let api: ListenBrainzApi
    @ObservationIgnored private var queue: [Listen]?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var sending = false
    @ObservationIgnored private var sendAgain = false
    /// Whether a send asked for while another ran was one that goes at once.
    @ObservationIgnored private var sendAgainNow = false
    /// Failures in a row, and when the next try is due after them.
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var nextTryAt = Date.distantPast
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private let network = NWPathMonitor()

    /// The keychain entry the token is kept under, apart from the server password's, so
    /// signing out of the server keeps ListenBrainz connected.
    static let tokenAccount = "octo.listenbrainz.token"

    private static var version: String { Session.appVersion }

    private static var queueFile: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("listenbrainz_queue.json")
    }

    private init() {
        let transport = ListenBrainzTransport(userAgent: octoUserAgent(Session.appVersion))
        api = ListenBrainzApi(send: { await transport.send($0) })
    }

    /// At app start: reads what waited from last time and sends it, and again whenever a
    /// connection comes back.
    func start() {
        guard !started else { return }
        started = true
        loadQueue()
        Task { await send(now: true) }
        network.pathUpdateHandler = { path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await ListenBrainzSync.shared.send(now: true) }
        }
        network.start(queue: DispatchQueue(label: "app.winters.octo.listenbrainz.network"))
    }

    // MARK: What the player tells it

    /// A play counted. It waits in the queue until ListenBrainz has it. Radio streams are left
    /// out by the caller; a song without a title or artist is not kept.
    func played(_ song: PlayedSong, startedAt: Date) {
        let prefs = settings.listenBrainz
        guard prefs.keepsPlays, shouldSend(prefs.sendPlays, reachesServer: song.reachesServer),
              let listen = song.listen(startedAtMs: Int64(startedAt.timeIntervalSince1970 * 1000))
        else { return }
        updateQueue { $0.plusListen(listen) }
        Task { await send(now: false) }
    }

    /// A song started. ListenBrainz shows it as playing now; a failure here does not matter, as
    /// the next song replaces it, except that a refused token needs pasting again.
    func nowPlaying(_ song: PlayedSong) {
        let prefs = settings.listenBrainz
        guard prefs.sends, prefs.nowPlaying, shouldSend(prefs.sendPlays, reachesServer: song.reachesServer),
              let listen = song.listen(startedAtMs: Int64(Date().timeIntervalSince1970 * 1000)),
              let token = token()
        else { return }
        Task {
            if await api.playingNow(token, listen, clientVersion: Self.version) == .unauthorized { setNeedsAttention(true) }
        }
    }

    // MARK: What the Scrobbling page does

    /// Checks a pasted token and, when ListenBrainz accepts it, keeps it and sends what is waiting.
    func connect(_ typed: String) async -> TokenCheck {
        let clean = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let check = await api.validate(clean)
        guard case .valid(let user) = check else { return check }
        let store = settings.listenBrainzStore
        let otherUser = store.string(forKey: AppSettings.Keys.user).map { $0 != user } ?? false
        Keychain.save(clean, for: Self.tokenAccount)
        store.set(true, forKey: AppSettings.Keys.tokenSealed)
        store.set(user, forKey: AppSettings.Keys.user)
        store.set(false, forKey: AppSettings.Keys.needsAttention)
        store.set(true, forKey: AppSettings.Keys.enabled)
        settings.refreshListenBrainz()
        if otherUser { updateQueue { _ in [] } }
        failures = 0
        nextTryAt = .distantPast
        Task { await send(now: true) }
        return check
    }

    /// Forgets the token, the user and every waiting play, and switches ListenBrainz off, once a
    /// send in progress has finished.
    func disconnect() async {
        while sending { try? await Task.sleep(for: .milliseconds(100)) }
        let store = settings.listenBrainzStore
        for key in [AppSettings.Keys.tokenSealed, AppSettings.Keys.user, AppSettings.Keys.needsAttention] { store.removeObject(forKey: key) }
        store.set(false, forKey: AppSettings.Keys.enabled)
        Keychain.delete(for: Self.tokenAccount)
        settings.refreshListenBrainz()
        updateQueue { _ in [] }
    }

    func setEnabled(_ on: Bool) {
        settings.listenBrainzStore.set(on, forKey: AppSettings.Keys.enabled)
        settings.refreshListenBrainz()
        if on { Task { await send(now: true) } }
    }

    func setSendPlays(_ mode: SendPlays) {
        settings.listenBrainzStore.set(mode.storedName, forKey: AppSettings.Keys.sendPlays)
        settings.refreshListenBrainz()
    }

    func setNowPlaying(_ on: Bool) {
        settings.listenBrainzStore.set(on, forKey: AppSettings.Keys.nowPlaying)
        settings.refreshListenBrainz()
    }

    /// Puts back the choices from a backup in one go. Who is connected is left as it is.
    func restoreChoices(enabled: Bool, sendPlays: SendPlays, nowPlaying: Bool) {
        let store = settings.listenBrainzStore
        store.set(enabled, forKey: AppSettings.Keys.enabled)
        store.set(sendPlays.storedName, forKey: AppSettings.Keys.sendPlays)
        store.set(nowPlaying, forKey: AppSettings.Keys.nowPlaying)
        settings.refreshListenBrainz()
    }

    // MARK: Sending

    private func setNeedsAttention(_ on: Bool) {
        settings.listenBrainzStore.set(on, forKey: AppSettings.Keys.needsAttention)
        settings.refreshListenBrainz()
    }

    /// The token, opened only for the call that needs it. Nil when none is saved, or when its
    /// keychain entry is gone (a backup restored on another phone).
    private func token() -> String? {
        guard settings.listenBrainz.connected else { return nil }
        return Keychain.read(for: Self.tokenAccount)
    }

    /// Sends the waiting plays, oldest first, in batches. `now` tries even while waiting after
    /// failures; a new play waits its turn.
    private func send(now: Bool) async {
        if !now, Date() < nextTryAt { return }
        guard !sending else {
            sendAgain = true
            sendAgainNow = sendAgainNow || now
            return
        }
        guard settings.listenBrainz.sends else { return }
        guard let token = token() else {
            // The saved token can no longer be opened, so it needs pasting again.
            if settings.listenBrainz.connected { setNeedsAttention(true) }
            return
        }
        sending = true
        defer {
            sending = false
            if sendAgain {
                // The send asked for meanwhile runs next, as it was asked: at once when it was.
                let now = sendAgainNow
                sendAgain = false
                sendAgainNow = false
                Task { await send(now: now) }
            }
        }
        while true {
            let batch = nextBatch(loadQueue())
            if batch.isEmpty { break }
            switch await deliver(token, batch) {
            case .sent:
                failures = 0
                nextTryAt = .distantPast
            case .unauthorized:
                setNeedsAttention(true)
                return
            case .rateLimited(let ms):
                retryIn(ms)
                return
            case .failed, .rejected:
                failures += 1
                retryIn(retryDelayMs(failures))
                return
            }
        }
    }

    /// Sends one batch. When ListenBrainz refuses a batch, its halves go on their own, so one bad
    /// play does not hold back the rest; a single play refused is let go.
    private func deliver(_ token: String, _ batch: [Listen]) async -> SubmitResult {
        let result = await api.submit(token, batch, clientVersion: Self.version)
        if result == .sent || (result == .rejected && batch.count == 1) {
            let done = Set(batch)
            updateQueue { $0.filter { !done.contains($0) } }
            return .sent
        }
        if result == .rejected {
            let half = batch.count / 2
            let first = await deliver(token, Array(batch[..<half]))
            return first != .sent ? first : await deliver(token, Array(batch[half...]))
        }
        return result
    }

    private func retryIn(_ ms: Int64) {
        nextTryAt = Date().addingTimeInterval(Double(ms) / 1000)
        retry?.cancel()
        retry = Task {
            try? await Task.sleep(for: .milliseconds(ms))
            guard !Task.isCancelled else { return }
            await send(now: true)
        }
    }

    // MARK: The queue file

    @discardableResult
    private func loadQueue() -> [Listen] {
        if let queue { return queue }
        let read = (try? Data(contentsOf: Self.queueFile)).flatMap { try? JSONDecoder().decode([Listen].self, from: $0) } ?? []
        queue = read
        queued = read.count
        return read
    }

    /// Changes the queue and writes it whole, safely, so it survives restarts.
    private func updateQueue(_ change: ([Listen]) -> [Listen]) {
        let next = change(loadQueue())
        if let data = try? JSONEncoder().encode(next) { try? data.write(to: Self.queueFile, options: .atomic) }
        queue = next
        queued = next.count
    }
}

extension PlayedSong {
    /// A song from the server as ListenBrainz hears it. A server song always reaches the server.
    init(_ song: Song, playedMs: Int64? = nil) {
        self.init(song.title, song.displayArtist ?? song.artist ?? "", song.album ?? "",
                  durationMs: playedMs ?? Int64(song.duration) * 1000, trackNumber: song.track, reachesServer: true)
    }
}
