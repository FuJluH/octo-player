import Foundation

/// Runs blocks after a wait on one thread, and tells the time; a stand-in drives it in tests.
public protocol PlaybackClock: AnyObject {
    /// Milliseconds on a clock that never goes back.
    func now() -> Int
    /// Milliseconds since 1970.
    func wallNow() -> Int
    /// Runs `block` after `ms`; the answer calls it off.
    func after(_ ms: Int, _ block: @escaping () -> Void) -> () -> Void
}

/// Counts how long each song was actually heard (pauses excluded) and records a play the moment
/// enough of it was heard, or when it moves on if that moment was missed. Also says when each
/// song first starts to play.
public final class PlayTracker {
    private let started: (String) -> Void
    private let record: (_ trackId: String, _ startedAt: Int, _ heardMs: Int, _ durationMs: Int) -> Void
    private let isPlaying: () -> Bool
    private let clock: PlaybackClock

    public private(set) var trackId: String?
    private var durationMs = 0
    private var startedAt = 0
    private var heardMs = 0
    private var playingSince: Int?
    private var announced = false
    private var counted = false
    private var callOff: (() -> Void)?

    public init(started: @escaping (String) -> Void, record: @escaping (String, Int, Int, Int) -> Void,
                isPlaying: @escaping () -> Bool, clock: PlaybackClock) {
        self.started = started
        self.record = record
        self.isPlaying = isPlaying
        self.clock = clock
    }

    public func playingChanged(_ playing: Bool) {
        if playing {
            playingSince = clock.now()
            announce()
            watch()
        } else {
            stopClock()
            stopWatching()
        }
    }

    /// The song changed. Songs change while music keeps playing, so the clock keeps running.
    public func moved(_ id: String?, length: Int) {
        flush(stillPlaying: isPlaying())
        trackId = id
        durationMs = length
        startedAt = clock.wallNow()
        announced = false
        counted = false
        if isPlaying() {
            announce()
            watch()
        }
    }

    /// The song's length as the player measured it, once it has opened: a play is measured by
    /// the length of its sound, not its listing.
    public func lengthFound(_ id: String, length: Int) {
        guard id == trackId, length > 0, length != durationMs else { return }
        durationMs = length
        if callOff != nil { watch() }
    }

    /// Once per song, the first time it actually plays.
    private func announce() {
        guard !announced else { return }
        announced = true
        if let trackId { started(trackId) }
    }

    /// Records the current song if it counts and was not recorded already, then starts over.
    public func flush(stillPlaying: Bool = false) {
        stopWatching()
        stopClock()
        if !counted, let trackId { record(trackId, startedAt, heardMs, durationMs) }
        heardMs = 0
        if stillPlaying { playingSince = clock.now() }
    }

    private func heardNow() -> Int { heardMs + (playingSince.map { clock.now() - $0 } ?? 0) }

    /// Waits for the moment the song counts, while it plays and has not yet.
    private func watch() {
        stopWatching()
        guard !counted, trackId != nil, playingSince != nil,
              let left = msLeftToCount(playedMs: heardNow(), durationMs: durationMs) else { return }
        callOff = clock.after(max(left, 1)) { [weak self] in self?.due() }
    }

    private func due() {
        callOff = nil
        guard let id = trackId, !counted, playingSince != nil else { return }
        let heard = heardNow()
        if !countsAsPlay(playedMs: heard, durationMs: durationMs) { return watch() }
        counted = true
        record(id, startedAt, heard, durationMs)
    }

    private func stopWatching() {
        callOff?()
        callOff = nil
    }

    private func stopClock() {
        if let since = playingSince { heardMs += clock.now() - since }
        playingSince = nil
    }
}
