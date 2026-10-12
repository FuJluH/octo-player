import Foundation

/// The quietest a silence gate can be, in dBFS.
public let silenceFloorDb = -60.0

/// How far below a song's body level its silence gate sits.
public let silenceBelowBodyDb = 45.0

/// How far below the body level the song has to stay for its outro to begin.
public let outroBelowBodyDb = 6.0

/// How much the level must change between the two seconds before and after a moment for it to
/// count as a section boundary.
public let boundaryStepDb = 4.0

/// The body level is this percentile of the 400 ms level. A song's start, or the whole song
/// heard as it plays, uses `headBodyPercentile`; the end of a song alone uses
/// `tailBodyPercentile`, since a tail that is mostly outro would otherwise read too quiet.
public let headBodyPercentile = 0.75
public let tailBodyPercentile = 0.9

/// The tempo range the beat finder looks in.
public let slowestBpm = 70.0
public let fastestBpm = 180.0

/// A tempo is trusted when its period scores at least `tempoConfident` (see pickPeriod) and both
/// halves of the section pick the same period to within `steadyWithin`, after halving or
/// doubling.
public let tempoConfident = 0.4
public let steadyWithin = 0.02

/// A tag tempo picks an octave of the found tempo only when that octave is within this share of
/// the tag.
public let tagWithin = 0.02

/// The onsets are measured against their mean over this long around each hop.
public let onsetTrendMs = 1_000.0

/// The beat periods tried are this many hops apart.
public let periodStep = 0.1

/// The multiples of the beat period whose autocorrelation scores it, and the weight of the half
/// period.
private let harmonics: [Double] = [1, 2, 4, 8]
private let halfBeatWeight = 0.5

/// Tempos are shown halved or doubled into this up to twice this.
public let displaySlowestBpm = 81.0

/// How near an onset peak a beat has to fall to count as landing on it.
public let beatHitMs = 35.0

/// Beats in a bar.
public let beatsPerBar = 4

/// Below this spread of the onsets about their local mean they are too faint to carry a beat,
/// so no tempo is reported.
private let faintestBeat = 1e-4

/// An onset peak must reach at least this, and one standard deviation above the mean onset of
/// the sounding part.
private let faintestPeak = 0.05

private let bodyWindowMs = 400
private let soundWindowMs = 50
private let outroWindowMs = 1000
private let boundarySideMs = 2000

private let sqrt2 = 1.4142135623730951

/// A song's beat grid. Beat times are song times in milliseconds: beats fall on
/// firstBeatMs + n * beatMs and bars start on downbeatMs + n * barMs. `confidence` is the beat
/// period's score, `consistency` the share of the grid's beats that land on an onset peak, and
/// `steady` whether both halves of the section heard the same beat.
public struct Tempo: Sendable, Equatable {
    public var bpm: Double
    public var confidence: Double
    public var consistency: Double
    public var beatMs: Double
    public var firstBeatMs: Double
    public var downbeatMs: Double
    public var steady: Bool

    public init(bpm: Double, confidence: Double, consistency: Double, beatMs: Double, firstBeatMs: Double,
                downbeatMs: Double, steady: Bool = true) {
        self.bpm = bpm
        self.confidence = confidence
        self.consistency = consistency
        self.beatMs = beatMs
        self.firstBeatMs = firstBeatMs
        self.downbeatMs = downbeatMs
        self.steady = steady
    }

    public var confident: Bool { steady && confidence >= tempoConfident }

    /// The tempo as it is usually written: halved or doubled into `displaySlowestBpm` up to twice
    /// that.
    public var displayBpm: Double {
        var shown = bpm
        if shown <= 0 { return shown }
        while shown >= 2 * displaySlowestBpm { shown /= 2 }
        while shown < displaySlowestBpm { shown *= 2 }
        return shown
    }

    public var barMs: Double { beatMs * Double(beatsPerBar) }

    /// The beat nearest a time, extending the grid either way.
    public func nearestBeat(_ ms: Double) -> Double { firstBeatMs + roundHalfUp((ms - firstBeatMs) / beatMs) * beatMs }

