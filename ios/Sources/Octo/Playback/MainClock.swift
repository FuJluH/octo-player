import Foundation
import OctoKit

/// The player's clock: real time on the main thread, for the play counter and the sleep timer.
/// It keeps counting while the phone sleeps, so a countdown left running is still right after.
@MainActor
final class MainClock: PlaybackClock {
    nonisolated func now() -> Int { Int(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000) }

    nonisolated func wallNow() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    nonisolated func after(_ ms: Int, _ block: @escaping () -> Void) -> () -> Void {
        let work = Unchecked(block)
        let item = DispatchWorkItem { work.value() }
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + .milliseconds(max(0, ms)), execute: item)
        return { item.cancel() }
    }
}

/// The sleep timer's clock: it keeps counting while the phone sleeps, and its waits end on time
/// even when the phone slept through them.
@MainActor
final class SleepClock: PlaybackClock {
    nonisolated func now() -> Int { Int(clock_gettime_nsec_np(CLOCK_MONOTONIC) / 1_000_000) }

    nonisolated func wallNow() -> Int { Int(Date().timeIntervalSince1970 * 1000) }

    nonisolated func after(_ ms: Int, _ block: @escaping () -> Void) -> () -> Void {
        let work = Unchecked(block)
        let item = DispatchWorkItem { work.value() }
        DispatchQueue.main.asyncAfter(wallDeadline: .now() + .milliseconds(max(0, ms)), execute: item)
        return { item.cancel() }
    }
}
