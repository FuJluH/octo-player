import Foundation

// The colour-keeping veil under a cover's words, as cover-design.json's "veil" describes it: only
// what is too bright for white words is darkened, by OKLab lightness with hue and chroma kept,
// deep yellows turned toward amber (or green), and only as far as each block of words needs.

/// A block of words' region: its box in pixels (left, top, right, bottom), how far the veil fades
/// out beyond it (shares of the side, across and down), the luminance aimed for and the most
/// allowed, and the largest share of a pixel's luminance it may take to reach the aim.
public struct VeilRegion: Equatable, Sendable {
    public var box: [Float]
    public var falloffX: Double
    public var falloffY: Double
    public var aim: Double
    public var least: Double
    public var maxDrop: Double
}

private let luma = (0.2126, 0.7152, 0.0722)

private func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

/// The most a background's luminance may be for white words at `inkOpacity` (laid over it in sRGB,
/// as the apps draw) to reach `contrast`, taken on a grey background.
public func veilLimit(_ contrast: Double, inkOpacity: Double = 1) -> Double {
    if inkOpacity >= 1 { return 1.05 / contrast - 0.05 }
    var lo = 0.0, hi = 1.0
    for _ in 0..<40 {
        let mid = (lo + hi) / 2
        let bg = linearToChannel(mid)
        let ink = channelToLinear(bg + (1 - bg) * inkOpacity)
        if (ink + 0.05) / (mid + 0.05) >= contrast { lo = mid } else { hi = mid }
    }
    return lo
}

/// The regions for a cover's laid-out words: the title block (name and its second line together)
/// from the top corner on the words' side, and the foot line from the bottom corner.
public func veilRegions(_ words: [CoverWords], side: Int, book: CoverBook = .standard) -> [VeilRegion] {
    let s = Float(side)
    let veil = book.veil
    var out: [VeilRegion] = []
    let block = words.filter { $0.role != .footer }
    if let first = block.first {
        let v = veil.title
        let pad = v.pad * s
        let bottom = (block.map { $0.top + $0.height }.max() ?? 0) + pad
        let box: [Float] = first.align == .right
            ? [(block.map { $0.inked[0] }.min() ?? 0) - pad, 0, s, bottom]
            : [0, 0, (block.map { $0.inked[2] }.max() ?? 0) + pad, bottom]
        let aim = veilLimit(v.aimContrast) * (1 - veil.margin)
        let least = veilLimit(v.minContrast) * (1 - veil.margin)
        out.append(VeilRegion(box: box, falloffX: v.falloff[0], falloffY: v.falloff[1], aim: aim, least: least, maxDrop: v.maxDrop))
    }
    if let w = words.first(where: { $0.role == .footer }) {
        let v = veil.footer
        let pad = v.pad * s
        let box: [Float] = w.align == .right ? [w.inked[0] - pad, w.top - pad, s, s] : [0, w.top - pad, w.inked[2] + pad, s]
        let need = veilLimit(v.contrast, inkOpacity: Double(book.layout.footer.opacity)) * (1 - veil.margin)
        out.append(VeilRegion(box: box, falloffX: v.falloff[0], falloffY: v.falloff[1], aim: need, least: need, maxDrop: 1))
    }
    return out
}

