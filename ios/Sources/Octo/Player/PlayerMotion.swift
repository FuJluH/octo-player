import Observation
import OctoKit
import QuartzCore

/// Whether the player is opening, pulled, springing back or closing right now. The frame loops
/// that show during those read `moving` and run every frame while it is true, so nothing in the
/// transition lags or stops; once it is false again they go back to their resting paces.
@MainActor
@Observable
final class PlayerMotion {
    static let shared = PlayerMotion()

    private(set) var moving = false
    @ObservationIgnored private var clock = PlayerMotionClock()
    @ObservationIgnored private var settle: Task<Void, Never>?

    private init() {}

    /// A transition of `seconds` starts now.
    func moved(for seconds: Double) {
        clock.moved(at: CACurrentMediaTime(), for: seconds)
        refresh()
    }

    /// A finger took the player, or let it go.
    func hold(_ on: Bool) {
        clock.hold(on, at: CACurrentMediaTime())
        refresh()
    }

    private func refresh() {
        let now = CACurrentMediaTime()
        let next = clock.moving(at: now)
        if next != moving { moving = next }
        settle?.cancel()
        settle = nil
        guard next, let wait = clock.restsIn(at: now) else { return }
        settle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
