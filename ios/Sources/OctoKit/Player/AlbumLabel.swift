import Foundation

/// The album name at the top of the player, or nothing when the song is a single: a one-song
/// release, or one named after the song itself, would only repeat the title shown below.
public func albumLabel(_ album: String?, _ title: String?, _ albumSongs: Int) -> String? {
    guard let album, !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    if albumSongs <= 1 { return nil }
    if album.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasSuffix("- single") { return nil }
    if let title, bareName(album) == bareName(title) { return nil }
    return album
}

// A name without a "- Single" or "- EP" ending, read as a whole name, for comparing a release
// with its song.
private func bareName(_ name: String) -> String {
    matchKey(name.replacingOccurrences(of: #"\s*-\s*(single|ep)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]))
}
