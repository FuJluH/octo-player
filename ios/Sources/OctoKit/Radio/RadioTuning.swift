import Foundation

/// How a listener tunes Octo's radio: how much of it is music from outside the library, how far
/// it strays from the seeds, how soon an artist or an album comes back, and whether favorites
/// come around more often. The defaults play as radio always has, apart from where the outside
/// songs land.
public struct RadioTuning: Sendable, Equatable {
    public var discovery: RadioDiscovery = .balanced
    public var adventure: RadioAdventure = .balanced
    public var variety: RadioVariety = .normal
    public var favorites = false

    public init(discovery: RadioDiscovery = .balanced, adventure: RadioAdventure = .balanced, variety: RadioVariety = .normal,
                favorites: Bool = false) {
        self.discovery = discovery
        self.adventure = adventure
        self.variety = variety
        self.favorites = favorites
    }

    /// How many songs to ask the server for: more when most of the radio is to come from outside
    /// the library, so the share can be reached.
    public var suggestions: Int { discovery.share > 0.5 ? 100 : 50 }
}

/// The share of a radio kept for songs the library does not have, from the server's suggestions.
/// Balanced is the share Octo's Your Mix keeps. Stored by the raw names.
public enum RadioDiscovery: String, Sendable, CaseIterable {
    case libraryOnly = "LibraryOnly"
    case aLittle = "ALittle"
    case balanced = "Balanced"
    case lots = "Lots"
    case mostlyNew = "MostlyNew"

    public var share: Double {
        switch self {
        case .libraryOnly: 0.0
        case .aLittle: 0.15
        case .balanced: 0.35
        case .lots: 0.6
        case .mostlyNew: 0.85
        }
    }

    public var label: String {
        switch self {
        case .libraryOnly: "Only my library"
        case .aLittle: "A little"
        case .balanced: "Balanced"
        case .lots: "Lots"
        case .mostlyNew: "Mostly new"
        }
    }

    public var detail: String {
        switch self {
        case .libraryOnly: "Never a song from outside your library"
        case .aLittle: "About 1 song in 7 from outside your library"
        case .balanced: "About 1 song in 3 from outside your library"
        case .lots: "About 3 songs in 5 from outside your library"
        case .mostlyNew: "About 5 songs in 6 from outside your library"
        }
    }
}

/// How far down the best matches a pick may land, as a share of their total weight, and how many
/// of the library's matches stay in the running.
public enum RadioAdventure: String, Sendable, CaseIterable {
    case focused = "Focused"
    case balanced = "Balanced"
    case wander = "Wander"

    public var reach: Double {
        switch self {
        case .focused: 0.2
        case .balanced: 0.5
        case .wander: 1.0
        }
    }

    public var keep: Double {
        switch self {
        case .focused: 0.5
        case .balanced: 1.0
        case .wander: 2.0
        }
    }

    public var label: String { rawValue }

    public var detail: String {
        switch self {
        case .focused: "Only the closest matches"
        case .balanced: "Close matches, with some surprises"
        case .wander: "Deep cuts and further afield"
        }
    }
}

/// How far apart an album and an artist play, against the usual spacing, which grows with the
/// library. Another version of the same song always waits the usual spacing.
public enum RadioVariety: String, Sendable, CaseIterable {
    case tight = "Tight"
    case normal = "Normal"
    case wide = "Wide"

    public var scale: Double {
        switch self {
        case .tight: 0.5
        case .normal: 1.0
        case .wide: 1.6
        }
    }

    public var label: String { rawValue }

    public var detail: String {
        switch self {
        case .tight: "Artists and albums come back sooner"
        case .normal: "Spaced to suit your library's size"
        case .wide: "Artists and albums come back much later"
        }
    }
}

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
