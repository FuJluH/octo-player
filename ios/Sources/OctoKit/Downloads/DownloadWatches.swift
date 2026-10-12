import Foundation
import Observation

/// How often the sheet's list is asked for: while it is open, while something runs (so the pill can
/// show it), and otherwise, to notice a download started somewhere else.
public let downloadsOpenPollMs: Int64 = 2_000
public let downloadsRunningPollMs: Int64 = 3_000
public let downloadsIdlePollMs: Int64 = 30_000

/// How often an open log, and a running Find songs search, are asked for.
public let logPollMs: Int64 = 1_500
public let findPollMs: Int64 = 1_500

/// How long a finished download's log is still asked for: its lyrics are looked for once the song
/// is in, and their line comes a little after.
public let logFinishedGraceMs: Int64 = 60_000

/// Waits the given milliseconds; tests pass one that only moves their clock.
public typealias Sleeper = @Sendable (Int64) async -> Void

public let realSleep: Sleeper = { ms in try? await Task.sleep(nanoseconds: UInt64(max(0, ms)) * 1_000_000) }

/// The server's own words in an error, when it gave any.
public func serverWords(_ error: Error) -> String? {
    guard let error = error as? OctoError else { return nil }
    switch error {
    case .server(_, let message), .notFound(let message), .wrongCredentials(let message), .authUnsupported(_, let message):
        return message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : message
    default:
        return nil
    }
}

/// What following the sheet needs from the app: the server's two lists.
public protocol DownloadsSource: Sendable {
    /// The downloads, or throws when the server cannot be asked now.
    func acquisitions() async throws -> [Acquisition]
    /// The higher quality copies asked for, or an empty list on a server that cannot look for them.
    func upgrades() async throws -> [Upgrade]
    /// Takes finished downloads off the list on the server, or one by key.
    func clear(_ key: String?) async throws
}

/// Follows the sheet's rows for one server, for as long as it is started.
@MainActor
@Observable
public final class DownloadsWatch {
    /// What the sheet shows, running first.
    public private(set) var rows: [DownloadRow] = []
    /// The higher quality copies as the server last listed them.
    public private(set) var upgrades: [Upgrade] = []
    /// Whether the server has answered since the start.
    public private(set) var loaded = false
    /// When the newest list that came back was asked for, or nil before any did: songs asked for
    /// before then are on it if they are on their way.
    public private(set) var listedSince: Int64?

    /// Whether the sheet is open: it is then asked for every two seconds.
    public var open = false {
        didSet { if open && !oldValue { wake() } }
    }

    /// Whether the app is in front; behind it, only running rows are followed, at the slow pace.
    public var foreground = true

    /// Called with each list of higher quality copies that comes back.
    @ObservationIgnored public var upgradesRead: (([Upgrade]) -> Void)?

    @ObservationIgnored private let source: DownloadsSource
    @ObservationIgnored private let clock: @Sendable () -> Int64
    @ObservationIgnored private let wakeUp: Wake
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastAcquisitions: [Acquisition] = []
    @ObservationIgnored private var lastUpgrades: [Upgrade] = []
    /// Rows cleared here that the server still lists: upgrades, which it keeps a week.
    @ObservationIgnored private var hidden = Set<String>()

    public init(source: DownloadsSource, clock: @escaping @Sendable () -> Int64 = { msSince1970() }, sleep: @escaping Sleeper = realSleep) {
        self.source = source
        self.clock = clock
        wakeUp = Wake(sleep: sleep)
    }

