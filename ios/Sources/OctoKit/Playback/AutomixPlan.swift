import Foundation

/// Songs shorter than this get the plain crossfade, never a planned one.
public let shortestAutomixSongMs = 35_000

/// The shortest planned blend, and the longest that still counts as a cut.
public let shortestBlendMs = 1_800
public let cutBlendMs = 2_400

/// The latest a blend may end: this long before the outgoing song's end.
public let endMarginMs = 250

/// The earliest a blend may start: this far into the song, this share of it, once the song has
/// played long enough to count as played (half of it or `countsAsPlayedMs`, whichever is less),
/// and no more than `longestEarlyExitMs` before the latest end.
public let earliestStartMs = 30_000
public let earliestStartShare = 0.5
public let countsAsPlayedMs = 240_000
public let longestEarlyExitMs = 45_000

/// The incoming song needs this long to get ready before the blend starts.
public let preRollMs = 3_000

/// Without a beat grid the start is tried every this many milliseconds.
public let startStepMs = 250

/// The incoming song's entry moves onto a beat this close to its first sound.
public let entrySnapMs = 300.0

/// Both songs play this much quieter through the overlap, so their sum does not clip.
public let overlapHeadroomDb = 1.0

/// Songs in these genres get the plain crossfade, never a planned one.
public func isPlainCrossfadeGenre(_ genre: String) -> Bool {
    let lower = genre.lowercased()
    return ["classical", "opera", "spoken", "audiobook", "podcast", "comedy"].contains { lower.contains($0) }
}

/// How the two songs meet.
public enum TransitionKind: String, Sendable {
    /// One song straight after the other, no overlap.
    case gapless = "GAPLESS"
    /// The fixed equal-power crossfade at the end of the song.
    case crossfade = "CROSSFADE"
    /// A short planned swap.
    case cut = "CUT"
    /// A planned blend into a louder song.
    case lift = "LIFT"
    /// A planned blend.
    case blend = "BLEND"
}

/// What the player sets for planned transitions.
public struct AutomixSettings: Sendable, Equatable, Hashable {
    /// The longest blend, from the crossfade slider; 0 turns crossfade off.
    public var maxOverlapMs: Int
    /// Off plays the fixed crossfade at the end of each song.
    public var smart: Bool
    public var filterSweeps: Bool
    /// Nudges the incoming song's speed to the outgoing song's tempo.
    public var beatMatch: Bool
    /// The curve of the fixed crossfade, with smart transitions off. Planned transitions keep
    /// their own curves.
    public var fadeCurve: FadeCurve

    public init(maxOverlapMs: Int, smart: Bool = true, filterSweeps: Bool = true, beatMatch: Bool = false,
                fadeCurve: FadeCurve = .equalPower) {
        self.maxOverlapMs = maxOverlapMs
        self.smart = smart
        self.filterSweeps = filterSweeps
        self.beatMatch = beatMatch
        self.fadeCurve = fadeCurve
    }
}

/// Where the player is when it plans, and what it knows besides the scouted sections. `nowMs` is
/// the outgoing song's position and `playedMs` how much of it has actually been heard (less than
/// nowMs after a seek forward). `bodyLevelDb` and `tempoPrior` come from a LiveTap of the
/// outgoing song. A pace other than 1 or skip-silence moves media time away from the beat, so
/// they turn off bar lock and tempo matching.
public struct TransitionContext: Sendable, Equatable {
    public var nowMs: Int
    public var playedMs: Int
    public var repeatOne: Bool
    public var stopAtEndOfSong: Bool
    public var pace: Double
    public var skipSilence: Bool
    public var currentGenre: String?
    public var nextGenre: String?
    public var bodyLevelDb: Double?
    public var tempoPrior: Double?

