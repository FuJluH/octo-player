import Foundation
@testable import OctoKit

/// A made-up song built from layers, rendered the same way by every engine's tests from
/// automix-vectors.json. Each layer sounds from fromMs to toMs with its level moving in a
/// straight line (in dB) from db to endDb.
///
/// tone:  amplitude * sin(2 pi hz n / rate), n the sample index in the song.
/// pulse: a hit at firstMs + j * every * 60000 / bpm for every whole j with the hit inside
///        [fromMs, toMs); each hit adds amplitude(hit time) * exp(-d / decayMs) * sin(2 pi hz d / 1000)
///        for d = sample time minus hit time in ms, 0 <= d < 8 * decayMs.
/// The sample time of sample n is n * 1000 / rate ms. Every channel carries the same signal.
struct SongLayer: Equatable {
    var kind: String
    var fromMs: Double
    var toMs: Double
    var hz: Double
    var db: Double
    var endDb: Double
    var bpm: Double = 0
    var firstMs: Double = 0
    var every: Int = 1
    var decayMs: Double = 0

    init(_ kind: String, _ fromMs: Double, _ toMs: Double, hz: Double, db: Double, endDb: Double? = nil, bpm: Double = 0,
         firstMs: Double = 0, every: Int = 1, decayMs: Double = 0) {
        self.kind = kind
        self.fromMs = fromMs
        self.toMs = toMs
        self.hz = hz
        self.db = db
        self.endDb = endDb ?? db
        self.bpm = bpm
        self.firstMs = firstMs
        self.every = every
        self.decayMs = decayMs
    }

    func amplitudeAt(_ ms: Double) -> Double {
        let u = toMs > fromMs ? min(max((ms - fromMs) / (toMs - fromMs), 0), 1) : 0
        return pow(10, (db + (endDb - db) * u) / 20)
    }
}

struct SyntheticSong {
    var rate: Int
    var channels: Int
    var lengthMs: Int
    var layers: [SongLayer]

    /// Mono samples for song times [fromMs, toMs).
    func renderMono(_ fromMs: Double, _ toMs: Double) -> [Float] {
        let r = Double(rate)
        let first = Int((fromMs * r / 1000).rounded(.down))
        let end = Int((min(toMs, Double(lengthMs)) * r / 1000).rounded(.down))
        var out = [Double](repeating: 0, count: max(0, end - first))
        for layer in layers {
            switch layer.kind {
            case "tone":
                let from = max(first, Int((layer.fromMs * r / 1000).rounded(.up)))
                let to = min(end, Int((layer.toMs * r / 1000).rounded(.up)))
                if from < to {
                    for n in from..<to {
                        let ms = Double(n) * 1000.0 / r
                        out[n - first] += layer.amplitudeAt(ms) * sin(2 * Double.pi * layer.hz * Double(n) / r)
                    }
                }
            case "pulse":
                let gap = Double(layer.every) * 60_000.0 / layer.bpm
                var j = Int(((layer.fromMs - layer.firstMs) / gap).rounded(.up))
                while true {
                    let hit = layer.firstMs + Double(j) * gap
                    if hit >= layer.toMs { break }
                    j += 1
                    if hit < layer.fromMs { continue }
                    let tail = 8 * layer.decayMs
                    if hit + tail < fromMs || hit >= toMs { continue }
                    let amplitude = layer.amplitudeAt(hit)
                    let from = max(first, Int((hit * r / 1000).rounded(.up)))
                    let to = min(end, Int(((hit + tail) * r / 1000).rounded(.up)))
                    if from >= to { continue }
                    for n in from..<to {
                        let d = Double(n) * 1000.0 / r - hit
                        if d < 0 || d >= tail { continue }
                        out[n - first] += amplitude * exp(-d / layer.decayMs) * sin(2 * Double.pi * layer.hz * d / 1000)
                    }
                }
            default:
                fatalError("unknown layer \(layer.kind)")
            }
        }
        return out.map { Float($0) }
    }

    /// The envelope of [fromMs, toMs), fed to the builder in blocks of `block` interleaved samples
    /// so the streaming path is exercised.
    func envelope(_ fromMs: Double, _ toMs: Double, block: Int = 4_093) -> SectionEnvelope {
        let mono = renderMono(fromMs, toMs)
        let interleaved = channels == 1 ? mono : (0..<(mono.count * channels)).map { mono[$0 / channels] }
        let startMs = Int((fromMs * Double(rate) / 1000).rounded(.down)) * 1000 / rate
        let builder = EnvelopeBuilder(sampleRate: rate, channels: channels, startMs: startMs)
        var at = 0
        while at < interleaved.count {
            let length = min(block, interleaved.count - at)
            builder.push(interleaved, offset: at, length: length)
            at += length
        }
        return builder.build()
    }