    /// Every bar line from fromMs to toMs, both included.
    public func barsBetween(_ fromMs: Double, _ toMs: Double) -> [Double] { gridBetween(downbeatMs, barMs, fromMs, toMs) }

    /// Every beat from fromMs to toMs, both included.
    public func beatsBetween(_ fromMs: Double, _ toMs: Double) -> [Double] { gridBetween(firstBeatMs, beatMs, fromMs, toMs) }

    /// The first bar line at or after a time.
    public func downbeatFrom(_ ms: Double) -> Double { downbeatMs + ((ms - downbeatMs) / barMs - 1e-9).rounded(.up) * barMs }

    /// The same grid at double or half the tempo, as often as it takes to come within a factor of
    /// sqrt 2 of `bpm`.
    public func inOctaveOf(_ bpm: Double) -> Tempo {
        if bpm <= 0 { return self }
        var factor = 1.0
        while self.bpm * factor > bpm * sqrt2 { factor /= 2 }
        while self.bpm * factor < bpm / sqrt2 { factor *= 2 }
        if factor == 1 { return self }
        var moved = self
        moved.bpm = self.bpm * factor
        moved.beatMs = beatMs / factor
        return moved
    }
}

private func gridBetween(_ anchor: Double, _ step: Double, _ fromMs: Double, _ toMs: Double) -> [Double] {
    var points: [Double] = []
    var n = ((fromMs - anchor) / step - 1e-9).rounded(.up)
    while true {
        let at = anchor + n * step
        if at > toMs + 1e-6 { break }
        points.append(at)
        n += 1
    }
    return points
}

/// What the planner needs to know about one stretch of a song. Times are song times in
/// milliseconds. The sound times are nil when the stretch is silent throughout; the tempo is nil
/// when no beat was found.
public struct SectionFeatures: Sendable, Equatable {
    /// The level of the song's body, in dBFS.
    public var bodyDb: Double
    /// Below this the song counts as silent.
    public var gateDb: Double
    public var soundStartMs: Int?
    public var soundEndMs: Int?
    /// From here on the song never again comes within 6 dB of its body level.
    public var outroStartMs: Int?
    /// Where the level steps up or down by 4 dB or more, two seconds either side.
    public var boundariesMs: [Int]
    public var tempo: Tempo?
    /// Where the song first comes within 6 dB of its body level: the end of a quiet intro, or
    /// the sound start when it starts at full level.
    public var introEndMs: Int?

    public init(bodyDb: Double, gateDb: Double, soundStartMs: Int?, soundEndMs: Int?, outroStartMs: Int?,
                boundariesMs: [Int], tempo: Tempo?, introEndMs: Int? = nil) {
        self.bodyDb = bodyDb
        self.gateDb = gateDb
        self.soundStartMs = soundStartMs
        self.soundEndMs = soundEndMs
        self.outroStartMs = outroStartMs
        self.boundariesMs = boundariesMs
        self.tempo = tempo
        self.introEndMs = introEndMs
    }
}

/// An envelope with the features found in it.
public final class SectionAnalysis: @unchecked Sendable {
    public let envelope: SectionEnvelope
    public let features: SectionFeatures
    private let prefix: [Double]
    private let body: [Double]
    private let sound: [Double]
    private let outro: [Double]

    private init(envelope: SectionEnvelope, features: SectionFeatures, prefix: [Double], body: [Double], sound: [Double], outro: [Double]) {
        self.envelope = envelope
        self.features = features
        self.prefix = prefix
        self.body = body
        self.sound = sound
        self.outro = outro
    }

    /// The mean level from fromMs to toMs in dBFS, power averaged, over the part of that span the
    /// envelope covers; `silentDb` when it covers none.
    public func levelDb(_ fromMs: Double, _ toMs: Double) -> Double {
        let from = max(0, envelope.indexAt(fromMs))
        let to = min(envelope.size, envelope.indexAt(toMs))
        if to <= from { return Double(silentDb) }
        return Double(dbOf((prefix[to] - prefix[from]) / Double(to - from)))
    }

