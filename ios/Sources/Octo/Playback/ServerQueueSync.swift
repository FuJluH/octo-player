import Foundation
import Observation
import OctoKit

/// How long the queue has to stay put before it is saved on the server.
private let saveAfterMs = 10_000

/// Coming back to the front more often than this asks the server only once.
private let checkEveryMs = 30_000

/// How long the queue has to reach a server being left.
private let leaveSaveMs = 3_000

/// An offer to carry on from another device.
struct ResumeOffer: Identifiable, Equatable {
    let device: String
    let title: String
    let artist: String?
    let remote: RemoteQueue

    var id: Int { remote.changedAt ?? 0 }

    static func == (a: ResumeOffer, b: ResumeOffer) -> Bool { a.id == b.id && a.title == b.title && a.device == b.device }
}

/// A queue ready to load: its songs, the current one, and where in it.
struct ResumeQueue {
    let trackIds: [String]
    let index: Int
    let positionMs: Int
}

/// Keeps the play queue on the server, so another device (or another app) can carry on from it,
/// and offers to carry on from a queue saved elsewhere. Saves a short while after the queue or
/// the song changes, and at a pause.
@MainActor
@Observable
final class ServerQueueSync {
    /// The offer showing, if any.
    private(set) var offer: ResumeOffer?
    /// "Sync play queue with the server", on unless switched off, as the Server page and backups
    /// keep it.
    var enabled: Bool { ServerSyncChoices().syncQueue }

    @ObservationIgnored private let session: Session
    /// The choice as last seen, so turning it off is caught once.
    @ObservationIgnored private var wasEnabled = ServerSyncChoices().syncQueue
    @ObservationIgnored private var choiceWatch: NSObjectProtocol?
    @ObservationIgnored private let data: DataServices?
    @ObservationIgnored private let store = UserDefaults(suiteName: "server_queue") ?? .standard
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var saving: Task<Void, Never>?
    /// What the server was last sent, by account, so the same queue is not sent twice.
    @ObservationIgnored private var lastSent: (account: String, queue: ServerQueue)?
    @ObservationIgnored private var lastCheck = 0
    /// The restored queue's songs and current place, until something changes.
    @ObservationIgnored private var baseline: (ids: [String], index: Int)?

