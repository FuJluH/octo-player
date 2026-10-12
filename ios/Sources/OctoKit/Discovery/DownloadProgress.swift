import Foundation

// How often to ask the server how its downloads are going: often while a song downloading is on
// screen, less often otherwise, and seldom while the app is in the background.
public let pollWatchedMs: Int64 = 2_000
public let pollMs: Int64 = 5_000
public let pollAwayMs: Int64 = 30_000

// How many times, and how far apart, to bring a finished song into the library while the server
// takes it in.
public let arrivalTries = 3
public let arrivalRetryMs: Int64 = 20_000

/// A download the server has not listed for this long is no longer followed.
public let unseenMs: Int64 = 10 * 60_000

/// After this long a download that never arrived can be asked for again.
public let giveUpMs: Int64 = 24 * 60 * 60_000

/// A song found online, as the app keeps it: the server id it is starred with, the server it
/// came from, what it is, when it was asked for (0 when not), and the library song it became
/// (empty until it arrives).
public struct FindSong: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var sourceId: String
    public var title: String
    public var artist: String
    public var album: String
    public var albumId: String?
    public var durationMs: Int64
    public var requestedAt: Int64
    public var adoptedId: String

    public init(id: String, sourceId: String, title: String, artist: String, album: String = "", albumId: String? = nil,
                durationMs: Int64 = 0, requestedAt: Int64 = 0, adoptedId: String = "") {
        self.id = id
        self.sourceId = sourceId
        self.title = title
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.durationMs = durationMs
        self.requestedAt = requestedAt
        self.adoptedId = adoptedId
    }
}

public enum DownloadState: Sendable, Equatable { case none, requested, done }

/// What a find's download button shows.
public enum DownloadPhase: Sendable, Equatable {
    case none
    /// Asked for: waiting its turn on the server, or looking for a source.
    case queued
    /// On its way, with how far from 0 to 1, or nil when not known.
    case downloading(Double?)
    /// Downloaded, and being checked and put into the library.
    case adding
    case done
    case failed(String)

    /// The plain state, for places that only need to know whether a download can be asked for.
    /// A failed one can be asked for again.
    public var state: DownloadState {
        switch self {
        case .done: .done
        case .none, .failed: .none
        default: .requested
        }
    }

    /// What a screen reader says the add button is doing.
    public var spoken: String {
        switch self {
        case .none: "Not in your library"
        case .queued: "Queued"
        case .downloading(let progress): progress.map { "Downloading, \(Int(($0 * 100).rounded())) percent" } ?? "Downloading"
        case .adding: "Adding to your library"
        case .done: "In your library"
        case .failed: "Could not download"
        }
    }
}

/// What the server's word for a download means here. A finished download is still being added
/// until the song really is in the library.
public func phaseOf(_ acquisition: Acquisition) -> DownloadPhase {
    switch acquisition.stage {
    case .queued, .searching, .unknown: .queued
    case .downloading: .downloading(acquisition.fraction)
    case .verifying, .importing, .done: .adding
    case .failed:
        .failed(acquisition.error.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "the server did not say why")
    }
}

/// What one find shows: the library has the last word, then the server's news. A download the
/// server's newest list does not show is queued only while it is still taken as asked for
/// (`stillAsked`), and otherwise not on its way, so it can be asked for again. `listedSince` is
/// when that list was asked for, `album` whether the song was asked for with its album, and
/// `lists` whether the server lists its downloads at all: one that does not is only ever asked
/// about through the library, so its downloads stay queued until they arrive or are given up.
public func phaseFor(_ row: FindSong, live: DownloadPhase?, now: Int64, listedSince: Int64? = nil, album: Bool = false,
                     lists: Bool = true) -> DownloadPhase {
    switch stateOf(row, now: now) {
    case .done: return .done
    case .none: return .none
    case .requested:
        if let live { return live }
        return !lists || stillAsked(askOf(row, album: album), listedSince: listedSince, now: now) ? .queued : .none
    }
}

/// A find asked for, as the shared rule reads it.
public func askOf(_ row: FindSong, album: Bool = false) -> AskedSong {
    AskedSong(serverId: row.id, askedAt: row.requestedAt, album: album)
}

/// The finds among `rows` asked for with their whole album: an album ask gives every song of an
/// album one time, which a song asked for alone never shares with another song of its album.
public func askedWithAlbum(_ rows: [FindSong]) -> Set<String> {
    var groups: [String: [FindSong]] = [:]
    for row in rows where row.requestedAt > 0 {
        guard let albumId = row.albumId, !albumId.isEmpty else { continue }
        groups["\(albumId)\u{0}\(row.requestedAt)", default: []].append(row)
    }
    var found = Set<String>()
    for group in groups.values where group.count > 1 { for row in group { found.insert(row.id) } }
    return found
}