    /// The share of the hops from fromMs to toMs whose 400 ms level is at or above thresholdDb;
    /// 0 when the envelope covers none of them.
    public func shareAtLeast(_ fromMs: Double, _ toMs: Double, _ thresholdDb: Double) -> Double {
        let from = max(0, envelope.indexAt(fromMs))
        let to = min(envelope.size, envelope.indexAt(toMs))
        if to <= from { return 0 }
        var at = 0
        for i in from..<to where body[i] >= thresholdDb { at += 1 }
        return Double(at) / Double(to - from)
    }

    /// The same section measured against a body level known from elsewhere, such as the whole
    /// song heard as it played: the gate, sound times, outro and intro move with it; the
    /// boundaries and tempo stay.
    public func withBodyLevel(_ bodyDb: Double) -> SectionAnalysis {
        let levels = levelsFor(envelope, bodyDb, sound, outro)
        var moved = features
        moved.bodyDb = bodyDb
        moved.gateDb = levels.gate
        moved.soundStartMs = levels.soundStart
        moved.soundEndMs = levels.soundEnd
        moved.outroStartMs = levels.outroStart
        moved.introEndMs = levels.introEnd
        return SectionAnalysis(envelope: envelope, features: moved, prefix: prefix, body: body, sound: sound, outro: outro)
    }

    /// An envelope with features found elsewhere, such as a server that analyzed the whole song:
    /// the levels the planner reads come from the envelope, the rest from the features as they are.
    public static func fromFeatures(_ envelope: SectionEnvelope, _ features: SectionFeatures) -> SectionAnalysis {
        let hop = envelope.hopMs
        let prefix = prefixOf(powerOf(envelope.db))
        return SectionAnalysis(envelope: envelope, features: features, prefix: prefix,
                               body: smoothed(prefix, framesOf(bodyWindowMs, hop)),
                               sound: smoothed(prefix, framesOf(soundWindowMs, hop)),
                               outro: smoothed(prefix, framesOf(outroWindowMs, hop)))
    }

    /// Finds the features of an envelope. `tagBpm`, when the song's tags carry a tempo within
    /// `tagWithin` of double or half the tempo found, picks that octave; any other tag is
    /// ignored. `bodyLevelDb`, when known from elsewhere, replaces the body level measured here
    /// at `bodyPercentile`.
    public static func of(_ envelope: SectionEnvelope, tagBpm: Double? = nil, bodyLevelDb: Double? = nil,
                          bodyPercentile: Double = headBodyPercentile) -> SectionAnalysis {
        let hop = envelope.hopMs
        let prefix = prefixOf(powerOf(envelope.db))
        let body = smoothed(prefix, framesOf(bodyWindowMs, hop))
        let sound = smoothed(prefix, framesOf(soundWindowMs, hop))
        let outro = smoothed(prefix, framesOf(outroWindowMs, hop))
        let bodyDb = bodyLevelDb ?? bodyLevelOf(body, bodyPercentile)
        let levels = levelsFor(envelope, bodyDb, sound, outro)
        let features = SectionFeatures(
            bodyDb: bodyDb,
            gateDb: levels.gate,
            soundStartMs: levels.soundStart,
            soundEndMs: levels.soundEnd,
            outroStartMs: levels.outroStart,
            boundariesMs: boundaries(envelope, body),
            tempo: levels.soundStart == nil ? nil : tempoOf(envelope, levels.first, levels.last, tagBpm),
            introEndMs: levels.introEnd)
        return SectionAnalysis(envelope: envelope, features: features, prefix: prefix, body: body, sound: sound, outro: outro)
    }
}

/// The features of the start of a song.
public func analyzeHead(_ envelope: SectionEnvelope, tagBpm: Double? = nil) -> SectionAnalysis {
    SectionAnalysis.of(envelope, tagBpm: tagBpm, bodyPercentile: headBodyPercentile)
}

/// The features of the end of a song. Without a body level from the whole song, the tail's own
/// upper level stands in for it.
public func analyzeTail(_ envelope: SectionEnvelope, tagBpm: Double? = nil, bodyLevelDb: Double? = nil) -> SectionAnalysis {
    SectionAnalysis.of(envelope, tagBpm: tagBpm, bodyLevelDb: bodyLevelDb, bodyPercentile: tailBodyPercentile)
}

