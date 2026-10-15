import Foundation

// The lists Octo makes for the listener, by kind: Made for you, its stations, charts, and mixes
// by year, genre, artist and country. Only a server that runs Octo has them.

/// A kind of list Octo makes, in the order its groups show.
public enum OctoListGroup: String, CaseIterable, Sendable, Hashable, Identifiable {
    case forYou
    case stations
    case charts
    case years
    case genres
    case artists
    case countries
    case more

    public var id: String { rawValue }

    /// The group's name, as its heading shows it.
    public var title: String {
        switch self {
        case .forYou: "Made for you"
        case .stations: "Radio"
        case .charts: "Charts"
        case .years: "Years"
        case .genres: "Genres"
        case .artists: "Artists"
        case .countries: "Countries"
        case .more: "More from Octo"
        }
    }

    /// The Home shelf that shows the group's lists, for the mixes.
    public var homeSection: HomeSection? {
        switch self {
        case .years: .yearMixes
        case .genres: .genreMixes
        case .artists: .artistMixes
        case .countries: .countryMixes
        default: nil
        }
    }
}

/// Whether a playlist is the listener's: its owner is them, case aside, or either name is blank.
func ownedByListener(_ playlist: Playlist, _ listener: String) -> Bool {
    let me = listener.trimmingCharacters(in: .whitespacesAndNewlines)
    let owner = (playlist.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return me.isEmpty || owner.isEmpty || owner.lowercased() == me.lowercased()
}

/// Which of Octo's groups a server playlist belongs to, or nil for one Octo did not make for
/// this listener: someone else's (see `ownedByListener`), the Liked Songs list, the listener's
/// own and smart playlists. The server's own word for the kind decides, a decade and a year both
/// being Years and a word not known More. An older server that says no kind marks Made for you
/// lists only; past those, with `guess` (no list in the same answer says its kind), a read-only
/// list with an id of Octo's own shape counts: a station's ("or") is Radio, one named like
/// "1990s Mix" Years, any other More. Another server's own ids can have that shape, so a list
/// the listener can change never counts by its id.
public func octoListGroup(_ playlist: Playlist, listener: String, guess: Bool = true) -> OctoListGroup? {
    guard ownedByListener(playlist, listener) else { return nil }
    if let group = playlist.octoGroup {
        switch group {
        case "forYou": return .forYou
        case "station": return .stations
        case "chart": return .charts
        case "genre": return .genres
        case "artist": return .artists
        case "country": return .countries
        case "decade", "year": return .years
        case "liked": return nil
        default: return .more
        }
    }
    if let list = playlist.octoList { return list == octoListLiked ? nil : .forYou }
    guard guess, playlist.readonly, isDrawnCoverId(playlist.id) else { return nil }
    if playlist.id.hasPrefix(stationIdPrefix) { return .stations }
    return isDecadeMixName(playlist.name) ? .years : .more
}

/// Whether a name is a decade's mix, like "1990s Mix".
func isDecadeMixName(_ name: String) -> Bool {
    leadingYear(name) != nil && name.dropFirst(4) == "s Mix"
}

/// The year a name leads with, as its first four characters, when they are digits.
func leadingYear(_ name: String) -> Int? {
    let lead = name.prefix(4)
    guard lead.count == 4, lead.allSatisfy(\.isASCIIDigit) else { return nil }
    return Int(lead)
}

/// Octo's lists for the listener in their groups, in the groups' order; a group with none is left
/// out. A server that marks the kind of any list is never guessed at by ids. Made for you and
/// Charts keep the server's order. Years has the decades first, then single years, each newest
/// first, then by name. Every other group is by name, case aside.
public func octoListGroups(_ playlists: [Playlist], listener: String) -> [(group: OctoListGroup, lists: [Playlist])] {
    let guess = !playlists.contains { $0.octoGroup != nil }
    var byGroup: [OctoListGroup: [Playlist]] = [:]
    for playlist in playlists {
        if let group = octoListGroup(playlist, listener: listener, guess: guess) { byGroup[group, default: []].append(playlist) }
    }
    return OctoListGroup.allCases.compactMap { group in
        guard let lists = byGroup[group], !lists.isEmpty else { return nil }
        switch group {
        case .forYou, .charts: return (group, lists)
        case .years: return (group, lists.sorted(by: yearOrder))
        default: return (group, lists.sorted(by: nameOrder))
        }
    }
}

private func nameOrder(_ a: Playlist, _ b: Playlist) -> Bool {
    let left = a.name.lowercased(), right = b.name.lowercased()
    return left != right ? left < right : a.name < b.name
}

/// Decades, then single years, then the rest; newest first within each, then by name.
private func yearOrder(_ a: Playlist, _ b: Playlist) -> Bool {
    func rank(_ list: Playlist) -> Int {
        guard leadingYear(list.name) != nil else { return 2 }
        return list.name.dropFirst(4).hasPrefix("s") ? 0 : 1
    }
    let ra = rank(a), rb = rank(b)
    if ra != rb { return ra < rb }
    let ya = leadingYear(a.name) ?? 0, yb = leadingYear(b.name) ?? 0
    if ya != yb { return ya > yb }
    return nameOrder(a, b)
}

/// Whether a server list opens as the server has it, read-only: on a server that runs Octo, one
/// of the listener's that Octo made, by its kind, or read-only with an id of Octo's own shape.
public func opensAsServerList(_ playlist: Playlist, runsOcto: Bool, listener: String) -> Bool {
    guard runsOcto, ownedByListener(playlist, listener) else { return false }
    return playlist.octoGroup != nil || (playlist.readonly && isDrawnCoverId(playlist.id))
}

/// The mixes each of Home's mix shelves shows, from the server's playlists.
public func homeMixes(_ playlists: [Playlist], listener: String, sourceId: String) -> [HomeSection: [Station]] {
    var shelves: [HomeSection: [Station]] = [:]
    for (group, lists) in octoListGroups(playlists, listener: listener) {
        if let section = group.homeSection { shelves[section] = lists.map { Station($0, sourceId: sourceId) } }
    }
    return shelves
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
