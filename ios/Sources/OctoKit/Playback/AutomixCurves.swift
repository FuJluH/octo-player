import Foundation

/// The curve weight of each kind of transition: how much of the S-shaped curve is mixed into the
/// equal-power one. Higher swaps the songs faster around the middle.
public let cutCurve = 0.75
public let liftCurve = 0.55
public let blendCurve = 0.2
public let crossfadeCurve = 0.4

/// How deep the filter sweeps go, 0 for none and 1 for the full range.
public let filterStrength = 0.7

/// The outgoing song's low-pass runs from `openLowPassHz` down toward `lowPassFloorHz`.
public let openLowPassHz = 18_000.0
public let lowPassFloorHz = 450.0

/// The outgoing song's bass cut rises from `openHighPassHz` toward `bassSwapHz` by the middle of
/// the blend.
public let openHighPassHz = 10.0
public let bassSwapHz = 300.0
public let bassSwapAt = 0.5

/// The incoming song's high-pass starts at `incomingHighPassHz` and opens to `incomingOpenHz` by
/// `incomingOpenAt` through the blend.
public let incomingHighPassHz = 675.0
public let incomingOpenHz = 20.0
public let incomingOpenAt = 0.6

/// After the blend a tempo-matched incoming song eases back to its own speed over this long.
public let beatMatchSettleMs = 5_000.0

private func sigmoid12(_ t: Double) -> Double { 1 / (1 + exp(-12 * (t - 0.5))) }

private let sigmoidLow = sigmoid12(0)
private let sigmoidHigh = sigmoid12(1)

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

/// The S curve scaled to run exactly from 0 at the start to 1 at the end.
public func sCurve(_ t: Double) -> Double { (sigmoid12(clamp01(t)) - sigmoidLow) / (sigmoidHigh - sigmoidLow) }

/// The outgoing song's volume at `t` through the blend (0 to 1): an equal-power fade mixed with
/// an S curve by weight `k`.
public func automixOutGain(_ t: Double, _ k: Double) -> Double {
    let p = clamp01(t)
    return clamp01(cos(p * Double.pi / 2) * (1 - k) + (1 - sCurve(p)) * k)
}

/// The incoming song's volume: whatever keeps the two volumes' squares at one.
public func automixInGain(_ t: Double, _ k: Double) -> Double {
    let out = automixOutGain(t, k)
    return max(0, 1 - out * out).squareRoot()
}

/// Moves from `from` to `to` on a log scale as u goes from 0 to 1.
private func logBetween(_ from: Double, _ to: Double, _ u: Double) -> Double { from * pow(to / from, clamp01(u)) }

/// The outgoing song's low-pass cutoff in Hz at `t`, falling smoothly.
public func outgoingLowPassHz(_ t: Double, _ strength: Double) -> Double {
    let end = openLowPassHz * pow(lowPassFloorHz / openLowPassHz, clamp01(strength))
    return logBetween(openLowPassHz, end, t)
}

/// The same low-pass moving in steps on the beat: it holds each beat's cutoff until `glide`
/// before the next beat, then glides to the next one. `beats` are the beats' places through the
/// blend (0 to 1, rising) and `glide` is in the same units.
public func steppedOutgoingLowPassHz(_ t: Double, _ strength: Double, _ beats: [Double], _ glide: Double) -> Double {
    let p = clamp01(t)
    var from = 0.0
    var to = 1.0
    for beat in beats {
        if beat <= 0 || beat >= 1 { continue }
        if beat <= p { from = beat } else { to = beat; break }
    }
    let g = min(max(0, glide), to - from)
    let glideStart = to - g
    let at = (p < glideStart || g <= 0) ? from : from + (p - glideStart) / g * (to - from)
    return outgoingLowPassHz(at, strength)
}

/// The outgoing song's bass cut in Hz at `t`: rises to its top by the middle of the blend and
/// holds there.
public func outgoingHighPassHz(_ t: Double, _ strength: Double) -> Double {
    let top = max(openHighPassHz, bassSwapHz * clamp01(strength))
    return logBetween(openHighPassHz, top, t / bassSwapAt)
}

/// The incoming song's high-pass cutoff in Hz at `t`: thin at first, fully open by
/// `incomingOpenAt`.
public func incomingHighPassHz(_ t: Double, _ strength: Double) -> Double {
    let start = max(incomingOpenHz, incomingHighPassHz * clamp01(strength))
    return logBetween(start, incomingOpenHz, t / incomingOpenAt)
}

/// The incoming song's playback rate `sinceEntryMs` after it came in: `rate` through the blend,
/// then eased back to 1 over `beatMatchSettleMs`.
public func beatMatchRateAt(_ rate: Double, _ sinceEntryMs: Double, _ overlapMs: Double) -> Double {
    if sinceEntryMs <= overlapMs { return rate }
    let u = (sinceEntryMs - overlapMs) / beatMatchSettleMs
    if u >= 1 { return 1 }
    return rate + (1 - rate) * (1 - cos(Double.pi * u)) / 2
}
