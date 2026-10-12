import Foundation

// The words and small rules the library pages share.

/// "1,234" whatever the phone's language: the comma grouping the other apps write.
public func grouped(_ count: Int) -> String { SettingsSummaries.grouped(count) }

/// "1 song" or "1,234 songs".
public func countText(_ count: Int, _ one: String, _ many: String) -> String {
    SettingsSummaries.count(count, one: one, many: many)
}

/// A song's length as a row shows it, like 3:45. Nothing when it is not known, rather than 0:00.
public func rowLength(_ durationMs: Int64) -> String? { durationMs >= 1_000 ? asClock(Int(durationMs / 1_000)) : nil }

/// The widest length the row's length column is sized for: anything under an hour.
public let lengthSlotSample = "00:00"

/// The album a row names. A song found online often has its own title for an album, which says
/// nothing new, so that is left off.
public func rowAlbum(title: String, album: String, find: Bool) -> String {
    rowAlbum(Song(id: "", title: title, album: album, isExternal: find))
}

/// "Artist • Album" under a song's title.
public func songSubtitle(title: String, artist: String, album: String, find: Bool) -> String {
    songSubtitle(Song(id: "", title: title, artist: artist, album: album, isExternal: find))
}

/// "120 of 2,835 songs", for a filtered list.
public func filteredCount(shown: Int, all: Int) -> String {
    "\(grouped(shown)) of \(grouped(all)) \(all == 1 ? "song" : "songs")"
}

/// Which way the sort button's arrow points, in degrees: the up arrow as drawn for ascending,
/// turned half round for descending.
public func sortArrowTurn(descending: Bool) -> Double { descending ? 180 : 0 }

/// Whether a page title, at its whole one-line width, fits beside its buttons on a line `width`
/// wide.
public func titleFitsBeside(titleWidth: Double, buttonsWidth: Double, width: Double) -> Bool {
    titleWidth + buttonsWidth <= width
}

/// The button for the phone's music, worded for whether the system still asks.
public func accessButtonLabel(deniedForever: Bool) -> String { deniedForever ? "Open settings" : "Allow access" }

// MARK: Deleting from disk

public let deleteFromDiskWords = "Delete from disk"
public let recentlyRemovedWords = "Recently removed"
public let putBackWords = "Put back"
public let lookUpTagsWords = "Look up tags"
public let undoLastChangeWords = "Undo the last change"

/// What the question names: the song's title for one, "3 songs" for more.
public func deleteNames(_ titles: [String]) -> String {
    titles.count == 1 ? titles[0] : countText(titles.count, "song", "songs")
}

/// The question before songs leave the server's disk.
public func deleteTitle(_ count: Int) -> String {
    count == 1 ? "Delete this song from disk?" : "Delete \(countText(count, "song", "songs")) from disk?"
}

/// What deleting does, for `names`. The server keeps the file in its trash for `keepDays` (0 is
/// until someone clears it).
public func deleteBody(_ names: String, keepDays: Int) -> String {
    let kept = keepDays > 0 ? "for \(countText(keepDays, "day", "days"))" : "until someone clears it"
    return "This takes \(names) off the server's disk and out of your library. The server keeps the file in its trash \(kept), "
        + "so you can put it back from Library health. Octo will not download it again by itself."
}

/// The line after a delete.
public func deletedLine(_ count: Int, title: String?) -> String {
    if count == 1, let title { return "Deleted \(title) from disk." }
    return "Deleted \(countText(count, "song", "songs")) from disk."
}

/// What Recently removed says about a song whose file another copy replaced.
public func replacedText(was: String?, now: String?) -> String {
    var parts: [String] = []
    if let was = was?.trimmingCharacters(in: .whitespaces), !was.isEmpty { parts.append("was \(was)") }
    if let now = now?.trimmingCharacters(in: .whitespaces), !now.isEmpty { parts.append("now \(now)") }
    return parts.isEmpty ? "Replaced by another copy" : "Replaced: \(parts.joined(separator: ", "))"
}

/// What a screen reader says for that line.
public func replacedSpoken(was: String?, now: String?) -> String {
    let text = replacedText(was: was, now: now)
    return text.hasPrefix("Replaced: ") ? "Replaced by another copy. Yours " + text.dropFirst("Replaced: ".count) : text
}

/// One song's time left in the trash, from the server's "goneAt", counted from `nowMillis`.
public func goneText(goneAtMillis: Int64?, nowMillis: Int64) -> String {
    guard let goneAtMillis else { return "Kept until someone clears the trash" }
    let days = max(0, (goneAtMillis - nowMillis) / 86_400_000)
    switch days {
    case 0: return "Deleted for good today"
    case 1: return "Deleted for good tomorrow"
    default: return "Deleted for good in \(days) days"
    }
}

/// When the server deletes a song for good, from its "goneAt", or nil when it keeps it until
/// someone clears the trash or did not say.
public func goneAtMillis(_ text: String?) -> Int64? {
    guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = parser.date(from: text) { return Int64(date.timeIntervalSince1970 * 1_000) }
    parser.formatOptions = [.withInternetDateTime]
    return parser.date(from: text).map { Int64($0.timeIntervalSince1970 * 1_000) }
}

/// How long the server keeps a deleted song, in a sentence.
public func keepsFor(_ keepDays: Int) -> String {
    keepDays > 0 ? "The server keeps a song deleted from disk for \(countText(keepDays, "day", "days")), then deletes it for good."
        : "The server keeps a song deleted from disk until someone clears its trash."
}

// MARK: Album page

