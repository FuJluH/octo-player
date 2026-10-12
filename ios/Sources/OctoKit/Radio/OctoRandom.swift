import Foundation

/// A seeded random sequence the same as the other apps' (xorwow), so a radio drawn with the same
/// seed is the same mix everywhere.
public struct OctoRandom: RandomNumberGenerator, Sendable {
    private var x: Int32, y: Int32, z: Int32, w: Int32, v: Int32, addend: Int32

    public init(seed: Int32) {
        let seed2 = seed >> 31
        x = seed
        y = seed2
        z = 0
        w = 0
        v = ~seed
        addend = (seed << 10) ^ Int32(bitPattern: UInt32(bitPattern: seed2) >> 4)
        for _ in 0..<64 { _ = nextInt() }
    }

    /// Seeded from the clock, for a mix that differs each time.
    public init() {
        self.init(seed: Int32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000) ^ Int.random(in: 0..<Int(Int32.max))))
    }

    public mutating func nextInt() -> Int32 {
        var t = x
        t = t ^ Int32(bitPattern: UInt32(bitPattern: t) >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362437
        return t &+ addend
    }

    private mutating func nextBits(_ bitCount: Int32) -> Int32 {
        let value = nextInt()
        return Int32(bitPattern: UInt32(bitPattern: value) >> UInt32(32 - bitCount)) & ((-bitCount) >> 31)
    }

    /// A number from 0 up to but not including 1.
    public mutating func nextDouble() -> Double {
        let high = Int64(nextBits(26)), low = Int64(nextBits(27))
        return Double((high << 27) + low) / Double(Int64(1) << 53)
    }

    /// A number from 0 up to but not including `until`, which must be above 0.
    public mutating func nextInt(_ until: Int) -> Int {
        let n = Int32(until)
        precondition(n > 0, "until must be positive")
        if n & -n == n {
            return Int(nextBits(31 - Int32(n.leadingZeroBitCount)))
        }
        while true {
            let bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
            let value = bits % n
            if bits &- value &+ (n &- 1) >= 0 { return Int(value) }
        }
    }

    public mutating func next() -> UInt64 {
        UInt64(UInt32(bitPattern: nextInt())) << 32 | UInt64(UInt32(bitPattern: nextInt()))
    }

    /// The items in a random order, drawn as the other apps draw it.
    public mutating func shuffled<T>(_ items: [T]) -> [T] {
        var out = items
        var i = out.count - 1
        while i >= 1 {
            let j = nextInt(i + 1)
            out.swapAt(i, j)
            i -= 1
        }
        return out
    }
}
