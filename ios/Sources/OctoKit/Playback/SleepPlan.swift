import Foundation

/// Where the sleep timer is: off, counting down, or waiting for songs to end.
public enum SleepState: Sendable, Equatable {
    case off
    case counting(remainingMs: Int)
    case endOfSong
    /// Waiting for this many songs to end, the one playing included. Always 2 or more; the last
    /// one is `endOfSong`.
    case songs(left: Int)
    /// Waiting for one song further down the queue to end: `key` is its queue entry, `title`
    /// what to call it.
    case afterSong(key: String, title: String)
}

/// The lengths offered, in minutes.
public let sleepMinutes = [5, 15, 30, 45, 60]

/// What a running countdown can be lengthened by, in minutes.
public let sleepExtensions = [5, 10]

/// How many songs the music can stop after, the one playing included.
public let sleepSongCounts = [1, 2, 3, 5]

/// The longest custom timer: twelve hours.
public let maxSleepMinutes = 720

/// The last stretch of a timer, over which the music fades out.
public let sleepFadeMs = 30_000

/// How loud the music is with this long left: full until the last 30 seconds, then down to
/// silence. Squared, so the fade sounds even.
public func sleepFade(_ remainingMs: Int) -> Float {
    let left = min(max(Float(remainingMs) / Float(sleepFadeMs), 0), 1)
    return left * left
}

/// How long until the next tick: on each whole second while counting, so the clock on screen
/// never skips, and ten times a second through the fade.
public func untilNextSleepTick(_ remainingMs: Int) -> Int {
    let step = remainingMs > sleepFadeMs ? 1_000 : 100
    return (remainingMs - 1) % step + 1
}

/// A timer in words, for the timer's card and its button.
public func sleepSummary(_ state: SleepState) -> String {
    switch state {
    case .off: "Off"
    case .counting(let remaining): "\((remaining + 59_999) / 60_000) min left"
    case .endOfSong: "At the end of this song"
    case .songs(let left): "After " + (left == 1 ? "1 song" : "\(left) songs")
    case .afterSong(_, let title): "After \(title)"
    }
}
