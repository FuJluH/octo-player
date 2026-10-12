import Foundation

// The switch that keeps songs found online out of sight, its words the same on the phone and the
// desktop, and the album page's own toggle.

public let libraryOnlySetting = "Library songs only"
public let libraryOnlyHelp = "Shows only songs in your library: albums, search, artists and radio leave out outside songs."
public let onlyMySongs = "Only my songs"

/// The songs to show: all of them, or with `hide` only those `outside` does not mark, in their
/// order.
public func librarySongsOnly<T>(_ songs: [T], hide: Bool, outside: (T) -> Bool) -> [T] {
    hide ? songs.filter { !outside($0) } : songs
}
