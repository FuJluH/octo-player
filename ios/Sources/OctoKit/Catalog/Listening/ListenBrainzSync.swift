import Foundation

// The rules of sending plays to the listener's ListenBrainz profile, with or without a server.
// Each counted play waits in a queue on the phone until ListenBrainz has it; sending never holds
// up playback or shows a message, and what fails is tried again later.

/// The ListenBrainz settings. `user` is who the saved token belongs to, or nil when none is saved.
public struct ListenBrainzPrefs: Sendable, Equatable {
    public var enabled: Bool
    public var user: String?
    public var needsAttention: Bool
    public var sendPlays: SendPlays
    public var nowPlaying: Bool

    public init(enabled: Bool = false, user: String? = nil, needsAttention: Bool = false, sendPlays: SendPlays = .all,
                nowPlaying: Bool = true) {
        self.enabled = enabled
        self.user = user
        self.needsAttention = needsAttention
        self.sendPlays = sendPlays
        self.nowPlaying = nowPlaying
    }

    public var connected: Bool { user != nil }

    /// Plays are kept while switched on and connected, even while the token needs attention, so
    /// none are lost before it is fixed.
    public var keepsPlays: Bool { enabled && connected }

    public var sends: Bool { keepsPlays && !needsAttention }
}

/// The stored "which plays" choice, all of them when nothing or something unknown is stored.
public func sendPlaysOf(_ stored: String?) -> SendPlays {
    stored.flatMap(SendPlays.init(rawValue:)) ?? .all
}

/// Whether connecting a token lets the waiting plays go: they were kept for someone else.
public func connectingLetsQueueGo(previousUser: String?, user: String) -> Bool {
    previousUser != nil && previousUser != user
}

/// The waiting plays as the queue file keeps them: a JSON list.
public func encodeListenQueue(_ listens: [Listen]) -> Data {
    (try? JSONEncoder().encode(listens)) ?? Data("[]".utf8)
}

/// The waiting plays from the queue file; none when it is missing or cannot be read.
public func decodeListenQueue(_ data: Data?) -> [Listen] {
    guard let data else { return [] }
    return (try? JSONDecoder().decode([Listen].self, from: data)) ?? []
}

/// The play to queue when a play is counted: nil while plays are not kept, for a song this mode
/// leaves out, or for one without a title or artist.
public func listenToQueue(_ prefs: ListenBrainzPrefs, _ song: PlayedSong?, startedAtMs: Int64) -> Listen? {
    guard prefs.keepsPlays, let song, shouldSend(prefs.sendPlays, reachesServer: song.reachesServer) else { return nil }
    return song.listenAt(startedAtMs)
}

/// The play to show as playing now, when a song starts: nil while not sending, with now playing
/// switched off, or for a song that would not be queued either.
public func listenPlayingNow(_ prefs: ListenBrainzPrefs, _ song: PlayedSong?, nowMs: Int64) -> Listen? {
    guard prefs.sends, prefs.nowPlaying, let song, shouldSend(prefs.sendPlays, reachesServer: song.reachesServer) else {
        return nil
    }
    return song.listenAt(nowMs)
}

/// What sending does after one batch's answer.
public enum ListenBrainzNext: Sendable, Equatable {
    /// Sent: on to the next batch.
    case goOn
    /// The token is no longer accepted: stop until it is pasted again.
    case needsAttention
    /// Stop, and try again after this long.
    case retry(afterMs: Int64)
}

/// Failures in a row, and when the next try is due after them.
public struct ListenBrainzBackoff: Sendable, Equatable {
    public var failures: Int
    public var nextTryAt: Int64

    public init(failures: Int = 0, nextTryAt: Int64 = 0) {
        self.failures = failures
        self.nextTryAt = nextTryAt
    }

    /// Whether sending may start at `atMs`. `now` tries even while waiting after failures; a new
    /// play waits its turn.
    public func allowsSend(now: Bool, atMs: Int64) -> Bool {
        now || atMs >= nextTryAt
    }

    /// What one batch's answer at `atMs` means for the sending.
    public mutating func heard(_ result: SubmitResult, atMs: Int64) -> ListenBrainzNext {
        switch result {
        case .sent:
            failures = 0
            nextTryAt = 0
            return .goOn
        case .unauthorized:
            return .needsAttention
        case .rateLimited(let retryInMs):
            nextTryAt = atMs &+ retryInMs
            return .retry(afterMs: retryInMs)
        case .failed, .rejected:
            failures += 1
            let wait = retryDelayMs(failures)
            nextTryAt = atMs &+ wait
            return .retry(afterMs: wait)
        }
    }

    /// A newly accepted token starts afresh.
    public mutating func reset() {
        failures = 0
        nextTryAt = 0
    }
}

/// Sends one batch through `submit`, and takes what ListenBrainz has, or refused for good, out of
/// the queue through `remove`. When ListenBrainz refuses a batch, its halves go on their own, so
/// one bad play does not hold back the rest; a single play refused is let go.
public func deliverListens(
    _ batch: [Listen],
    submit: ([Listen]) async throws -> SubmitResult,
    remove: ([Listen]) async throws -> Void
) async rethrows -> SubmitResult {
    if batch.isEmpty { return .sent }
    let result = try await submit(batch)
    if result == .sent || (result == .rejected && batch.count == 1) {
        try await remove(batch)
        return .sent
    }
    guard result == .rejected else { return result }
    let half = batch.count / 2
    let first = try await deliverListens(Array(batch[..<half]), submit: submit, remove: remove)
    if first != .sent { return first }
    return try await deliverListens(Array(batch[half...]), submit: submit, remove: remove)
}
