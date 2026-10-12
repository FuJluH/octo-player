import Foundation

/// How much of a song is ready before it starts playing, the same choices on every app. A
/// second is what players wait by default.
public enum StartAfter: String, CaseIterable, Sendable {
    case instant = "Instant"
    case short = "Short"
    case steady = "Steady"
    case safe = "Safe"
    case long = "Long"

    public var ms: Int {
        switch self {
        case .instant: 250
        case .short: 1_000
        case .steady: 2_500
        case .safe: 5_000
        case .long: 10_000
        }
    }

    public var label: String {
        switch self {
        case .instant: "As soon as possible"
        case .short: "1 second"
        case .steady: "2.5 seconds"
        case .safe: "5 seconds"
        case .long: "10 seconds"
        }
    }
}

public let startAfterSetting = "Start playing after"
public let startAfterHelp = "Waits for this much audio before a song starts. Shorter starts faster on a slow connection; longer stutters less."

/// What the player does after running dry before it plays on, at the least.
public let bufferForPlaybackAfterRebufferMs = 2_000

/// Whether enough is buffered to start: `startAfterMs` of playing time at this speed, or after
/// running dry at least `bufferForPlaybackAfterRebufferMs`.
public func hasEnoughToStart(bufferedUs: Int, speed: Float, rebuffering: Bool, startAfterMs: Int) -> Bool {
    let playout = (speed == 1 || speed <= 0) ? bufferedUs : Int((Double(bufferedUs) / Double(speed)).rounded())
    let need = rebuffering ? max(startAfterMs, bufferForPlaybackAfterRebufferMs) : startAfterMs
    return playout >= need * 1_000
}
