import Foundation

/// Builds a SectionEnvelope from decoded sound fed to it in blocks of any size, so a decoder can
/// hand over each block as it comes out. Samples are interleaved when there is more than one
/// channel and are summed to mono. A block may end in the middle of a frame; the rest of that
/// frame is taken from the next block. Each hop's onsets come from a Hann-windowed FFT of the
/// last `onsetFftSize` mono samples up to the hop's end (zeros before the first sample).
public final class EnvelopeBuilder {
    private let sampleRate: Int
    private let channels: Int
    private let startMs: Int
    private let hopMs: Int

    /// The bass band's low-pass, run inline: y = b0 x + b1 x1 + b2 x2 - a1 y1 - a2 y2.
    private let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    private var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    private var channel = 0
    private var frameSum = 0.0

    /// Frames taken so far, and the frame at which the current hop ends: hop k covers frames
    /// k * rate * hop / 1000 up to (k + 1) * rate * hop / 1000.
    private var frame = 0
    private var hop = 0
    private var hopEnd = 0
    private var hopStart = 0
    private var sumSquares = 0.0
    private var lowSquares = 0.0

    /// The last `onsetFftSize` mono samples, oldest at `ringAt`.
    private let ring: UnsafeMutablePointer<Double>
    private var ringAt = 0
    private let window: UnsafeMutablePointer<Double>
    private let fft = RealFft(size: onsetFftSize)
    private let frameIn: UnsafeMutablePointer<Double>
    private let magnitudes: UnsafeMutablePointer<Double>
    private var compressed: UnsafeMutablePointer<Double>
    private var lastCompressed: UnsafeMutablePointer<Double>

    /// Bins 1 until lowEnd are the bass band, lowEnd until highFrom the middle band, highFrom up
    /// to size / 2 the high band.
    private let lowEnd: Int
    private let highFrom: Int

    private var db: [Float] = []
    private var lowDb: [Float] = []
    private var onset: [Float] = []
    private var lowOnset: [Float] = []

