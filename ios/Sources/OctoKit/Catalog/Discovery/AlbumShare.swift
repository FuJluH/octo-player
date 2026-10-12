import Foundation

/// How much of an album found online the library already holds, as Octo counts it from the
/// album's songs (under whatever album the library filed them). Library albums, and albums the
/// server did not count, have no share.
public enum AlbumShare: Sendable, Hashable {
    case none, part, whole
}

public func albumShare(_ album: Album) -> AlbumShare? {
    guard let owned = album.ownedCount else { return nil }
    if !album.isExternal || album.songCount <= 0 { return nil }
    if owned <= 0 { return AlbumShare.none }
    if owned >= album.songCount { return .whole }
    return .part
}

/// The quiet line on the card of an album found online that the library holds in part: "2 of 11
/// in your library". Nothing otherwise, as the heading above the card already says where it
/// stands.
public func albumShareLine(_ album: Album) -> String? {
    albumShare(album) == .part ? albumShareLine(owned: album.ownedCount, songs: album.songCount) : nil
}

/// The same from the counts alone: some of the songs, not none or all.
public func albumShareLine(owned: Int?, songs: Int) -> String? {
    guard let owned, owned >= 1, owned < songs else { return nil }
    return "\(owned) of \(songs) in your library"
}

/// The heading over albums found online that the library holds in part.
public let partlyInLibraryText = "Partly in your library"