    public init(nowMs: Int = 0, playedMs: Int? = nil, repeatOne: Bool = false, stopAtEndOfSong: Bool = false, pace: Double = 1,
                skipSilence: Bool = false, currentGenre: String? = nil, nextGenre: String? = nil, bodyLevelDb: Double? = nil,
                tempoPrior: Double? = nil) {
        self.nowMs = nowMs
        self.playedMs = playedMs ?? nowMs
        self.repeatOne = repeatOne
        self.stopAtEndOfSong = stopAtEndOfSong
        self.pace = pace
        self.skipSilence = skipSilence
        self.currentGenre = currentGenre
        self.nextGenre = nextGenre
        self.bodyLevelDb = bodyLevelDb
        self.tempoPrior = tempoPrior
    }
}

/// How to move from one song to the next. At startMs into the outgoing song the incoming song
/// starts playing from entryMs, and over overlapMs the volumes follow `automixOutGain` /
/// `automixInGain` with curve weight k, both lowered by headroomDb. With a filterStrength above 0
/// the filter sweeps run through the overlap and are bypassed once it ends. beatMatchRate, when
/// set, is the incoming song's playback rate through the blend. beatMs and beatAnchorMs, when
/// set, are the outgoing song's beat length and one of its beats in song time: the blend is
/// locked to the bar and the low-pass steps on the beat. `late` marks a blend placed at the end
/// because there was no time or data to choose a better place. `reason` says why this plan was
/// chosen.
public struct TransitionPlan: Sendable, Equatable {
    public var startMs: Int
    public var entryMs: Int
    public var overlapMs: Int
    public var kind: TransitionKind
    public var k: Double
    public var filterStrength: Double
    public var beatMatchRate: Double?
    public var beatMs: Double?
    public var beatAnchorMs: Double?
    public var late: Bool
    public var headroomDb: Double
    public var reason: String
    /// A fixed crossfade's chosen curve, followed in place of the curve weight k when set.
    public var curve: FadeCurve?

    public init(startMs: Int, entryMs: Int, overlapMs: Int, kind: TransitionKind, k: Double, filterStrength: Double,
                beatMatchRate: Double?, beatMs: Double?, beatAnchorMs: Double?, late: Bool, headroomDb: Double, reason: String,
                curve: FadeCurve? = nil) {
        self.startMs = startMs
        self.entryMs = entryMs
        self.overlapMs = overlapMs
        self.kind = kind
        self.k = k
        self.filterStrength = filterStrength
        self.beatMatchRate = beatMatchRate
        self.beatMs = beatMs
        self.beatAnchorMs = beatAnchorMs
        self.late = late
        self.headroomDb = headroomDb
        self.reason = reason
        self.curve = curve
    }

    public var barLocked: Bool { beatMs != nil }

    public func progressAt(_ outgoingMs: Double) -> Double {
        overlapMs <= 0 ? 1 : min(max((outgoingMs - Double(startMs)) / Double(overlapMs), 0), 1)
    }

    public func outGain(_ t: Double) -> Double {
        if let curve { return fadeGains(curve, t, overlapMs: overlapMs).out }
        return automixOutGain(t, k)
    }

    public func inGain(_ t: Double) -> Double {
        if let curve { return fadeGains(curve, t, overlapMs: overlapMs).incoming }
        return automixInGain(t, k)
    }

    /// The outgoing song's beats inside the blend as places through it (0 to 1). A beat within a
    /// twentieth of a beat of either end counts as the end itself and is left out.
    public func beatProgress() -> [Double] {
        guard let beat = beatMs, let anchor = beatAnchorMs, overlapMs > 0, beat > 0 else { return [] }
        let grid = Tempo(bpm: 60_000.0 / beat, confidence: tempoConfident, consistency: 1, beatMs: beat, firstBeatMs: anchor, downbeatMs: anchor)
        let margin = beat / 20
        return grid.beatsBetween(Double(startMs) + margin, Double(startMs + overlapMs) - margin)
            .map { ($0 - Double(startMs)) / Double(overlapMs) }
    }

