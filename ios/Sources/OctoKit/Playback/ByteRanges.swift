import Foundation

/// Byte ranges held, kept sorted and merged.
public struct ByteRanges: Sendable, Equatable {
    public init() {}

    public private(set) var ranges: [Range<Int64>] = []

    public mutating func insert(_ range: Range<Int64>) {
        guard !range.isEmpty else { return }
        var merged = range
        var kept: [Range<Int64>] = []
        for existing in ranges {
            if existing.upperBound < merged.lowerBound || existing.lowerBound > merged.upperBound {
                kept.append(existing)
            } else {
                merged = min(existing.lowerBound, merged.lowerBound)..<max(existing.upperBound, merged.upperBound)
            }
        }
        kept.append(merged)
        ranges = kept.sorted { $0.lowerBound < $1.lowerBound }
    }

    public func covers(_ range: Range<Int64>) -> Bool {
        guard !range.isEmpty else { return true }
        return ranges.contains { $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound }
    }

    /// How many bytes from `offset` on are held without a gap.
    public func contiguous(from offset: Int64) -> Int64 {
        ranges.first { $0.lowerBound <= offset && $0.upperBound > offset }.map { $0.upperBound - offset } ?? 0
    }

    public var total: Int64 { ranges.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } }
}
