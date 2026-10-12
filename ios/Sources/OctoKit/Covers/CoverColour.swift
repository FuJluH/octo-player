import Foundation

// Colour in the OKLCH space, where equal steps look like equal steps, as covers are designed in
// it: a colour keeps its hue while its lightness is set to what the design needs. Colours are
// ARGB in a UInt32.

/// A colour as lightness (0 black to 1 white), chroma (0 grey, about 0.3 at the most vivid) and
/// hue in degrees.
public struct Lch: Equatable, Sendable {
    public var l: Double
    public var c: Double
    public var h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }

    public var argb: UInt32 { lchToArgb(l, c, h) }
}

private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

/// One 8-bit sRGB channel (0 to 1) as light, and back.
public func channelToLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

public func linearToChannel(_ v: Double) -> Double {
    let c = min(max(v, 0), 1)
    return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
}

private func encoded(_ v: Double) -> Double { v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055 }

@inline(__always) func red(_ argb: UInt32) -> Int { Int(argb >> 16 & 0xFF) }
@inline(__always) func green(_ argb: UInt32) -> Int { Int(argb >> 8 & 0xFF) }
@inline(__always) func blue(_ argb: UInt32) -> Int { Int(argb & 0xFF) }
@inline(__always) func opaque(_ r: Int, _ g: Int, _ b: Int) -> UInt32 { 0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }

/// Linear sRGB to OKLab (L, a, b).
public func linearToOklab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}

/// OKLab to linear sRGB; outside 0 to 1 when the screen cannot show it.
public func oklabToLinear(_ lightness: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
    let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
    let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
    let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
    return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
}

public func toLch(_ argb: UInt32) -> Lch {
    let (lightness, a, b) = linearToOklab(channelToLinear(Double(red(argb)) / 255), channelToLinear(Double(green(argb)) / 255),
                                          channelToLinear(Double(blue(argb)) / 255))
    var hue = degrees(atan2(b, a))
    if hue < 0 { hue += 360 }
    return Lch(l: lightness, c: hypot(a, b), h: hue)
}

private func linearRgb(_ l: Double, _ c: Double, _ h: Double) -> (Double, Double, Double) {
    let rad = radians(h)
    return oklabToLinear(l, c * cos(rad), c * sin(rad))
}

private func shown(_ rgb: (Double, Double, Double)) -> Bool {
    [rgb.0, rgb.1, rgb.2].allSatisfy { $0 >= -1e-4 && $0 <= 1.0001 }
}

/// The colour at this lightness, chroma and hue as ARGB. A chroma the screen cannot show is
/// lowered until it can, keeping the lightness and hue.
public func lchToArgb(_ l: Double, _ c: Double, _ h: Double) -> UInt32 {
    let lightness = min(max(l, 0), 1)
    var rgb = linearRgb(lightness, c, h)
    if !shown(rgb) {
        var low = 0.0
        var high = c
        for _ in 0..<24 {
            let mid = (low + high) / 2
            if shown(linearRgb(lightness, mid, h)) { low = mid } else { high = mid }
        }
        rgb = linearRgb(lightness, low, h)
    }
    func byte(_ v: Double) -> Int { min(max(Int((encoded(min(max(v, 0), 1)) * 255).rounded()), 0), 255) }
    return opaque(byte(rgb.0), byte(rgb.1), byte(rgb.2))
}

