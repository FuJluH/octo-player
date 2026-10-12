import Foundation

/// What a screen reader adds for artwork of something not in the library.
public let notInLibraryText = "Not in your library"

/// The finds whose download has arrived in the library.
public func adoptedFinds(_ phases: [String: DownloadPhase]) -> Set<String> {
    Set(phases.filter { $0.value == .done }.keys)
}

/// Whether a song is one found online and not in the library yet.
public func isOutsideLibrary(songId: String?, isExternal: Bool, adopted: Set<String>) -> Bool {
    guard let songId else { return false }
    return isExternal && !adopted.contains(songId)
}

/// How big the not-in-library mark is for artwork of a given side: an eighth of it, never so
/// small the plus blurs, nor big enough to crowd a large cover.
public func notInLibraryMarkSize(_ art: Double) -> Double { min(20, max(12, art * 0.125)) }

/// How far the mark sits in from the bottom and right edges. On a square cover, just clear of
/// the rounded corner. On a round picture, along the diagonal, far enough in that the whole disc
/// stays inside the circle.
public func notInLibraryMarkInset(_ art: Double, mark: Double, round: Bool) -> Double {
    let margin = max(3, art * 0.04)
    if !round { return margin }
    let radius = art / 2
    let center = radius - (radius - margin - mark / 2) / 2.0.squareRoot()
    return center - mark / 2
}

/// What a screen reader says for a picture, with the note for one not in the library.
public func artworkDescription(_ description: String?, outside: Bool) -> String? {
    guard outside else { return description }
    guard let description, !description.isEmpty else { return notInLibraryText }
    return "\(description), \(notInLibraryText.lowercased())"
}