    /// The outgoing low-pass: stepped on the beat when the blend is locked to the bar, gliding
    /// over an eighth of a bar.
    public func outgoingLowPassAt(_ t: Double) -> Double {
        guard let beat = beatMs, overlapMs > 0 else { return outgoingLowPassHz(t, filterStrength) }
        return steppedOutgoingLowPassHz(t, filterStrength, beatProgress(), beat * Double(beatsPerBar) / 8 / Double(overlapMs))
    }

    public func outgoingHighPassAt(_ t: Double) -> Double { outgoingHighPassHz(t, filterStrength) }

    public func incomingHighPassAt(_ t: Double) -> Double { incomingHighPassHz(t, filterStrength) }

    /// The incoming song's playback rate `sinceEntryMs` after it came in.
    public func incomingRateAt(_ sinceEntryMs: Double) -> Double {
        beatMatchRate.map { beatMatchRateAt($0, sinceEntryMs, Double(overlapMs)) } ?? 1
    }
}

/// Plans the move from the playing song to the next one. `tail` is the analysis of the end of
/// the playing song (analyzeTail) and `head` of the start of the next one (analyzeHead), either
/// nil when it is not ready. Every rule of crossfadeLength still holds: when it gives no
/// crossfade the songs play gaplessly. With smart transitions off the plan is the equal-power
/// crossfade (fixedCrossfadePlan); for a song under 35 s or in a genre that should not be mixed,
/// the fixed crossfade with the plain curve. Without the tail, or when no start is left at least
/// `preRollMs` ahead, the plan is a late one: the blend at the end, with the curve and the
/// filters but no bar lock.
public func planTransition(current: FadeSong, next: FadeSong?, tail: SectionAnalysis?, head: SectionAnalysis?,
                           settings: AutomixSettings, context: TransitionContext = TransitionContext()) -> TransitionPlan {
    let plain = crossfadeLength(current, next, fadeMs: settings.maxOverlapMs, repeatOne: context.repeatOne,
                                stopAtEndOfSong: context.stopAtEndOfSong)
    guard plain != 0, let next else {
        return gaplessPlan(current, gaplessReason(current, next, settings.maxOverlapMs, context.repeatOne, context.stopAtEndOfSong))
    }
    let lenA = current.durationMs
    let lenB = next.durationMs
    if !settings.smart { return fixedCrossfadePlan(lenA: lenA, length: plain, why: "smart transitions off", curve: settings.fadeCurve) }
    if let genre = [context.currentGenre, context.nextGenre].compactMap({ $0 }).first(where: isPlainCrossfadeGenre) {
        return crossfadePlan(lenA, plain, "genre \(genre)")
    }
    if lenA < shortestAutomixSongMs || lenB < shortestAutomixSongMs {
        return crossfadePlan(lenA, plain, "a song under \(shortestAutomixSongMs / 1000) s")
    }

    let limit = min(Double(settings.maxOverlapMs), Double(min(lenA, lenB)) / 2.0)
    let sweeps = settings.filterSweeps ? filterStrength : 0.0
    let headFeatures = head?.features.soundStartMs != nil ? head?.features : nil
    let headEntry = headFeatures?.soundStartMs ?? 0
    let canLock = context.pace == 1.0 && !context.skipSilence
    let fixedEnd = Double(lenA - endMarginMs)

    guard let tail else {
        return latePlan(lenA, fixedEnd, limit, context.nowMs, headEntry, nil, head, sweeps, "no analysis of this song's end")
    }
    let measured = context.bodyLevelDb.map(tail.withBodyLevel) ?? tail
    let a = measured.features
    guard let soundEndA = a.soundEndMs, let outroA = a.outroStartMs else {
        return latePlan(lenA, fixedEnd, limit, context.nowMs, headEntry, nil, head, sweeps, "this song's end is silent")
    }

    let latestEnd = Double(min(soundEndA, lenA - endMarginMs))
    let outroStart = min(Double(outroA), latestEnd)
    var tempoA = a.tempo?.confident == true ? a.tempo : nil
    if let found = tempoA, let prior = context.tempoPrior, prior > 0 {
        // The end must keep the tempo the whole song has.
        let moved = found.inOctaveOf(prior)
        tempoA = abs(moved.bpm / prior - 1) <= 0.04 ? moved : nil
    }
    let tempoB = headFeatures?.tempo?.confident == true ? headFeatures?.tempo : nil
    let lockA = canLock && tempoB != nil ? tempoA : nil
    let lockB = lockA != nil ? tempoB : nil
    let ratio: Double? = if let lockA, let lockB { foldTempoRatio(lockA.bpm / lockB.bpm) } else { nil }

    let soundStartB = Double(headEntry)
    var entry = soundStartB
    if let lockB {
        let beat = lockB.nearestBeat(entry)
        if abs(beat - entry) <= entrySnapMs { entry = max(0, beat) }
    }

    var bars = 0
    var overlap: Double
    if let lockA, let ratio {
        bars = abs(ratio - 1) > 0.08 ? 2 : 4
        overlap = Double(bars) * lockA.barMs
    } else {
        overlap = latestEnd - outroStart
    }
    // The next song's quiet start plays under the end of this one, so the blend lasts at least
    // until the next song is near its full level.
    let quietStart = headFeatures?.introEndMs.map { max(0, Double($0) - entry) } ?? 0
    let lengthened = quietStart > overlap
    if lengthened {
        if let lockA, bars > 0 {
            bars = Int((quietStart / lockA.barMs - 1e-9).rounded(.up))
            overlap = Double(bars) * lockA.barMs
        } else {
            overlap = quietStart
        }
    }
    overlap = min(max(overlap, Double(shortestBlendMs)), limit)
    if let lockA, bars > 0, overlap < Double(bars) * lockA.barMs {
        // Cut back to whole bars that fit, when that is still long enough.
        bars = Int((limit / lockA.barMs + 1e-9).rounded(.down))
        let whole = Double(bars) * lockA.barMs
        if bars >= 1 && whole >= Double(shortestBlendMs) { overlap = whole } else { bars = 0 }
    }
    overlap = (overlap + 0.5).rounded(.down)

    // Where the song will count as played, at the current pace of listening.
    let countsAsPlayed = context.nowMs + max(0, min(lenA / 2, countsAsPlayedMs) - context.playedMs)
    let lo = max(
        max(earliestStartShare * Double(lenA), Double(earliestStartMs), Double(countsAsPlayed)),
        latestEnd - Double(longestEarlyExitMs),
        Double(tail.envelope.startMs),
        Double(context.nowMs + preRollMs))
    let hi = latestEnd - overlap
    if hi < lo {
        return latePlan(lenA, latestEnd, overlap, context.nowMs, headEntry, measured, head, sweeps,
                        "no start left before \(automixSeconds(Int(hi)))")
    }

    // Bar lines when the blend is locked to the bar, otherwise a fixed step back from the latest start.
    let barLines = lockA?.barsBetween(lo, hi) ?? []
    let onBars = !barLines.isEmpty
    var candidates = barLines
    if candidates.isEmpty {
        var at = hi
        while at >= lo - 1e-6 {
            candidates.append(at)
            at -= Double(startStepMs)
        }
        candidates.reverse()
    }
    let phraseAnchor = lockA.map { $0.downbeatMs + roundHalfUp((outroStart - $0.downbeatMs) / $0.barMs) * $0.barMs }
    let fullDb = a.bodyDb - 3

    var bestStart = candidates[candidates.count - 1]
    var bestScore = -Double.infinity
    for start in candidates {
        var score = -0.08 * (latestEnd - (start + overlap)) / 1000
        if outroStart < latestEnd - 1000 { score -= 0.15 * abs(start - outroStart) / 1000 }
        if a.boundariesMs.contains(where: { abs(Double($0) - start) <= 250 }) { score += 1.0 }
        if let lockA, let phraseAnchor, onBars {
            score += 0.6
            let barsBack = Int(roundHalfUp((phraseAnchor - start) / lockA.barMs))
            if barsBack % 8 == 0 { score += 0.8 }
        }
        score -= 1.5 * measured.shareAtLeast(start, start + overlap, fullDb)
        if score >= bestScore {
            bestScore = score
            bestStart = start
        }
    }

    var rate: Double?
    if settings.beatMatch, lockA != nil, let lockB, let ratio {
        let gap = abs(ratio - 1)
        if gap >= 0.005 && gap <= 0.04 {
            rate = min(max(ratio, 0.94), 1.06)
            entry = max(0, lockB.downbeatFrom(soundStartB - entrySnapMs))
        }
    }

    let kind = kindOf(overlap, measured, head, bestStart, entry)
    let start = Int((bestStart + 0.5).rounded(.down))
    let entryMs = Int((entry + 0.5).rounded(.down))
    var reason = kind.rawValue.lowercased()
    reason += " at \(automixSeconds(start)) over \(automixSeconds(Int(overlap)))"
    if bars > 0, let lockA { reason += " (\(bars) bars of \(automixDecimals(lockA.displayBpm, 1)) BPM)" }
    reason += ", next song from \(automixSeconds(entryMs))"
    if lengthened { reason += " (full from \(automixSeconds(Int(entry + quietStart))))" }
    reason += ", outro at \(automixSeconds(Int(outroStart)))"
    reason += ", latest end \(automixSeconds(Int(latestEnd)))"
    if head == nil { reason += ", no analysis of the next song's start" }
    if let rate { reason += ", rate \(automixDecimals(rate, 3))" }
    return TransitionPlan(startMs: start, entryMs: entryMs, overlapMs: Int(overlap), kind: kind, k: curveOf(kind),
                          filterStrength: sweeps, beatMatchRate: rate, beatMs: lockA?.beatMs, beatAnchorMs: lockA?.firstBeatMs,
                          late: false, headroomDb: overlapHeadroomDb, reason: reason)
}

