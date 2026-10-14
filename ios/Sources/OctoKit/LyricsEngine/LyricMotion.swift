import Foundation

// Everything here is plain arithmetic on the lyric clock, so it can be checked without a screen.
// Times are in seconds, sizes in pixels unless they say em (the main line's font size).

// MARK: - Line layout

/// The focus line's middle sits this far down the view. A third of the way down, with the sung
/// lines above it, so the lyrics use the whole screen rather than only its lower half.
public let FOCUS_AT = 0.33

/// Where line `i` goes so the anchor line `a` sits at the focus: every line stacked on the ones
/// above it, shifted so the anchor's middle lands at the focus height of the view. `above` holds,
/// for each line, the height of all lines before it (one more entry than there are lines).
public func targetY(_ i: Int, a: Int, above: [Double], heights: [Double], viewHeight: Double) -> Double {
    above[i] - above[a] + (FOCUS_AT * viewHeight - heights[a] / 2)
}

/// The running heights `targetY` needs.
public func heightsAbove(_ heights: [Double]) -> [Double] {
    var above = [Double](repeating: 0.0, count: heights.count + 1)
    for i in heights.indices { above[i + 1] = above[i] + heights[i] }
    return above
}

/// Lines count as on screen from a little above the top to a little below the bottom; outside
/// that they jump instead of moving.
public func onScreen(_ y: Double, height: Double, viewHeight: Double) -> Bool {
    y >= -(height + 0.3 * viewHeight) && y <= 1.3 * viewHeight
}

/// A line never springs further than this many views; it is moved closer first.
public let MAX_TRAVEL_VIEWS = 1.5

// MARK: - The ripple

public let CASCADE_STEP_S = 0.05
public let CASCADE_SHRINK = 1.05

/// How long each line waits before heading for its new place when the focus moves, so the lines
/// ripple up one after another. Walking down the lines on screen, each waits one step longer than
/// the one above; from the focus line down, the step shrinks a little each line, so the ripple
/// tightens below it. Lines off screen do not wait. `stepScale` is the Ripple setting.
public func cascadeDelays(_ targets: [Double], focus: Int, viewHeight: Double, stepScale: Double) -> [Double] {
    var delays = [Double](repeating: 0.0, count: targets.count)
    var step = CASCADE_STEP_S * stepScale
    var waited = 0.0
    for i in targets.indices {
        let y = targets[i]
        if y < 0 || y > viewHeight { continue }
        delays[i] = waited
        waited += step
        if i >= focus { step /= CASCADE_SHRINK }
    }
    return delays
}

// MARK: - How each line looks

public enum LineStatus: String, Sendable {
    case upcoming = "Upcoming"
    case active = "Active"
    case passed = "Passed"
}

public let UPCOMING_OPACITY = 0.55
public let PASSED_SHOWN_OPACITY = 0.45
public let MAX_BLUR = 3.0

/// Opacity and blur settle toward their targets with this time constant.
public let FADE_TIME_S = 0.12
public let OPACITY_SNAP = 0.002
public let BLUR_SNAP = 0.01

public func opacityTarget(_ status: LineStatus, showPassed: Bool) -> Double {
    switch status {
    case .active: 1.0
    case .upcoming: UPCOMING_OPACITY
    case .passed: showPassed ? PASSED_SHOWN_OPACITY : 0.0
    }
}

/// Sharp for the lines being sung, softer the further a line is from the focus, but gently: the
/// next lines stay readable at a glance.
public func blurTarget(_ status: LineStatus, distance: Int) -> Double {
    status == .active ? 0.0 : min(MAX_BLUR, 0.4 + 0.6 * Double(distance))
}

/// One frame of settling toward a target, the same at any frame rate.
public func settle(_ current: Double, target: Double, dt: Double, snap: Double) -> Double {
    let next = current + (target - current) * (1 - exp(-dt / FADE_TIME_S))
    return abs(target - next) <= snap ? target : next
}

/// The blur as drawn: in quarter steps, and none below a tenth of a pixel.
public func shownBlur(_ blur: Double) -> Double {
    let stepped = Double(roundToInt(blur * 4)) / 4.0
    return stepped < 0.1 ? 0.0 : stepped
}

