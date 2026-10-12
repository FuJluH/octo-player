import Foundation

/// The size, in pixels, of the square the background is drawn at before it is blurred and
/// stretched over the screen.
public let WashSize = 512

/// One copy of the cover in the layered composite. Its offset from the center is x0 + xAmp
/// sin(xSpeed t + xPhase) across and y0 + yAmp cos(ySpeed t + yPhase) down; its turn is spin R +
/// tilt + wobble sin(wobbleSpeed t + wobblePhase). Copies that breathe are magnified by the
/// breathing scale too.
public struct WashCopy: Equatable, Sendable {
    public var name: String
    public var opacity: Float
    public var zoom: Float
    public var breathes: Bool
    public var x0: Float = 0
    public var xAmp: Float = 0
    public var xSpeed: Float = 0
    public var xPhase: Float = 0
    public var y0: Float = 0
    public var yAmp: Float = 0
    public var ySpeed: Float = 0
    public var yPhase: Float = 0
    public var spin: Float = 0
    public var tilt: Float = 0
    public var wobble: Float = 0
    public var wobbleSpeed: Float = 0
    public var wobblePhase: Float = 0

    public func offsetX(_ t: Float) -> Float { x0 + xAmp * sin(xSpeed * t + xPhase) }
    public func offsetY(_ t: Float) -> Float { y0 + yAmp * cos(ySpeed * t + yPhase) }
    public func angle(_ t: Float, _ r: Float) -> Float { spin * r + tilt + wobble * sin(wobbleSpeed * t + wobblePhase) }
    public func magnification(_ b: Float) -> Float { breathes ? zoom * b : zoom }
}

/// The parallax copies step round by the golden angle, so the three never line up.
public let GoldenAngle: Float = 2.39996

private let FloatSpeed: Float = 0.5
private let Wobble: Float = 0.02

/// The eight copies, drawn in this order, each over the result so far at its opacity, starting
/// from black.
public let WashCopies: [WashCopy] = [
    WashCopy(name: "Base", opacity: 1.0, zoom: 3.0, breathes: false),
    WashCopy(name: "Parallax 1", opacity: 0.60, zoom: 3.0, breathes: true,
             x0: 0.10, xAmp: 0.08, xSpeed: 0.25, y0: 0.10, yAmp: 0.06, ySpeed: 0.25, spin: 0.5),
    WashCopy(name: "Parallax 2", opacity: 0.30, zoom: 3.8, breathes: true,
             x0: 0.25, xAmp: 0.08, xSpeed: 0.25, xPhase: GoldenAngle, y0: 0.25, yAmp: 0.06, ySpeed: 0.25, yPhase: GoldenAngle,
             spin: 0.5, tilt: 0.15),
    WashCopy(name: "Parallax 3", opacity: 0.20, zoom: 4.6, breathes: true,
             x0: 0.40, xAmp: 0.08, xSpeed: 0.25, xPhase: 2 * GoldenAngle, y0: 0.40, yAmp: 0.06, ySpeed: 0.25, yPhase: 2 * GoldenAngle,
             spin: 0.5, tilt: 0.30),
    WashCopy(name: "Primary", opacity: 0.85, zoom: 2.4, breathes: true,
             xAmp: 0.05, xSpeed: FloatSpeed, yAmp: 0.04, ySpeed: FloatSpeed, spin: 1, wobble: Wobble, wobbleSpeed: FloatSpeed),
    WashCopy(name: "Secondary", opacity: 0.70, zoom: 2.0, breathes: true,
             x0: 0.30, xAmp: 0.06, xSpeed: FloatSpeed, xPhase: 1, y0: 0.30, yAmp: 0.05, ySpeed: FloatSpeed, yPhase: 1,
             spin: -0.5, wobble: Wobble, wobbleSpeed: 0.7, wobblePhase: 1),
    WashCopy(name: "Tertiary", opacity: 0.55, zoom: 1.8, breathes: true,
             x0: -0.20, xAmp: 0.07, xSpeed: 0.4, y0: 0.40, yAmp: 0.05, ySpeed: 0.3,
             spin: 0.8, wobble: Wobble, wobbleSpeed: 0.8, wobblePhase: 2),
    WashCopy(name: "Fourth", opacity: 0.40, zoom: 2.2, breathes: true,
             x0: 0.40, xAmp: 0.08, xSpeed: 0.35, xPhase: 3, y0: -0.10, yAmp: 0.06, ySpeed: 0.25, yPhase: 3,
             spin: 1.5, wobble: Wobble, wobbleSpeed: 0.6, wobblePhase: 3),
]