/// A tempo ratio folded by halving or doubling into 0.707 to 1.414, so a song at half or double
/// the tempo counts as the same tempo.
public func foldTempoRatio(_ ratio: Double) -> Double {
    if ratio <= 0 { return ratio }
    var r = ratio
    while r > 1.4142135623730951 { r /= 2 }
    while r < 0.7071067811865476 { r *= 2 }
    return r
}

/// A cut for a short overlap; a lift when the next song's first 8 s are at least 3 dB louder than
/// this song through the overlap; else a blend.
private func kindOf(_ overlap: Double, _ tail: SectionAnalysis?, _ head: SectionAnalysis?, _ start: Double, _ entry: Double) -> TransitionKind {
    if overlap <= Double(cutBlendMs) { return .cut }
    if let tail, let head, head.levelDb(entry, entry + 8_000) >= tail.levelDb(start, start + overlap) + 3 { return .lift }
    return .blend
}

private func curveOf(_ kind: TransitionKind) -> Double {
    switch kind {
    case .cut: cutCurve
    case .lift: liftCurve
    case .blend: blendCurve
    default: crossfadeCurve
    }
}

/// The blend at the end: ending at latestEnd, over `overlap` or whatever is left after nowMs, with
/// the curve and filters but no bar lock. Too little left to blend plays gaplessly.
private func latePlan(_ lenA: Int, _ latestEnd: Double, _ overlap: Double, _ nowMs: Int, _ entryMs: Int, _ tail: SectionAnalysis?,
                      _ head: SectionAnalysis?, _ sweeps: Double, _ why: String) -> TransitionPlan {
    let start = max(Double(nowMs), latestEnd - overlap)
    let length = (latestEnd - start + 0.5).rounded(.down)
    if length < Double(shortestFadeMs) {
        return gaplessPlan(FadeSong(albumId: nil, albumOrder: nil, durationMs: lenA), "too late to blend: \(why)")
    }
    let kind = kindOf(length, tail, head, start, Double(entryMs))
    let startMs = Int((start + 0.5).rounded(.down))
    return TransitionPlan(
        startMs: startMs, entryMs: entryMs, overlapMs: Int(length), kind: kind, k: curveOf(kind), filterStrength: sweeps,
        beatMatchRate: nil, beatMs: nil, beatAnchorMs: nil, late: true, headroomDb: overlapHeadroomDb,
        reason: "late \(kind.rawValue.lowercased()) at \(automixSeconds(startMs)) over \(automixSeconds(Int(length))), next song from \(automixSeconds(entryMs)): \(why)")
}