    /// The last 60 s and the first 30 s, as the player scouts them.
    func tail() -> SectionAnalysis { analyzeTail(envelope(max(0, Double(lengthMs) - 60_000), Double(lengthMs))) }

    func head() -> SectionAnalysis { analyzeHead(envelope(0, min(30_000, Double(lengthMs)))) }
}

/// The made-up songs and song pairs the automix tests and automix-vectors.json share.
enum AutomixCases {
    private static func pad(_ fromMs: Double, _ toMs: Double, _ db: Double, _ endDb: Double? = nil) -> [SongLayer] {
        let end = endDb ?? db
        return [
            SongLayer("tone", fromMs, toMs, hz: 300, db: db, endDb: end),
            SongLayer("tone", fromMs, toMs, hz: 100, db: db - 3, endDb: end - 3),
        ]
    }

    /// A kick on every bar and a click on every beat over a quiet pad.
    private static func beat(_ lengthMs: Double, _ bpm: Double, _ firstMs: Double) -> [SongLayer] {
        [
            SongLayer("tone", firstMs, lengthMs, hz: 300, db: -26),
            SongLayer("pulse", firstMs, lengthMs, hz: 60, db: -6, bpm: bpm, firstMs: firstMs, every: 4, decayMs: 80),
            SongLayer("pulse", firstMs, lengthMs, hz: 2_000, db: -16, bpm: bpm, firstMs: firstMs, every: 1, decayMs: 10),
        ]
    }

    static let songNames = ["silence-tail", "fade-out", "hot-end", "beat-120", "beat-120-b", "beat-100", "beat-118", "beat-128",
                            "plain-b", "quiet-intro"]

    static let songs: [String: SyntheticSong] = [
        // 8 s of silence after the music stops.
        "silence-tail": SyntheticSong(rate: 44_100, channels: 2, lengthMs: 200_000, layers: pad(0, 192_000, -14)),
        // Full level until 180 s, then a 40 s fade to nothing.
        "fade-out": SyntheticSong(rate: 48_000, channels: 1, lengthMs: 220_000, layers: pad(0, 180_000, -14) + pad(180_000, 220_000, -14, -74)),
        // Full level to the last sample.
        "hot-end": SyntheticSong(rate: 44_100, channels: 2, lengthMs: 200_000, layers: pad(0, 200_000, -14)),
        "beat-120": SyntheticSong(rate: 48_000, channels: 2, lengthMs: 200_000, layers: beat(200_000, 120, 500)),
        "beat-120-b": SyntheticSong(rate: 22_050, channels: 1, lengthMs: 180_000, layers: beat(180_000, 120, 1_000)),
        "beat-100": SyntheticSong(rate: 44_100, channels: 1, lengthMs: 180_000, layers: beat(180_000, 100, 600)),
        "beat-118": SyntheticSong(rate: 44_100, channels: 1, lengthMs: 180_000, layers: beat(180_000, 118, 400)),
        "beat-128": SyntheticSong(rate: 44_100, channels: 1, lengthMs: 60_000, layers: beat(60_000, 128, 300)),
        // 1.5 s of silence, then full level.
        "plain-b": SyntheticSong(rate: 44_100, channels: 2, lengthMs: 180_000, layers: pad(1_500, 180_000, -14)),
        // 6 s of a quiet pad 24 dB under the body, then full level.
        "quiet-intro": SyntheticSong(rate: 44_100, channels: 2, lengthMs: 180_000, layers: pad(0, 6_000, -38) + pad(6_000, 180_000, -14)),
    ]

    struct Pair {
        var name: String
        var a: String
        var b: String
        var settings: AutomixSettings
        var sameAlbumInOrder = false
        var context = TransitionContext()
        var tailMissing = false
        var headMissing = false

        var current: FadeSong { FadeSong(albumId: sameAlbumInOrder ? "album" : "a", albumOrder: 1, durationMs: songs[a]!.lengthMs) }
        var next: FadeSong { FadeSong(albumId: sameAlbumInOrder ? "album" : "b", albumOrder: 2, durationMs: songs[b]!.lengthMs) }
    }

    private static let eight = AutomixSettings(maxOverlapMs: 8_000)

