import Foundation
import OctoKit

/// The player's clock: real time on the main thread, for the play counter and the sleep timer.
@MainActor
final class MainClock: PlaybackClock {
    nonisolated func now() -> Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }

    nonisolated func wallNow() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    nonisolated func after(_ ms: Int, _ block: @escaping () -> Void) -> () -> Void {
        let work = Unchecked(block)
        let item = DispatchWorkItem { work.value() }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(max(0, ms)), execute: item)
        return { item.cancel() }
    }
}
