import Foundation

/// One color found in a picture, with how many of its pixels it stands for.
public struct Swatch: Sendable, Equatable {
    /// `0xRRGGBB`.
    public let rgb: UInt32
    public let population: Int
    public let hsl: (hue: Float, saturation: Float, lightness: Float)

    public init(rgb: UInt32, population: Int) {
        self.rgb = rgb & 0xFFFFFF
        self.population = population
        hsl = paletteHsl(rgb)
    }

    public static func == (a: Swatch, b: Swatch) -> Bool { a.rgb == b.rgb && a.population == b.population }
}

/// What a swatch is picked for: ranges and targets of saturation and lightness, and how much
/// each counts against the swatch's share of the picture.
public struct PaletteTarget: Sendable, Equatable {
    var saturation: (min: Float, target: Float, max: Float) = (0, 0.5, 1)
    var lightness: (min: Float, target: Float, max: Float) = (0, 0.5, 1)
    var weights: (saturation: Float, lightness: Float, population: Float) = (0.24, 0.52, 0.24)

    public static func == (a: PaletteTarget, b: PaletteTarget) -> Bool {
        a.saturation == b.saturation && a.lightness == b.lightness && a.weights == b.weights
    }

    private static func make(light: Int, vibrant: Bool) -> PaletteTarget {
        var t = PaletteTarget()
        switch light {
        case 1: t.lightness = (0.55, 0.74, 1)
        case 0: t.lightness = (0.3, 0.5, 0.7)
        default: t.lightness = (0, 0.26, 0.45)
        }
        t.saturation = vibrant ? (0.35, 1, 1) : (0, 0.3, 0.4)
        return t
    }

    public static let lightVibrant = make(light: 1, vibrant: true)
    public static let vibrant = make(light: 0, vibrant: true)
    public static let darkVibrant = make(light: -1, vibrant: true)
    public static let lightMuted = make(light: 1, vibrant: false)
    public static let muted = make(light: 0, vibrant: false)
    public static let darkMuted = make(light: -1, vibrant: false)

    /// The targets in the order they are picked; each swatch is picked at most once.
    public static let all = [lightVibrant, vibrant, darkVibrant, lightMuted, muted, darkMuted]
}

/// The colors picked out of a picture.
public struct ArtworkSwatches: Sendable {
    public let swatches: [Swatch]
    public let dominant: Swatch?
    public let lightVibrant: Swatch?
    public let vibrant: Swatch?
    public let darkVibrant: Swatch?
    public let lightMuted: Swatch?
    public let muted: Swatch?
    public let darkMuted: Swatch?

    /// Picks the colors out of `pixels` (`0xAARRGGBB`, alpha ignored), with up to
    /// `maximumColors` colors found first.
    public init(pixels: [UInt32], maximumColors: Int = 16) {
        let found = quantize(pixels, maxColors: maximumColors)
        swatches = found
        var dominant: Swatch?
        for swatch in found where swatch.population > (dominant?.population ?? Int.min) { dominant = swatch }
        self.dominant = dominant
        var used = Set<UInt32>()
        var picked: [Swatch?] = []
        for target in PaletteTarget.all {
            let weights = normalized(target.weights)
            let maxPopulation = Float(dominant?.population ?? 1)
            var best: Swatch?
            var bestScore: Float = 0
            for swatch in found {
                let (_, s, l) = swatch.hsl
                guard s >= target.saturation.min, s <= target.saturation.max,
                      l >= target.lightness.min, l <= target.lightness.max,
                      !used.contains(swatch.rgb) else { continue }
                var score: Float = 0
                if weights.saturation > 0 { score += weights.saturation * (1 - abs(s - target.saturation.target)) }
                if weights.lightness > 0 { score += weights.lightness * (1 - abs(l - target.lightness.target)) }
                if weights.population > 0 { score += weights.population * (Float(swatch.population) / maxPopulation) }
                if best == nil || score > bestScore {
                    best = swatch
                    bestScore = score
                }
            }
            if let best { used.insert(best.rgb) }
            picked.append(best)
        }
        lightVibrant = picked[0]
        vibrant = picked[1]
        darkVibrant = picked[2]
        lightMuted = picked[3]
        muted = picked[4]
        darkMuted = picked[5]
    }
}