    static let pairs: [Pair] = [
        Pair(name: "trailing-silence", a: "silence-tail", b: "plain-b", settings: eight),
        Pair(name: "fade-out", a: "fade-out", b: "plain-b", settings: eight),
        Pair(name: "hot-end", a: "hot-end", b: "plain-b", settings: eight),
        Pair(name: "quiet-intro", a: "hot-end", b: "quiet-intro", settings: eight),
        Pair(name: "quiet-intro-capped", a: "hot-end", b: "quiet-intro", settings: AutomixSettings(maxOverlapMs: 4_000)),
        Pair(name: "same-tempo", a: "beat-120", b: "beat-120-b", settings: eight),
        Pair(name: "same-tempo-long", a: "beat-120", b: "beat-120-b", settings: AutomixSettings(maxOverlapMs: 16_000)),
        Pair(name: "same-tempo-short", a: "beat-120", b: "beat-120-b", settings: AutomixSettings(maxOverlapMs: 5_000)),
        Pair(name: "tempo-clash", a: "beat-120", b: "beat-100", settings: eight),
        Pair(name: "beat-match", a: "beat-120", b: "beat-118", settings: AutomixSettings(maxOverlapMs: 8_000, beatMatch: true)),
        Pair(name: "beat-match-off", a: "beat-120", b: "beat-118", settings: eight),
        Pair(name: "no-sweeps", a: "beat-120", b: "beat-120-b", settings: AutomixSettings(maxOverlapMs: 8_000, filterSweeps: false)),
        Pair(name: "no-analysis", a: "hot-end", b: "plain-b", settings: eight, tailMissing: true, headMissing: true),
        Pair(name: "no-tail", a: "fade-out", b: "plain-b", settings: eight, tailMissing: true),
        Pair(name: "no-head", a: "beat-120", b: "plain-b", settings: eight, headMissing: true),
        Pair(name: "smart-off", a: "beat-120", b: "beat-120-b", settings: AutomixSettings(maxOverlapMs: 8_000, smart: false)),
        Pair(name: "album-in-order", a: "beat-120", b: "beat-120-b", settings: eight, sameAlbumInOrder: true),
        Pair(name: "repeat-one", a: "beat-120", b: "beat-120-b", settings: eight, context: TransitionContext(repeatOne: true)),
        Pair(name: "stop-at-end", a: "beat-120", b: "beat-120-b", settings: eight, context: TransitionContext(stopAtEndOfSong: true)),
        Pair(name: "crossfade-off", a: "beat-120", b: "beat-120-b", settings: AutomixSettings(maxOverlapMs: 0)),
        Pair(name: "classical", a: "beat-120", b: "beat-120-b", settings: eight, context: TransitionContext(nextGenre: "Classical; Baroque")),
        Pair(name: "podcast", a: "hot-end", b: "plain-b", settings: eight, context: TransitionContext(currentGenre: "Podcast")),
        Pair(name: "pace", a: "beat-120", b: "beat-120-b", settings: AutomixSettings(maxOverlapMs: 8_000, beatMatch: true),
             context: TransitionContext(pace: 1.25)),
        Pair(name: "skip-silence", a: "beat-120", b: "beat-118", settings: AutomixSettings(maxOverlapMs: 8_000, beatMatch: true),
             context: TransitionContext(skipSilence: true)),
        Pair(name: "late", a: "beat-120", b: "beat-120-b", settings: eight, context: TransitionContext(nowMs: 190_000)),
        Pair(name: "late-short", a: "beat-120", b: "beat-120-b", settings: eight, context: TransitionContext(nowMs: 197_000)),
        Pair(name: "too-late", a: "beat-120", b: "beat-120-b", settings: eight, context: TransitionContext(nowMs: 199_500)),
        Pair(name: "pre-roll", a: "fade-out", b: "plain-b", settings: eight, context: TransitionContext(nowMs: 183_000)),
        Pair(name: "seeked-forward", a: "fade-out", b: "plain-b", settings: eight, context: TransitionContext(nowMs: 170_000, playedMs: 60_000)),
        Pair(name: "whole-song-level", a: "fade-out", b: "plain-b", settings: eight, context: TransitionContext(bodyLevelDb: -24)),
        Pair(name: "tempo-prior", a: "beat-120", b: "beat-120-b", settings: eight, context: TransitionContext(tempoPrior: 60)),
        Pair(name: "tempo-prior-off", a: "beat-120", b: "beat-120-b", settings: eight, context: TransitionContext(tempoPrior: 100)),
    ]

    private static let cache = AnalysisCache()

    static func tail(_ song: String) -> SectionAnalysis { cache.get("tail:\(song)") { songs[song]!.tail() } }

    static func head(_ song: String) -> SectionAnalysis { cache.get("head:\(song)") { songs[song]!.head() } }

    static func plan(_ pair: Pair) -> TransitionPlan {
        planTransition(current: pair.current, next: pair.next, tail: pair.tailMissing ? nil : tail(pair.a),
                       head: pair.headMissing ? nil : head(pair.b), settings: pair.settings, context: pair.context)
    }

    static func pair(_ name: String) -> Pair { pairs.first { $0.name == name }! }
}

/// Analyses worked out once and shared by every test that needs them.
final class AnalysisCache: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: SectionAnalysis] = [:]

    func get(_ key: String, _ make: () -> SectionAnalysis) -> SectionAnalysis {
        if let found = lock.withLock({ values[key] }) { return found }
        let made = make()
        return lock.withLock {
            if let found = values[key] { return found }
            values[key] = made
            return made
        }
    }
}
