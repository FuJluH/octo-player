import Foundation

/// One of Home's shelves, by the id it is stored under. The cases are in the default order.
/// `stations` is Octo's own stations, shown as Radio; `internetRadio` the internet radio stations
/// added to the server, shown as Live radio; the mixes Octo's lists by year, genre, artist and country.
public enum HomeSection: String, CaseIterable, Sendable, Hashable, Identifiable {
    case pinned
    case recentlyPlayed
    case madeForYou
    case stations
    case internetRadio
    case yearMixes
    case genreMixes
    case artistMixes
    case countryMixes
    case recentlyAdded
    case mostPlayed
    case favoriteAlbums
    case charts
    case artists
    case somethingDifferent
    case notPlayedLately
    case neverFinished
    case neverPlayed

    public var id: String { rawValue }

    /// The shelf's name, as Home shows it.
    public var title: String {
        switch self {
        case .pinned: "Pinned"
        case .recentlyPlayed: "Recently played"
        case .madeForYou: "Made for you"
        case .stations: "Radio"
        case .internetRadio: "Live radio"
        case .yearMixes: "Year mixes"
        case .genreMixes: "Genre mixes"
        case .artistMixes: "Artist mixes"
        case .countryMixes: "Country mixes"
        case .recentlyAdded: "Recently added"
        case .mostPlayed: "Most played"
        case .favoriteAlbums: "Favorite albums"
        case .charts: "Charts"
        case .artists: "Artists"
        case .somethingDifferent: "Something different"
        case .notPlayedLately: "Not played in 6 months"
        case .neverFinished: "Albums you never finished"
        case .neverPlayed: "Unplayed albums"
        }
    }
}

/// A shelf in its place on Home, and whether it shows.
public struct HomeSectionEntry: Sendable, Hashable, Identifiable {
    public var section: HomeSection
    public var shown: Bool

    public init(_ section: HomeSection, shown: Bool = true) {
        self.section = section
        self.shown = shown
    }

    public var id: String { section.rawValue }
}

/// The settings key Home's order and hidden shelves are kept under.
public let homeSectionsKey = "home_sections"

/// Every shelf in the default order, all shown.
public let defaultHomeSections: [HomeSectionEntry] = HomeSection.allCases.map { HomeSectionEntry($0) }

/// Home's shelves from the stored string: ids separated by commas, in order, a hidden one led by
/// "-". Unknown ids are passed over and an id written twice counts once, where it first stands.
/// A shelf the string leaves out goes in shown, just after the shelf before it in the default
/// order (first of all when none of those is there). Nothing stored is the default.
public func homeSectionOrder(stored: String?) -> [HomeSectionEntry] {
    var entries: [HomeSectionEntry] = []
    for piece in (stored ?? "").split(separator: ",", omittingEmptySubsequences: true) {
        var id = piece.trimmingCharacters(in: .whitespaces)
        let hidden = id.hasPrefix("-")
        if hidden { id = String(id.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard let section = HomeSection(rawValue: id), !entries.contains(where: { $0.section == section }) else { continue }
        entries.append(HomeSectionEntry(section, shown: !hidden))
    }
    let all = HomeSection.allCases
    for (index, section) in all.enumerated() where !entries.contains(where: { $0.section == section }) {
        let before = all[..<index].reversed().lazy.compactMap { earlier in entries.firstIndex { $0.section == earlier } }.first
        entries.insert(HomeSectionEntry(section), at: before.map { $0 + 1 } ?? 0)
    }
    return entries
}

/// The string Home's shelves are stored as: every id in order, a hidden one led by "-".
public func encodeHomeSections(_ entries: [HomeSectionEntry]) -> String {
    entries.map { ($0.shown ? "" : "-") + $0.section.rawValue }.joined(separator: ",")
}

/// The shelves with the ones at `offsets` moved to stand before `destination`, as a list's drag
/// reports it (`destination` counts places in the list before the move).
public func moveHomeSections(_ entries: [HomeSectionEntry], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [HomeSectionEntry] {
    let valid = IndexSet(offsets.filter { entries.indices.contains($0) })
    guard !valid.isEmpty else { return entries }
    let moving = valid.map { entries[$0] }
    var rest: [HomeSectionEntry] = []
    var place = 0
    for (index, entry) in entries.enumerated() where !valid.contains(index) {
        if index < destination { place += 1 }
        rest.append(entry)
    }
    rest.insert(contentsOf: moving, at: min(max(place, 0), rest.count))
    return rest
}

/// The shelves with one moved to stand at `index` of the new order.
public func moveHomeSection(_ entries: [HomeSectionEntry], _ section: HomeSection, to index: Int) -> [HomeSectionEntry] {
    guard let from = entries.firstIndex(where: { $0.section == section }) else { return entries }
    var next = entries
    let entry = next.remove(at: from)
    next.insert(entry, at: min(max(index, 0), next.count))
    return next
}

/// The shelves with one shown or hidden, in its place.
public func toggleHomeSection(_ entries: [HomeSectionEntry], _ section: HomeSection, shown: Bool) -> [HomeSectionEntry] {
    entries.map { $0.section == section ? HomeSectionEntry(section, shown: shown) : $0 }
}

/// Every shelf back in the default order, and shown.
public func resetHomeSections() -> [HomeSectionEntry] { defaultHomeSections }

/// The line under "Home sections" in Settings: how many shelves are hidden, and whether the
/// order was changed.
public func homeSectionsSummary(_ entries: [HomeSectionEntry]) -> String {
    let hidden = entries.filter { !$0.shown }.count
    let moved = entries.map(\.section) != HomeSection.allCases
    switch (hidden, moved) {
    case (0, false): return "Every section, in the usual order"
    case (0, true): return "Every section, in your order"
    case (1, _): return moved ? "1 hidden, in your order" : "1 hidden"
    default: return moved ? "\(hidden) hidden, in your order" : "\(hidden) hidden"
    }
}