/// The body level of a whole envelope: the given percentile of its 400 ms level over the hops
/// above the silence gate, or nil when it is silent.
public func bodyLevelOf(_ envelope: SectionEnvelope, percentile: Double = headBodyPercentile) -> Double? {
    let body = smoothed(prefixOf(powerOf(envelope.db)), framesOf(bodyWindowMs, envelope.hopMs))
    let level = bodyLevelOf(body, percentile)
    return level > Double(silentDb) ? level : nil
}

/// The gate depends on the body level and the body level on the gate, so the body is measured
/// above the floor first, then above its own gate.
private func bodyLevelOf(_ body: [Double], _ percentile: Double) -> Double {
    var gate = silenceFloorDb
    var bodyDb = Double(silentDb)
    for _ in 0..<2 {
        guard let level = percentileAbove(body, gate, percentile) else { continue }
        bodyDb = level
        gate = max(silenceFloorDb, level - silenceBelowBodyDb)
    }
    return bodyDb
}

private struct Levels {
    let gate: Double
    let first: Int
    let last: Int
    let soundStart: Int?
    let soundEnd: Int?
    let outroStart: Int?
    let introEnd: Int?
}

private func levelsFor(_ envelope: SectionEnvelope, _ bodyDb: Double, _ sound: [Double], _ outro: [Double]) -> Levels {
    let gate = max(silenceFloorDb, bodyDb - silenceBelowBodyDb)
    var first = -1
    var last = -1
    for i in sound.indices where sound[i] > gate {
        if first < 0 { first = i }
        last = i
    }
    let soundStart = first < 0 ? nil : envelope.timeOf(first)
    let soundEnd = last < 0 ? nil : envelope.timeOf(last + 1)
    let outroStart = soundEnd.map { end -> Int in
        var lastLoud = -1
        for i in outro.indices where outro[i] >= bodyDb - outroBelowBodyDb { lastLoud = i }
        return min(envelope.timeOf(lastLoud + 1), end)
    }
    let introEnd: Int? = soundStart == nil ? nil : outro.firstIndex { $0 >= bodyDb - outroBelowBodyDb }.map { envelope.timeOf($0) }
    return Levels(gate: gate, first: first, last: last, soundStart: soundStart, soundEnd: soundEnd, outroStart: outroStart, introEnd: introEnd)
}

private func framesOf(_ ms: Int, _ hopMs: Int) -> Int { max(1, ms / hopMs) }

private func powerOf(_ db: [Float]) -> [Double] { db.map { pow(10.0, Double($0) / 10.0) } }

private func prefixOf(_ values: [Double]) -> [Double] {
    var prefix = [Double](repeating: 0, count: values.count + 1)
    for i in values.indices { prefix[i + 1] = prefix[i] + values[i] }
    return prefix
}

/// The level of each hop averaged, as power, with the hops up to half the window either side
/// (fewer at the edges).
private func smoothed(_ prefix: [Double], _ window: Int) -> [Double] {
    let size = prefix.count - 1
    let half = window / 2
    return (0..<max(0, size)).map { i in
        let from = max(0, i - half)
        let to = min(size, i + half + 1)
        return Double(dbOf((prefix[to] - prefix[from]) / Double(to - from)))
    }
}

/// A percentile of the levels above a gate, the lower of the two neighbors when it falls between
/// two, or nil when none is above it.
private func percentileAbove(_ levels: [Double], _ gate: Double, _ percentile: Double) -> Double? {
    let above = levels.filter { $0 > gate }.sorted()
    if above.isEmpty { return nil }
    return above[Int((percentile * Double(above.count - 1)).rounded(.down))]
}

