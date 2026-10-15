import Foundation

/// The full player's title row: the song's name and artist, and beside them the heart (or the add
/// or plus) and More, which sit on the middle of the name's capitals, the same for a song and a
/// station, whatever the name is doing.
public enum PlayerTitleRow {
    /// Each button's round target, in points.
    public static let buttonSize = 44.0
    /// How strongly the buttons' icons show: a step quieter than the name, as actions beside it.
    public static let iconAlpha: Float = 0.7
    /// How tall the heart stands against the name's capitals.
    public static let heightOverCap = 1.15
    /// How far the artist line sits up into the room under the name, so the two read as one.
    public static let artistRaise = 3.0
}

/// The middle of `capHeight` capitals standing on `baseline`, both measured down from the top of
/// the name's line.
public func capMiddle(baseline: Double, capHeight: Double) -> Double { baseline - capHeight / 2 }

/// Where the buttons go across a row whose right edge is `sideMargin` in from the screen's: the
/// gap between the heart and the dots is also the gap from the dots to the screen's edge, so the
/// two read evenly spaced. `heartHalf` and `dotsHalf` are half of what each icon covers across.
/// The answer is how far the buttons reach past the row's right edge (into its margin).
public func titleButtonsReach(sideMargin: Double, buttonSize: Double = PlayerTitleRow.buttonSize, heartHalf: Double, dotsHalf: Double) -> Double {
    let gap = buttonSize - heartHalf - dotsHalf
    let dotsRight = sideMargin - gap
    return max(0, dotsRight + (buttonSize / 2 - dotsHalf))
}

/// How strongly icons drawn a step quieter than the words, in `ink`, show over the color `under`
/// them: `soft` where that keeps `contrast`, more as far as reading needs over a background close
/// to the words' limit, at most fully.
public func quietAlpha(_ under: UInt32, ink: UInt32, soft: Float, contrast: Double = PlayerContrast) -> Float {
    func reads(_ alpha: Float) -> Bool { contrastRatio(overlay(ink, alpha, under), under) >= contrast }
    if reads(soft) { return soft }
    if !reads(1) { return 1 }
    var low = soft
    var high: Float = 1
    for _ in 0..<20 {
        let mid = (low + high) / 2
        if reads(mid) { high = mid } else { low = mid }
    }
    return high
}

/// The color the quiet icons sit on: the background's brightest part under white words (as far
/// as it shows over the base), its darkest under dark ones; the base while the cover is not ready.
public func quietIconsUnder(_ range: WashRange?, base: UInt32, dark: Bool, show: Float) -> UInt32 {
    guard let range else { return base }
    return dark ? range.low : overlay(range.high, show, base)
}

/// A single line too long for its room: it fades out softly at its right edge, and with scrolling
/// on it scrolls through a few times, as a marquee does, fading softly at its left edge only while
/// it moves, so at rest its first letter sits crisp.
public enum Marquee {
    /// How long the fades are, in points.
    public static let fade = 28.0
    /// How fast a line scrolls, in points a second.
    public static let speed = 30.0
    /// How long it rests before each pass, in seconds.
    public static let rest = 1.2
    /// The room after the line before it comes round again, as a share of the room.
    public static let spacing = 1.0 / 3.0
    /// How many passes.
    public static let passes = 3
    /// How long the left fade takes to come and go, in seconds.
    public static let fadeIn = 0.25

    /// Where a pass stands `t` seconds after the line started: how far it has moved (0 at rest)
    /// and how strong its left fade is (0 to 1). `distance` is the line's length plus the room
    /// after it. After the last pass it rests for good.
    public static func at(_ t: Double, distance: Double) -> (offset: Double, leftFade: Double) {
        guard distance > 0, t > 0 else { return (0, 0) }
        let moving = distance / speed
        let cycle = rest + moving + fadeIn
        let pass = Int(t / cycle)
        guard pass < passes else { return (0, 0) }
        let local = t - Double(pass) * cycle
        if local < rest { return (0, 0) }
        let into = local - rest
        if into < moving {
            return (min(into * speed, distance), min(into / fadeIn, 1))
        }
        // Back at the start without a jump (the copy behind sits where the line began), the
        // left fade going.
        return (0, max(0, 1 - (into - moving) / fadeIn))
    }

    /// How long all the passes take, after which the line rests.
    public static func duration(distance: Double) -> Double {
        guard distance > 0 else { return 0 }
        return Double(passes) * (rest + distance / speed + fadeIn)
    }

    /// The eased fade from shown to gone, as stops (place 0 to 1, opacity) along a smooth curve
    /// rather than a straight ramp, so the fade has no visible start.
    public static let easedOut: [(at: Double, alpha: Double)] = (0...8).map { i in
        let t = Double(i) / 8
        let eased = t * t * (3 - 2 * t)
        return (t, max(0, 1 - eased))
    }
}
