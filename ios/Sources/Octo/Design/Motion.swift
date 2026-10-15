import Foundation
import Observation
import OctoKit
import SwiftUI

/// The easing curves Octo's motion uses, as plain functions of progress from 0 to 1.
enum Easing {
    /// Speeds up quickly and settles slowly.
    static func fastOutSlowIn(_ x: Double) -> Double { cubicBezier(0.4, 0, 0.2, 1, x) }
    /// Starts at full speed and settles slowly.
    static func linearOutSlowIn(_ x: Double) -> Double { cubicBezier(0, 0, 0.2, 1, x) }

    /// The y of a CSS-style cubic bezier from (0, 0) to (1, 1) at the point whose x is `x`.
    static func cubicBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
        EasingCurve(x1, y1, x2, y2).at(min(1, max(0, x)))
    }
}

/// Octo's own Reduce motion, beside the phone's: off by default, kept with the other settings
/// (Settings, Appearance, Motion).
@MainActor
@Observable
final class MotionSettings {
    private let store: AppSettings

    init(store: AppSettings = .shared) { self.store = store }

    var reduceMotion: Bool {
        get { store.player.reduceMotion }
        set { store.setReduceMotion(newValue) }
    }
}

extension EnvironmentValues {
    /// The motion scale in force: reduced when Octo's Reduce motion or the phone's is on.
    @Entry var motionScale: MotionScale = .full
    /// Whether motion is reduced, by Octo's own setting or the phone's. Surfaces then fade
    /// rather than move.
    @Entry var octoReduceMotion = false
}

extension View {
    /// Gives everything inside the motion scale from Octo's setting and the phone's.
    func motionScaled(_ settings: MotionSettings) -> some View {
        modifier(MotionScaled(settings: settings))
    }
}

private struct MotionScaled: ViewModifier {
    let settings: MotionSettings
    @Environment(\.accessibilityReduceMotion) private var system

    func body(content: Content) -> some View {
        let scale = MotionScale.of(systemReduced: system, reduce: settings.reduceMotion)
        content
            .environment(\.motionScale, scale)
            .environment(\.octoReduceMotion, scale.still)
    }
}

extension Animation {
    /// One of Octo's springs, by damping ratio and stiffness.
    static func octo(_ spring: SpringSpec) -> Animation {
        .spring(response: spring.response, dampingFraction: spring.damping)
    }

    /// A spring by damping ratio and stiffness.
    static func octoSpring(_ damping: Double, _ stiffness: Double) -> Animation {
        octo(SpringSpec(damping, stiffness))
    }

    /// A tween of `ms` milliseconds on `curve`, after the motion scale.
    static func octoTween(_ ms: Int, _ curve: EasingCurve = OctoEasing.spring, scale: MotionScale = .full,
                          delay: Int = 0) -> Animation {
        Animation.timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: Double(scale.ms(ms)) / 1_000)
            .delay(Double(scale.ms(delay)) / 1_000)
    }

    /// A tween of `ms` milliseconds on `curve`, not scaled.
    static func octoTween(fixed ms: Int, _ curve: EasingCurve = OctoEasing.standard, delay: Int = 0) -> Animation {
        Animation.timingCurve(curve.x1, curve.y1, curve.x2, curve.y2, duration: Double(ms) / 1_000)
            .delay(Double(delay) / 1_000)
    }
}

extension EasingCurve {
    /// The curve as a SwiftUI timing curve.
    var unitCurve: UnitCurve { .bezier(startControlPoint: UnitPoint(x: x1, y: y1), endControlPoint: UnitPoint(x: x2, y: y2)) }
}
