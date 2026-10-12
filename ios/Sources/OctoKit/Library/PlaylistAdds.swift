import Foundation

// Adding songs to a playlist: which songs are new to the playlist, the question when some are
// not, and the words once they are in.

/// What adding songs to a playlist would do: every song once, in the order given, split into
/// those not on the playlist yet and those that are.
public struct AddPlan: Equatable, Sendable {
    public var songs: [String]
    public var fresh: [String]
    public var repeats: [String]

    public init(songs: [String], fresh: [String], repeats: [String]) {
        self.songs = songs
        self.fresh = fresh
        self.repeats = repeats
    }

    /// Some are on the playlist already, so ask before adding them again.
    public var asks: Bool { !repeats.isEmpty }

    /// A choice between adding every song and only the new ones.
    public var offersNewOnly: Bool { songs.count > 1 && !fresh.isEmpty }
}

public func planAdd(_ trackIds: [String], onPlaylist: Set<String>) -> AddPlan {
    var seen = Set<String>()
    let songs = trackIds.filter { seen.insert($0).inserted }
    return AddPlan(songs: songs, fresh: songs.filter { !onPlaylist.contains($0) }, repeats: songs.filter(onPlaylist.contains))
}

/// What is asked before songs already on a playlist go on it again.
public func addAgainQuestion(_ name: String, _ plan: AddPlan) -> String {
    if plan.songs.count == 1 { return "Already in \(name). Add again?" }
    if plan.fresh.isEmpty { return "These songs are already in \(name). Add them again?" }
    if plan.repeats.count == 1 { return "1 of these songs is already in \(name)." }
    return "\(plan.repeats.count) of these songs are already in \(name)."
}

/// The button that adds every song anyway: "Add" for one song, "Add again" when all are there,
/// "Add all" beside "Add new ones".
public func addAgainChoice(_ plan: AddPlan) -> String {
    if plan.offersNewOnly { return "Add all" }
    return plan.songs.count == 1 ? "Add" : "Add again"
}

/// The button that adds only the songs not on the playlist yet.
public let addNewOnes = "Add new ones"

/// "Added to Road trip" or "Added 5 songs to Road trip".
public func addedMessage(_ name: String, _ count: Int) -> String {
    count == 1 ? "Added to \(name)" : "Added \(count) songs to \(name)"
}

/// How many playlists added to lately are remembered.
public let recentPlaylistCount = 3

/// The playlists added to lately, newest first: `id` goes to the front, and only `keep` are
/// remembered.
public func recentPlaylists(_ recent: [String], adding id: String, keep: Int = recentPlaylistCount) -> [String] {
    Array(([id] + recent.filter { $0 != id }).prefix(keep))
}

/// The playlists with those added to lately first, newest first, and the rest in the order they
/// came.
public func recentFirst<T>(_ playlists: [T], recent: [String], id: (T) -> String) -> [T] {
    var rank: [String: Int] = [:]
    for (index, value) in recent.enumerated() where rank[value] == nil { rank[value] = index }
    return playlists.enumerated().sorted { a, b in
        let ra = rank[id(a.element)] ?? Int.max
        let rb = rank[id(b.element)] ?? Int.max
        return ra != rb ? ra < rb : a.offset < b.offset
    }.map(\.element)
}

/// The name a copy of a playlist gets.
public func playlistCopyName(_ name: String) -> String { "\(name.trimmingCharacters(in: .whitespacesAndNewlines)) (copy)" }

/// The line that says a copy was made.
public func copiedMessage(_ copy: String) -> String { "Made a copy: \(copy)" }

/// "Imported 42 of 45 songs into "Road trip"", or why nothing was.
public func importSummary(_ report: ImportReport) -> String {
    if report.total == 0 { return "\"\(report.name)\" has no songs in it." }
    if report.matched == 0 { return "None of the \(report.total) songs in \"\(report.name)\" are in your library." }
    return "Imported \(report.matched) of \(report.total == 1 ? "1 song" : "\(report.total) songs") into \"\(report.name)\""
}
