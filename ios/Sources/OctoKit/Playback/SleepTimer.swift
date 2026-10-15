import Foundation

/// What the sleep timer works on: the player, or a stand-in in tests.
public protocol SleepTarget: AnyObject {
    /// Volume on top of any ducking: 1 is full, 0 is silent.
    var sleepFade: Float { get set }
    var pauseAtEndOfSong: Bool { get set }
    /// The queue entry playing now.
    var currentKey: String? { get }
    /// Whether a crossfade is under way, so a song change is the song ending.
    var isBlending: Bool { get }
    /// Whether a queue entry is still in the queue.
    func hasEntry(_ key: String) -> Bool
    func pause()
}

/// Why the song on now changed.
public enum SongChange: Sendable, Equatable {
    /// The one before ended and the next followed.
    case auto
    /// The song started again on repeat.
    case repeated
    /// A skip or a jump to another song.
    case seek
    /// A new queue, or the queue changed under it (including a crossfade's hand-over).
    case playlistChanged
}

/// A song changed because the one before it ended, not by a skip or a new queue: on its own,
/// on repeat, or through a crossfade.
func endedOnItsOwn(_ reason: SongChange, blending: Bool) -> Bool {
    reason == .auto || reason == .repeated || (reason == .playlistChanged && blending)
}

/// Stops the music after a while, or at the end of the song. The player attaches itself; the
/// app starts and cancels it.
public final class SleepTimer {
    private let clock: PlaybackClock
    public private(set) var state: SleepState = .off {
        didSet { if state != oldValue { onChange?(state) } }
    }
    /// Told of every new state.
    public var onChange: ((SleepState) -> Void)?

    private var target: SleepTarget?
    private var ticker: (() -> Void)?
    private var endsAt = 0

    public init(clock: PlaybackClock) {
        self.clock = clock
    }

    public func attach(_ player: SleepTarget) {
        target = player
        apply(player)
    }

    /// A running timer goes with the player: there is nothing left for it to stop.
    public func detach() {
        cancel()
        target = nil
    }

    // MARK: What the player tells it

    /// The player paused; `endOfSong` when it paused itself at the end of a song.
    public func playWhenReadyChanged(_ playWhenReady: Bool, endOfSong: Bool) {
        if !playWhenReady && endOfSong && stopsAfterThisSong() { cancel() }
    }

    /// A timer waiting on songs follows them: it counts songs as they end.
    public func songChanged(_ reason: SongChange) {
        switch state {
        case .songs(let left) where endedOnItsOwn(reason, blending: target?.isBlending == true):
            set(left <= 2 ? .endOfSong : .songs(left: left - 1))
        case .afterSong:
            if let target { apply(target) }
        default:
            break
        }
    }

    /// The queue changed: a timer waiting for a song that left the queue goes.
    public func queueChanged() {
        if case .afterSong(let key, _) = state, target?.hasEntry(key) == false { cancel() }
    }

    // MARK: What the app asks

    /// Replaces any timer that is already set.
    public func start(minutes: Int) {
        stopTicker()
        endsAt = clock.now() + minutes * 60_000
        let first = tick()
        if first > 0 { schedule(after: first) }
    }

    public func startEndOfSong() {
        stopTicker()
        set(.endOfSong)
    }

    /// Adds time to a running countdown, lifting any fade already begun.
    public func extend(minutes: Int) {
        guard case .counting = state else { return }
        endsAt += minutes * 60_000
        let left = tick()
        stopTicker()
        if left > 0 { schedule(after: left) }
    }

    /// Stops once this many songs have ended, the one playing included.
    public func startAfterSongs(_ count: Int) {
        if count <= 1 { return startEndOfSong() }
        stopTicker()
        set(.songs(left: count))
    }

    /// Stops once one song in the queue has ended: `key` is its queue entry.
    public func startAfter(key: String, title: String) {
        if key == target?.currentKey { return startEndOfSong() }
        stopTicker()
        set(.afterSong(key: key, title: title))
    }

    /// Also puts the volume back and stops pausing at the end of the song.
    public func cancel() {
        stopTicker()
        set(.off)
    }

    // MARK: Inside

    private func schedule(after left: Int) {
        ticker = clock.after(untilNextSleepTick(left)) { [weak self] in
            guard let self else { return }
            self.ticker = nil
            let next = self.tick()
            if next > 0 { self.schedule(after: next) }
        }
    }

    private func stopTicker() {
        ticker?()
        ticker = nil
    }

    /// Moves the countdown and the fade along; at zero, pauses and turns off.
    @discardableResult
    private func tick() -> Int {
        let remaining = max(0, endsAt - clock.now())
        set(.counting(remainingMs: remaining))
        if remaining == 0 {
            target?.pause()
            cancel()
        }
        return remaining
    }

    private func set(_ next: SleepState) {
        state = next
        if let target { apply(target) }
    }

    private func apply(_ player: SleepTarget) {
        if case .counting(let remaining) = state {
            player.sleepFade = sleepFade(remaining)
        } else {
            player.sleepFade = 1
        }
        player.pauseAtEndOfSong = stopsAfterThisSong()
    }

    /// Whether the song playing now is the last one before stopping.
    private func stopsAfterThisSong() -> Bool {
        switch state {
        case .endOfSong: true
        case .afterSong(let key, _): key == target?.currentKey
        default: false
        }
    }
}