    public init(sampleRate: Int, channels: Int, startMs: Int, hopMs: Int = envelopeHopMs) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        precondition(channels > 0, "channels must be positive")
        precondition(hopMs > 0, "hopMs must be positive")
        self.sampleRate = sampleRate
        self.channels = channels
        self.startMs = startMs
        self.hopMs = hopMs
        let bass = Biquad.lowPass(sampleRate: sampleRate, hz: bassCutoffHz)
        b0 = bass.b0
        b1 = bass.b1
        b2 = bass.b2
        a1 = bass.a1
        a2 = bass.a2
        let bins = onsetFftSize / 2 + 1
        ring = .allocate(capacity: onsetFftSize)
        ring.initialize(repeating: 0, count: onsetFftSize)
        window = .allocate(capacity: onsetFftSize)
        for i in 0..<onsetFftSize { window[i] = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(onsetFftSize)) }
        frameIn = .allocate(capacity: onsetFftSize)
        frameIn.initialize(repeating: 0, count: onsetFftSize)
        magnitudes = .allocate(capacity: bins)
        magnitudes.initialize(repeating: 0, count: bins)
        compressed = .allocate(capacity: bins)
        compressed.initialize(repeating: 0, count: bins)
        lastCompressed = .allocate(capacity: bins)
        lastCompressed.initialize(repeating: 0, count: bins)
        let binHz = Double(sampleRate) / Double(onsetFftSize)
        func bandEdge(_ hz: Double) -> Int { min(bins, max(1, Int((hz / binHz).rounded(.up)))) }
        lowEnd = bandEdge(bassCutoffHz)
        highFrom = max(lowEnd, bandEdge(trebleFromHz))
        hopEnd = hopEndOf(0)
        db.reserveCapacity(1024)
        lowDb.reserveCapacity(1024)
        onset.reserveCapacity(1024)
        lowOnset.reserveCapacity(1024)
    }

    deinit {
        ring.deallocate()
        window.deallocate()
        frameIn.deallocate()
        magnitudes.deallocate()
        compressed.deallocate()
        lastCompressed.deallocate()
    }

    private func hopEndOf(_ k: Int) -> Int { (k + 1) * sampleRate * hopMs / 1000 }

    /// Samples between -1 and 1. The running state is held in locals through the block, which
    /// keeps the loop quick in any build.
    public func push(_ samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress else { return }
        let count = samples.count
        let channels = channels, ring = ring, size = onsetFftSize
        let b0 = b0, b1 = b1, b2 = b2, a1 = a1, a2 = a2
        var x1 = x1, x2 = x2, y1 = y1, y2 = y2
        var channel = channel, frameSum = frameSum, frame = frame, hopEnd = hopEnd
        var sumSquares = sumSquares, lowSquares = lowSquares, ringAt = ringAt
        let divisor = Double(channels)
        var i = 0
        while i < count {
            frameSum += Double(base[i])
            i += 1
            channel += 1
            if channel != channels { continue }
            let x = frameSum / divisor
            frameSum = 0
            channel = 0
            let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1
            x1 = x
            y2 = y1
            y1 = y
            sumSquares += x * x
            lowSquares += y * y
            ring[ringAt] = x
            ringAt = ringAt == size - 1 ? 0 : ringAt + 1
            frame += 1
            if frame == hopEnd {
                self.ringAt = ringAt
                self.frame = frame
                self.sumSquares = sumSquares
                self.lowSquares = lowSquares
                closeHop()
                sumSquares = 0
                lowSquares = 0
                hopEnd = self.hopEnd
            }
        }
        self.x1 = x1
        self.x2 = x2
        self.y1 = y1
        self.y2 = y2
        self.channel = channel
        self.frameSum = frameSum
        self.frame = frame
        self.sumSquares = sumSquares
        self.lowSquares = lowSquares
        self.ringAt = ringAt
    }

    public func push(_ samples: [Float], offset: Int = 0, length: Int? = nil) {
        let count = length ?? samples.count - offset
        samples.withUnsafeBufferPointer { push(UnsafeBufferPointer(rebasing: $0[offset..<(offset + count)])) }
    }

    /// 16-bit samples, as some decoders give them.
    public func push(_ samples: [Int16], offset: Int = 0, length: Int? = nil) {
        let count = length ?? samples.count - offset
        samples.withUnsafeBufferPointer { buffer in
            for i in offset..<(offset + count) {
                frameSum += Double(buffer[i]) / 32768.0
                channel += 1
                if channel == channels { takeFrame() }
            }
        }
    }

    @inline(__always) private func takeFrame() {
        let x = frameSum / Double(channels)
        frameSum = 0
        channel = 0
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        sumSquares += x * x
        lowSquares += y * y
        ring[ringAt] = x
        ringAt = ringAt == onsetFftSize - 1 ? 0 : ringAt + 1
        frame += 1
        if frame == hopEnd { closeHop() }
    }

    private func closeHop() {
        let frames = Double(frame - hopStart)
        let ring = ring, window = window, frameIn = frameIn, magnitudes = magnitudes, ringAt = ringAt
        let size = onsetFftSize
        for i in 0..<size {
            let at = ringAt + i
            frameIn[i] = ring[at >= size ? at - size : at] * window[i]
        }
        fft.magnitudes(frameIn, magnitudes)
        let scale = 4.0 / Double(size)
        let now = compressed, before = lastCompressed
        for k in 0...(size / 2) { now[k] = log(1 + onsetCompression * magnitudes[k] * scale) }
        let first = db.isEmpty
        let bassFlux = first ? 0.0 : Self.flux(now, before, 1, lowEnd)
        let allFlux = first ? 0.0 : bassFlux + Self.flux(now, before, lowEnd, highFrom) + Self.flux(now, before, highFrom, size / 2 + 1)
        lastCompressed = now
        compressed = before

        db.append(dbOf(sumSquares / frames))
        lowDb.append(dbOf(lowSquares / frames))
        onset.append(Float(allFlux))
        lowOnset.append(Float(bassFlux))
        sumSquares = 0
        lowSquares = 0
        hopStart = frame
        hop += 1
        hopEnd = hopEndOf(hop)
    }

    /// The mean rise of the compressed magnitudes over bins from until to.
    private static func flux(_ now: UnsafeMutablePointer<Double>, _ before: UnsafeMutablePointer<Double>, _ from: Int, _ to: Int) -> Double {
        if to <= from { return 0 }
        var sum = 0.0
        for k in from..<to {
            let rise = now[k] - before[k]
            if rise > 0 { sum += rise }
        }
        return sum / Double(to - from)
    }

    /// How much sound the whole hops fed so far cover, in milliseconds.
    public var heardMs: Int { db.count * hopMs }

    /// The envelope of every whole hop fed so far; a last partial hop is left out.
    public func build() -> SectionEnvelope {
        SectionEnvelope(startMs: startMs, hopMs: hopMs, db: db, lowDb: lowDb, onset: onset, lowOnset: lowOnset)
    }
}