/// Hops where the mean of the 400 ms level (in dB) over the two seconds after differs from the
/// two seconds before by `boundaryStepDb` or more, keeping only the strongest change within two
/// seconds either way. Earlier wins a tie.
private func boundaries(_ envelope: SectionEnvelope, _ body: [Double]) -> [Int] {
    let side = framesOf(boundarySideMs, envelope.hopMs)
    let size = envelope.size
    if size < 2 * side { return [] }
    let prefix = prefixOf(body)
    var change = [Double](repeating: 0, count: size)
    var i = side
    while i < size - side + 1 {
        if i >= size { break }
        let before = (prefix[i] - prefix[i - side]) / Double(side)
        let after = (prefix[i + side] - prefix[i]) / Double(side)
        change[i] = abs(after - before)
        i += 1
    }
    var found: [Int] = []
    for i in side..<size {
        let step = change[i]
        if step < boundaryStepDb { continue }
        var peak = true
        for j in max(0, i - side)...min(size - 1, i + side) {
            if j < i && change[j] >= step { peak = false; break }
            if j > i && change[j] > step { peak = false; break }
        }
        if peak && !found.contains(where: { abs($0 - i) < side }) { found.append(i) }
    }
    return found.map(envelope.timeOf)
}

/// The beat grid from the onsets: the beat period whose multiples carry the most
/// autocorrelation (pickPeriod) over the sounding hops; the beat phase with the largest onset sum
/// along the grid, fitted to the onset peaks; and of the four beats in a bar, the one whose beats
/// carry the most bass onset. The confidence is the period's score; the grid is steady when each
/// half of the sounding hops picks the same period to within `steadyWithin`, after halving or
/// doubling. The consistency is measured over the sounding hops first to last. A tag tempo only
/// chooses among the grid's own octaves: when half or double the found tempo is within
/// `tagWithin` of the tag, the grid is redone at that octave; any other tag is ignored.
private func tempoOf(_ envelope: SectionEnvelope, _ first: Int, _ last: Int, _ tagBpm: Double?) -> Tempo? {
    let onset = envelope.onset
    let hop = Double(envelope.hopMs)
    if first < 0 || last <= first { return nil }
    let sounding = Array(onset[first...last])
    guard let (picked, confidence) = pickPeriod(sounding, hop) else { return nil }
    let middle = sounding.count / 2
    let steady = [Array(sounding[0..<middle]), Array(sounding[middle...])].allSatisfy { half in
        guard let p = pickPeriod(half, hop) else { return false }
        return abs(foldTempoRatio(p.0 / picked) - 1) <= steadyWithin
    }
    let found = gridOf(envelope, first, last, picked, confidence, steady)
    guard let tagBpm, tagBpm > 0 else { return found }
    if abs(found.bpm / tagBpm - 1) <= tagWithin { return found }
    for factor in [0.5, 2.0] where abs(found.bpm * factor / tagBpm - 1) <= tagWithin {
        return gridOf(envelope, first, last, picked / factor, confidence, steady)
    }
    return found
}

/// The grid at a beat period of `start` hops, fitted to the onset peaks.
private func gridOf(_ envelope: SectionEnvelope, _ first: Int, _ last: Int, _ start: Double, _ confidence: Double, _ steady: Bool) -> Tempo {
    let onset = envelope.onset
    let size = onset.count
    let hop = Double(envelope.hopMs)
    var period = start

    var bestPhase = 0
    var best = -1.0
    for p in 0..<Int(period.rounded(.up)) {
        let sum = combMean(onset, Double(p), period, 0, 1)
        if sum > best {
            best = sum
            bestPhase = p
        }
    }
    var phase = Double(bestPhase)

    // Fit the grid to the onset peaks the beats land on, which corrects a period read off whole
    // hops: first to the peaks within a quarter beat, then twice to those within beatHitMs.
    let peaks = onsetPeaks(envelope, first, last)
    for pass in 0..<3 {
        let reach = pass == 0 ? period / 4 : beatHitMs / hop
        guard let fit = fitGrid(peaks, phase, period, size, reach) else { continue }
        period = fit.1
        phase = fit.0 - (fit.0 / period).rounded(.down) * period
    }

    var bar = 0
    var bestBass = -1.0
    for q in 0..<beatsPerBar {
        let sum = combMean(envelope.lowOnset, phase, period, q, beatsPerBar)
        if sum > bestBass {
            bestBass = sum
            bar = q
        }
    }

    let beatMs = period * hop
    let firstBeat = Double(envelope.startMs) + phase * hop
    return Tempo(bpm: 60_000.0 / beatMs, confidence: confidence,
                 consistency: consistencyOf(envelope, peaks, first, last, firstBeat, beatMs),
                 beatMs: beatMs, firstBeatMs: firstBeat, downbeatMs: firstBeat + Double(bar) * beatMs, steady: steady)
}

