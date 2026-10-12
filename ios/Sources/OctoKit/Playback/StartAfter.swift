import Foundation

/// What the player does after running dry before it plays on, at the least.
public let bufferForPlaybackAfterRebufferMs = 2_000

/// Whether enough is buffered to start: `startAfterMs` of playing time at this speed, or after
/// running dry at least `bufferForPlaybackAfterRebufferMs`.
public func hasEnoughToStart(bufferedUs: Int, speed: Float, rebuffering: Bool, startAfterMs: Int) -> Bool {
    let playout = (speed == 1 || speed <= 0) ? bufferedUs : Int((Double(bufferedUs) / Double(speed)).rounded())
    let need = rebuffering ? max(startAfterMs, bufferForPlaybackAfterRebufferMs) : startAfterMs
    return playout >= need * 1_000
}