private func normalized(_ w: (saturation: Float, lightness: Float, population: Float)) -> (saturation: Float, lightness: Float, population: Float) {
    let sum = max(0, w.saturation) + max(0, w.lightness) + max(0, w.population)
    guard sum > 0 else { return w }
    return (w.saturation > 0 ? w.saturation / sum : w.saturation,
            w.lightness > 0 ? w.lightness / sum : w.lightness,
            w.population > 0 ? w.population / sum : w.population)
}

/// The colors a song's artwork lends the player and the glow: four for the moving field, a
/// base under everything, and the artwork's main color as it came.
public struct ArtworkColors: Sendable, Equatable {
    /// `0xRRGGBB` each.
    public let mesh: [UInt32]
    public let base: UInt32
    public let dominant: UInt32?

    public init(mesh: [UInt32], base: UInt32, dominant: UInt32? = nil) {
        self.mesh = mesh
        self.base = base
        self.dominant = dominant
    }

    /// Before artwork loads, or for music without any: quiet shades of the accent.
    public static let quiet = ArtworkColors(mesh: [0x2A3438, 0x1A1A1B, 0x3A4A50, 0x0A0B0F], base: 0x0C0C0D)

    /// The colors for a picture's pixels; nil when it has neither a main nor a dark muted color.
    public static func from(pixels: [UInt32]) -> ArtworkColors? {
        from(ArtworkSwatches(pixels: pixels, maximumColors: 16))
    }

    public static func from(_ palette: ArtworkSwatches) -> ArtworkColors? {
        guard let main = palette.dominant?.rgb ?? palette.darkMuted?.rgb else { return nil }
        let bright = palette.vibrant?.rgb ?? palette.lightVibrant?.rgb ?? shiftLightness(main, 0.16)
        let deep = palette.darkVibrant?.rgb ?? palette.darkMuted?.rgb ?? shiftLightness(main, -0.18)
        let base = blendToward(palette.darkMuted?.rgb ?? main, 0x000000, 0.7)
        return ArtworkColors(mesh: [main, bright, deep, 0x0A0B0F], base: base, dominant: palette.dominant?.rgb)
    }
}

/// The side of the square picture colors are read from, before it is cut down to about
/// 112 by 112 pixels.
public let artworkSampleSize = 128
/// The most pixels a picture is read at.
public let artworkSampleArea = 112 * 112

/// The size a picture of `width` by `height` is read at.
public func paletteSampleSize(width: Int, height: Int) -> (width: Int, height: Int) {
    let area = width * height
    guard area > artworkSampleArea else { return (width, height) }
    let ratio = (Double(artworkSampleArea) / Double(area)).squareRoot()
    return (Int((Double(width) * ratio).rounded(.up)), Int((Double(height) * ratio).rounded(.up)))
}

/// The same hue, lighter or darker.
public func shiftLightness(_ rgb: UInt32, _ amount: Float) -> UInt32 {
    let hsl = paletteHsl(rgb)
    return paletteColor(hue: hsl.hue, saturation: hsl.saturation, lightness: min(1, max(0, hsl.lightness + amount)))
}

/// Two colors blended, `ratio` of the way to the second, each channel cut to a whole byte.
public func blendToward(_ a: UInt32, _ b: UInt32, _ ratio: Float) -> UInt32 {
    let inverse = 1 - ratio
    func channel(_ shift: UInt32) -> UInt32 {
        UInt32(Float((a >> shift) & 0xFF) * inverse + Float((b >> shift) & 0xFF) * ratio)
    }
    return channel(16) << 16 | channel(8) << 8 | channel(0)
}

/// Hue (degrees), saturation and lightness, as the picture reader works them out.
public func paletteHsl(_ rgb: UInt32) -> (hue: Float, saturation: Float, lightness: Float) {
    let r = Float((rgb >> 16) & 0xFF) / 255
    let g = Float((rgb >> 8) & 0xFF) / 255
    let b = Float(rgb & 0xFF) / 255
    let high = max(r, max(g, b))
    let low = min(r, min(g, b))
    let spread = high - low
    let l = (high + low) / 2
    var h: Float = 0
    var s: Float = 0
    if high != low {
        if high == r {
            h = ((g - b) / spread).truncatingRemainder(dividingBy: 6)
        } else if high == g {
            h = (b - r) / spread + 2
        } else {
            h = (r - g) / spread + 4
        }
        s = spread / (1 - abs(2 * l - 1))
    }
    h = (h * 60).truncatingRemainder(dividingBy: 360)
    if h < 0 { h += 360 }
    return (min(360, max(0, h)), min(1, max(0, s)), min(1, max(0, l)))
}