/// The background's pixels (ARGB, `side` square) with the veil laid in.
public func applyVeil(_ pixels: [UInt32], side: Int, regions: [VeilRegion], book: CoverBook = .standard) -> [UInt32] {
    if regions.isEmpty { return pixels }
    let n = side * side
    let toLinear = (0..<256).map { channelToLinear(Double($0) / 255) }
    let y = (0..<n).map { i -> Double in
        let p = pixels[i]
        return luma.0 * toLinear[red(p)] + luma.1 * toLinear[green(p)] + luma.2 * toLinear[blue(p)]
    }
    // Each region keeps a share of a pixel's luminance; shares multiply, so where two regions meet
    // the veil stays smooth.
    var keep = [Double](repeating: 1, count: n)
    var reach = [Double](repeating: 0, count: n)
    for r in regions {
        let x0 = Double(r.box[0]), y0 = Double(r.box[1]), x1 = Double(r.box[2]), y1 = Double(r.box[3])
        let across = (0..<side).map { i -> Double in
            let c = Double(i) + 0.5
            return max(max(x0 - c, c - x1), 0) / (r.falloffX * Double(side))
        }
        let down = (0..<side).map { i -> Double in
            let c = Double(i) + 0.5
            return max(max(y0 - c, c - y1), 0) / (r.falloffY * Double(side))
        }
        for row in 0..<side {
            let dy = down[row]
            if dy >= 1 { continue }
            for col in 0..<side {
                let dx = across[col]
                let w = 1 - smoothstep(0, 1, sqrt(dx * dx + dy * dy))
                if w <= 0 { continue }
                let i = row * side + col
                let limit = min(max(r.aim, y[i] * (1 - r.maxDrop)), r.least)
                keep[i] *= 1 - w * (1 - min(1, limit / max(y[i], 1e-9)))
                if w > reach[i] { reach[i] = w }
            }
        }
    }
    let yellow = book.veil.yellow
    let lo = yellow.hues[0], fullLo = yellow.hues[1], fullHi = yellow.hues[2], hi = yellow.hues[3]
    func labOf(_ p: UInt32) -> (Double, Double, Double) { linearToOklab(toLinear[red(p)], toLinear[green(p)], toLinear[blue(p)]) }
    func hueOf(_ lab: (Double, Double, Double)) -> Double {
        let h = atan2(lab.2, lab.1) * 180 / .pi
        return (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
    func yellowness(_ h: Double, _ c: Double) -> Double {
        smoothstep(lo, fullLo, h) * (1 - smoothstep(fullHi, hi, h)) * min(max(c / yellow.chromaFrom, 0), 1)
    }

    // One direction per cover: where the yellows under the veil lean yellow they deepen to amber,
    // where they lean lime, to green.
    var mass = 0.0, weighted = 0.0
    for i in 0..<n where reach[i] > 0 {
        let lab = labOf(pixels[i])
        let c = hypot(lab.1, lab.2)
        let h = hueOf(lab)
        let m = yellowness(h, c) * c * reach[i]
        mass += m
        weighted += h * m
    }
    let lean = mass > 0 ? weighted / mass : 0
    let towards = lean <= yellow.split ? yellow.towards[0] : yellow.towards[1]

    var out = pixels
    for i in 0..<n {
        let y0 = y[i]
        let target = y0 * keep[i]
        if target >= y0 - 1e-9 { continue }
        let lab = labOf(pixels[i])
        let c = hypot(lab.1, lab.2)
        let h = hueOf(lab)
        let wy = yellowness(h, c)
        let drop = 1 - target / y0
        let share = min(max(yellow.turnPerDrop * drop, 0), 1) * wy
        let h2 = (h + (towards - h) * share) * .pi / 180
        let c2 = c * (1 + yellow.chromaLift * drop * wy)
        let a2 = c2 * cos(h2), b2 = c2 * sin(h2)
        var l2 = lab.0 * cbrt(target / y0)
        for _ in 0..<book.veil.refine {
            let rgb = settle(l2, a2, b2)
            let got = luma.0 * rgb.0 + luma.1 * rgb.1 + luma.2 * rgb.2
            l2 *= cbrt(target / max(got, 1e-6))
        }
        let rgb = settle(l2, a2, b2)
        func byte(_ v: Double) -> Int { min(max(Int((linearToChannel(v) * 255).rounded()), 0), 255) }
        out[i] = (pixels[i] & 0xFF00_0000) | UInt32(byte(rgb.0)) << 16 | UInt32(byte(rgb.1)) << 8 | UInt32(byte(rgb.2))
    }
    return out
}

private func inGamut(_ rgb: (Double, Double, Double), _ slack: Double) -> Bool {
    [rgb.0, rgb.1, rgb.2].allSatisfy { $0 >= -slack && $0 <= 1 + slack }
}

/// An OKLab colour as linear sRGB the screen can show: one outside is taken toward grey at the
/// same lightness (the largest share of its chroma that fits, halving 12 times), blended with a
/// plain clip for colours only just outside, so nothing jumps.
func settle(_ l: Double, _ a: Double, _ b: Double) -> (Double, Double, Double) {
    let raw = oklabToLinear(l, a, b)
    if inGamut(raw, 0) { return raw }
    var lo = 0.0, hi = 1.0
    for _ in 0..<12 {
        let mid = (lo + hi) / 2
        if inGamut(oklabToLinear(l, a * mid, b * mid), 1e-4) { lo = mid } else { hi = mid }
    }
    let test = oklabToLinear(l, a * lo, b * lo)
    let excess = max(-min(raw.0, raw.1, raw.2), max(raw.0, raw.1, raw.2) - 1)
    let t = min(max(excess / 0.05, 0), 1)
    let w = t * t * (3 - 2 * t)
    func clip(_ v: Double) -> Double { min(max(v, 0), 1) }
    return (clip(raw.0) * (1 - w) + clip(test.0) * w, clip(raw.1) * (1 - w) + clip(test.1) * w, clip(raw.2) * (1 - w) + clip(test.2) * w)
}