/// Where one copy samples the cover, per frame: a 2 x 2 matrix taking a point (relative to the
/// center, after the offset) into the cover's space, which holds both the zoom and the turn, and
/// the offset itself.
public func copyPlacement(_ copy: WashCopy, _ t: Float, _ r: Float, _ b: Float, _ out: inout [Float], _ at: Int) {
    let scale = 1 / copy.magnification(b)
    let a = copy.angle(t, r)
    let c = cos(a) * scale
    let s = sin(a) * scale
    out[at] = c
    out[at + 1] = -s
    out[at + 2] = s
    out[at + 3] = c
    out[at + 4] = copy.offsetX(t)
    out[at + 5] = copy.offsetY(t)
}

/// Where a point of the square samples one copy's cover, both 0 to 1 across the square: the
/// offset first, then the zoom and turn, all about the center.
public func copySample(_ copy: WashCopy, _ t: Float, _ r: Float, _ b: Float, _ u: Float, _ v: Float) -> (Float, Float) {
    var m = [Float](repeating: 0, count: 6)
    copyPlacement(copy, t, r, b, &m, 0)
    let px = u - 0.5 + m[4]
    let py = v - 0.5 + m[5]
    return (m[0] * px + m[1] * py + 0.5, m[2] * px + m[3] * py + 0.5)
}

/// The warp: three upright dividers at a quarter, a half and three quarters across swing
/// sideways on sine waves that change down the picture, and the four bands between them stretch
/// or squeeze to fill.
public let WarpRest: [Float] = [0.25, 0.5, 0.75]
public let WarpAmplitude: Float = 60.0 / 512.0 * 1.5
public let WarpScales: [Float] = [0.35 * 0.05, 0.35 * 0.03, 0.35 * 0.06]
public let WarpMinBand: Float = 0.01
/// Each divider swings on the shared warp phase a third of a turn apart from the next.
public let WarpPhaseSteps: [Float] = [0, Float(2 * Double.pi / 3), Float(4 * Double.pi / 3)]

/// Where the dividers are on one row (y in pixels down the 512 square), kept in order with every
/// band at least 0.01 wide.
public func warpDividers(_ yPx: Float, _ r: Float, _ phase: Float) -> [Float] {
    var out = (0..<3).map { k in WarpRest[k] + WarpAmplitude * sin(phase + WarpPhaseSteps[k] + yPx * 0.1 * r * WarpScales[k] * 10) }
    out[0] = out[0].clamped(WarpMinBand, 1 - 3 * WarpMinBand)
    out[1] = max(out[1], out[0] + WarpMinBand)
    out[2] = min(max(out[2], out[1] + WarpMinBand), 1 - WarpMinBand)
    out[1] = min(out[1], out[2] - WarpMinBand)
    out[0] = min(out[0], out[1] - WarpMinBand)
    return out
}

/// The piecewise-linear remap: a point in the band between two moved dividers samples the
/// matching quarter of the picture.
public func warpX(_ x: Float, _ dividers: [Float]) -> Float {
    let left: Float
    let right: Float
    let band: Float
    if x < dividers[0] {
        (left, right, band) = (0, dividers[0], 0)
    } else if x < dividers[1] {
        (left, right, band) = (dividers[0], dividers[1], 1)
    } else if x < dividers[2] {
        (left, right, band) = (dividers[1], dividers[2], 2)
    } else {
        (left, right, band) = (dividers[2], 1, 3)
    }
    return (band + (x - left) / (right - left)) * 0.25
}