/// A color from hue (degrees), saturation and lightness, as the picture reader makes it.
public func paletteColor(hue: Float, saturation: Float, lightness: Float) -> UInt32 {
    let c = (1 - abs(2 * lightness - 1)) * saturation
    let m = lightness - 0.5 * c
    let x = c * (1 - abs((hue / 60).truncatingRemainder(dividingBy: 2) - 1))
    func byte(_ v: Float) -> UInt32 { UInt32(min(255, max(0, (255 * v).rounded(.toNearestOrAwayFromZero)))) }
    let rgb: (Float, Float, Float)
    switch Int(hue) / 60 {
    case 0: rgb = (c + m, x + m, m)
    case 1: rgb = (x + m, c + m, m)
    case 2: rgb = (m, c + m, x + m)
    case 3: rgb = (m, x + m, c + m)
    case 4: rgb = (x + m, m, c + m)
    case 5, 6: rgb = (c + m, m, x + m)
    default: rgb = (0, 0, 0)
    }
    return byte(rgb.0) << 16 | byte(rgb.1) << 8 | byte(rgb.2)
}

// MARK: Finding the colors

private let wordWidth: UInt32 = 5
private let wordMask: UInt32 = (1 << wordWidth) - 1

private func quantizedRed(_ c: UInt32) -> UInt32 { (c >> (wordWidth * 2)) & wordMask }
private func quantizedGreen(_ c: UInt32) -> UInt32 { (c >> wordWidth) & wordMask }
private func quantizedBlue(_ c: UInt32) -> UInt32 { c & wordMask }

private func modifyWordWidth(_ value: UInt32, _ current: UInt32, _ target: UInt32) -> UInt32 {
    let v = target > current ? value << (target - current) : value >> (current - target)
    return v & ((1 << target) - 1)
}

private func quantize888(_ argb: UInt32) -> UInt32 {
    let r = modifyWordWidth((argb >> 16) & 0xFF, 8, wordWidth)
    let g = modifyWordWidth((argb >> 8) & 0xFF, 8, wordWidth)
    let b = modifyWordWidth(argb & 0xFF, 8, wordWidth)
    return r << (wordWidth * 2) | g << wordWidth | b
}

private func approximate888(_ r: UInt32, _ g: UInt32, _ b: UInt32) -> UInt32 {
    modifyWordWidth(r, wordWidth, 8) << 16 | modifyWordWidth(g, wordWidth, 8) << 8 | modifyWordWidth(b, wordWidth, 8)
}

private func approximate888(_ c: UInt32) -> UInt32 { approximate888(quantizedRed(c), quantizedGreen(c), quantizedBlue(c)) }

/// Near black, near white, and the skin tones along the red line are never picked.
private func ignored(_ hsl: (hue: Float, saturation: Float, lightness: Float)) -> Bool {
    let isBlack = hsl.lightness <= 0.05
    let isWhite = hsl.lightness >= 0.95
    let nearRedLine = hsl.hue >= 10 && hsl.hue <= 37 && hsl.saturation <= 0.82
    return isBlack || isWhite || nearRedLine
}

/// A box of colors in the 5-bit cube, over a run of the sorted color list.
private final class ColorBox {
    var lower: Int
    var upper: Int
    var population = 0
    var minR: UInt32 = 0, maxR: UInt32 = 0, minG: UInt32 = 0, maxG: UInt32 = 0, minB: UInt32 = 0, maxB: UInt32 = 0

    init(_ lower: Int, _ upper: Int, _ colors: [UInt32], _ hist: [Int]) {
        self.lower = lower
        self.upper = upper
        fit(colors, hist)
    }

    var volume: Int { Int(maxR - minR + 1) * Int(maxG - minG + 1) * Int(maxB - minB + 1) }
    var canSplit: Bool { upper - lower + 1 > 1 }

    func fit(_ colors: [UInt32], _ hist: [Int]) {
        var lowR = UInt32.max, lowG = UInt32.max, lowB = UInt32.max
        var highR: UInt32 = 0, highG: UInt32 = 0, highB: UInt32 = 0
        var count = 0
        for i in lower...upper {
            let c = colors[i]
            count += hist[Int(c)]
            let r = quantizedRed(c), g = quantizedGreen(c), b = quantizedBlue(c)
            highR = max(highR, r); lowR = min(lowR, r)
            highG = max(highG, g); lowG = min(lowG, g)
            highB = max(highB, b); lowB = min(lowB, b)
        }
        minR = lowR; maxR = highR; minG = lowG; maxG = highG; minB = lowB; maxB = highB
        population = count
    }

