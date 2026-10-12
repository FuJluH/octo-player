import Foundation

/// One envelope value per this many milliseconds of sound.
public let envelopeHopMs = 10

/// The level written for a hop with no sound at all, in dBFS.
public let silentDb: Float = -100

/// Where the bass band of the envelope ends: kick drums and bass lines.
public let bassCutoffHz = 150.0

/// Where the middle band of the onsets ends and the high band begins.
public let trebleFromHz = 2_500.0

/// The onsets look at the last this many samples at the end of every hop.
public let onsetFftSize = 1024

/// Magnitudes are compressed as ln(1 + onsetCompression * magnitude), with a full-scale sine
/// reading magnitude 1 in its bin.
public let onsetCompression = 100.0

/// Loudness over time for one stretch of a song, one value per hop. `db` is the whole band,
/// `lowDb` only the sound below `bassCutoffHz`, both as RMS in dBFS. `onset` is the spectral
/// flux: for each of three bands (below `bassCutoffHz`, up to `trebleFromHz`, and above), the
/// mean rise of the compressed FFT magnitudes since the hop before, rises only, added up.
/// `lowOnset` is the bass band's part of it. Onsets peak on drum hits and note starts. Times are
/// song times: hop i covers startMs + i * hopMs onwards.
public struct SectionEnvelope: Sendable {
    public let startMs: Int
    public let hopMs: Int
    public let db: [Float]
    public let lowDb: [Float]
    public let onset: [Float]
    public let lowOnset: [Float]

    public init(startMs: Int, hopMs: Int, db: [Float], lowDb: [Float], onset: [Float], lowOnset: [Float]) {
        precondition(hopMs > 0, "hopMs must be positive")
        precondition(db.count == lowDb.count && db.count == onset.count && db.count == lowOnset.count,
                     "the envelope's arrays must be the same length")
        self.startMs = startMs
        self.hopMs = hopMs
        self.db = db
        self.lowDb = lowDb
        self.onset = onset
        self.lowOnset = lowOnset
    }

    public var size: Int { db.count }

    public var endMs: Int { startMs + size * hopMs }

    public func timeOf(_ index: Int) -> Int { startMs + index * hopMs }

    /// The hop that holds a song time; below 0 or at size and above when the time lies outside
    /// the envelope.
    public func indexAt(_ ms: Double) -> Int { Int(((ms - Double(startMs)) / Double(hopMs)).rounded(.down)) }
}

/// Builds a SectionEnvelope from decoded sound fed to it in blocks of any size, so a decoder can
/// RMS level in dBFS from a mean square, never below `silentDb`.
func dbOf(_ meanSquare: Double) -> Float {
    meanSquare <= 1e-10 ? silentDb : Float(max(Double(silentDb), 10 * log10(meanSquare)))
}
