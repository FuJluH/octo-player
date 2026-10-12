import Foundation

/// Shortens quiet stretches inside a song: a run below the quiet level that lasts past 100 ms
/// keeps a fifth of its length, at most two seconds; the rest is left out.
public final class SilenceSkipper {
    private let threshold: Float = 1024.0 / 32768.0
    private let shortest: Int
    private let longestKept: Int
    private var run = 0
    private var kept = 0

    public init(sampleRate: Double) {
        shortest = Int(sampleRate * 0.1)
        longestKept = Int(sampleRate * 2)
    }

    public func reset() {
        run = 0
        kept = 0
    }

    /// The ranges of frames to keep from a block.
    public func keep(_ buffers: [UnsafeMutablePointer<Float>], frames: Int) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?
        for i in 0..<frames {
            let quiet = abs(buffers[0][i]) < threshold && abs(buffers[1][i]) < threshold
            var keepThis = true
            if quiet {
                run += 1
                if run > shortest {
                    let allowed = max(shortest, min(Int(Double(run) * 0.2), longestKept))
                    keepThis = kept < allowed
                }
                if keepThis { kept += 1 }
            } else {
                run = 0
                kept = 0
            }
            if keepThis {
                if start == nil { start = i }
            } else if let from = start {
                ranges.append(from..<i)
                start = nil
            }
        }
        if let from = start { ranges.append(from..<frames) }
        return ranges
    }
}