    /// Splits at the population's middle along the longest side; returns the upper half.
    func split(_ colors: inout [UInt32], _ hist: [Int]) -> ColorBox {
        let point = splitPoint(&colors, hist)
        let upperBox = ColorBox(point + 1, upper, colors, hist)
        upper = point
        fit(colors, hist)
        return upperBox
    }

    private func splitPoint(_ colors: inout [UInt32], _ hist: [Int]) -> Int {
        let r = maxR - minR, g = maxG - minG, b = maxB - minB
        let dimension = r >= g && r >= b ? 0 : (g >= r && g >= b ? 1 : 2)
        reorder(&colors, dimension)
        colors[lower...upper].sort()
        reorder(&colors, dimension)
        let middle = population / 2
        var count = 0
        for i in lower...upper {
            count += hist[Int(colors[i])]
            if count >= middle { return min(upper - 1, i) }
        }
        return lower
    }

    /// Moves the chosen channel to the top bits so sorting orders by it, and back again.
    private func reorder(_ a: inout [UInt32], _ dimension: Int) {
        guard dimension != 0 else { return }
        for i in lower...upper {
            let c = a[i]
            if dimension == 1 {
                a[i] = quantizedGreen(c) << (wordWidth * 2) | quantizedRed(c) << wordWidth | quantizedBlue(c)
            } else {
                a[i] = quantizedBlue(c) << (wordWidth * 2) | quantizedGreen(c) << wordWidth | quantizedRed(c)
            }
        }
    }

    func average(_ colors: [UInt32], _ hist: [Int]) -> Swatch {
        var r = 0, g = 0, b = 0, total = 0
        for i in lower...upper {
            let c = colors[i]
            let n = hist[Int(c)]
            total += n
            r += n * Int(quantizedRed(c))
            g += n * Int(quantizedGreen(c))
            b += n * Int(quantizedBlue(c))
        }
        func mean(_ sum: Int) -> UInt32 { UInt32((Float(sum) / Float(total)).rounded(.toNearestOrAwayFromZero)) }
        return Swatch(rgb: approximate888(mean(r), mean(g), mean(b)), population: total)
    }
}

/// A heap that keeps its boxes in the same order as the reference queue, larger volume first,
/// so ties are broken the same way.
private struct BoxQueue {
    var items: [ColorBox] = []

    private func before(_ a: ColorBox, _ b: ColorBox) -> Int { b.volume - a.volume }

    mutating func offer(_ x: ColorBox) {
        var k = items.count
        items.append(x)
        while k > 0 {
            let parent = (k - 1) >> 1
            let e = items[parent]
            if before(x, e) >= 0 { break }
            items[k] = e
            k = parent
        }
        items[k] = x
    }

    mutating func poll() -> ColorBox? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty { siftDown(0, last) }
        return first
    }

    private mutating func siftDown(_ start: Int, _ x: ColorBox) {
        var k = start
        let size = items.count
        let half = size >> 1
        while k < half {
            var child = (k << 1) + 1
            var c = items[child]
            let right = child + 1
            if right < size && before(c, items[right]) > 0 {
                child = right
                c = items[child]
            }
            if before(x, c) <= 0 { break }
            items[k] = c
            k = child
        }
        items[k] = x
    }
}

private func quantize(_ pixels: [UInt32], maxColors: Int) -> [Swatch] {
    var hist = [Int](repeating: 0, count: 1 << (wordWidth * 3))
    for p in pixels { hist[Int(quantize888(p))] += 1 }
    var colors: [UInt32] = []
    for color in 0..<hist.count where hist[color] > 0 {
        if ignored(paletteHsl(approximate888(UInt32(color)))) {
            hist[color] = 0
        } else {
            colors.append(UInt32(color))
        }
    }
    if colors.count <= maxColors {
        return colors.map { Swatch(rgb: approximate888($0), population: hist[Int($0)]) }
    }
    var queue = BoxQueue()
    queue.offer(ColorBox(0, colors.count - 1, colors, hist))
    while queue.items.count < maxColors {
        guard let box = queue.poll(), box.canSplit else { break }
        queue.offer(box.split(&colors, hist))
        queue.offer(box)
    }
    return queue.items.map { $0.average(colors, hist) }.filter { !ignored($0.hsl) }
}
