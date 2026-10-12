import Foundation

/// What a screen reader adds for artwork of something not in the library.
public let notInLibraryText = "Not in your library"

/// Whether a song is one found online and not in the library yet.
public func isOutsideLibrary(_ song: Song?, adopted: Set<String>) -> Bool {
    guard let song else { return false }
    return song.isExternal && !adopted.contains(song.id)
}

/// The same, from a song's id and whether the server marks it outside the library.
public func isOutsideLibrary(songId: String?, isExternal: Bool, adopted: Set<String>) -> Bool {
    guard let songId else { return false }
    return isExternal && !adopted.contains(songId)
}

/// The finds whose download has arrived in the library.
public func adoptedFinds(_ phases: [String: DownloadPhase]) -> Set<String> {
    Set(phases.filter { $0.value == .done }.keys)
}

/// How a song row says a song is not in the library: the add button at its end, the small plus on
/// its artwork, or nothing. A row says it once, so a row with the button has no mark.
public enum AddSign: Sendable, Equatable { case button, mark, none }

/// In a list that offers the button, a find keeps it after it is added, so the check has its
/// moment before the row turns into the library song. Elsewhere a find gets the mark until it is
/// in the library.
public func rowAddSign(isFind: Bool, adopted: Bool, offersAdd: Bool) -> AddSign {
    if !isFind { return .none }
    if offersAdd { return .button }
    if adopted { return .none }
    return .mark
}

/// Whether a row keeps an empty space where the add button would be, so its length lines up with
/// the rows that have one. Only where the list gives its library songs that space.
public func rowKeepsAddSpace(_ sign: AddSign, librarySpace: Bool) -> Bool { librarySpace && sign != .button }

/// What a song row has after its length: the add button, the button's space left empty, or what
/// the list puts there (maybe nothing).
public enum RowEnd: Sendable, Equatable { case addButton, addSpace, trailing }

public func rowEnd(_ sign: AddSign, librarySpace: Bool, hasTrailing: Bool) -> RowEnd {
    if sign == .button { return .addButton }
    if !hasTrailing && rowKeepsAddSpace(sign, librarySpace: librarySpace) { return .addSpace }
    return .trailing
}

/// What a screen reader says for a picture, with the note for one not in the library.
public func artworkDescription(_ description: String?, outside: Bool) -> String? {
    if !outside { return description }
    guard let description, !description.isEmpty else { return notInLibraryText }
    return "\(description), \(notInLibraryText.lowercased())"
}

/// The quiet line on an album page from the server, beside its add button, where the big cover
/// carries no mark. Only for an album partly in the library: the button already says the rest is
/// not.
public func albumLibraryNote(songs: Int, outside: Int) -> String? {
    if outside <= 0 || outside >= songs { return nil }
    return "\(songs - outside) of \(songs) in your library"
}

/// The words for adding the songs of an album the library lacks.
public func addMissingLabel(_ count: Int) -> String { count == 1 ? "Add the missing song" : "Add the \(count) missing songs" }

/// How big the mark is for artwork of a given side: an eighth of it, never so small the plus
/// blurs, nor big enough to crowd a large cover.
public func notInLibraryMarkSize(_ art: Double) -> Double { min(20, max(12, art * 0.125)) }

/// How far the mark sits in from the bottom and right edges. On a square cover, just clear of the
/// rounded corner. On a round picture, along the diagonal, far enough in that the whole disc stays
/// inside the circle.
public func notInLibraryMarkInset(_ art: Double, mark: Double, round: Bool) -> Double {
    let margin = max(art * 0.04, 3)
    if !round { return margin }
    let radius = art / 2
    let center = radius - (radius - margin - mark / 2) / 2.0.squareRoot()
    return center - mark / 2
}

/// How long a find's row keeps its check once the song is in the library, from when the check
/// starts drawing: the draw and a short hold.
public let checkHoldMs = 1_200

/// How long the row's words and artwork take to fade into the library song's.
public let swapFadeDurationMs = 300

/// What a row for a song found online shows: the find, the check saying it is now in the library,
/// or the library song it became.
public enum FindFace: Sendable, Equatable { case find, check, library }

/// The face a find's row moves to, given whether its song is in the library (nil while that is
/// not known yet). A row that opens on a song already in the library shows the library song
/// straight away. One whose song arrives while it is shown has the check's moment first, where the
/// row has the add button; elsewhere it turns at once.
public func nextFindFace(_ face: FindFace?, adopted: Bool?, offersAdd: Bool) -> FindFace? {
    guard let adopted else { return face }
    guard let face else { return adopted ? .library : .find }
    if face == .find && adopted { return offersAdd ? .check : .library }
    return face
}

/// The face once the check has had its moment.
public func afterCheck(_ face: FindFace?) -> FindFace? { face == .check ? .library : face }

/// How long the turn into the library song fades. Only a row that showed the find fades; one that
/// opened on the library song, or with reduced motion, swaps at once.
public func swapFadeMs(sawFind: Bool, calm: Bool) -> Int { sawFind && !calm ? swapFadeDurationMs : 0 }

/// The album a row names. A song found online often has its own title for an album, which says
/// nothing new, so that is left off.
public func rowAlbum(_ song: Song) -> String {
    let album = song.album ?? ""
    if song.isExternal && album.trimmingCharacters(in: .whitespacesAndNewlines)
        .caseInsensitiveCompare(song.title.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame {
        return ""
    }
    return album
}

/// "Artist • Album" under a song's title.
public func songSubtitle(_ song: Song) -> String {
    [song.byline, rowAlbum(song)].filter { !$0.isEmpty }.joined(separator: " • ")
}
