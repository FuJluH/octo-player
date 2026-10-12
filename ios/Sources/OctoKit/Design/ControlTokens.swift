import Foundation

/// The sizes a switch comes in: its track and its thumb, in points.
public enum SwitchSize: CaseIterable, Sendable {
    case small, standard, large

    public var width: Double {
        switch self {
        case .small: 30
        case .standard: 36
        case .large: 44
        }
    }

    public var height: Double {
        switch self {
        case .small: 18
        case .standard: 22
        case .large: 26
        }
    }

    public var thumb: Double {
        switch self {
        case .small: 14
        case .standard: 18
        case .large: 22
        }
    }

    /// The room between the track's edge and the thumb.
    public static let padding = 2.0
}

/// How much wider the thumb stretches while it is held.
public let switchSquish = 1.18

/// Where a switch's thumb is and how wide.
public struct SwitchThumb: Sendable, Equatable {
    public let x: Double
    public let width: Double

    public init(_ x: Double, _ width: Double) {
        self.x = x
        self.width = width
    }
}

/// The thumb in a track `track` wide with `padding` either side. `position` runs from 0 (off,
/// at the start) to 1 (on, at the end); `stretch` from 0 (at rest) to 1 (held). A held thumb
/// grows toward where it is going, keeping the edge on the side it is leaving.
public func switchThumb(track: Double, thumb: Double, padding: Double, position: Double, stretch: Double) -> SwitchThumb {
    let width = thumb * (1 + (switchSquish - 1) * stretch)
    let travel = track - 2 * padding - thumb
    let x = padding + travel * position - (width - thumb) * position
    return SwitchThumb(x, width)
}

/// The sizes a standard button comes in: its height, its height in a dense list, the room
/// either side of its words, its icon and the size of its words. Large is the phone's.
public enum ButtonSize: CaseIterable, Sendable {
    case extraSmall, small, medium, large

    public var height: Double {
        switch self {
        case .extraSmall: 24
        case .small: 30
        case .medium: 36
        case .large: 50
        }
    }

    public var dense: Double {
        switch self {
        case .extraSmall: 20
        case .small: 24
        case .medium: 28
        case .large: 40
        }
    }

    public var padding: Double {
        switch self {
        case .extraSmall: 8
        case .small, .medium: 12
        case .large: 24
        }
    }

    public var iconSize: Double {
        switch self {
        case .extraSmall: 14
        case .small: 16
        case .medium: 18
        case .large: 20
        }
    }

    public var fontSize: Double {
        switch self {
        case .extraSmall: 12.5
        case .small, .medium, .large: 13.5
        }
    }
}

/// How strongly a tab the selection passes over flashes.
public let gearShiftTintMax = 0.22

/// How strongly the tab at `index` flashes while the selection pill, at `pill` (in tabs from
/// the first), passes over it: most as the pill's middle crosses it, none once the pill is a
/// whole tab away. The tab the pill is heading for does not flash.
public func gearShiftTint(_ index: Int, pill: Double, selected: Int) -> Double {
    if index == selected { return 0 }
    return gearShiftTintMax * min(1, max(0, 1 - abs(pill - Double(index))))
}

/// A small gesture an icon makes when its action happens.
public enum IconAccent: CaseIterable, Sendable {
    /// Up a little and back, for sending something up or away.
    case lift
    /// Down a little and back, for a download or a drop into a list.
    case drop
    /// Up and a touch larger, for raising something to the top.
    case raise
    /// Forward 4 points and back, for next.
    case slideForward
    /// Back 4 points and return, for previous.
    case slideBack
    /// Larger and back, for opening something out.
    case expand
    /// Smaller and back, for folding something away.
    case collapse
    /// A beat larger and back, for liking.
    case pulse
    /// A bell's swing, dying away.
    case ring
    /// One full turn, for refreshing.
    case spinStep
}

/// Where an icon is part-way through its gesture: moved by `dx`, `dy` points, grown by
/// `scale`, turned by `rotation` degrees.
public struct AccentPose: Sendable, Equatable {
    public var dx = 0.0
    public var dy = 0.0
    public var scale = 1.0
    public var rotation = 0.0

    public init(dx: Double = 0, dy: Double = 0, scale: Double = 1, rotation: Double = 0) {
        self.dx = dx
        self.dy = dy
        self.scale = scale
        self.rotation = rotation
    }

    public static let rest = AccentPose()
}

/// Where the peak of every icon gesture falls.
public let accentPeak = 0.45

/// How long an icon gesture lasts, in milliseconds before the motion scale.
public let accentDuration = OctoDuration.neutral

/// How far into its gesture an icon is at `progress` (0 to 1): nothing at either end, all of
/// it at the peak.
public func accentStrength(_ progress: Double) -> Double {
    if progress <= 0 || progress >= 1 { return 0 }
    if progress < accentPeak { return OctoEasing.spring.at(progress / accentPeak) }
    return 1 - OctoEasing.spring.at((progress - accentPeak) / (1 - accentPeak))
}

/// The pose of `accent` at `progress`, with travel and growth multiplied by `distance`, so
/// reduced motion keeps icons still.
public func accentPose(_ accent: IconAccent, _ progress: Double, distance: Double = 1) -> AccentPose {
    if distance == 0 || progress <= 0 || progress >= 1 { return .rest }
    let s = accentStrength(progress) * distance
    switch accent {
    case .lift: return AccentPose(dy: -3 * s)
    case .drop: return AccentPose(dy: 3 * s)
    case .raise: return AccentPose(dy: -2 * s, scale: 1 + 0.08 * s)
    case .slideForward: return AccentPose(dx: 4 * s)
    case .slideBack: return AccentPose(dx: -4 * s)
    case .expand: return AccentPose(scale: 1 + 0.15 * s)
    case .collapse: return AccentPose(scale: 1 - 0.15 * s)
    case .pulse: return AccentPose(scale: 1 + 0.2 * s)
    case .ring: return AccentPose(rotation: 16 * distance * sin(progress * 6 * Double.pi) * (1 - progress))
    case .spinStep: return AccentPose(rotation: 360 * distance * OctoEasing.spring.at(progress))
    }
}

/// A fraction moved to the nearest of `steps` equal steps; with no steps it is left alone.
public func snapToSteps(_ fraction: Double, _ steps: Int) -> Double {
    let f = min(1, max(0, fraction))
    if steps <= 0 { return f }
    return (f * Double(steps)).rounded(.toNearestOrAwayFromZero) / Double(steps)
}
