import Foundation

/// How long the still crossfades into the loop once its first frame is drawn, and back when the
/// loop goes.
public let loopFadeMs = 450

/// What a loop on screen does right now.
public enum LoopPlay: Sendable, Equatable {
    /// Plays, muted and looping.
    case play
    /// Stops where it is: the frame it stopped on stays (the still, when it never started).
    case hold
    /// Shows only the still: the loop is not even loaded.
    case stillOnly
}

/// What a loop does: only the still with Reduce motion on; held while its view is not seen
/// (screen off, app in the background, player closed, page covered) or while the device saves
/// power; else it plays.
public func loopPlay(seen: Bool, powerSave: Bool, reduceMotion: Bool) -> LoopPlay {
    if reduceMotion { return .stillOnly }
    if !seen || powerSave { return .hold }
    return .play
}

/// The albums whose art to ask about when a song starts: its own, then the next songs' (each
/// once, blanks left out).
public func albumsToAsk(playing: String?, next: [String?], ahead: Int = 1) -> [String] {
    var seen = Set<String>()
    return ([playing] + next.prefix(max(ahead, 0))).compactMap { $0 }.filter { id in
        !id.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert(id).inserted
    }
}
