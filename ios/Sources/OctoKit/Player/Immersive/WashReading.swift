import Foundation

// The choices the wash's settings offer: the brightness cap, saturation and drift speed in
// percent, the contrast as a factor, and the frame rates it can be held to.
public let BrightnessCapRange = 20...100
public let SaturationRange = 0...300
public let ContrastRange: ClosedRange<Float> = 0.5...2
public let FpsChoices = [30, 60, 90, 120]
public let SpeedRange = 5...100

/// The darkest and the brightest a background gets, as colors.
public struct WashRange: Equatable, Sendable {
    public var low: UInt32
    public var high: UInt32

    public init(_ low: UInt32, _ high: UInt32) {
        self.low = low
        self.high = high
    }

    /// Both dimmed (or brightened) by `gain`, as the wash's final pass does.
    public func scaled(_ gain: Float) -> WashRange { WashRange(scale(low, gain), scale(high, gain)) }

    /// A background of this one color, or of these few (a flat fill, the classic mesh).
    public static func of(_ colors: UInt32...) -> WashRange { of(colors) }

    public static func of(_ colors: [UInt32]) -> WashRange {
        guard var low = colors.first else { return WashRange(0xFF00_0000, 0xFF00_0000) }
        var high = low
        for color in colors {
            if relativeLuminance(color) < relativeLuminance(low) { low = color }
            if relativeLuminance(color) > relativeLuminance(high) { high = color }
        }
        return WashRange(low, high)
    }
}

/// The range of a picture as a background drawn blurred from it shows: the picture averaged in
/// `cells` x `cells` blocks, and the darkest and brightest block. A patch of color much smaller
/// than a block is blurred away; one as big survives.
public func washRange(_ pixels: [UInt32], _ width: Int, cells: Int = 32) -> WashRange {
    guard width > 0, !pixels.isEmpty else { return WashRange(0xFF00_0000, 0xFF00_0000) }
    let height = pixels.count / width
    let bw = max(1, width / cells)
    let bh = max(1, height / cells)
    var low: UInt32 = 0xFF00_0000
    var high: UInt32 = 0xFF00_0000
    var lowL = Double.greatestFiniteMagnitude
    var highL = -1.0
    for cy in 0..<(height / bh) {
        for cx in 0..<(width / bw) {
            var r = 0
            var g = 0
            var b = 0
            for y in (cy * bh)..<((cy + 1) * bh) {
                for x in (cx * bw)..<((cx + 1) * bw) {
                    let p = pixels[y * width + x]
                    r += Int((p >> 16) & 0xFF)
                    g += Int((p >> 8) & 0xFF)
                    b += Int(p & 0xFF)
                }
            }
            let n = bw * bh
            let mean = packArgb(255, r / n, g / n, b / n)
            let l = relativeLuminance(mean)
            if l < lowL {
                lowL = l
                low = mean
            }
            if l > highL {
                highL = l
                high = mean
            }
        }
    }
    return WashRange(low, high)
}

private func scale(_ argb: UInt32, _ gain: Float) -> UInt32 {
    func channel(_ shift: UInt32) -> Int { Int((Float((argb >> shift) & 0xFF) * gain).rounded()).clamped(0, 255) }
    return packArgb(255, channel(16), channel(8), channel(0))
}

/// The dark words used over a light background.
public let DarkInkArgb: UInt32 = 0xFF14_1416
private let WhiteArgb: UInt32 = 0xFFFF_FFFF

/// The contrast the player's words keep against what is drawn under them, the usual minimum for
/// reading.
public let PlayerContrast = 4.5

/// What words over a background need: whether they are dark, and how much of the background
/// shows over the color under it (`show`, 1 for all of it) so that they read.
public struct WashInk: Equatable, Sendable {
    public var dark: Bool
    public var show: Float

    public init(dark: Bool, show: Float) {
        self.dark = dark
        self.show = show
    }
}

/// The words' color for a background spanning `range`, drawn over `under`. Dark words when they
/// read on its darkest part as it is and white ones would need it dimmed; otherwise white words,
/// with the background dimmed just enough that they read on its brightest part. A background
/// both light and dark in places gets white words and a little dimming, never dark words over
/// its dark half.
public func inkOver(_ range: WashRange, _ under: UInt32, contrast: Double = PlayerContrast) -> WashInk {
    let white = readableAlpha(range.high, under, WhiteArgb, contrast, 1)
    let darkReads = contrastRatio(DarkInkArgb, range.low) >= contrast
    return darkReads && white < 1 ? WashInk(dark: true, show: 1) : WashInk(dark: false, show: white)
}

/// The brightest the wash gets over a prepared cover, as a color: the pixel at the 98th
/// percentile of brightness (every `step`th pixel is looked at), dimmed as the final pass leaves
/// it.
public func washPeak(_ pixels: [UInt32], step: Int = 7) -> UInt32 {
    if pixels.isEmpty { return 0xFF00_0000 }
    let picked = stride(from: 0, to: pixels.count, by: max(step, 1)).map { pixels[$0] }
    let light = picked.map(relativeLuminance)
    let line = light.sorted()[Int((Float(picked.count - 1) * 0.98).rounded())]
    let bright = picked[light.firstIndex(of: line) ?? 0]
    let gain = min(FinalGain, 1)
    func channel(_ shift: UInt32) -> Int { Int((Float((bright >> shift) & 0xFF) * gain).rounded()).clamped(0, 255) }
    return packArgb(255, channel(16), channel(8), channel(0))
}

/// One color laid over another at some opacity, channel by channel, as the screen blends them.
public func overlay(_ top: UInt32, _ alpha: Float, _ under: UInt32) -> UInt32 {
    func channel(_ shift: UInt32) -> Int {
        let t = Float((top >> shift) & 0xFF)
        let u = Float((under >> shift) & 0xFF)
        return Int((u + (t - u) * alpha).rounded()).clamped(0, 255)
    }
    return packArgb(255, channel(16), channel(8), channel(0))
}

/// How much of a wash can show over a page's color (`base`) while words in `ink` keep at least
/// `contrast` against the wash's brightest part (`peak`): the most, up to `most`, that still
/// reads.
public func readableAlpha(_ peak: UInt32, _ base: UInt32, _ ink: UInt32, _ contrast: Double, _ most: Float) -> Float {
    func reads(_ alpha: Float) -> Bool { contrastRatio(ink, overlay(peak, alpha, base)) >= contrast }
    if reads(most) { return most }
    if !reads(0) { return 0 }
    var low: Float = 0
    var high = most
    for _ in 0..<20 {
        let mid = (low + high) / 2
        if reads(mid) { low = mid } else { high = mid }
    }
    return low
}