public func stateOf(_ row: FindSong, now: Int64) -> DownloadState {
    if !row.adoptedId.isEmpty { return .done }
    if row.requestedAt > 0 && now - row.requestedAt < giveUpMs { return .requested }
    return .none
}

/// How long to wait before asking the server again.
public func pollDelayMs(downloadingOnScreen: Bool, foreground: Bool) -> Int64 {
    if !foreground { return pollAwayMs }
    return downloadingOnScreen ? pollWatchedMs : pollMs
}

/// The server's entry for a find: the one starred with its id, or else one with the same title
/// and artist, as songs of an album asked for at once may carry the album's id. An entry without
/// an artist is matched by its title and kind of recording alone. The newest wins when there are
/// several.
public func acquisitionFor(_ find: FindSong, _ list: [Acquisition]) -> Acquisition? {
    let byId = list.filter { !$0.id.isEmpty && $0.id == find.id }
    let candidates = !byId.isEmpty ? byId : list.filter {
        !$0.title.trimmingCharacters(in: .whitespaces).isEmpty
            && ($0.artist.trimmingCharacters(in: .whitespaces).isEmpty
                ? SongIdentity.sameTitle($0.title, find.title).isSame
                : sameRecording($0.title, $0.artist, find.title, find.artist))
    }
    return candidates.max { ($0.startedAt ?? "") < ($1.startedAt ?? "") }
}

/// The finds asked for on server `sourceId` that have not reached the library, by the id the
/// server lists them under. None while signed out.
public func askedSongs(_ rows: [FindSong], sourceId: String?) -> [AskedSong] {
    guard let sourceId else { return [] }
    let withAlbum = askedWithAlbum(rows)
    return rows.filter { $0.sourceId == sourceId && $0.requestedAt > 0 && $0.adoptedId.isEmpty }
        .map { askOf($0, album: withAlbum.contains($0.id)) }
}

/// What the finds' phases are read from: the finds asked for, what the server last said of each,
/// when its newest list was asked for, whether it lists downloads at all, and the server in use.
/// A list from the server in use says nothing of another server's finds.
public struct PhaseInputs: Sendable {
    public var rows: [FindSong]
    public var live: [String: DownloadPhase]
    public var listedSince: Int64?
    public var lists: Bool
    public var sourceId: String?

    public init(rows: [FindSong], live: [String: DownloadPhase], listedSince: Int64?, lists: Bool, sourceId: String?) {
        self.rows = rows
        self.live = live
        self.listedSince = listedSince
        self.lists = lists
        self.sourceId = sourceId
    }
}

public func phasesOf(_ inputs: PhaseInputs, now: Int64) -> [String: DownloadPhase] {
    let withAlbum = askedWithAlbum(inputs.rows)
    var phases: [String: DownloadPhase] = [:]
    for row in inputs.rows {
        let since = row.sourceId == inputs.sourceId ? inputs.listedSince : nil
        phases[row.id] = phaseFor(row, live: inputs.live[row.id], now: now, listedSince: since,
                                  album: withAlbum.contains(row.id), lists: inputs.lists)
    }
    return phases
}

/// How long until a find's phase may change by the clock alone: when the first one still taken as
/// asked for runs out.
public func recheckMs(_ inputs: PhaseInputs, now: Int64) -> Int64? {
    guard inputs.lists else { return nil }
    let withAlbum = askedWithAlbum(inputs.rows)
    return inputs.rows
        .filter { $0.adoptedId.isEmpty && inputs.live[$0.id] == nil && stateOf($0, now: now) == .requested }
        .compactMap { row in
            stillAskedForMs(askOf(row, album: withAlbum.contains(row.id)),
                            listedSince: row.sourceId == inputs.sourceId ? inputs.listedSince : nil, now: now)
        }
        .min()
}

/// What following downloads needs from the rest of the app.
public protocol AcquisitionHost: AnyObject, Sendable {
    /// Finds asked for that are not in the library yet.
    func waiting() async -> [FindSong]
    /// What the server is downloading, or nil when it cannot say. Throws when the server cannot
    /// be reached right now.
    func acquisitions() async throws -> [Acquisition]?
    /// Brings one finished song into the library by its server id, and answers the library song
    /// it became.
    func takeIn(_ libraryId: String) async throws -> String?
    /// Links a find to the library song it became.
    func adopt(_ findId: String, _ trackId: String) async
    /// Looks at the library again and waits for it; songs that arrived are adopted along the way.
    func syncAndWait() async throws
}