// MARK: - Brightness

/// How bright a line's sung and unsung words are.
public struct Brightness: Equatable, Sendable {
    public var bright: Double
    public var dark: Double

    public init(_ bright: Double, _ dark: Double) {
        self.bright = bright
        self.dark = dark
    }
}

/// Touching a line lights it right up.
public let TouchedBrightness = Brightness(1.0, 0.85)

/// Follows the line's size: `grown` is 0 at the other lines' size and 1 at full size (the scale
/// spring's own value), so a line dims as it shrinks. At full size sung words are at 100% and the
/// rest at 40%; other lines are 30% all through. Rounded to 0.02 so tiny changes do not redraw.
public func brightness(_ grown: Double) -> Brightness {
    let e = grown.clamped(0.0, 1.0)
    return Brightness(round2(0.3 + 0.7 * e), round2(0.3 + 0.1 * e))
}

private func round2(_ value: Double) -> Double { Double(roundToInt(value * 50)) / 50.0 }

// MARK: - The word fill

/// The fill is an alpha mask slid across the word: bright, a soft edge, then dark, wider than the
/// word so it can slide right off either side. The soft edge is always half a line height wide
/// (times the Fill softness setting). `size` is the mask's width in word widths; the stops are
/// fractions of the mask's width.
public struct MaskShape: Equatable, Sendable {
    public var edge: Double
    public var size: Double
    public var brightStop: Double
    public var darkStop: Double

    public init(edge: Double, size: Double, brightStop: Double, darkStop: Double) {
        self.edge = edge
        self.size = size
        self.brightStop = brightStop
        self.darkStop = darkStop
    }
}

public func maskShape(wordWidth: Double, lineHeight: Double, softness: Double) -> MaskShape {
    let f = wordWidth > 0 ? (0.5 * lineHeight * softness) / wordWidth : 0.0
    let size = 2 + f
    let v = f / size
    let bright = (1 - v) / 2
    return MaskShape(edge: f, size: size, brightStop: bright, darkStop: bright + v)
}

/// Where the mask's left edge goes for this much of the word sung: at 0 the dark part covers the
/// word, at 1 the bright part does. Right-to-left words use the mask mirrored (dark on the left),
/// so it slides the other way.
public func maskLeft(_ progress: Double, wordLeft: Double, wordWidth: Double, shape: MaskShape, rtl: Bool) -> Double {
    let travel = (1 + shape.edge) * wordWidth
    let p = progress.clamped(0.0, 1.0)
    return rtl ? wordLeft - p * travel : wordLeft - (1 - p) * travel
}

/// How much of a word is sung: none before it starts, all after it ends, evenly in between.
public func wordProgress(_ t: Double, start: Double, end: Double) -> Double {
    if t <= start { return 0.0 }
    if t >= end { return 1.0 }
    return (t - start) / (end - start)
}

/// The fill sets off a little before the word, by as long as its soft edge takes to cross half
/// its own width. Without that, the middle of the edge is still half an edge short of the word as
/// it is sung, so the word lights late. With it, the middle of the edge is on the word's first
/// letter as the word starts and the word is mostly lit by the middle of its time. The mask's path
/// and speed stay as they are. Long, narrow words lead by no more than a quarter second. `edge`
/// is the soft edge in word widths.
public let FILL_LEAD_MAX_S = 0.25

public func fillLead(_ start: Double, end: Double, edge: Double) -> Double {
    let length = end - start
    if length <= 0.0 || edge <= 0.0 { return 0.0 }
    return min(FILL_LEAD_MAX_S, length * edge / (2 * (1 + edge)))
}

/// How much of a word the fill has covered by `t`.
public func fillProgress(_ t: Double, start: Double, end: Double, edge: Double) -> Double {
    wordProgress(t + fillLead(start, end: end, edge: edge), start: start, end: end)
}

// MARK: - Easing

/// A CSS-style cubic-bezier timing curve from (0,0) to (1,1).
public struct CubicBezier: Sendable {
    private let x1: Double
    private let y1: Double
    private let x2: Double
    private let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    private func curve(_ a: Double, _ b: Double, _ u: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }

    private func slope(_ a: Double, _ b: Double, _ u: Double) -> Double {
        let v = 1 - u
        return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
    }

    /// The curve's height where it is `x` of the way along.
    public func at(_ x: Double) -> Double {
        if x <= 0 { return 0.0 }
        if x >= 1 { return 1.0 }
        // Newton's method first, with halving as the fallback.
        var u = x
        for _ in 0..<8 {
            let error = curve(x1, x2, u) - x
            if abs(error) < 1e-7 { return curve(y1, y2, u) }
            let d = slope(x1, x2, u)
            if abs(d) < 1e-6 { continue }
            u -= error / d
        }
        var low = 0.0
        var high = 1.0
        u = x
        for _ in 0..<40 {
            let found = curve(x1, x2, u)
            if abs(found - x) < 1e-7 { return curve(y1, y2, u) }
            if found < x { low = u } else { high = u }
            u = (low + high) / 2
        }
        return curve(y1, y2, u)
    }
}

public let EaseOut = CubicBezier(0.0, 0.0, 0.58, 1.0)
private let SwellUp = CubicBezier(0.2, 0.4, 0.58, 1.0)
private let SwellDown = CubicBezier(0.3, 0.0, 0.58, 1.0)

/// Up to 1 at the middle and back down to 0: how a held letter swells.
public func upAndBack(_ t: Double) -> Double {
    if t <= 0 || t >= 1 { return 0.0 }
    if t < 0.5 { return SwellUp.at(t / 0.5) }
    return 1 - SwellDown.at((t - 0.5) / 0.5)
}

public func easeOutExpo(_ x: Double) -> Double { x >= 1 ? 1.0 : 1 - pow(2.0, -10 * x) }

private let BACK_C2 = 2.5949095

public func easeInOutBack(_ x: Double) -> Double {
    if x < 0.5 {
        return pow(2 * x, 2) * ((BACK_C2 + 1) * 2 * x - BACK_C2) / 2
    }
    return (pow(2 * x - 2, 2) * ((BACK_C2 + 1) * (x * 2 - 2) + BACK_C2) + 2) / 2
}

// MARK: - Word lift

public let LIFT_EM = 0.05
public let BACKGROUND_LIFT_EM = 0.10
/// How far sung words rise with fast singing blooming too.
public let FAST_LIFT_EM = 0.08
public let FAST_BACKGROUND_LIFT_EM = 0.16

/// How far a sung word rises in all, in em, before the Lift setting.
public func liftHeightEm(background: Bool, fast: Bool) -> Double {
    fast ? (background ? FAST_BACKGROUND_LIFT_EM : FAST_LIFT_EM) : (background ? BACKGROUND_LIFT_EM : LIFT_EM)
}

/// How far a sung word has risen, in em (up is negative): it eases up over at least a second from
/// its start and stays up. With fast singing blooming too, it rises further.
public func liftEm(_ t: Double, start: Double, end: Double, background: Bool, lift: Double, fast: Bool = false) -> Double {
    let over = max(1.0, end - start)
    let done = ((t - start) / over).clamped(0.0, 1.0)
    return -liftHeightEm(background: background, fast: fast) * lift * EaseOut.at(done)
}

// MARK: - Long-word emphasis

/// Words held at least this long bloom letter by letter.
public let EMPHASIS_MIN_S = 1.0
/// With fast singing blooming too, a shorter word blooms when it is held at least this long and
/// this many times as long as the line's middle word.
public let FAST_HELD_MIN_S = 0.6
public let FAST_HELD_OVER_MIDDLE = 2.5
/// A fast-held word blooms as strongly as one held this long.
public let FAST_BLOOM_MIN_S = 1.6

/// Which of a line's words are held long enough to bloom: those held `EMPHASIS_MIN_S` or more,
/// and with `fast`, those held `FAST_HELD_MIN_S` or more and `FAST_HELD_OVER_MIDDLE` times the
/// middle length of the line's words (the median of those above zero), so a held note stands
/// out from quick singing around it.
public func heldWords(_ words: [SyncWord], fast: Bool) -> [Bool] {
    heldDurations(words.map { $0.end - $0.start }, fast: fast)
}