/// The beat period, in hops, that the onsets repeat at most, and its score. The onsets lose their
/// local mean (the mean over `onsetTrendMs` around each hop), keeping rises only, then their
/// overall mean; their autocorrelation, as a share of its value at lag 0, is read between whole
/// lags on straight lines. Each period from `fastestBpm` to `slowestBpm`, in steps of
/// `periodStep` hops, scores the autocorrelation at one, two, four and eight periods (beat, half
/// bar, bar, two bars) plus `halfBeatWeight` of it at half a period. The first best period wins.
/// Nil when there are too few hops, the onsets hardly move, or nothing repeats.
private func pickPeriod(_ onset: [Float], _ hopMs: Double) -> (Double, Double)? {
    let size = onset.count
    let perMinute = 60_000.0 / hopMs
    let shortest = perMinute / fastestBpm
    let longest = perMinute / slowestBpm
    if size < 2 * (Int(longest.rounded(.up)) + 1) { return nil }
    let reach = Int(roundHalfUp(onsetTrendMs / hopMs / 2))
    var prefix = [Double](repeating: 0, count: size + 1)
    for i in 0..<size { prefix[i + 1] = prefix[i] + Double(onset[i]) }
    var rises = (0..<size).map { i -> Double in
        let from = max(0, i - reach)
        let to = min(size, i + reach + 1)
        let trend = (prefix[to] - prefix[from]) / Double(to - from)
        return max(0, Double(onset[i]) - trend)
    }
    let mean = rises.reduce(0, +) / Double(size)
    for i in 0..<size { rises[i] -= mean }
    let most = min(size - 1, Int((harmonics.last! * longest).rounded(.up)) + 1)
    var r = [Double](repeating: 0, count: most + 1)
    rises.withUnsafeBufferPointer { x in
        for lag in 0...most {
            var sum = 0.0
            for i in 0..<(size - lag) { sum += x[i] * x[i + lag] }
            r[lag] = sum / Double(size - lag)
        }
    }
    if r[0] < faintestBeat { return nil }
    let zero = r[0]
    for lag in 0...most { r[lag] /= zero }
    func at(_ lag: Double) -> Double {
        let whole = Int(lag.rounded(.down))
        if whole + 1 > most { return 0 }
        let part = lag - Double(whole)
        return r[whole] * (1 - part) + r[whole + 1] * part
    }
    var bestPeriod = shortest
    var bestScore = -Double.infinity
    var k = 0
    while true {
        let period = shortest + Double(k) * periodStep
        if period > longest + 1e-9 { break }
        var score = halfBeatWeight * at(period / 2)
        for m in harmonics { score += at(m * period) }
        if score > bestScore {
            bestScore = score
            bestPeriod = period
        }
        k += 1
    }
    return bestScore > 0 ? (bestPeriod, bestScore) : nil
}

/// The onset peaks from hop `first` to hop `last`, as hop indexes: a hop above the hop before and
/// at least the hop after, reaching `faintestPeak` and one standard deviation above the mean
/// onset of those hops.
private func onsetPeaks(_ envelope: SectionEnvelope, _ first: Int, _ last: Int) -> [Int] {
    let onset = envelope.onset
    if last <= first { return [] }
    var sum = 0.0
    var squares = 0.0
    for i in first...last {
        sum += Double(onset[i])
        squares += Double(onset[i]) * Double(onset[i])
    }
    let n = Double(last - first + 1)
    let mean = sum / n
    let spread = max(0, squares / n - mean * mean).squareRoot()
    let threshold = max(faintestPeak, mean + spread)
    var peaks: [Int] = []
    let low = max(first, 1), high = min(last, onset.count - 2)
    if low <= high {
        for i in low...high {
            let x = onset[i]
            if Double(x) >= threshold && x > onset[i - 1] && x >= onset[i + 1] { peaks.append(i) }
        }
    }
    return peaks
}

