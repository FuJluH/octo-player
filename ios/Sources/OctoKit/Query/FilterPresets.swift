import Foundation

/// The filters a song list offers in a tap. Each is an ordinary rule, so a pill says it with
/// `label()`.
public enum FilterPresets {
    public static let addedThisWeek = QueryRule(.added, .inTheLast, days: 7)
    public static let addedThisMonth = QueryRule(.added, .inTheLast, days: 30)
    public static let addedThisYear = QueryRule(.added, .inTheLast, days: 365)
    public static let neverPlayed = QueryRule(.lastPlayed, .never)
    public static let notPlayedLately = QueryRule(.lastPlayed, .notInTheLast, days: 180)
    public static let favorites = QueryRule(.favorite, .is, flag: true)
    public static let lossless = QueryRule(.lossless, .is, flag: true)

    /// The ones that need nothing chosen, in the order the chips run.
    public static let simple = [favorites, addedThisWeek, addedThisMonth, addedThisYear, neverPlayed, notPlayedLately, lossless]

    public static func ratingAtLeast(_ stars: Int) -> QueryRule { QueryRule(.rating, .atLeast, number: Int64(stars)) }

    /// How a choice of `ratingAtLeast` reads in a list: "5 stars", "4 stars or more".
    public static func ratingWords(_ stars: Int) -> String {
        switch stars {
        case 5: "5 stars"
        case 1: "1 star or more"
        default: "\(stars) stars or more"
        }
    }

    public static func genre(_ name: String) -> QueryRule { QueryRule(.genre, .is, text: name) }

    /// A decade, from the year it starts: 1990 is 1990 to 1999.
    public static func decade(_ start: Int) -> QueryRule { QueryRule(.year, .between, number: Int64(start), to: Int64(start) + 9) }

    // More that a live list offers beside the quick ones.

    public static func playedInTheLast(_ days: Int) -> QueryRule { QueryRule(.lastPlayed, .inTheLast, days: days) }
    public static func notPlayedInTheLast(_ days: Int) -> QueryRule { QueryRule(.lastPlayed, .notInTheLast, days: days) }
    public static func playedAtLeast(_ times: Int) -> QueryRule { QueryRule(.plays, .atLeast, number: Int64(times)) }
    public static func shorterThan(_ seconds: Int) -> QueryRule { QueryRule(.duration, .atMost, number: Int64(seconds)) }
    public static func longerThan(_ seconds: Int) -> QueryRule { QueryRule(.duration, .atLeast, number: Int64(seconds)) }
    public static func artist(_ name: String) -> QueryRule { QueryRule(.artist, .is, text: name) }
}

/// The artists a list's songs are by, A to Z, each once however it is spelled in case or accents.
public func artistsIn<F: SongFields>(_ songs: [F.Item], fields: F) -> [String] {
    var seen: [String: String] = [:]
    for song in songs {
        guard let name = fields.artist(song), !LibraryQuery.isBlank(name) else { continue }
        let folded = foldText(name)
        if seen[folded] == nil { seen[folded] = name.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
    return seen.values.map { (key: naturalSortKey($0), name: $0) }
        .sorted { $0.key != $1.key ? $0.key < $1.key : $0.name < $1.name }
        .map(\.name)
}

/// The genres a list's songs are filed under, A to Z, each once however it is spelled in case or
/// accents (the first spelling met is kept).
public func genresIn<F: SongFields>(_ songs: [F.Item], fields: F) -> [String] {
    var seen = Set<String>()
    var names: [String] = []
    for song in songs {
        for name in fields.genres(song) where !LibraryQuery.isBlank(name) {
            if seen.insert(foldText(name)).inserted { names.append(name.trimmingCharacters(in: .whitespacesAndNewlines)) }
        }
    }
    return names.enumerated().map { (key: naturalSortKey($0.element), place: $0.offset, name: $0.element) }
        .sorted { $0.key != $1.key ? $0.key < $1.key : $0.place < $1.place }
        .map(\.name)
}

/// The decades a list's songs come from, oldest first, as the year each starts: 1990 for the
/// 1990s.
public func decadesIn<F: SongFields>(_ songs: [F.Item], fields: F) -> [Int] {
    Set(songs.compactMap { song in fields.year(song).flatMap { $0 > 0 ? $0 / 10 * 10 : nil } }).sorted()
}