/// The same, for the words' lengths in seconds.
public func heldDurations(_ durations: [Double], fast: Bool) -> [Bool] {
    let timed = durations.filter { $0 > 0 }.sorted()
    let middle = timed.isEmpty ? 0 : timed[timed.count / 2]
    return durations.map { d in
        d >= EMPHASIS_MIN_S || (fast && d >= FAST_HELD_MIN_S && d >= FAST_HELD_OVER_MIDDLE * middle)
    }
}

/// How strongly a held word blooms, and over how long.
public struct Emphasis: Equatable, Sendable {
    /// Scale, spread and rise strength, with the Emphasis setting in it.
    public var amount: Double
    /// Glow strength, with the Glow setting in it.
    public var glow: Double
    /// How far the glow spreads, in em.
    public var glowRadiusEm: Double
    /// How long each letter's swell runs.
    public var run: Double
    /// How much later each letter starts than the one before.
    public var stagger: Double

    public init(amount: Double, glow: Double, glowRadiusEm: Double, run: Double, stagger: Double) {
        self.amount = amount
        self.glow = glow
        self.glowRadiusEm = glowRadiusEm
        self.run = run
        self.stagger = stagger
    }
}

/// The bloom for a word held `duration` seconds with `glyphs` letters (not counting spaces), or
/// nil when it is not `held` (see `heldWords`; left out, held for `EMPHASIS_MIN_S` or more). The
/// line's last word blooms harder and longer. With `fast`, a held word swells and glows at least as
/// much as one held `FAST_BLOOM_MIN_S`, and a glow under three seconds comes up sooner (to the
/// power 1.5, not cubed); each still runs for its own length.
public func emphasisFor(_ duration: Double, glyphs: Int, last: Bool, emphasis: Double, glow: Double,
                        fast: Bool = false, held: Bool? = nil) -> Emphasis? {
    guard held ?? (duration >= EMPHASIS_MIN_S), glyphs > 0 else { return nil }
    let d = (fast ? max(duration, FAST_BLOOM_MIN_S) : duration) * 1000
    var a = d / 2000
    a = (a > 1 ? a.squareRoot() : a * a * a) * 0.6
    var g = d / 3000
    g = (g > 1 ? g.squareRoot() : (fast ? g * g.squareRoot() : g * g * g)) * 0.5
    var run = duration
    if last {
        a *= 1.6
        g *= 1.5
        run *= 1.2
    }
    let amount = min(1.2, a) * emphasis
    let shine = min(0.8, g) * glow
    return Emphasis(amount: amount, glow: shine, glowRadiusEm: min(0.3, shine * 0.3), run: run, stagger: run / 2.5 / Double(glyphs))
}

/// When letter `i` starts to swell.
public func glyphStart(_ wordStart: Double, emphasis: Emphasis, i: Int) -> Double { wordStart + emphasis.stagger * Double(i) }

/// One letter's pose: its scale, how far it moves across and up (em), and its glow's strength.
public struct GlyphPose: Equatable, Sendable {
    public var scale: Double
    public var dxEm: Double
    public var dyEm: Double
    public var glowAlpha: Double

    public init(scale: Double, dxEm: Double, dyEm: Double, glowAlpha: Double) {
        self.scale = scale
        self.dxEm = dxEm
        self.dyEm = dyEm
        self.glowAlpha = glowAlpha
    }
}

public let RestingGlyph = GlyphPose(scale: 1.0, dxEm: 0.0, dyEm: 0.0, glowAlpha: 0.0)

public func glyphPose(_ t: Double, wordStart: Double, emphasis: Emphasis, i: Int, glyphs: Int) -> GlyphPose {
    let start = glyphStart(wordStart, emphasis: emphasis, i: i)
    let e = upAndBack((t - start) / emphasis.run)
    if e == 0.0 { return RestingGlyph }
    return GlyphPose(
        scale: 1 + 0.1 * emphasis.amount * e,
        dxEm: -0.03 * emphasis.amount * (Double(glyphs) / 2.0 - Double(i)) * e,
        dyEm: -0.025 * emphasis.amount * e,
        glowAlpha: e * emphasis.glow
    )
}