    init(session: Session, data: DataServices?) {
        self.session = session
        self.data = data
        choiceWatch = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.choiceChanged() }
        }
    }

    /// Switching syncing off cancels a save waiting to go and puts the offer away.
    private func choiceChanged() {
        let now = enabled
        guard now != wasEnabled else { return }
        wasEnabled = now
        if !now {
            pending?.cancel()
            pending = nil
            offer = nil
        }
    }

    #if DEBUG
    /// Shows an offer made up on the phone, to see the card.
    func showSample(_ sample: ResumeOffer) {
        offer = sample
    }
    #endif

    func setEnabled(_ on: Bool) {
        ServerSyncChoices().setSyncQueue(on)
        choiceChanged()
    }

    /// The queue the phone brought back from last time. Bringing it back is not a change, so it
    /// is not saved over a newer queue from elsewhere.
    func restored(_ snapshot: QueueSnapshot) {
        baseline = (snapshot.trackIds, snapshot.index)
    }

    /// The queue or the current song changed: save once it has settled, on the server in use now.
    func changed(_ snapshot: QueueSnapshot, items: [QueueItem]) {
        let server = session.inUse
        if let baseline, baseline.ids == snapshot.trackIds, baseline.index == snapshot.index { return }
        baseline = nil
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(saveAfterMs))
            guard !Task.isCancelled, let self, let server else { return }
            await self.save(server, snapshot, items, exact: false)
        }
    }

    /// Playback paused: save now, with the exact position.
    func paused(_ snapshot: QueueSnapshot, items: [QueueItem]) {
        let server = session.inUse
        baseline = nil
        pending?.cancel()
        pending = Task { [weak self] in
            guard let self, let server else { return }
            await self.save(server, snapshot, items, exact: true)
        }
    }

    /// Leaving a server for another: its queue goes to it now, exactly, and is done before the
    /// next server is in use. A server out of reach does not hold the switch up for long.
    func leaving(_ snapshot: QueueSnapshot, items: [QueueItem]) async {
        guard let server = session.inUse else { return }
        pending?.cancel()
        pending = nil
        baseline = nil
        offer = nil
        let work = Task { await self.save(server, snapshot, items, exact: true) }
        // Whichever comes first: the save done, or the time up. The save carries on unwatched.
        let once = Once()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            Task {
                await work.value
                if once.take() { done.resume() }
            }
            Task {
                try? await Task.sleep(for: .milliseconds(leaveSaveMs))
                if once.take() { done.resume() }
            }
        }
    }

    /// Forgets what was noted for a server taken off the list.
    func forget(_ account: String) {
        for key in [savedKey(account), answeredKey(account), stampKey(account)] { store.removeObject(forKey: key) }
    }

    /// Another server is in use: the queue it offers is looked for at once.
    func arrived() {
        lastCheck = 0
        offer = nil
        check()
    }

    /// The app came to the front: look for a queue saved elsewhere.
    func check() {
        let now = epochMs()
        if now - lastCheck < checkEveryMs { return }
        lastCheck = now
        Task { await lookForOffer() }
    }

    /// The songs to load for an offer taken up, and the offer is put away.
    func take(_ offer: ResumeOffer) async -> ResumeQueue? {
        answered(offer)
        let remote = offer.remote
        guard let discovery = data?.discovery else {
            let ids = remote.songs.map(\.id)
            return ids.isEmpty ? nil : ResumeQueue(trackIds: ids, index: remote.index, positionMs: remote.positionMs)
        }
        let tracks = await discovery.resolveFromServer(remote.songs)
        guard !tracks.isEmpty else { return nil }
        var index: Int?
        if let current = remote.current, let found = await discovery.resolveFromServer([current]).first {
            index = tracks.firstIndex { $0.id == found.id }
        }
        return ResumeQueue(trackIds: tracks.map(\.id), index: index ?? 0, positionMs: index != nil ? remote.positionMs : 0)
    }

    /// Not now: the same queue is not offered again.
    func dismiss(_ offer: ResumeOffer) {
        answered(offer)
    }

    private func answered(_ answered: ResumeOffer) {
        if offer == answered { offer = nil }
        guard let account = session.inUse?.account, let at = answered.remote.changedAt else { return }
        store.set(at, forKey: answeredKey(account))
    }

    private func lookForOffer() async {
        guard enabled, let server = session.inUse else {
            offer = nil
            return
        }
        let indexBased = takesIndex(server)
        let remote: RemoteQueue?
        do {
            remote = indexBased ? try await server.client.playQueueByIndex().map(remoteQueueOf(byIndex:))
                : try await server.client.playQueue().map(remoteQueueOf(byId:))
        } catch {
            // Quietly nothing: the offer is a nicety.
            return
        }
        // An older version kept these by the server's address.
        let savedAt = number(savedKey(server.account)) ?? number(oldSavedKey(server.sourceId)) ?? 0
        let answeredAt = number(answeredKey(server.account)) ?? number(oldAnsweredKey(server.sourceId)) ?? 0
        let ownStamp = number(stampKey(server.account)) ?? number(oldStampKey(server.sourceId))
        if let remote, let current = remote.current,
           shouldOfferResume(remote, lastSavedAt: savedAt, answeredUpTo: answeredAt, ownStamp: ownStamp) {
            let device = (remote.changedBy ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            offer = ResumeOffer(device: device.isEmpty ? "another device" : device, title: current.title,
                                artist: current.displayArtist ?? current.artist, remote: remote)
        } else {
            offer = nil
        }
    }

    /// A save after a change is skipped when only the position moved; a save at a pause is
    /// skipped only when nothing did. Saves run one at a time.
    private func save(_ server: ServerInUse, _ snapshot: QueueSnapshot, _ items: [QueueItem], exact: Bool) async {
        let before = saving
        let run = Task { [weak self] in
            await before?.value
            guard let self, self.enabled else { return }
            let serverIds = await self.serverIdsOf(server.sourceId, items)
            guard let queue = serverQueueOf(snapshot, serverIdOf: { serverIds[$0] })?.trimmed() else { return }
            let sent = self.lastSent?.account == server.account ? self.lastSent?.queue : nil
            if sent == queue || (!exact && sent?.ids == queue.ids && sent?.index == queue.index) { return }
            let indexBased = takesIndex(server)
            do {
                if indexBased {
                    try await server.client.savePlayQueueByIndex(queue.ids, currentIndex: queue.index, positionMs: queue.positionMs)
                } else {
                    try await server.client.savePlayQueue(queue.ids, currentIndex: queue.index, positionMs: queue.positionMs)
                }
                self.lastSent = (server.account, queue)
                // The server's time for this save is how this phone knows its own queue later,
                // whatever name other phones running it give.
                let stamp = indexBased ? (try? await server.client.playQueueByIndex()).flatMap { $0 }.map(remoteQueueOf(byIndex:))?.changedAt
                    : (try? await server.client.playQueue()).flatMap { $0 }.map(remoteQueueOf(byId:))?.changedAt
                self.store.set(self.epochMs(), forKey: self.savedKey(server.account))
                if let stamp { self.store.set(stamp, forKey: self.stampKey(server.account)) }
            } catch {
                playbackLog.info("queue save failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        saving = run
        await run.value
    }

    /// The server's id for each song that has one: a song streaming from this server, a library
    /// song's copy on it (the lowest id when several), or a find's own id. Stations have none.
    private func serverIdsOf(_ sourceId: String, _ items: [QueueItem]) async -> [String: String] {
        var ids: [String: String] = [:]
        for item in items where ids[item.trackId] == nil && !isRadio(item.trackId) {
            if isFind(item.trackId) {
                ids[item.trackId] = String(item.trackId.dropFirst(findPrefix.count))
            } else if let copies = await data?.library.copies(item.trackId), !copies.isEmpty {
                if let lowest = copies.filter({ $0.sourceId == sourceId }).map(\.nativeId).min() { ids[item.trackId] = lowest }
            } else if let streamed = serverSongOf(item.uri, sourceId: sourceId) {
                ids[item.trackId] = streamed
            }
        }
        return ids
    }

    /// Whether the server takes a queue by index: it lists the extension, at any version.
    private func takesIndex(_ server: ServerInUse) -> Bool { server.extensions.contains { $0.hasPrefix(indexBasedQueue + ":") } }

    private func number(_ key: String) -> Int? { store.object(forKey: key) as? Int }

    private func epochMs() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    // When this phone last saved its queue on a server, the last offer answered there, and the
    // server's own time for that save, for each kept server by its id.
    private func savedKey(_ account: String) -> String { "saved_at@\(account)" }
    private func answeredKey(_ account: String) -> String { "answered_at@\(account)" }
    private func stampKey(_ account: String) -> String { "own_stamp@\(account)" }
    private func oldSavedKey(_ sourceId: String) -> String { "saved_at:\(sourceId)" }
    private func oldAnsweredKey(_ sourceId: String) -> String { "answered_at:\(sourceId)" }
    private func oldStampKey(_ sourceId: String) -> String { "own_stamp:\(sourceId)" }
}

/// Says yes to the first that asks, whichever thread it is on, and no after.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func take() -> Bool {
        lock.withLock {
            defer { done = true }
            return !done
        }
    }
}