/// Follows the downloads asked for on a server that says how they are going, until none is left
/// waiting. Only while the app runs.
public final class ProgressWatch: @unchecked Sendable {
    private let host: AcquisitionHost
    private let clock: @Sendable () -> Int64
    private let lock = NSLock()

    private var _live: [String: DownloadPhase] = [:]
    private var _listedSince: Int64?
    private var highest: [String: Double] = [:]
    private var tries: [String: Int] = [:]
    private var triedAt: [String: Int64] = [:]
    private var lastSeen: [String: Acquisition] = [:]
    private var passedOver: [String: Acquisition] = [:]
    private var unseenSince: [String: Int64] = [:]
    private var onScreen: [String: Int] = [:]
    private var _foreground = true
    private let wakeUp: Wake

    /// Called on any thread whenever `live` or `listedSince` change.
    public var changed: (@Sendable () -> Void)?

    /// `sleep` waits the given milliseconds; tests pass one that only moves their clock.
    public init(host: AcquisitionHost, clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1_000) },
                sleep: @escaping @Sendable (Int64) async -> Void = { try? await Task.sleep(nanoseconds: UInt64(max(0, $0)) * 1_000_000) }) {
        self.host = host
        self.clock = clock
        wakeUp = Wake(sleep: sleep)
    }

    /// What the server last said about each find it is downloading.
    public var live: [String: DownloadPhase] { lock.withLock { _live } }

    /// When the newest list that came back was asked for, or nil before any did: a find asked
    /// for before then that `live` leaves out is not on that list.
    public var listedSince: Int64? { lock.withLock { _listedSince } }

    /// Whether the app is in front. Coming back asks at once.
    public var foreground: Bool {
        get { lock.withLock { _foreground } }
        set {
            let back = lock.withLock {
                let back = newValue && !_foreground
                _foreground = newValue
                return back
            }
            if back { wake() }
        }
    }

    /// Asks the server again now, not at the next turn.
    public func wake() { wakeUp.signal() }

    /// A find's button is on screen until the answer is called.
    public func show(_ findId: String) -> @Sendable () -> Void {
        let downloading = lock.withLock { () -> Bool in
            onScreen[findId, default: 0] += 1
            if case .downloading = _live[findId] { return true }
            return false
        }
        if downloading { wake() }
        return { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                let left = (self.onScreen[findId] ?? 1) - 1
                if left > 0 { self.onScreen[findId] = left } else { self.onScreen[findId] = nil }
            }
        }
    }

    /// A find asked for again starts afresh: a failure the server still lists is passed over,
    /// and its progress starts from nothing.
    public func retry(_ findId: String) {
        lock.withLock {
            if let seen = lastSeen[findId], seen.stage == .failed { passedOver[findId] = seen }
            highest[findId] = nil
            tries[findId] = nil
            triedAt[findId] = nil
            unseenSince[findId] = nil
            _live[findId] = nil
        }
        changed?()
        wake()
    }

    enum Poll {
        case unsupported
        case idle
        case asked([(FindSong, Acquisition)])
    }

    /// Asks the server until nothing is left waiting. Answers false at once when the server cannot
    /// say how its downloads are going. A canceled run stops at its next turn, answering true, so
    /// nothing takes over from it.
    public func run() async -> Bool {
        var arriving: Task<Void, Never>?
        var arrivingDone = true
        let doneFlag = Flag()
        while true {
            if Task.isCancelled { return true }
            arrivingDone = arriving == nil || doneFlag.value
            switch await poll(canArrive: arrivingDone) {
            case .unsupported:
                await arriving?.value
                return false
            case .idle:
                // Songs still being brought in may need another look.
                if let job = arriving, !doneFlag.value { await job.value } else { return true }
            case .asked(let due):
                if !due.isEmpty {
                    doneFlag.value = false
                    arriving = Task { [weak self] in
                        await self?.arrive(due)
                        doneFlag.value = true
                        self?.wake()
                    }
                }
                await wakeUp.wait(ms: nextDelayMs())
            }
        }
    }

    /// One question to the server, and what it means for each find.
    func poll(canArrive: Bool) async -> Poll {
        let waiting = await host.waiting()
        if waiting.isEmpty {
            lock.withLock { _live = [:] }
            changed?()
            return .idle
        }
        let askedAt = clock()
        let list: [Acquisition]
        do {
            guard let answer = try await host.acquisitions() else { return .unsupported }
            list = answer
        } catch {
            // Out of reach for now: ask again at the next turn.
            return .asked([])
        }
        let now = clock()
        var next: [String: DownloadPhase] = [:]
        var due: [(FindSong, Acquisition)] = []
        var pending = false
        let withAlbum = askedWithAlbum(waiting)
        lock.withLock {
            for find in waiting {
                let skip = passedOver[find.id]
                guard let entry = acquisitionFor(find, skip == nil ? list : list.filter { $0 != skip }) else {
                    let since = unseenSince[find.id] ?? now
                    unseenSince[find.id] = since
                    if now - since < unseenMs || stillAsked(askOf(find, album: withAlbum.contains(find.id)), listedSince: askedAt, now: now) {
                        pending = true
                    }
                    continue
                }
                unseenSince[find.id] = nil
                lastSeen[find.id] = entry
                next[find.id] = steady(find.id, phaseOf(entry))
                switch entry.stage {
                case .failed: break
                case .done:
                    let tried = tries[find.id] ?? 0
                    let last = triedAt[find.id]
                    if canArrive && tried < arrivalTries && (last == nil || now - last! >= arrivalRetryMs) {
                        tries[find.id] = tried + 1
                        triedAt[find.id] = now
                        due.append((find, entry))
                    }
                    if (tries[find.id] ?? 0) < arrivalTries {
                        pending = true
                    } else if !due.contains(where: { $0.0.id == find.id }) {
                        // In the server's library, and brought in as often as it will be: in the
                        // library, whether or not a copy of it here has been linked yet.
                        next[find.id] = .done
                    }
                default: pending = true
                }
            }
            _live = next
            _listedSince = askedAt
        }
        changed?()
        return pending || !due.isEmpty ? .asked(due) : .idle
    }

    /// Progress never goes back: a lower or unknown figure keeps the highest one seen for this
    /// find. Called with the lock held.
    private func steady(_ findId: String, _ phase: DownloadPhase) -> DownloadPhase {
        guard case .downloading(let progress) = phase else { return phase }
        let best = max(highest[findId] ?? 0, progress ?? 0)
        if progress == nil && highest[findId] == nil { return phase }
        highest[findId] = best
        return .downloading(best)
    }

    /// Songs the server finished: each one it names is brought in at once, then the library is
    /// looked at again, which adopts the rest.
    func arrive(_ due: [(FindSong, Acquisition)]) async {
        for (find, entry) in due {
            guard let libraryId = entry.libraryId, !libraryId.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            // The look below still finds it.
            if let track = try? await host.takeIn(libraryId) { await host.adopt(find.id, track) }
        }
        // Tried again at the next finished answer.
        try? await host.syncAndWait()
    }

    func nextDelayMs() -> Int64 {
        lock.withLock {
            let watched = _live.contains { id, phase in
                if case .downloading = phase { return onScreen[id] != nil }
                return false
            }
            return pollDelayMs(downloadingOnScreen: watched, foreground: _foreground)
        }
    }
}