    public var started: Bool { task != nil }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.poll()
                await self.wakeUp.wait(ms: self.delayMs())
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        wakeUp.signal()
    }

    /// Forgets what the last server said, for a sign-in to another one.
    public func reset() {
        lastAcquisitions = []
        lastUpgrades = []
        hidden.removeAll()
        loaded = false
        listedSince = nil
        rows = []
        upgrades = []
    }

    /// Asks again now, as after a song was asked for.
    public func wake() { wakeUp.signal() }

    func delayMs() -> Int64 {
        if open && foreground { return downloadsOpenPollMs }
        if runningCount(rows) > 0 && foreground { return downloadsRunningPollMs }
        return downloadsIdlePollMs
    }

    /// One look at the server. A moment without the server changes nothing.
    public func poll() async {
        let askedAt = clock()
        do {
            lastAcquisitions = try await source.acquisitions()
            if let fresh = try? await source.upgrades() { lastUpgrades = fresh }
            loaded = true
            if upgrades != lastUpgrades { upgrades = lastUpgrades }
            show()
            listedSince = askedAt
            upgradesRead?(lastUpgrades)
        } catch {
            // Kept as it was.
        }
    }

    private func show() {
        let next = drawerRows(lastAcquisitions, lastUpgrades, now: clock(), hidden: hidden)
        if next != rows { rows = next }
    }

    /// The key of the newest download of a song by the id it was asked for with, so a song's own
    /// button can open its log.
    public func keyFor(_ id: String) -> String? {
        lastAcquisitions.filter { $0.id == id || $0.libraryId == id }.max { ($0.startedAt ?? "") < ($1.startedAt ?? "") }?.key
    }

    /// Takes finished rows off the list, or the one with this key. The server forgets its
    /// downloads; upgrades stay on it and are hidden here.
    public func clear(_ key: String? = nil) async {
        let gone = rows.filter { $0.finished && (key == nil || $0.key == key) }
        if gone.isEmpty { return }
        for row in gone { hidden.insert(row.key) }
        show()
        do {
            if key == nil {
                try await source.clear(nil)
            } else {
                for logKey in gone.compactMap(\.logKey) { try await source.clear(logKey) }
            }
        } catch {
            // Hidden here anyway; the server lets them go on its own.
        }
        wake()
    }
}

/// Follows one download's log while it is open: often while it runs, and for a minute once it has
/// finished, since lyrics are looked for once the song is in; then no more. A log that finished
/// longer ago than that is read once. Behind the app it waits until the app is in front again.
@MainActor
@Observable
public final class DownloadLogWatch {
    public private(set) var row: Acquisition?
    /// Why the log could not be read, in words, while it cannot.
    public private(set) var problem: String?

    /// Whether the app is in front; behind it, the log is not asked for.
    public var foreground = true {
        didSet { if foreground && !oldValue { front.signal() } }
    }

    @ObservationIgnored private let load: @Sendable (String) async throws -> Acquisition
    @ObservationIgnored private let pollMs: Int64
    @ObservationIgnored private let graceMs: Int64
    @ObservationIgnored private let clock: @Sendable () -> Int64
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private let front: Wake
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var round = 0
    /// Whether the log is still being asked for.
    @ObservationIgnored public private(set) var following = false

    public init(load: @escaping @Sendable (String) async throws -> Acquisition, pollMs: Int64 = logPollMs, graceMs: Int64 = logFinishedGraceMs,
                clock: @escaping @Sendable () -> Int64 = { msSince1970() }, sleep: @escaping Sleeper = realSleep) {
        self.load = load
        self.pollMs = pollMs
        self.graceMs = graceMs
        self.clock = clock
        self.sleep = sleep
        front = Wake(sleep: realSleep)
    }

    /// Follows the download with this key until it has finished a while, another is followed, or
    /// the log closes.
    public func follow(_ key: String) {
        task?.cancel()
        row = nil
        problem = nil
        following = true
        round += 1
        let mine = round
        task = Task { [weak self] in
            // How long it has been seen finished here.
            var finishedFor: Int64 = 0
            defer { self?.ended(mine) }
            while !Task.isCancelled {
                guard let self else { return }
                while !self.foreground && !Task.isCancelled { await self.front.wait(ms: 60_000) }
                if Task.isCancelled { return }
                do {
                    let now = try await self.load(key)
                    if Task.isCancelled { return }
                    self.row = now
                    self.problem = nil
                    if now.stage == .done || now.stage == .failed {
                        let age = serverAgeMs(now.updatedAt, now: self.clock()) ?? 0
                        if finishedFor >= self.graceMs || age >= self.graceMs { return }
                        finishedFor += self.pollMs
                    }
                } catch {
                    if Task.isCancelled { return }
                    if case OctoError.notFound = error {
                        self.problem = "This download is no longer on the server"
                        return
                    }
                    self.problem = "Could not reach the server"
                }
                await self.sleep(self.pollMs)
            }
        }
    }

    private func ended(_ which: Int) { if which == round { following = false } }

    /// Waits for the log to stop being asked for, for tests.
    public func settle() async { await task?.value }

    public func close() {
        task?.cancel()
        task = nil
        following = false
        row = nil
        problem = nil
        front.signal()
    }
}

/// What Find songs needs from the app: the server's three calls. `anyway` is nil when it is not to
/// be sent at all.
public protocol FindSource: Sendable {
    func start(_ id: String) async throws -> FoundSongs
    func get(_ search: String) async throws -> FoundSongs
    func pick(_ search: String, _ copy: FoundCandidate, anyway: Bool?) async throws -> PickResult
}

