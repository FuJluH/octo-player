import Foundation

// The words for library health, so a finding reads the same on every app: what each check is
// called, what it means, and what to do about it.

extension HealthCheck {
    public var title: String {
        switch self {
        case .duplicates: "Songs you have twice"
        case .splitAlbums: "Albums split apart"
        case .noLength: "Songs with no length"
        case .noTrackNumber: "No track number"
        case .noAlbumArtist: "No album artist"
        case .noCover: "No cover art"
        case .noYear: "No year"
        case .noGenre: "No genre"
        }
    }

    /// How much a check found, in its own terms.
    public func countLabel(_ count: Int) -> String {
        switch self {
        case .duplicates: countText(count, "song with more than one copy", "songs with more than one copy")
        case .splitAlbums: countText(count, "album", "albums")
        default: countText(count, "song", "songs")
        }
    }

    /// What a finding means for the listener.
    public var meaning: String {
        switch self {
        case .duplicates:
            "The same recording is in your library more than once, so it shows up twice in your lists and takes up space."
        case .splitAlbums:
            "Each of these albums shows up as more than one album, because its songs' tags do not agree."
        case .noLength:
            "The server could not tell how long these songs are, which usually means the file is damaged or cut short."
        case .noTrackNumber:
            "These songs are on albums but have no track number, so their albums play out of order."
        case .noAlbumArtist:
            "Without an album artist, an album can be filed under each song's own artist and fall apart."
        case .noCover:
            "These songs have no picture, so they show a blank square."
        case .noYear:
            "These songs have no year, so year filters leave them out and they sort last by year."
        case .noGenre:
            "These songs have no genre, so genre pages and genre filters leave them out."
        }
    }

    /// What to do about it.
    public var advice: String {
        switch self {
        case .duplicates:
            "The first copy of each is the one to keep: it sounds best, or has the fullest tags. "
                + "Remove the others, unless a copy belongs to an album you want to keep whole."
        case .splitAlbums:
            "Give every song of the album the same album title, album artist and year with a tag editor, then let the server rescan."
        case .noLength:
            "Play one to check. If it will not play, replace the file."
        case .noCover:
            "Add a picture to the files, or put a cover image in the album's folder, then let the server rescan."
        case .noTrackNumber, .noAlbumArtist, .noYear, .noGenre:
            "Add the missing tag with a tag editor, then let the server rescan."
        }
    }

    /// What a fix button says for `count` items.
    public func fixAllLabel(_ count: Int) -> String {
        switch self {
        case .duplicates: "Fix \(countText(count, "song", "songs"))"
        case .splitAlbums: "Join \(countText(count, "album", "albums"))"
        case .noCover: "Find \(countText(count, "cover", "covers"))"
        case .noLength: "Find higher quality for \(countText(count, "song", "songs"))"
        case .noYear, .noGenre, .noAlbumArtist: "Fill in \(countText(count, "song", "songs")) from their albums"
        case .noTrackNumber: "Look up \(countText(count, "song", "songs"))"
        }
    }

    /// How a fix for a check works, in a sentence, for the preview.
    public var fixMeaning: String {
        switch self {
        case .duplicates:
            "Keeps the best copy of each song, fills in the tags it lacks from the others, and moves the others to the server's trash, where they can be put back."
        case .splitAlbums:
            "Gives the songs of the other parts the album tags of the largest part, album artist and all, so each album shows as one. "
                + "When one part's album artist already names every part's artist, that part leads instead."
        case .noCover:
            "Looks for each album's cover and puts it inside songs that have no picture. A picture already there is never replaced."
        case .noLength:
            "Asks the server for a higher quality copy of each song, which takes the damaged file's place once it passes the server's checks."
        case .noYear, .noGenre, .noAlbumArtist:
            "Fills in the tag where the rest of the album agrees on it. The others can be looked up the way a download is tagged, and every change is shown before it is written."
        case .noTrackNumber:
            "Looks each song up the way a download is tagged, and shows what it found before anything is written."
        }
    }
}

extension DuplicateBasis {
    public var words: String {
        switch self {
        case .tags: "Tagged as the same recording"
        case .titleAndLength: "Same title, artist and length"
        }
    }
}