/// A flag shared between a task and the loop that started it.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = true
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

/// A wake-up that is kept until it is waited for, and a wait that ends early when woken.
final class Wake: @unchecked Sendable {
    private let sleep: @Sendable (Int64) async -> Void
    private let lock = NSLock()
    private var pending = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var round = 0

    init(sleep: @escaping @Sendable (Int64) async -> Void) { self.sleep = sleep }

    func signal() {
        let resume: CheckedContinuation<Void, Never>? = lock.withLock {
            if let waiter {
                self.waiter = nil
                return waiter
            }
            pending = true
            return nil
        }
        resume?.resume()
    }

    /// Ends early when woken, or when the task waiting is canceled.
    func wait(ms: Int64) async {
        let mine: Int = lock.withLock {
            round += 1
            return round
        }
        await withTaskCancellationHandler {
            await sleepUnlessWoken(ms: ms, round: mine)
        } onCancel: {
            signal()
        }
    }

    private func sleepUnlessWoken(ms: Int64, round mine: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let now: Bool = lock.withLock {
                if pending {
                    pending = false
                    return true
                }
                waiter = continuation
                return false
            }
            if now {
                continuation.resume()
                return
            }
            Task { [weak self, sleep] in
                await sleep(ms)
                guard let self else { return }
                let late: CheckedContinuation<Void, Never>? = self.lock.withLock {
                    guard self.round == mine, let waiter = self.waiter else { return nil }
                    self.waiter = nil
                    return waiter
                }
                late?.resume()
            }
        }
    }
}
