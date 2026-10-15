import Foundation

/// A play only counts once enough of the song was heard: half of it or four minutes, whichever
/// comes first, and never for clips under 30 seconds.
public func countsAsPlay(playedMs: Int, durationMs: Int) -> Bool {
    durationMs >= 30_000 && playedMs >= min(durationMs / 2, 240_000)
}

/// How much more of a song must be heard before a play counts, or nil when it never can (a
/// clip under 30 seconds, or no known length).
public func msLeftToCount(playedMs: Int, durationMs: Int) -> Int? {
    durationMs < 30_000 ? nil : max(0, min(durationMs / 2, 240_000) - playedMs)
}

/// The same rule in seconds, for callers that keep time that way.
public enum PlayRules {
    public static func countsAsPlay(played: TimeInterval, duration: TimeInterval) -> Bool {
        OctoKit.countsAsPlay(playedMs: Int(played * 1000), durationMs: Int(duration * 1000))
    }
}