extension BestReason {
    /// Which copy to keep and why, for a set whose best copy sounds like `best`.
    public func words(_ best: String) -> String {
        switch self {
        case .sound: "Keep the first, \(best)"
        case .tags: "They sound alike; the first has fuller tags"
        case .none: "They sound alike"
        }
    }
}

extension DuplicateGroup {
    /// "3 copies. Same title, artist and length. Keep the first, FLAC, 24-bit, 96 kHz."
    public func summary(_ fields: HealthFields<T>) -> String {
        "\(copies.count) copies. \(basis.words). \(bestReason.words(qualityText(best, fields)))."
    }

    /// The song and its artist.
    public func heading(_ fields: HealthFields<T>) -> String {
        guard let artist = fields.artist(best), !artist.trimmingCharacters(in: .whitespaces).isEmpty else { return fields.title(best) }
        return "\(fields.title(best)) by \(artist)"
    }
}

extension SplitAlbum {
    public var heading: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let by = artist.trimmingCharacters(in: .whitespaces).isEmpty ? name : "\(name) by \(artist.trimmingCharacters(in: .whitespacesAndNewlines))"
        return "\(by), shown as \(parts.count) albums"
    }

    /// Why the parts are one album, when their album artists differ, then what they disagree on.
    public var summary: String { (reasons.map(\.words) + differences.map(\.words)).joined(separator: " ") }
}

extension SplitReason {
    public var words: String {
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        switch basis {
        case .sharedArtist:
            return trim(song).isEmpty
                ? "One album filed under two artists: the part by \(trim(other)) names \(trim(artist)) too."
                : "One album filed under two artists: the part by \(trim(other)) has \(trim(song)) by \(trim(artist))."
        case .sameRelease: return "The parts are tagged as the same MusicBrainz release."
        case .sameReleaseGroup: return "The parts are tagged as the same MusicBrainz release group."
        case .sameBarcode: return "The parts carry the same barcode, \(value)."
        case .sameLabelAndYear: return "The parts came out on the same label in the same year: \(value)."
        }
    }
}

extension AlbumDifferenceValues {
    public var words: String {
        let trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let listed = trimmed.map { $0.isEmpty ? "none" : $0 }.joined(separator: ", ")
        // A space before or after the words is there but cannot be seen.
        let spaceOnly = Set(trimmed).count == 1
        if spaceOnly && kind == .title { return "The album title has a stray space on some songs." }
        if spaceOnly && kind == .albumArtist { return "The album artist has a stray space on some songs." }
        switch kind {
        case .title: return "The album title is written differently: \(listed)."
        case .albumArtist: return "The album artist differs: \(listed)."
        case .year: return "The year differs: \(listed)."
        case .other: return "Something else in the tags differs, often a release date or an album id on only some songs."
        }
    }
}

/// How a copy sounds, in a few words: "FLAC, 24-bit, 96 kHz" or "MP3, 320 kbps".
public func qualityText<T>(_ song: T, _ fields: HealthFields<T>) -> String {
    qualityText(format: fields.format(song), lossless: fields.lossless(song), bitDepth: fields.bitDepth(song),
                sampleRate: fields.sampleRate(song), bitRate: fields.bitRate(song))
}

public func qualityText(format: String?, lossless: Bool, bitDepth: Int?, sampleRate: Int?, bitRate: Int?) -> String {
    var parts: [String] = []
    if let format, !format.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(format.uppercased()) }
    if lossless {
        if let bitDepth, bitDepth > 0 { parts.append("\(bitDepth)-bit") }
        if let sampleRate, sampleRate > 0 {
            let tenths = (sampleRate + 50) / 100
            parts.append(tenths % 10 == 0 ? "\(tenths / 10) kHz" : "\(tenths / 10).\(tenths % 10) kHz")
        }
    } else if let bitRate, bitRate > 0 {
        parts.append("\(bitRate) kbps")
    }
    return parts.isEmpty ? "unknown quality" : parts.joined(separator: ", ")
}

extension HealthReport {
    /// The line under the page's title.
    public var overview: String {
        let checkedText = "Checked \(countText(checked, "song", "songs"))."
        if clean { return checkedText }
        let kinds = findings.count
        return "\(checkedText) \(kinds == 1 ? "One thing" : "\(kinds) things") could be better."
    }
}

/// What the page says when there is nothing to fix.
public let healthAllClear = "No second copies, no split albums and no missing tags. There is nothing to fix."