/// A least-squares line through the peak nearest each beat of the grid (within `reach` hops; the
/// earlier of two equally near): the fitted phase and period in hops, or nil when fewer than 8
/// beats, or under half of them, find a peak.
private func fitGrid(_ peaks: [Int], _ phase: Double, _ period: Double, _ size: Int, _ reach: Double) -> (Double, Double)? {
    var count = 0
    var beats = 0
    var sn = 0.0, st = 0.0, snn = 0.0, snt = 0.0
    var at = 0
    var n = 0
    while true {
        let beat = phase + Double(n) * period
        if beat >= Double(size) { break }
        beats += 1
        while at < peaks.count && Double(peaks[at]) < beat - reach { at += 1 }
        var nearest = -1
        var j = at
        while j < peaks.count && Double(peaks[j]) <= beat + reach {
            if nearest < 0 || abs(Double(peaks[j]) - beat) < abs(Double(peaks[nearest]) - beat) { nearest = j }
            j += 1
        }
        if nearest >= 0 {
            let t = Double(peaks[nearest])
            count += 1
            sn += Double(n)
            st += t
            snn += Double(n) * Double(n)
            snt += Double(n) * t
        }
        n += 1
    }
    if count < 8 || count * 2 < beats { return nil }
    let d = Double(count) * snn - sn * sn
    if d <= 0 { return nil }
    let slope = (Double(count) * snt - sn * st) / d
    if slope <= 0 { return nil }
    return ((st - slope * sn) / Double(count), slope)
}

/// The share of the grid's beats from hop `first` to hop `last` that fall within `beatHitMs` of
/// an onset peak.
private func consistencyOf(_ envelope: SectionEnvelope, _ peaks: [Int], _ first: Int, _ last: Int, _ firstBeat: Double, _ beatMs: Double) -> Double {
    let beats = gridBetween(firstBeat, beatMs, Double(envelope.timeOf(first)), Double(envelope.timeOf(last)))
    if beats.isEmpty { return 0 }
    var hits = 0
    var at = 0
    for beat in beats {
        while at < peaks.count && Double(envelope.timeOf(peaks[at])) < beat - beatHitMs { at += 1 }
        if at < peaks.count && abs(Double(envelope.timeOf(peaks[at])) - beat) <= beatHitMs { hits += 1 }
    }
    return Double(hits) / Double(beats.count)
}

/// The mean of values at phase + n * period (rounded to a hop), taking every `every`th beat from
/// beat `from`.
private func combMean(_ values: [Float], _ phase: Double, _ period: Double, _ from: Int, _ every: Int) -> Double {
    var sum = 0.0
    var count = 0
    var n = from
    while true {
        let i = Int(roundHalfUp(phase + Double(n) * period))
        if i >= values.count { break }
        sum += Double(values[i])
        count += 1
        n += every
    }
    return count == 0 ? 0 : sum / Double(count)
}

/// Rounds halves up, the same in every language.
func roundHalfUp(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

/// Listens to a song as it plays and keeps its envelope, so the whole song's body level and tempo
/// are known when the next transition is planned. Feed it the same samples the listener hears;
/// start it again for each song.
public final class LiveTap {
    private let builder: EnvelopeBuilder

    public init(sampleRate: Int, channels: Int) {
        builder = EnvelopeBuilder(sampleRate: sampleRate, channels: channels, startMs: 0)
    }

    public func push(_ samples: UnsafeBufferPointer<Float>) { builder.push(samples) }

    public func push(_ samples: [Float], offset: Int = 0, length: Int? = nil) { builder.push(samples, offset: offset, length: length) }

    /// How much has been heard, in milliseconds.
    public func heardMs() -> Int { builder.heardMs }

    /// The body level of everything heard, or nil while it is all silence.
    public func bodyLevelDb() -> Double? { bodyLevelOf(builder.build()) }

    /// The tempo of everything heard when it is trusted, else nil.
    public func tempoPrior(tagBpm: Double? = nil) -> Double? {
        guard let tempo = SectionAnalysis.of(builder.build(), tagBpm: tagBpm).features.tempo, tempo.confident else { return nil }
        return tempo.bpm
    }
}