/// A Find songs search, followed until every source has answered, and the copy picked from it.
@MainActor
@Observable
public final class FindSongsWatch {
    /// The search as the server last said it.
    public private(set) var found: FoundSongs?
    public private(set) var problem: String?
    /// What the last pick did.
    public private(set) var picked: PickResult?
    /// A pick waiting for an answer, while its search is the one on screen.
    public private(set) var question: PickQuestion?

    /// Whether the server asks before a copy replaces the library's (octoAcquisitions 3). Only then
    /// is `anyway` sent: false to ask, which never fetches a library song, and true once the person
    /// said yes. An older server never gets it and says no in words instead.
    public var asksFirst = false

    @ObservationIgnored private let source: FindSource
    @ObservationIgnored private let pollMs: Int64
    @ObservationIgnored private let sleep: Sleeper
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(source: FindSource, pollMs: Int64 = findPollMs, sleep: @escaping Sleeper = realSleep) {
        self.source = source
        self.pollMs = pollMs
        self.sleep = sleep
    }

    /// Starts a search for a song by its id on the server, followed until it ends.
    public func search(_ id: String) {
        task?.cancel()
        found = nil
        problem = nil
        picked = nil
        question = nil
        task = Task { [weak self] in
            guard let self else { return }
            var now: FoundSongs
            do {
                now = try await self.source.start(id)
            } catch {
                if !Task.isCancelled { self.problem = serverWords(error) ?? "Could not start the search" }
                return
            }
            if Task.isCancelled { return }
            self.found = now
            while !Task.isCancelled && now.searching {
                await self.sleep(self.pollMs)
                if Task.isCancelled { return }
                do {
                    now = try await self.source.get(now.id)
                } catch {
                    if !Task.isCancelled { self.problem = serverWords(error) ?? "Could not reach the server" }
                    return
                }
                if Task.isCancelled { return }
                self.found = now
            }
        }
    }

    /// Waits for the running search to stop asking, for tests.
    public func settle() async { await task?.value }

    /// Fetches one copy from the search `search`, and answers what the server did. Never while the
    /// search runs, nor from a list that another search has replaced. A server that asks first
    /// answers a library song's pick with a question instead, which waits in `question`.
    @discardableResult
    public func pick(_ search: String, _ copy: FoundCandidate) async -> PickResult {
        question = nil
        return await send(search, copy, anyway: asksFirst ? false : nil)
    }

    /// Sends the pick the question was about again with anyway=true. Nil when that question is no
    /// longer the one waiting, and nothing is sent.
    public func replaceAnyway(_ asked: PickQuestion) async -> PickResult? {
        guard question == asked else { return nil }
        question = nil
        return await send(asked.search, asked.copy, anyway: true)
    }

    /// Leaves the library's copy as it is: nothing is sent. Given a question, only that one is let
    /// go, not one asked since.
    public func keepMine(_ asked: PickQuestion? = nil) {
        if asked == nil || question == asked { question = nil }
    }

    private func send(_ search: String, _ copy: FoundCandidate, anyway: Bool?) async -> PickResult {
        let refused: String? = if found == nil || found?.id != search { findListChanged } else if found?.searching == true { findPickWait } else { nil }
        if let refused {
            let result = PickResult(pickSkipped, refused)
            picked = result
            return result
        }
        let result: PickResult
        do {
            result = try await source.pick(search, copy, anyway: anyway)
        } catch {
            result = PickResult(pickSkipped, serverWords(error) ?? "The server could not be asked")
        }
        if showing(search) {
            let song = found?.song
            var asked: PickQuestion?
            if result.confirm {
                let words = result.detail.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? replaceAnywayFallback
                asked = PickQuestion(search: search, copy: copy, words: words, kind: .confirm, compare: result.compare,
                                     songId: song?.libraryId, title: song?.title ?? "")
            } else if result.ready {
                asked = PickQuestion(search: search, copy: copy, words: replaceQuestion(copy), kind: .ready, compare: result.compare,
                                     songId: song?.libraryId, title: song?.title ?? "")
            }
            if let asked {
                picked = nil
                question = asked
            } else {
                picked = result
            }
        }
        return result
    }

    /// Whether the search `search` is still the one followed: not closed, and not replaced.
    public func showing(_ search: String) -> Bool { found?.id == search }

    public func close() {
        task?.cancel()
        task = nil
        found = nil
        problem = nil
        picked = nil
        question = nil
    }
}