/// How far apart two hues are around the circle, 0 to 180 degrees.
public func hueDistance(_ a: Double, _ b: Double) -> Double {
    let d = ((a - b).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    return d > 180 ? 360 - d : d
}

/// The hue a share `t` of the way from `a` to `b`, the short way round.
public func hueBetween(_ a: Double, _ b: Double, _ t: Double) -> Double {
    var d = ((b - a).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    return ((a + d * t).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
}

/// How far apart two colours look, in the same space (0 the same).
public func colourDistance(_ a: UInt32, _ b: UInt32) -> Double { lchDistance(toLch(a), toLch(b)) }

func lchDistance(_ x: Lch, _ y: Lch) -> Double {
    let ra = radians(x.h), rb = radians(y.h)
    let da = x.c * cos(ra) - y.c * cos(rb)
    let db = x.c * sin(ra) - y.c * sin(rb)
    return sqrt(pow(x.l - y.l, 2) + da * da + db * db)
}

/// The colour with this opacity.
func withAlpha(_ argb: UInt32, _ a: Float) -> UInt32 {
    UInt32(Int((min(max(a, 0), 1) * 255).rounded())) << 24 | (argb & 0xFF_FFFF)
}

// MARK: Swatches

/// One colour of a picture and how much of it that colour covers, 0 to 1.
public struct CoverSwatch: Equatable, Sendable {
    public var argb: UInt32
    public var share: Float

    public init(argb: UInt32, share: Float) {
        self.argb = argb
        self.share = share
    }
}

/// Pixels counted in coarse buckets (4 bits a channel): how many fell in each, and their channels
/// added up.
private struct Bucket {
    var key: Int
    var count = 0
    var r = 0
    var g = 0
    var b = 0

    var mean: UInt32 { opaque(r / count, g / count, b / count) }
}

/// Every `step`th pixel by bucket, the buckets in the order they were first seen.
private func buckets(_ pixels: [UInt32], step: Int) -> [Bucket] {
    var at: [Int: Int] = [:]
    var out: [Bucket] = []
    var i = 0
    while i < pixels.count {
        let p = pixels[i]
        let key = Int(p >> 20 & 0xF) << 8 | Int(p >> 12 & 0xF) << 4 | Int(p >> 4 & 0xF)
        let index: Int
        if let found = at[key] {
            index = found
        } else {
            index = out.count
            at[key] = index
            out.append(Bucket(key: key))
        }
        out[index].count += 1
        out[index].r += red(p)
        out[index].g += green(p)
        out[index].b += blue(p)
        i += step
    }
    return out
}

/// A picture's main colour: the most common of its colours, roughly, averaged within its bucket.
public func dominantColour(_ pixels: [UInt32], step: Int = 7) -> UInt32 {
    buckets(pixels, step: step).max { $0.count < $1.count }?.mean ?? 0xFF20_2020
}

/// Colours closer than this count as one.
private let sameColour = 0.09

/// A picture's main colours, most of the picture first, up to `most`: its buckets from the most
/// common down, each joining the first colour it looks like, or starting one of its own.
public func coverSwatches(_ pixels: [UInt32], step: Int = 3, most: Int = 6) -> [CoverSwatch] {
    guard !pixels.isEmpty else { return [] }
    let found = buckets(pixels, step: step).enumerated().sorted { a, b in
        a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset
    }.map(\.element)
    let total = Float(found.reduce(0) { $0 + $1.count })
    // Each colour is compared by where its first bucket sat; specks of a colour (under 0.2% of
    // the picture) are left out.
    var groups: [(lch: Lch, bucket: Bucket)] = []
    for bucket in found {
        if Float(bucket.count) < total * 0.002 { break }
        let seen = toLch(bucket.mean)
        if let near = groups.firstIndex(where: { lchDistance($0.lch, seen) < sameColour }) {
            groups[near].bucket.count += bucket.count
            groups[near].bucket.r += bucket.r
            groups[near].bucket.g += bucket.g
            groups[near].bucket.b += bucket.b
        } else if groups.count < most * 3 {
            groups.append((seen, bucket))
        }
    }
    return groups.map(\.bucket).enumerated().sorted { a, b in
        a.element.count != b.element.count ? a.element.count > b.element.count : a.offset < b.offset
    }.prefix(most).map { CoverSwatch(argb: $0.element.mean, share: Float($0.element.count) / total) }
}

/// The main colours of each quarter of a square picture, top left first.
public func quarterSwatches(_ pixels: [UInt32], width: Int, most: Int = 3) -> [[CoverSwatch]] {
    let height = width == 0 ? 0 : pixels.count / width
    if width < 2 || height < 2 { return [coverSwatches(pixels, most: most)] }
    let halfW = width / 2, halfH = height / 2
    return (0..<4).map { q in
        let x0 = (q % 2) * halfW, y0 = (q / 2) * halfH
        let part = (0..<(halfW * halfH)).map { i in pixels[(y0 + i / halfW) * width + x0 + i % halfW] }
        return coverSwatches(part, step: 2, most: most)
    }
}
