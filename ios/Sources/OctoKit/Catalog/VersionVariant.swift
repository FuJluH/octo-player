import Foundation

/// Which versions of a song its album says it is, read from where `SongIdentity` does not look:
/// a plainly named track on "Let's Get Lost Remixes", "Too Close (Radio Edit) - Single" or "Club
/// Hits (Extended Mixes)". Read word for word as the server reads an album, so the two agree on
/// what a version is.
public enum VersionVariant {
    private static let S = SongIdentity.S
    private static let W = SongIdentity.W
    private static let B = "(?<!\(W))"
    private static let E = "(?!\(W))"

    /// Case is ignored for every letter, as the server ignores it.
    private static func rxi(_ pattern: String) -> TextPattern {
        TextPattern(pattern, case: .unicode, unixLines: true)
    }

    /// Words that name a version wherever they stand, bracketed or not, under `SongIdentity`'s
    /// own names so the two readings can be compared. Only words no album, artist or label is
    /// likely to be called: no bare "clean" (Clean Bandit) or "acoustic" (Acoustic Soul); a
    /// bracket still reads those.
    private static let words: [(TextPattern, String)] = [
        (rxi("\(B)radio\(S)+(?:edit|version|mix|cut)s?\(E)"), "radio edit"),
        (rxi("\(B)extended\(E)(?!\(S)+(?:edition|play)\(E))"), "extended"),
        (rxi("\(B)(?:re-?mix(?:es|ed)?|rmx)\(E)"), "remix"),
        (rxi("\(B)(?:sped|speed)\(S)*up\(E)"), "sped up"),
        (rxi("\(B)slowed\(E)"), "slowed"),
        (rxi("\(B)nightcore\(E)"), "nightcore"),
        (rxi("\(B)instrumentals?\(E)"), "instrumental"),
        (rxi("\(B)(?:a\(S)*cappellas?|acapellas?)\(E)"), "acapella"),
        (rxi("\(B)karaoke\(E)"), "karaoke"),
        (rxi("\(B)drumless\(E)"), "drumless"),
        (rxi("\(B)mash(?:\(S)|-)?ups?\(E)"), "mashup"),
        (rxi("\(B)medley\(E)"), "medley"),
        (rxi("\(B)mega(?:\(S)|-)?mix\(E)"), "megamix"),
        (rxi("\(B)8d\(S)+audio\(E)"), "8d"),
        (rxi("\(B)(?:dj|continuous|non-?stop)\(S)+mix(?:es)?\(E)|\(B)mixed\(S)+by\(E)"), "dj mix"),
    ]

    /// What an album's brackets can say that is no version of the songs on it: a generic
    /// "(Japanese Version)" or "(Mix)", a label called Reprise, a "[+cover]" scan, a VIP pack,
    /// and the live words.
    private static let notFromAnAlbum: Set<String> = ["mix", "edit", "version", "reprise", "cover", "vip", "live", "unplugged", "bootleg"]

    /// An album edition, not a version of its songs.
    private static let edition = rxi("\(B)extended\(S)+(?:edition|play)\(E)")

    /// The words in a text, in the list's order.
    private static func wordsIn(_ text: String?) -> [String] {
        guard let text, !SongIdentity.isBlank(text) else { return [] }
        return words.filter { $0.0.containsMatch(in: text) }.map(\.1)
    }

    /// A title's versions that make it a different recording, as `SongIdentity` reads them.
    private static func distinct(_ title: String) -> Set<String> {
        SongIdentity.distinctVersions(SongIdentity.parseTitle(title))
    }

    /// The versions a title and an album ask for.
    public static func requested(_ title: String?, _ album: String?) -> Set<String> {
        var wanted = Set<String>()
        for text in [title, album].compactMap({ $0 }) where !SongIdentity.isBlank(text) {
            wanted.formUnion(distinct(text))
            wanted.formUnion(wordsIn(text))
        }
        return wanted
    }

    /// A letter or a number in one UTF-16 unit: half of a surrogate pair is neither.
    private static func letterOrNumber(_ unit: UInt16) -> Bool {
        let category = generalCategory(unit)
        if isLetterCategory(category) { return true }
        switch category {
        case .decimalNumber, .letterNumber, .otherNumber: return true
        default: return false
        }
    }

    /// Whether a match from `start` to `end` stands alone: no letter or number right before or
    /// after it.
    private static func standsAlone(_ units: [UInt16], _ start: Int, _ end: Int) -> Bool {
        !(start > 0 && letterOrNumber(units[start - 1])) && !(end < units.count && letterOrNumber(units[end]))
    }

    /// Every match of the pattern that stands alone, left to right and never overlapping: a
    /// start where the bounds fail is tried again one character on.
    private static func aloneMatches(_ pattern: TextPattern, _ text: String) -> [Range<Int>] {
        let units = text.units
        var found: [Range<Int>] = []
        var at = 0
        while at <= units.count {
            guard let candidate = pattern.find(text, from: at) else { break }
            let start = candidate.start
            let end = candidate.end
            if end > start && standsAlone(units, start, end) {
                found.append(start..<end)
                at = end
            } else if start < units.count {
                let pair = UTF16.isLeadSurrogate(units[start]) && start + 1 < units.count && UTF16.isTrailSurrogate(units[start + 1])
                at = start + (pair ? 2 : 1)
            } else {
                at = start + 1
            }
        }
        return found
    }

    /// The text with the artist's own name taken out, so a band called Live, or an album named
    /// after its artist, is never read as a version.
    public static func withoutArtist(_ text: String, _ artist: String?) -> String {
        guard let artist, !SongIdentity.isBlank(artist), !text.isEmpty else { return text }
        var names = SongIdentity.parseArtists(artist).names
        names.append(SongIdentity.trimSpace(artist))
        names = names.filter { SongIdentity.trimSpace($0).utf16.count > 1 }
        // Longest first, names of one length in their order.
        let ordered = names.enumerated().sorted { a, b in
            let la = a.element.utf16.count, lb = b.element.utf16.count
            return la != lb ? la > lb : a.offset < b.offset
        }.map(\.element)
        var result = text
        for name in ordered {
            let pattern = rxi(NSRegularExpression.escapedPattern(for: SongIdentity.trimSpace(name)))
            let found = aloneMatches(pattern, result)
            if found.isEmpty { continue }
            let units = result.units
            var replaced: [UInt16] = []
            replaced.reserveCapacity(units.count)
            var last = 0
            for range in found {
                replaced += units[last..<range.lowerBound]
                replaced.append(0x20)
                last = range.upperBound
            }
            replaced += units[last...]
            result = String(units: replaced)
        }
        return result
    }

    /// The versions an album's name says its songs are, live words left out.
    public static func inFolder(_ folder: String, _ artist: String?) -> Set<String> {
        let text = edition.replace(withoutArtist(folder, artist), " ")
        var found = distinct(text).filter { !notFromAnAlbum.contains($0) }
        found.formUnion(wordsIn(text))
        return found
    }
}