/// A small bob on top: it starts 400 ms before the letter and runs 1.4 times as long. Backing
/// vocals bob twice as far. In em, up is negative.
public func bobEm(_ t: Double, wordStart: Double, emphasis: Emphasis, i: Int, lift: Double, background: Bool) -> Double {
    let start = glyphStart(wordStart, emphasis: emphasis, i: i) - 0.4
    let length = 1.4 * emphasis.run
    let x = (t - start) / length
    if x <= 0 || x >= 1 { return 0.0 }
    return -0.05 * sin(Double.pi * x) * lift * (background ? 2 : 1)
}

// MARK: - Interlude dots

/// The three dots at `p` seconds into a gap of `f` seconds: their shared scale and opacity, and
/// each one's light. `grown` skips the grow-in, for a seek into the gap.
public struct DotsPose: Equatable, Sendable {
    public var scale: Double
    public var opacity: Double
    public var lights: [Double]

    public init(scale: Double, opacity: Double, lights: [Double]) {
        self.scale = scale
        self.opacity = opacity
        self.lights = lights
    }
}

public func dotsPose(_ p: Double, f: Double, grown: Bool) -> DotsPose {
    let period = f / ceil(f / 1.5)
    let breathe = sin(1.5 * Double.pi - 2 * p / period) / 20 + 1
    var scale = breathe
    var opacity = 1.0
    if !grown && p < 1 {
        scale = breathe * easeOutExpo(p / 2)
        opacity = p < 0.5 ? 0.0 : (p - 0.5) / 0.5
    }
    let r = f - p
    if r < 0.75 { scale *= 1 - easeInOutBack((0.75 - r) / 0.75 / 2) }
    if r < 0.375 { opacity = r / 0.375 }
    let u = max(0.001, f - 0.75)
    let lights = (0..<3).map { k in ((p - Double(k) * u / 3) * 3 / u * 0.75).clamped(0.25, 1.0) }
    return DotsPose(scale: scale * 0.7, opacity: opacity.clamped(0.0, 1.0), lights: lights)
}

/// Held still, for reduced motion.
public let StillDots = DotsPose(scale: 0.7, opacity: 1.0, lights: [0.85, 0.85, 0.85])

/// How much of its full height an interlude takes: it opens over 0.8 s and closes over the last
/// 0.6 s.
public func interludeOpen(_ p: Double, f: Double, grown: Bool) -> Double {
    if p < 0 || p >= f { return 0.0 }
    let opening = grown ? 1.0 : easeOutExpo(p / 0.8)
    let closing = easeOutExpo((f - p) / 0.6)
    return min(opening, closing)
}

// MARK: - Curved lyrics

public let ARC_DEPTH = 60.0
public let ARC_LIFT = 40.0
public let ARC_YAW = 0.09
public let ARC_PERSPECTIVE = 1400.0

/// A line bent around the drum: how far it moves inward, how far it comes forward, its turn
/// (radians) and the scale that stands in for coming forward. `side` is 1 for lines set on the
/// left and -1 for the right.
public struct ArcPose: Equatable, Sendable {
    public var translationX: Double
    public var z: Double
    public var rotationY: Double
    public var scale: Double

    public init(translationX: Double, z: Double, rotationY: Double, scale: Double) {
        self.translationX = translationX
        self.z = z
        self.rotationY = rotationY
        self.scale = scale
    }
}

public func arcPose(
    centre: Double,
    viewHeight: Double,
    side: Int,
    depth: Double = ARC_DEPTH,
    lift: Double = ARC_LIFT,
    yaw: Double = ARC_YAW,
    perspective: Double = ARC_PERSPECTIVE
) -> ArcPose {
    let radius = 0.55 * viewHeight
    let r = radius > 0 ? ((centre - FOCUS_AT * viewHeight) / radius).clamped(-1.0, 1.0) : 0.0
    let a = 1 - r * r
    let z = lift * a
    return ArcPose(
        translationX: Double(side) * depth * (1 - a),
        z: z,
        rotationY: Double(side) * yaw * r * a,
        scale: perspective / (perspective - z)
    )
}