private func gaplessPlan(_ current: FadeSong, _ reason: String) -> TransitionPlan {
    TransitionPlan(startMs: max(0, current.durationMs), entryMs: 0, overlapMs: 0, kind: .gapless, k: crossfadeCurve,
                   filterStrength: 0, beatMatchRate: nil, beatMs: nil, beatAnchorMs: nil, late: false, headroomDb: 0,
                   reason: "gapless: \(reason)")
}

/// The fixed crossfade at the end of the song: no filters, on the chosen curve. Equal power is
/// the crossfade as it was before planned transitions, with no curve weight and no headroom;
/// mix only plays both songs a little quieter through the overlap.
public func fixedCrossfadePlan(lenA: Int, length: Int, why: String, curve: FadeCurve = .equalPower) -> TransitionPlan {
    let start = max(0, lenA - length)
    let named = curve == .equalPower ? "" : ", \(curve.label.lowercased()) fade"
    return TransitionPlan(startMs: start, entryMs: 0, overlapMs: length, kind: .crossfade, k: 0, filterStrength: 0,
                          beatMatchRate: nil, beatMs: nil, beatAnchorMs: nil, late: false,
                          headroomDb: curve == .mixOnly ? mixOnlyHeadroomDb : 0,
                          reason: "crossfade at \(automixSeconds(start)) over \(automixSeconds(length)): \(why)\(named)",
                          curve: curve == .equalPower ? nil : curve)
}

