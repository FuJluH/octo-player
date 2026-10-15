import Foundation

/// How a cover is prepared before the background draws it: contrast, then saturation, then a
/// cap on brightness so white covers never glare behind the words. Contrast and saturation are
/// factors (1 leaves the color as it is); the cap is a fraction of full brightness.
public struct WashTuning: Equatable, Hashable, Sendable {
    public var contrast: Float
    public var saturation: Float
    public var brightnessCap: Float

    public init(contrast: Float = 1.3, saturation: Float = 1.8, brightnessCap: Float = 0.5) {
        self.contrast = contrast
        self.saturation = saturation
        self.brightnessCap = brightnessCap
    }
}

// How much red, green and blue count toward gray.
private let lumaR: Float = 0.299
private let lumaG: Float = 0.587
private let lumaB: Float = 0.114

/// Contrast and saturation together, as a 4 x 5 color matrix: channels in 0 to 255, each row
/// one output channel. Contrast is (c - 0.5) x contrast + 0.5; saturation then moves each color
/// away from its gray by the saturation factor.
public func washColorMatrix(_ tuning: WashTuning) -> [Float] {
    let c = tuning.contrast
    let s = tuning.saturation
    // The contrast's shift, carried through saturation unchanged, since each saturation row adds
    // up to 1.
    let shift = 127.5 * (1 - c)
    let luma = [lumaR, lumaG, lumaB]
    func row(_ own: Int) -> [Float] {
        (0..<5).map { j in
            switch j {
            case 0...2: c * ((1 - s) * luma[j] + (j == own ? s : 0))
            case 4: shift
            default: 0
            }
        }
    }
    return row(0) + row(1) + row(2) + [0, 0, 0, 1, 0]
}

/// One color through a color matrix: worked in floats, then rounded and held to 0 to 255.
public func applyColorMatrix(_ argb: UInt32, _ matrix: [Float]) -> UInt32 {
    let a = Float((argb >> 24) & 0xFF)
    let r = Float((argb >> 16) & 0xFF)
    let g = Float((argb >> 8) & 0xFF)
    let b = Float(argb & 0xFF)
    func channel(_ row: Int) -> Int {
        let o = row * 5
        let v = matrix[o] * r + matrix[o + 1] * g + matrix[o + 2] * b + matrix[o + 3] * a + matrix[o + 4]
        return Int(v.rounded()).clamped(0, 255)
    }
    return packArgb(channel(3), channel(0), channel(1), channel(2))
}

/// The brightness cap on one color: when the mean of its channels is over the cap, it is
/// darkened by (mean - cap) / cap of itself.
public func capBrightness(_ argb: UInt32, _ cap: Float) -> UInt32 {
    let r = Float((argb >> 16) & 0xFF) / 255
    let g = Float((argb >> 8) & 0xFF) / 255
    let b = Float(argb & 0xFF) / 255
    let mean = (r + g + b) / 3
    if cap <= 0 || mean <= cap { return argb }
    let keep = (1 - (mean - cap) / cap).clamped(0, 1)
    return packArgb(Int((argb >> 24) & 0xFF), Int((r * keep * 255).rounded()), Int((g * keep * 255).rounded()), Int((b * keep * 255).rounded()))
}

/// The same cap over a whole picture's pixels, in place.
public func capBrightness(_ pixels: inout [UInt32], _ cap: Float) {
    for i in pixels.indices { pixels[i] = capBrightness(pixels[i], cap) }
}

/// One color through every step of the preparation.
public func prepareColor(_ argb: UInt32, _ tuning: WashTuning) -> UInt32 {
    capBrightness(applyColorMatrix(argb, washColorMatrix(tuning)), tuning.brightnessCap)
}

/// How bright a color looks, 0 for black to 1 for white, by the sRGB curve.
public func relativeLuminance(_ argb: UInt32) -> Double {
    func linear(_ channel: UInt32) -> Double {
        let c = Double(channel) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear((argb >> 16) & 0xFF) + 0.7152 * linear((argb >> 8) & 0xFF) + 0.0722 * linear(argb & 0xFF)
}

/// How far apart two colors are for reading, from 1 (the same) to 21.
public func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
    let la = relativeLuminance(a)
    let lb = relativeLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// Whether white words would struggle on this color: under 3:1 against white and brighter
/// than 0.3.
public func washIsLight(_ argb: UInt32) -> Bool { contrastRatio(argb, 0xFFFF_FFFF) < 3 && relativeLuminance(argb) > 0.3 }

func packArgb(_ a: Int, _ r: Int, _ g: Int, _ b: Int) -> UInt32 {
    UInt32(a.clamped(0, 255)) << 24 | UInt32(r.clamped(0, 255)) << 16 | UInt32(g.clamped(0, 255)) << 8 | UInt32(b.clamped(0, 255))
}