/// The album's genre: the one most of its songs have, compared ignoring case, the first to
/// appear when two tie, written as first seen. Nothing when no song has one.
public func albumGenre(_ genres: [String]) -> String? {
    var counts: [String: (first: String, count: Int, order: Int)] = [:]
    for (order, genre) in genres.enumerated() where !genre.trimmingCharacters(in: .whitespaces).isEmpty {
        let key = genre.lowercased()
        if let seen = counts[key] {
            counts[key] = (seen.first, seen.count + 1, seen.order)
        } else {
            counts[key] = (genre, 1, order)
        }
    }
    return counts.values.max { a, b in a.count != b.count ? a.count < b.count : a.order > b.order }?.first
}

/// The average of the ratings its songs have, leaving out songs with none. Nothing when no song
/// is rated.
public func averageRating(_ ratings: [Int]) -> Double? {
    let rated = ratings.filter { (1...5).contains($0) }
    return rated.isEmpty ? nil : Double(rated.reduce(0, +)) / Double(rated.count)
}

/// Stars to one place, dropping a whole number's ".0": "4.3", "4".
public func starsText(_ average: Double) -> String {
    let rounded = (average * 10).rounded() / 10
    return rounded.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(rounded)) : String(format: "%.1f", rounded)
}

/// What a screen reader says for the average.
public func averageRatingSpoken(_ average: Double) -> String {
    let stars = starsText(average)
    return "Songs rated \(stars) \(stars == "1" ? "star" : "stars") on average"
}

/// What the album's download button says: what is left to do, if anything.
public func albumDownloadLabel(songs: Int, held: Int, done: Int) -> String {
    if held < songs { return "Download album" }
    if done < songs { return "Downloading" }
    return "Downloaded"
}

/// "<in library> of <songs> in your library", when some but not all songs are in it.
public func albumLibraryNote(inLibrary: Int, songs: Int) -> String? {
    inLibrary > 0 && inLibrary < songs ? "\(inLibrary) of \(songs) in your library" : nil
}

/// The add action's words on an album page with songs it lacks.
public func addMissingLabel(missing: Int) -> String {
    missing == 1 ? "Add the missing song" : "Add the \(missing) missing songs"
}

// MARK: Favorites

/// The parts of the Favorites page, in the order they show.
public enum FavoriteSegment: String, CaseIterable, Sendable, Codable {
    case songs = "Songs", albums = "Albums", artists = "Artists"
}

/// Which part the page opens on, once all three are read: liked songs when there are any,
/// otherwise the first part that has something; Songs when nothing does.
public func firstSegment(songs: Int, albums: Int, artists: Int) -> FavoriteSegment {
    if songs > 0 { return .songs }
    if albums > 0 { return .albums }
    if artists > 0 { return .artists }
    return .songs
}

// MARK: Downloads on the phone

/// A size in the units people read: "850 KB", "12.4 MB", "3.1 GB".
public func sizeLabel(_ bytes: Int64) -> String { SettingsWords.sizeLabel(bytes) }

/// Which rule keeps a download that was not asked for by hand, if one does. Reasons are
/// "manual", "liked" and "playlist:<id>".
public func keptBy(_ reasons: Set<String>, playlistNames: [String: String]) -> String? {
    if reasons.contains("manual") { return nil }
    if reasons.contains("liked") { return "Kept with Liked songs" }
    guard let playlist = reasons.sorted().first(where: { $0.hasPrefix("playlist:") }).map({ String($0.dropFirst("playlist:".count)) })
    else { return nil }
    return playlistNames[playlist].map { "Kept with \($0)" } ?? "Kept with a playlist"
}

/// The line under a download: where it is, or why it is kept.
public func downloadDetail(_ state: DownloadStatus, progress: Double, sizeBytes: Int64, reasons: Set<String>,
                           playlistNames: [String: String]) -> String {
    switch state {
    case .queued: return "Waiting"
    case .downloading: return "Downloading, \(Int((progress * 100).rounded()))%"
    case .failed: return "Could not download. Tap to try again"
    case .done: return [sizeLabel(sizeBytes), keptBy(reasons, playlistNames: playlistNames)].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The line under a switched-on keep rule: how many of its songs are on the phone.
public func keptSummary(serverOnly: Int, done: Int) -> String {
    if serverOnly == 0 { return "Every song is already on this phone" }
    if done >= serverOnly { return "All \(serverOnly) downloaded" }
    return "\(done) of \(serverOnly) downloaded"
}

// MARK: Playlists

/// Which playlists hold which of the songs, from (playlist, song) rows.
public func holdingsByPlaylist(_ rows: [(String, String)]) -> [String: Set<String>] {
    var out: [String: Set<String>] = [:]
    for (playlist, song) in rows { out[playlist, default: []].insert(song) }
    return out
}

/// The lead lines on the Playlists page.
public enum PlaylistsLead: CaseIterable, Sendable {
    case newPlaylist, newLiveList, importFile, importNote
}

/// The lead lines to show: making a playlist or a live list, importing, then how the last
/// import went while there is one.
public func playlistsLead(importNote: Bool) -> [PlaylistsLead] {
    PlaylistsLead.allCases.filter { $0 != .importNote || importNote }
}

// MARK: Finding a better copy

/// The song menu's row.
public let findHigherQualityWords = "Find higher quality"

/// The album menu's row: "Find higher quality for 9 songs".
public func findHigherQualityLabel(_ count: Int) -> String { "Find higher quality for \(songsCount(count))" }

/// What is asked before an album's songs go to the server. `source` is where the server says it
/// looks, named only when it said.
public func findHigherQualityAsk(_ count: Int, source: String? = nil) -> String {
    let named = source?.trimmingCharacters(in: .whitespaces) ?? ""
    return "Look for a higher quality copy of \(songsCount(count))\(named.isEmpty ? "" : " on \(named)")?"
}

public let keepsOriginalWords = "Each original is kept until its replacement passes."