private func crossfadePlan(_ lenA: Int, _ length: Int, _ why: String) -> TransitionPlan {
    TransitionPlan(startMs: lenA - length, entryMs: 0, overlapMs: length, kind: .crossfade, k: crossfadeCurve, filterStrength: 0,
                   beatMatchRate: nil, beatMs: nil, beatAnchorMs: nil, late: false, headroomDb: overlapHeadroomDb,
                   reason: "crossfade at \(automixSeconds(lenA - length)) over \(automixSeconds(length)): \(why)")
}

private func gaplessReason(_ current: FadeSong, _ next: FadeSong?, _ fadeMs: Int, _ repeatOne: Bool, _ stopAtEndOfSong: Bool) -> String {
    guard fadeMs > 0 else { return "crossfade off" }
    guard let next else { return "nothing next" }
    if repeatOne { return "repeat one" }
    if stopAtEndOfSong { return "stopping at the end of the song" }
    if current.durationMs <= 0 || next.durationMs <= 0 { return "a song's length is unknown" }
    if let album = current.albumId, album == next.albumId { return "the album plays in order" }
    return "a song too short to blend"
}

/// Milliseconds as seconds with two decimals, like "182.50 s".
func automixSeconds(_ ms: Int) -> String {
    let sign = ms < 0 ? "-" : ""
    let magnitude = abs(ms)
    let hundredths = (magnitude % 1000) / 10
    return "\(sign)\(magnitude / 1000).\(hundredths < 10 ? "0" : "")\(hundredths) s"
}

/// A positive number with a fixed count of decimals, like "120.0".
func automixDecimals(_ x: Double, _ places: Int) -> String {
    var scale = 1
    for _ in 0..<places { scale *= 10 }
    let scaled = Int((x * Double(scale) + 0.5).rounded(.down))
    var part = "\(scaled % scale)"
    while part.count < places { part = "0" + part }
    return "\(scaled / scale).\(part)"
}
