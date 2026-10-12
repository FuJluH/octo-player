import Foundation

/// The library song each find arrived as: the first with the same title, the same kind of
/// recording and the same artist, of about the same length when both are known. Finds not in the
/// library yet are left out.
public func adoptions(_ waiting: [OnlineSong], _ library: [LibraryTrack]) -> [String: LibraryTrack] {
    let byTitle = TitleIndex(library, title: \.title, artist: \.artist)
    var found: [String: LibraryTrack] = [:]
    for find in waiting {
        if let track = byTitle.candidates(find.title, find.artist).first(where: { sameSong(find.title, find.artist, find.durationMs, $0) }) {
            found[find.id] = track
        }
    }
    return found
}

/// Whether a song Octo finished downloading (its record's `title` and `artist`) is the one asked
/// for: the same recording by the same artist.
public func downloadMatches(_ find: OnlineSong, title: String, artist: String) -> Bool {
    sameRecording(title, artist, find.title, find.artist)
}
