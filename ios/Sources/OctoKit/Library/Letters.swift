import Foundation

// Filing a list ordered by name under letters, for its headings and the letter rail.

/// A stretch of a list under one letter: the letter, where it starts, and how many items.
public struct LetterRun: Hashable, Sendable {
    public var letter: Character
    public var start: Int
    public var count: Int

    public init(_ letter: Character, _ start: Int, _ count: Int) {
        self.letter = letter
        self.start = start
        self.count = count
    }
}

/// The items under each letter, in list order. A letter can come back, since names starting
/// with a number (at the top) and names in other scripts (at the end) both file under "#", so
/// each stretch gets its own run.
public func letterRuns(_ names: [String]) -> [LetterRun] {
    let letters = names.map(indexLetter)
    guard !letters.isEmpty else { return [] }
    var runs: [LetterRun] = []
    var start = 0
    for index in 1...letters.count where index == letters.count || letters[index] != letters[start] {
        runs.append(LetterRun(letters[start], start, index - start))
        start = index
    }
    return runs
}

/// A letter on the rail and the row of the list it jumps to.
public struct RailStop: Hashable, Sendable {
    public var letter: Character
    public var index: Int

    public init(_ letter: Character, _ index: Int) {
        self.letter = letter
        self.index = index
    }
}

/// Where each letter first starts in a list. With `headed`, the list puts a heading row before
/// each run; `before` counts any rows above the items. A letter that comes back jumps to its
/// first run.
public func railStops(_ runs: [LetterRun], headed: Bool, before: Int = 0) -> [RailStop] {
    var seen = Set<Character>()
    var stops: [RailStop] = []
    for (runIndex, run) in runs.enumerated() where seen.insert(run.letter).inserted {
        stops.append(RailStop(run.letter, before + run.start + (headed ? runIndex : 0)))
    }
    return stops
}

/// The first letter a list is grouped under; anything else goes under "#".
public func indexLetter(_ sortKey: String) -> Character {
    guard let first = sortKey.first else { return "#" }
    let upper = String(first).uppercased()
    guard upper.count == 1, let letter = upper.first, ("A"..."Z").contains(letter) else { return "#" }
    return letter
}

/// The fewest items a list by name needs before it gets the letter rail.
public let railMinItems = 60
