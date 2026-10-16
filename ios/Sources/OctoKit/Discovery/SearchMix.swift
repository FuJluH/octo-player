import Foundation

// How a search lists what the library has and what the server found online, the same as the phone
// and desktop apps: each kind is one list, the library's best few first and the finds right after
// them, so the finds are never under a long run of library songs.

/// How many library songs "All" shows before the songs found online, and how many of those it shows;
/// "See all" lists every one of both. Three keeps the line about looking online above the tab bar
/// under a row of artists.
public let librarySongsShown = 3
public let onlineSongsShown = 4

/// How many waiting rows stand in for the songs found online while the server looks: as many as
/// "All" shows, so the finds take their places and nothing below moves.
public let waitingRows = onlineSongsShown

/// Where looking online stands, for the line between the library's songs and the songs found online.
public enum OutsideLook: Sendable, Equatable {
    /// Not looking: "Library songs only", or no server that finds music.
    case off
    /// Asked, no answer yet.
    case looking
    /// Found songs, listed under the library's.
    case found
    /// Asked and found no songs.
    case noneFound
    /// The server could not be asked.
    case failed
}

public let searchingOutsideText = "Searching outside your library…"
/// Over the finds the line stays, quietly, where it said it was looking.
public let foundOutsideText = "Not in your library"
public let outsideFailedText = "Couldn't search outside your library"

/// `kind` names what was looked for in the plural: songs, albums, artists.
public func noneOutsideText(_ query: String, kind: String = "songs") -> String {
    "No \(kind) outside your library for \"\(query.trimmingCharacters(in: .whitespacesAndNewlines))\""
}

/// What the line says for each state; none when there is nothing to look for.
public func outsideLine(_ look: OutsideLook, query: String, kind: String = "songs") -> String? {
    switch look {
    case .looking: searchingOutsideText
    case .noneFound: noneOutsideText(query, kind: kind)
    case .failed: outsideFailedText
    case .found: foundOutsideText
    case .off: nil
    }
}

/// The state from what is known: whether finds are wanted at all, whether the answer is still
/// coming, whether asking failed, and how many came back.
public func outsideLook(wanted: Bool, looking: Bool, failed: Bool, count: Int) -> OutsideLook {
    if !wanted { return .off }
    if looking { return .looking }
    if failed { return .failed }
    return count > 0 ? .found : .noneFound
}

/// Whether "All" has more songs than it shows, of either kind.
public func moreSongsThanShown(library: Int, online: Int) -> Bool {
    library > librarySongsShown || online > onlineSongsShown
}

/// Whether "All" shows the songs at all: the library has some, or the line between them has
/// something to say.
public func songsShown(library: Int, look: OutsideLook) -> Bool {
    library > 0 || look != .off
}

extension DiscoverState {
    /// Where looking online stands for one kind, by how many of it came back.
    public func look(count: Int) -> OutsideLook {
        switch self {
        case .idle: .off
        case .loading: .looking
        case .failed: .failed
        case .done: count > 0 ? .found : .noneFound
        }
    }
}
