import Foundation

/// The shelves an artist page sorts their releases onto, in the order the page shows them.
public enum ReleaseGroup: CaseIterable, Sendable {
    case albums, singlesAndEps, compilations, live, appearsOn

    public var title: String {
        switch self {
        case .albums: "Albums"
        case .singlesAndEps: "Singles and EPs"
        case .compilations: "Compilations"
        case .live: "Live"
        case .appearsOn: "Appears on"
        }
    }
}

/// The shelf for one of the artist's own releases, from its release types (MusicBrainz's
/// words, in any case). A compilation comes first, then a live release, then a single or an EP;
/// anything else is an album.
public func releaseGroupOf(_ types: [String], compilation: Bool = false) -> ReleaseGroup {
    let words = types.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    if compilation || words.contains("compilation") { return .compilations }
    if words.contains("live") { return .live }
    if words.contains("single") || words.contains("ep") { return .singlesAndEps }
    return .albums
}

/// An artist's releases on their shelves, each shelf keeping the order it was given, and empty
/// shelves left out. `own` is false for a release by someone else that the artist appears on.
/// When no own release has release types, they all go under Albums.
public func groupReleases<T>(_ items: [T], types: (T) -> [String], compilation: (T) -> Bool = { _ in false },
                             own: (T) -> Bool = { _ in true }) -> [(group: ReleaseGroup, items: [T])] {
    let typed = items.contains { own($0) && !types($0).isEmpty }
    var byGroup: [ReleaseGroup: [T]] = [:]
    for item in items {
        let group: ReleaseGroup = if !own(item) { .appearsOn } else if !typed { .albums } else {
            releaseGroupOf(types(item), compilation: compilation(item))
        }
        byGroup[group, default: []].append(item)
    }
    return ReleaseGroup.allCases.compactMap { group in byGroup[group].map { (group, $0) } }
}
