import Foundation

/// What Home shows besides the resume card.
public struct HomeLayout: Sendable, Equatable {
    /// The quiet card asking for the music on the phone.
    public var askAccess: Bool
    /// The shelves, drawn from the whole library, phone and server together.
    public var shelves: Bool
    /// The note for a library with no songs at all.
    public var empty: Bool

    public init(askAccess: Bool, shelves: Bool, empty: Bool) {
        self.askAccess = askAccess
        self.shelves = shelves
        self.empty = empty
    }
}

/// Shelves whenever the library has songs, wherever they came from, so a listener with only a
/// server still gets a full Home. The phone access card shows only while access is missing and they
/// have not said "Not now". Nils are values not read yet: nothing shows for them, so nothing
/// flickers.
public func homeLayout(_ access: PhoneAccess, accessDismissed: Bool?, librarySongs: Int?) -> HomeLayout {
    HomeLayout(askAccess: access != .granted && accessDismissed == false,
               shelves: (librarySongs ?? 0) > 0,
               empty: librarySongs == 0)
}

/// The button for phone access, worded for whether the system still asks.
public func accessButtonLabel(_ access: PhoneAccess) -> String { access == .deniedForever ? "Open settings" : "Allow access" }

/// Stations change once a day, so a list older than this is asked for again when Home comes back.
public let stationsStaleMs: Int64 = 10 * 60 * 1_000

/// The words for a station the server no longer has: Octo makes its stations anew now and then, and
/// an old one is taken off Home.
public func stationGoneLine(_ name: String) -> String { "\(name) isn't on the server any more" }

/// The line under a Made for you list's name.
public func songCountLine(_ count: Int) -> String { count == 1 ? "1 song" : "\(count) songs" }

/// Whether Home should ask for the stations again: never while a load is running, always after one
/// failed, otherwise once the list is stale.
public func stationsDue(now: Int64, loadedAt: Int64?, failed: Bool, loading: Bool) -> Bool {
    if loading { return false }
    guard let loadedAt, !failed else { return true }
    return now - loadedAt >= stationsStaleMs
}
