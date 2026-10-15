import Foundation

/// What a comparison of two songs found.
public enum SongVerdict: String, Sendable, Codable {
    /// Another song, or another artist's song.
    case different = "Different"

    /// The same song in another version: live against studio, a remix, a sped-up upload, a
    /// different guest, or a length that is too far off.
    case sameSongDifferentVersion = "SameSongDifferentVersion"

    /// The same recording.
    case same = "Same"
}

/// A verdict, how sure it is (0 to 1), and why, in words a log or a person can read.
public struct SongMatch: Equatable, Sendable {
    public var verdict: SongVerdict
    public var confidence: Double
    public var reason: String

    public init(_ verdict: SongVerdict, _ confidence: Double, _ reason: String) {
        self.verdict = verdict
        self.confidence = confidence
        self.reason = reason
    }

    public var isSame: Bool { verdict == .same }
}

/// How one call site wants songs compared. The defaults are the strict reading.
public struct SongMatchOptions: Equatable, Sendable {
    /// How far apart two known lengths may be and still be one recording. Nil compares no
    /// lengths.
    public var lengthToleranceSeconds: Int?
    /// When on, a bracketed subtitle only one title carries ("Blue (Da Ba Dee)" against "Blue")
    /// makes them different songs. Off, it only lowers the confidence.
    public var extrasMustAgree: Bool
    /// Version markers this caller treats as the same recording, on top of the ones that always
    /// are (remaster, explicit, original mix, album version, mono, stereo).
    public var alsoNeutral: Set<String>

    public init(
        lengthToleranceSeconds: Int? = SongIdentity.LENGTH_TOLERANCE_SECONDS,
        extrasMustAgree: Bool = false,
        alsoNeutral: Set<String> = []
    ) {
        self.lengthToleranceSeconds = lengthToleranceSeconds
        self.extrasMustAgree = extrasMustAgree
        self.alsoNeutral = alsoNeutral
    }

    public static let Default = SongMatchOptions()

    /// Lengths left out, for a caller that compares them its own way.
    public static let AnyLength = SongMatchOptions(lengthToleranceSeconds: nil)
}

/// One side of a comparison. Seconds is the length when it is known. Isrcs are the codes a
/// source gave the song, as it wrote them; anything that is not a valid ISRC is ignored.
public struct SongRef: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var seconds: Double?
    public var isrcs: [String?]

    public init(title: String?, artist: String?, seconds: Double? = nil, isrcs: [String?] = []) {
        self.title = title
        self.artist = artist
        self.seconds = seconds
        self.isrcs = isrcs
    }
}

/// One query to try against a search service, in the order queryVariants gives them. Artist is
/// empty for the title-only query.
public struct SongQuery: Equatable, Hashable, Sendable {
    public var title: String
    public var artist: String

    public init(title: String, artist: String) {
        self.title = title
        self.artist = artist
    }

    /// The artist and the title as one free-text query.
    public var text: String { artist.isEmpty ? title : "\(artist) \(title)" }
}

/// A title read into its parts.
/// - raw: the title as given.
/// - core: what is left once track numbers, a leading "Artist - ", brackets, features and
///   version tails are taken off: the title a person would say.
/// - key: the core compared exactly: casefolded, accents and punctuation ignored, with any part
///   number ("Pt. 2") kept.
/// - looseKey: the key again with stylized characters read as letters ($ as s, 0 as o, 3 as e,
///   @ as a, ! as i). An additional key, never a replacement.
/// - versions: every version marker found, canonical names, sorted.
/// - remixers: keys of whoever a remix, mix, dub or edit is credited to.
/// - featured: artists the title credits, "(feat. X)".
/// - extras: keys of bracketed subtitles that are none of the above, "(Da Ba Dee)".
/// - artistFromTitle: the artist a title named in "Artist - Title" form.
/// - keyed: the core with its part numbers, before keying: where numbers are still apart.
public struct SongTitle: Equatable, Sendable {
    public var raw: String
    public var core: String
    public var key: String
    public var looseKey: String
    public var versions: [String]
    public var remixers: [String]
    public var featured: [String]
    public var extras: [String]
    public var artistFromTitle: String?
    var keyed: String

    public init(
        raw: String, core: String, key: String, looseKey: String, versions: [String], remixers: [String],
        featured: [String], extras: [String], artistFromTitle: String?, keyed: String? = nil
    ) {
        self.raw = raw
        self.core = core
        self.key = key
        self.looseKey = looseKey
        self.versions = versions
        self.remixers = remixers
        self.featured = featured
        self.extras = extras
        self.artistFromTitle = artistFromTitle
        self.keyed = keyed ?? core
    }
}

/// An artist credit read into its parts.
/// - display: the credit with channel suffixes, other-script aliases and bracketed guests taken
///   off.
/// - names: the artists in it, split on every separator but never inside a known name ("Tyler,
///   The Creator") or before "the" ("Bob Marley & The Wailers"). The first is the primary artist.
/// - featured: guests credited in brackets, "Drake (feat. Rihanna)".
/// - pieces: parts of a name kept whole only by the "the" rule, so "Bob Marley" alone still
///   matches "Bob Marley & The Wailers".
public struct SongArtists: Equatable, Sendable {
    public var raw: String
    public var display: String
    public var names: [String]
    public var featured: [String]
    public var pieces: [String]

    public init(raw: String, display: String, names: [String], featured: [String], pieces: [String]) {
        self.raw = raw
        self.display = display
        self.names = names
        self.featured = featured
        self.pieces = pieces
    }

    public var primary: String { names.first ?? display }
    public var isEmpty: Bool { SongIdentity.key(display).isEmpty && names.isEmpty }
}

/// How two artist credits relate.
public enum ArtistAgreement: String, Sendable {
    /// Either side is empty.
    case unknown = "Unknown"

    /// No artist in common.
    case none = "None"

    /// They share an artist, but each names a guest the other does not.
    case conflict = "Conflict"

    /// They share an artist only once stylized characters are read as letters.
    case loose = "Loose"

    /// They share an artist.
    case agree = "Agree"
}

/// A song's keys for remembering it across sources: its primary artist, and its title with the
/// version markers that make another recording.
public struct SongKeys: Equatable, Hashable, Sendable {
    public var artist: String
    public var title: String

    public init(artist: String, title: String) {
        self.artist = artist
        self.title = title
    }

    public var matchKey: String { "\(artist)|\(title)" }
}

/// One reading of song titles and artist credits for every place the app decides whether two
/// songs are the same: merging the library's sources, finding a library song for one the server
/// sent, following downloads, and the online lyrics. The server reads them the same way; the
/// shared case file (song-identity-cases.json) is the contract both run.
///
/// The rules, in the order a title is read:
///
/// 1. Fold: Unicode NFKC (fullwidth "＄" and "﹩" become "$", "（" becomes "("), curly quotes and
///    dashes made plain, underscores made spaces, Cyrillic and Greek lookalikes inside a Latin
///    word read as Latin.
/// 2. A track number in front ("01 - ", "01. ", "1-01 ") is dropped, and so is a leading
///    "Artist - " when it names the artist (or when no artist was given at all).
/// 3. Each bracket is read as a guest ("feat. X"), upload noise ("Official Video"), a part number
///    ("Pt. 2", kept in the key), one or more version markers, or a subtitle.
/// 4. A " - " tail that is a version or noise ("- Remastered 2011", "- Live at Wembley") is read
///    the same way, and so is a trailing "feat. X" and a trailing "Remix" or "Sped Up".
/// 5. The key is the rest, casefolded, accents stripped, and only letters, digits and the marks
///    some scripts need kept. A title of only symbols or emoji keeps its symbols instead.
///
/// Artist credits split on , & ; / 、 x × and with feat ft featuring vs, and the whole credit is
/// kept as a candidate beside its parts, so "Simon & Garfunkel" and "Earth, Wind & Fire" match
/// themselves however they are split. A small alias table covers renamed artists ("Ye" for Kanye
/// West), and a bracketed alias in another script ("Ye (侃爷)") is ignored.
///
/// Text is read one UTF-16 unit at a time wherever the server does, and the patterns spell out
/// their spaces, digits and word edges, so the apps, the tests and the server all agree.
public enum SongIdentity {
    /// How far apart two lengths may be and still be one recording.
    public static let LENGTH_TOLERANCE_SECONDS = 3

    /// Version markers that never make a different recording.
    public static let NeutralVersions: Set<String> = ["remaster", "explicit", "original", "album version", "single version", "mono", "stereo"]

    /// For telling duplicates apart: a subtitle only one title has ("Song (Interlude)") is
    /// another title.
    public static let StrictTitles = SongMatchOptions(lengthToleranceSeconds: nil, extrasMustAgree: true)

    // MARK: - Folding

    /// The text with its lookalikes made plain, case and accents untouched: NFKC, curly quotes
    /// and dashes folded, underscores as spaces, whitespace collapsed. What every other reading
    /// starts from, and what a query is sent as.
    public static func fold(_ value: String?) -> String {
        guard let value, !isBlank(value) else { return "" }
        // Plain ASCII has nothing to normalize and no lookalikes: only its spacing, backticks and
        // underscores change.
        if value.utf16.allSatisfy({ $0 >= 0x20 && $0 <= 0x7E }) {
            let plain = value.replacingUnit(0x60, with: 0x27).replacingUnit(0x5F, with: 0x20)
            return trimSpace(plain.utf16Contains("  ") ? Whitespace.replace(plain, " ") : plain)
        }
        let text = value.replacingUnit(0xB4, with: 0x27).precomposedStringWithCompatibilityMapping
        var sb: [UInt16] = []
        sb.reserveCapacity(text.utf16.count)
        for ch in text.utf16 {
            switch ch {
            case 0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x60: sb.append(0x27)
            case 0x201C, 0x201D, 0x201E, 0x201F, 0x2033: sb.append(0x22)
            case 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015, 0x2212: sb.append(0x2D)
            case 0x3010, 0x3016: sb.append(0x5B)
            case 0x3011, 0x3017: sb.append(0x5D)
            case 0x3014: sb.append(0x28)
            case 0x3015: sb.append(0x29)
            case 0x5F: sb.append(0x20)
            default: sb.append(isSpace(unit: ch) ? 0x20 : ch)
            }
        }
        return trimSpace(Whitespace.replace(foldMixedScriptWords(sb), " "))
    }

    /// The exact key: casefolded, accents stripped, "&" read as "and", and only letters, digits
    /// and combining marks kept. Symbols only when there is nothing else.
    public static func key(_ value: String?) -> String {
        let lower = lowerFold(fold(value))
        if lower.isEmpty { return "" }
        var sb = String.UnicodeScalarView()
        for point in lower.unicodeScalars {
            let type = point.properties.generalCategory
            if isLetterOrDigit(type) || type == .nonspacingMark || type == .spacingMark { sb.append(point) }
        }
        if !sb.isEmpty { return String(sb) }
        // "!!!" or an emoji: nothing is a letter, so the symbols are the name.
        for point in lower.unicodeScalars where !isSpace(point.value) { sb.append(point) }
        return String(sb)
    }

    /// The key with stylized characters read as letters, so "$uicideboy$" and "Suicideboys"
    /// agree. Only ever an additional key.
    public static func looseKey(_ value: String?) -> String { key(foldStylized(fold(value))) }

    /// Stylized characters read as the letters they stand for: $ as s, @ as a, 0 as o and 3 as e
    /// when they sit against a letter, ! as i between two letters. "2003", "Blink-182" and
    /// "Help!" are left alone.
    public static func foldStylized(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let text = value.units
        var sb: [UInt16] = []
        sb.reserveCapacity(text.count)
        for i in text.indices {
            let ch = text[i]
            let prev: UInt16 = i > 0 ? text[i - 1] : 0x20
            let next: UInt16 = i + 1 < text.count ? text[i + 1] : 0x20
            let letterBeside = isLetterUnit(prev) || isLetterUnit(next)
            let digitBeside = isDigit(prev) || isDigit(next)
            let upper = isLetterUnit(next) ? isUpper(next) : isUpper(prev)
            let read: UInt16?
            if ch == 0x24 && letterBeside {
                read = 0x73 // s
            } else if ch == 0x40 && letterBeside {
                read = 0x61 // a
            } else if ch == 0x21 && isLetterUnit(prev) && isLetterUnit(next) {
                read = 0x69 // i
            } else if ch == 0x30 && letterBeside && !digitBeside {
                read = 0x6F // o
            } else if ch == 0x33 && letterBeside && !digitBeside {
                read = 0x65 // e
            } else {
                read = nil
            }
            if let read { sb.append(upper ? read - 0x20 : read) } else { sb.append(ch) }
        }
        return String(units: sb)
    }

    /// The folded text lowercased and without accents, spacing and punctuation kept: for matching
    /// words inside something that is not a title, such as a file name.
    public static func plain(_ value: String?) -> String { lowerFold(fold(value)) }

    // Cyrillic and Greek letters that look Latin, read as Latin inside a word that also has
    // Latin letters. A word wholly in Cyrillic or Greek is left as it is.
    private static let Homoglyphs: [UInt16: UInt16] = {
        let pairs: [(Character, Character)] = [
            ("А", "A"), ("В", "B"), ("Е", "E"), ("К", "K"), ("М", "M"), ("Н", "H"), ("О", "O"),
            ("Р", "P"), ("С", "C"), ("Т", "T"), ("Х", "X"), ("І", "I"), ("Ј", "J"), ("Ѕ", "S"),
            ("а", "a"), ("е", "e"), ("о", "o"), ("р", "p"), ("с", "c"), ("у", "y"), ("х", "x"),
            ("і", "i"), ("ј", "j"), ("ѕ", "s"),
            ("Α", "A"), ("Β", "B"), ("Ε", "E"), ("Ζ", "Z"), ("Η", "H"), ("Ι", "I"), ("Κ", "K"),
            ("Μ", "M"), ("Ν", "N"), ("Ο", "O"), ("Ρ", "P"), ("Τ", "T"), ("Υ", "Y"), ("Χ", "X"),
            ("ο", "o"),
        ]
        var map: [UInt16: UInt16] = [:]
        for (from, to) in pairs { map[from.utf16.first!] = to.utf16.first! }
        return map
    }()

    // Words are runs of letters and marks, read one UTF-16 unit at a time, so a letter outside
    // the basic plane ends a word as it does on the server.
    private static func foldMixedScriptWords(_ text: [UInt16]) -> String {
        var sb: [UInt16] = []
        sb.reserveCapacity(text.count)
        var i = 0
        while i < text.count {
            if !isLetterOrMark(text[i]) {
                sb.append(text[i])
                i += 1
                continue
            }
            var end = i
            while end < text.count && isLetterOrMark(text[end]) { end += 1 }
            let word = text[i..<end]
            let latin = word.contains { ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }
            if latin && word.contains(where: { Homoglyphs[$0] != nil }) {
                for unit in word { sb.append(Homoglyphs[unit] ?? unit) }
            } else {
                sb += word
            }
            i = end
        }
        return String(units: sb)
    }

    // Lowercase, the letters that do not decompose spelled out, accents stripped, "&" and a
    // spaced "+" read as "and".
    private static func lowerFold(_ folded: String) -> String {
        if folded.isEmpty { return "" }
        // Plain ASCII has no accents to strip.
        if folded.utf16.allSatisfy({ $0 < 0x80 }) {
            return String(units: folded.utf16.map(simpleLower)).replacingAll("&", " and ").replacingAll(" + ", " and ")
        }
        let lower = lowerInvariant(folded)
            .replacingAll("ß", "ss").replacingAll("æ", "ae").replacingAll("œ", "oe").replacingAll("ø", "o")
            .replacingAll("đ", "d").replacingAll("ð", "d").replacingAll("ł", "l").replacingAll("þ", "th").replacingAll("ı", "i")
            .replacingAll("&", " and ").replacingAll(" + ", " and ")
        let decomposed = lower.decomposedStringWithCanonicalMapping
        var sb: [UInt16] = []
        sb.reserveCapacity(decomposed.utf16.count)
        for ch in decomposed.utf16 {
            // Only the Latin, Greek and Cyrillic accents. A kana's voicing mark is a different
            // letter, and stripping it would make two Japanese titles one.
            if (0x0300...0x036F).contains(ch) || (0x1AB0...0x1AFF).contains(ch) || (0x1DC0...0x1DFF).contains(ch)
                || (0xFE20...0xFE2F).contains(ch) {
                continue
            }
            sb.append(ch)
        }
        return String(units: sb).precomposedStringWithCanonicalMapping
    }

    // MARK: - Titles

    // "01 - ", "01. ", "1-01 ", "2) " in front of a title, with a letter after it.
    // "1-800-273-8255" and "99 Problems" keep their numbers.
    private static let TrackNumber = rx(
        #"^(?:\#(D){1,2}-\#(D){1,3}\#(S)+|\#(D){1,3}\#(S)*[.)]\#(S)*|\#(D){1,3}\#(S)+-\#(S)+)(?=[^\p{Nd}\t\n\u000B\f\r\u0085\p{Z}.])"#
    )

    private static let Bracket = rx(#"\#(S)*[\(\[\{]([^\(\)\[\]\{\}]*)[\)\]\}]"#)

    // A bracket a truncated title never closed, "Song (feat. X".
    private static let OpenBracket = rx(#"\#(S)+[\(\[]([^\(\)\[\]]*)$"#)

    private static let DashTail = rx(#"\#(S)+-\#(S)+"#)

    private static let TrailingFeature = rx(#"\#(S)+(?:feat\.?|ft\.?|featuring)\#(S)+(.+)$"#, ignoreCase: true)

    // Version words that mean a version even without brackets at the end of a title, "Mask Off
    // Remix", "Heat Waves Sped Up". Not "live" or "edit": too many titles end in them.
    private static let TrailingVersion = rx(
        #"\#(S)+(re-?mix|rmx|sped\#(S)*up|speed\#(S)*up|slowed(?:\#(S)*(?:\+|&|and|n)\#(S)*reverb(?:ed)?)?|slowed\#(S)+down|nightcore|instrumental|acapella|a\#(S)*cappella|karaoke(?:\#(S)+version)?|drumless|8d\#(S)+audio)$"#,
        ignoreCase: true
    )

    private static let FeatureLead = rx(#"^(?:feat\.\#(S)*|ft\.\#(S)*|w/\#(S)*|(?:feat|ft|featuring|with)\#(S)+)(.+)$"#, ignoreCase: true)

    private static let PartNumber = rx(#"^(?:(?:pt|part|vol|volume|chapter|ch|no|book)\.?\#(S)*)?(?:\#(D){1,3}|[ivx]{1,4})$"#, ignoreCase: true)

    private static let Year = rx(#"^(?:19|20)\#(D){2}$"#)

    // A part number, "Pt. 2", "Part II", "Vol. 3", spelled one way so "Part II" and "Pt. 2"
    // agree.
    private static let PartWord = rx(#"\#(B)(?:(pt|part)|(vol|volume)|(chapter|ch)|(book))\.?\#(S)*(\#(D){1,3}|[ivx]{1,4})\#(E)"#, ignoreCase: true)

    private static let Romans = ["i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x"]

    private static func partOf(_ match: TextMatch) -> String {
        let word: String
        if match.group(1) != nil {
            word = "pt"
        } else if match.group(2) != nil {
            word = "vol"
        } else if match.group(3) != nil {
            word = "ch"
        } else {
            word = "book"
        }
        let number = lowerInvariant(match.groupValue(5))
        let roman = Romans.firstIndex(of: number)
        return "\(word) \(roman.map { String($0 + 1) } ?? number)"
    }

    // Words that only ever describe how something was uploaded, never which recording it is. A
    // bracket made only of these is dropped.
    private static let UploadNoise = [
        "official", "music", "video", "audio", "lyric", "lyrics", "visualizer", "visualiser",
        "hd", "hq", "uhd", "4k", "8k", "1080p", "720p", "480p", "mv", "m/v", "clip", "videoclip",
        "with", "full", "song", "only", "new", "premiere", "animated",
    ]

    private static let NeutralPhrase = rx(
        #"^(?:from|taken from|as heard (?:in|on)|as featured in|as seen (?:in|on)|theme from|music from)\#(E)"#
            + #"|\#(B)(?:soundtrack|ost|motion picture|original score)\#(E)"#
            + #"|^bonus(?:\#(S)+tracks?)?(?:\#(S)+(?:edition|version))?$|^(?:prod|produced)\#(E)"#
            // A release edition is the same recordings packaged again; "Drumless Edition" is a
            // marker below.
            + #"|^(?:(?:super\#(S)+)?deluxe|expanded|(?:\#(D)+(?:st|nd|rd|th)\#(S)+)?anniversary|special|collector'?s|limited|tour|platinum)(?:\#(S)+(?:edition|version))?$"#
            + #"|^(?:copyright free|free download|out now|audio only|single|ep)$"#,
        ignoreCase: true
    )

    private struct Marker: Sendable {
        let pattern: TextPattern
        let name: String
        let credited: Bool
        let generic: Bool

        init(_ pattern: String, _ name: String, credited: Bool = false, generic: Bool = false) {
            self.pattern = SongIdentity.rx(pattern, ignoreCase: true)
            self.name = name
            self.credited = credited
            self.generic = generic
        }
    }

    // Version markers, most specific first. Each match is taken out of the text before the next
    // is looked for, so "Extended Mix" is extended and not also a mix.
    private static let Markers: [Marker] = [
        Marker(#"\#(B)radio\#(S)+(?:edit|version|mix|cut)\#(E)"#, "radio edit"),
        Marker(#"\#(B)extended(?:\#(S)+(?:mix|version|edit|cut))?\#(E)"#, "extended"),
        Marker(#"\#(B)original\#(S)+(?:mix|version)\#(E)"#, "original"),
        Marker(#"\#(B)(?:album|lp)\#(S)+version\#(E)"#, "album version"),
        Marker(#"\#(B)single\#(S)+version\#(E)"#, "single version"),
        Marker(#"\#(B)(?:\#(D){4}\#(S)+)?(?:digital(?:ly)?\#(S)+)?re-?master(?:ed)?(?:\#(S)+\#(D){4})?(?:\#(S)+(?:version|edition))?\#(E)"#, "remaster"),
        Marker(#"\#(B)live\#(E)"#, "live"),
        Marker(#"\#(B)unplugged\#(E)"#, "unplugged"),
        Marker(#"\#(B)acoustic(?:\#(S)+version)?\#(E)"#, "acoustic"),
        Marker(#"\#(B)instrumental(?:\#(S)+version)?\#(E)"#, "instrumental"),
        Marker(#"\#(B)(?:a\#(S)*cappella|acapella)\#(E)"#, "acapella"),
        Marker(#"\#(B)demo(?:\#(S)+version)?\#(E)"#, "demo"),
        Marker(#"\#(B)(?:sped\#(S)*up|speed\#(S)*up)\#(E)"#, "sped up"),
        Marker(#"\#(B)slowed(?:\#(S)+down)?\#(E)"#, "slowed"),
        Marker(#"\#(B)reverb(?:ed)?\#(E)"#, "reverb"),
        Marker(#"\#(B)nightcore\#(E)"#, "nightcore"),
        // Editions that change what is played, unlike a deluxe or anniversary one
        // (NeutralPhrase).
        Marker(#"\#(B)drumless\#(E)"#, "drumless"),
        Marker(#"\#(B)8d(?:\#(S)+audio)?\#(E)"#, "8d"),
        Marker(#"\#(B)piano(?:\#(S)+(?:version|edition|arrangement))?\#(E)"#, "piano"),
        Marker(#"\#(B)(?:orchestral|symphonic)(?:\#(S)+(?:version|edition|mix))?\#(E)"#, "orchestral"),
        Marker(#"\#(B)lo-?fi(?:\#(S)+(?:version|edit|mix))?\#(E)"#, "lofi"),
        Marker(#"\#(B)bass\#(S)*boost(?:ed)?\#(E)"#, "bass boosted"),
        // Two songs or more in one: never the song asked for. Ahead of "mix", so a megamix is
        // not a mix.
        Marker(#"\#(B)mash(?:\#(S)|-)?ups?\#(E)"#, "mashup"),
        Marker(#"\#(B)medley\#(E)"#, "medley"),
        Marker(#"\#(B)mega(?:\#(S)|-)?mix\#(E)"#, "megamix"),
        Marker(#"\#(B)blend\#(E)"#, "blend"),
        Marker(#"^([^\n]*?)\#(S)*\#(B)(?:re-?mix(?:ed)?|rmx)\#(E)"#, "remix", credited: true),
        Marker(#"\#(B)vip(?:\#(S)+mix)?\#(E)"#, "vip"),
        Marker(#"\#(B)bootleg\#(E)"#, "bootleg"),
        Marker(#"\#(B)rework(?:ed)?\#(E)"#, "rework"),
        Marker(#"^([^\n]*?)\#(S)*\#(B)dub(?:\#(S)+(?:mix|version))?\#(E)"#, "dub", credited: true),
        Marker(#"\#(B)(?:clean|censored)(?:\#(S)+(?:version|edit))?\#(E)"#, "clean"),
        Marker(#"\#(B)(?:explicit|dirty)(?:\#(S)+version)?\#(E)"#, "explicit"),
        Marker(#"\#(B)mono(?:\#(S)+(?:version|mix))?\#(E)"#, "mono"),
        Marker(#"\#(B)stereo(?:\#(S)+(?:version|mix))?\#(E)"#, "stereo"),
        Marker(
            #"\#(B)karaoke(?:\#(S)+version)?\#(E)|\#(B)originally performed by\#(E)|\#(B)in the style of\#(E)|\#(B)made (?:popular|famous) by\#(E)|\#(B)backing (?:version|track)\#(E)"#,
            "karaoke"
        ),
        Marker(#"\#(B)cover(?:\#(S)+version)?\#(E)"#, "cover"),
        Marker(#"\#(B)reprise\#(E)"#, "reprise"),
        Marker(#"\#(B)sessions?\#(E)"#, "session"),
        Marker(#"^([^\n]*?)\#(S)*\#(B)mix\#(E)"#, "mix", credited: true, generic: true),
        Marker(#"^([^\n]*?)\#(S)*\#(B)edit\#(E)"#, "edit", credited: true, generic: true),
        Marker(#"\#(B)version\#(E)"#, "version", generic: true),
    ]

    // Words in front of a mix that name its kind, not who made it.
    private static let NotACredit: Set<String> = ["", "the", "official", "club", "dance", "house", "main", "short", "long", "full", "new", "a"]

    private enum Kind { case noise, feature, part, version, extra }

    private struct Reading {
        let kind: Kind
        let versions: [String]
        let credits: [String]
        let names: [String]
    }

    // What one bracket or " - " tail says.
    private static func read(_ inner: String) -> Reading {
        let text = trimSpace(inner).trimUnits { $0 == 0x2D || $0 == 0x3A || $0 == 0x2C || $0 == 0x20 }
        var versions: [String] = []
        var credits: [String] = []
        if text.isEmpty { return Reading(kind: .noise, versions: versions, credits: credits, names: []) }

        let words = splitUnits(text, [0x20, 0x2D]).filter { !$0.isEmpty }
        if words.allSatisfy({ word in UploadNoise.contains { $0.equalsIgnoreCase(word) } }) {
            return Reading(kind: .noise, versions: versions, credits: credits, names: [])
        }

        if let feature = FeatureLead.find(text) {
            return Reading(kind: .feature, versions: versions, credits: credits, names: splitNames(feature.groupValue(1)).names)
        }

        if PartNumber.containsMatch(in: text) { return Reading(kind: .part, versions: versions, credits: credits, names: []) }
        if NeutralPhrase.containsMatch(in: text) || Year.containsMatch(in: text) {
            return Reading(kind: .noise, versions: versions, credits: credits, names: [])
        }

        var rest = text
        for marker in Markers {
            if marker.generic && !versions.isEmpty { continue }
            guard let match = marker.pattern.find(rest) else { continue }
            if !versions.contains(marker.name) { versions.append(marker.name) }
            if marker.credited {
                let credit = key(match.groupValue(1))
                if !NotACredit.contains(credit) { credits.append(credit) }
            }
            rest = rest.utf16Slice(0, match.start) + " " + rest.utf16Slice(from: match.end)
        }
        return versions.isEmpty
            ? Reading(kind: .extra, versions: versions, credits: credits, names: [])
            : Reading(kind: .version, versions: versions, credits: credits, names: [])
    }

    /// A title read into its core, its key, its version markers and its guests. The artist, when
    /// given, lets a leading "Artist - " be recognised; an artist given as empty means the song
    /// has none, and then any "X - Y" title is read as artist X and title Y. Nil reads the title
    /// alone.
    public static func parseTitle(_ title: String?, artist: String? = nil) -> SongTitle {
        let raw = title ?? ""
        var text = fold(raw)
        var versions: [String] = []
        var remixers: [String] = []
        var featured: [String] = []
        var extras: [String] = []
        var parts: [String] = []
        var artistFromTitle: String?

        func take(_ reading: Reading, _ original: String) {
            switch reading.kind {
            case .feature: featured += reading.names
            case .part: parts.append(trimSpace(original))
            case .version:
                for version in reading.versions where !versions.contains(version) { versions.append(version) }
                remixers += reading.credits
            case .extra: extras.append(key(original))
            case .noise: break
            }
        }

        if let numbered = TrackNumber.find(text) {
            let after = text.utf16Slice(from: numbered.value.utf16.count)
            if after.utf16.contains(where: isLetterUnit) { text = after }
        }

        // "Artist - Title": the artist named in front, or any name at all when no artist was
        // given.
        if let dash = DashTail.find(text), dash.start > 0 {
            let left = text.utf16Slice(0, dash.start)
            let right = text.utf16Slice(from: dash.end)
            let tail = read(right)
            let namesArtist = !isBlank(artist) && Self.namesArtist(left, artist!)
            let noArtist = artist != nil && isBlank(artist) && tail.kind == .extra && !key(right).isEmpty
            if (namesArtist && !key(right).isEmpty) || noArtist {
                artistFromTitle = trimSpace(left)
                text = right
            }
        }

        for _ in 0..<12 {
            guard let match = Bracket.find(text) else { break }
            let inner = match.groupValue(1)
            let rest = trimSpace(text.utf16Slice(0, match.start) + " " + text.utf16Slice(from: match.end))
            // A title that is nothing but a bracket, "(Exchange)", is the words inside it.
            let innerKind = read(inner).kind
            if key(rest).isEmpty && (innerKind == .extra || innerKind == .noise) {
                text = inner
                break
            }
            take(read(inner), inner)
            text = rest
        }
        if let open = OpenBracket.find(text) {
            take(read(open.groupValue(1)), open.groupValue(1))
            text = text.utf16Slice(0, open.start)
        }

        // " - Live at Wembley", " - Remastered 2011": only a tail that says what kind of
        // recording this is. "Pt. 2 - The Return" keeps its tail.
        for _ in 0..<4 {
            guard let last = DashTail.findAll(text).last else { break }
            if last.start == 0 { break }
            let tail = text.utf16Slice(from: last.end)
            let reading = read(tail)
            if reading.kind != .version && reading.kind != .noise && reading.kind != .feature { break }
            take(reading, tail)
            text = text.utf16Slice(0, last.start)
        }

        if let trailing = TrailingFeature.find(text), trailing.start > 0 {
            featured += splitNames(trailing.groupValue(1)).names
            text = text.utf16Slice(0, trailing.start)
        }

        for _ in 0..<3 {
            guard let trailing = TrailingVersion.find(text) else { break }
            if trailing.start == 0 { break }
            take(read(trailing.groupValue(1)), trailing.groupValue(1))
            text = text.utf16Slice(0, trailing.start)
        }

        var core = trimSpace(
            trimSpace(Whitespace.replace(text, " ")).trimEndUnits { $0 == 0x2D || $0 == 0x3A || $0 == 0x2C || $0 == 0x2F || $0 == 0x20 }
        )
        if key(core).isEmpty {
            // Nothing is left but brackets or symbols: the whole title is the name.
            let bare = fold(raw).replacingAll("(", " ").replacingAll(")", " ").replacingAll("[", " ").replacingAll("]", " ")
            core = trimSpace(Whitespace.replace(bare, " "))
            extras.removeAll()
        }
        let keyed = PartWord.replace(parts.isEmpty ? core : "\(core) \(parts.joined(separator: " "))", partOf)

        versions = versions.sorted(by: utf16Less)
        return SongTitle(
            raw: raw,
            core: core,
            key: key(keyed),
            looseKey: looseKey(keyed),
            versions: versions,
            remixers: distinct(remixers.filter { !$0.isEmpty }),
            featured: distinct(featured.filter { !key($0).isEmpty }),
            extras: distinct(extras.filter { !$0.isEmpty }),
            artistFromTitle: artistFromTitle,
            keyed: keyed
        )
    }

    /// The markers of a title that make it a different recording, for this caller.
    public static func distinctVersions(_ title: SongTitle, options: SongMatchOptions? = nil) -> Set<String> {
        Set(title.versions.filter { !NeutralVersions.contains($0) && options?.alsoNeutral.contains($0) != true })
    }

    /// Version markers the candidate carries that the request does not ("Song (Live)" for
    /// "Song"), empty when it adds none. One-directional, for a request whose title may be more
    /// specific than its match's.
    public static func addedVersions(_ requested: String?, _ candidate: String?, options: SongMatchOptions? = nil) -> Set<String> {
        let want = distinctVersions(parseTitle(requested), options: options)
        return distinctVersions(parseTitle(candidate), options: options).filter { !want.contains($0) }
    }

    /// The title without its guest credits, as a person would write it.
    public static func stripFeatures(_ title: String?) -> String {
        var text = trimSpace(title ?? "")
        text = Bracket.replace(text) { match in
            let inner = match.groupValue(1)
            if read(fold(inner)).kind == .feature { return "" }
            // "(Radio Edit - feat. Pharrell Williams)": the credit goes, the version stays.
            guard let credit = InnerFeature.find(inner), credit.start != 0 else { return match.value }
            let kept = trimSpace(inner.utf16Slice(0, credit.start)).trimEndUnits {
                $0 == 0x2D || $0 == 0x2013 || $0 == 0x2C || $0 == 0x3B || $0 == 0x2F || $0 == 0x20
            }
            return kept.isEmpty ? "" : match.value.replacingAll(inner, kept)
        }
        if let trailing = TrailingFeature.find(text), trailing.start > 0 {
            // "Song feat. X (Radio Edit)": the credit goes, a bracket after it stays.
            let rest = text.utf16Slice(from: trailing.start)
            let bracket = rest.units.firstIndex { $0 == 0x28 || $0 == 0x5B } ?? -1
            text = text.utf16Slice(0, trailing.start) + (bracket > 0 ? " " + rest.utf16Slice(from: bracket) : "")
        }
        // "Song - Radio Edit - feat. X" leaves the dash that led to the credit.
        text = trimSpace(text).trimEndUnits { $0 == 0x2D || $0 == 0x2013 || $0 == 0x2C || $0 == 0x20 }
        return trimSpace(Whitespace.replace(text, " "))
    }

    // A guest credit run on after a version inside one bracket, "Radio Edit - feat. X".
    private static let InnerFeature = rx(#"\#(S)*(?:[\-–,;/]\#(S)*)?\#(B)(?:feat\.?|ft\.?|featuring)\#(S)+.+$"#, ignoreCase: true)

    // MARK: - Artists

    // Names that contain a separator and are still one artist. Keys.
    private static let KnownNames: Set<String> = [
        "simonandgarfunkel", "earthwindandfire", "tylerthecreator", "acdc", "crosbystillsandnash",
        "crosbystillsnashandyoung", "emersonlakeandpalmer", "bloodsweatandtears", "peterpaulandmary",
        "hallandoates", "darylhallandjohnoates", "mumfordandsons", "ofmonstersandmen", "belleandsebastian",
        "chaseandstatus", "nicoandvinz", "macklemoreandryanlewis", "samanddave", "peachesandherb",
        "brooksanddunn", "bigandrich", "danandshay", "mattandkim", "sheandhim", "ironandwine",
        "angusandjuliastone", "yearsandyears", "coheedandcambria", "chloexhalle", "aura", "axwellingrosso",
        "aboveandbeyond", "alyandfila", "gabrielanddresden", "dimitrivegasandlikemike", "sonnyandcher",
        "captainandtennille", "ikeandtinaturner", "teganandsara", "ashfordandsimpson",
        "shovelsandrope", "florenceandthemachine",
    ]

    // Other names an artist goes by, as keys, to one canonical key. Small on purpose: renames
    // and stage names that sources really do disagree on.
    private static let Aliases: [String: String] = [
        "ye": "kanyewest", "kanye": "kanyewest",
        "2pac": "2pac", "tupac": "2pac", "tupacshakur": "2pac", "makaveli": "2pac",
        "diddy": "diddy", "pdiddy": "diddy", "puffdaddy": "diddy", "seancombs": "diddy",
        "snooplion": "snoopdogg", "snoopdoggydogg": "snoopdogg",
        "yasiinbey": "mosdef",
        "biggie": "notoriousbig", "biggiesmalls": "notoriousbig", "thenotoriousbig": "notoriousbig",
        "donaldglover": "childishgambino",
        "princeandthenewpowergeneration": "prince", "theartistformerlyknownasprince": "prince",
    ]

    private static let ArtistSeparator = rx(
        #"\#(S)*(?:,|;|/|、|×|&|\#(S)\+\#(S)|\#(S)[•·]\#(S)|\#(S)x\#(S)(?!(?:feat|ft|featuring|with|and|x)\#(E)|[\&,;/])|\#(S)(?:and|with|feat\.?|ft\.?|featuring|vs\.?|pres\.|presents)\#(S))\#(S)*"#,
        ignoreCase: true
    )

    // " - Topic" and "VEVO" are channel names. The server reads the letter before "VEVO" with
    // case ignored, so either case counts there.
    private static let ChannelSuffix = rx(#"(?:\#(S)+-\#(S)+topic|(?<=[\p{Lu}\p{Ll}\p{Lt}])vevo|\#(S)+vevo)$"#, ignoreCase: true)

    private static let HasLatin = rx("[A-Za-z]")

    private static func isJoiner(_ separator: String) -> Bool {
        let s = lowerInvariant(trimSpace(separator))
        return s == "&" || s == "and" || s == "+"
    }

    private struct Split {
        let names: [String]
        let pieces: [String]
    }

    private struct Part {
        let start: Int
        let end: Int
        let before: String
    }

    // A credit split into its artists, keeping known names and "X & the Y" whole.
    private static func splitNames(_ credit: String) -> Split {
        let text = trimSpace(credit)
        if text.isEmpty { return Split(names: [], pieces: []) }
        if KnownNames.contains(key(text)) { return Split(names: [text], pieces: []) }

        var parts: [Part] = []
        var at = 0
        var before = ""
        for separator in ArtistSeparator.findAll(text) {
            let index = separator.start
            if index > at { parts.append(Part(start: at, end: index, before: before)) }
            before = separator.value
            at = separator.end
        }
        let length = text.utf16.count
        if at < length { parts.append(Part(start: at, end: length, before: before)) }
        if parts.isEmpty { return Split(names: [text], pieces: []) }

        var names: [String] = []
        var starts: [Int] = []
        var pieces: [String] = []
        var i = 0
        while i < parts.count {
            // The longest run of parts that is a known name, "Tyler, The Creator".
            var end = i
            var j = parts.count - 1
            while j >= i + 1 {
                if KnownNames.contains(key(text.utf16Slice(parts[i].start, parts[j].end))) {
                    end = j
                    break
                }
                j -= 1
            }
            let name = trimSpace(text.utf16Slice(parts[i].start, parts[end].end))

            // "Bob Marley & The Wailers": a "the" after "&" or "and" belongs to the name before.
            if end == i && !names.isEmpty && isJoiner(parts[i].before) && name.startsWith("the ", ignoreCase: true) {
                pieces.append(names[names.count - 1])
                pieces.append(name)
                names[names.count - 1] = trimSpace(text.utf16Slice(starts[starts.count - 1], parts[i].end))
                i += 1
                continue
            }
            names.append(name)
            starts.append(parts[i].start)
            i = end + 1
        }
        return Split(names: names.filter { !key($0).isEmpty }, pieces: pieces.filter { !key($0).isEmpty })
    }

    /// An artist credit read into its artists.
    public static func parseArtists(_ artist: String?) -> SongArtists {
        let raw = artist ?? ""
        var text = trimSpace(ChannelSuffix.replace(fold(raw), ""))
        var featured: [String] = []
        // Every bracket goes: "(feat. X)" is a guest, "Ye (侃爷)" the same artist in another
        // script, and "Nirvana (US)" a disambiguation.
        text = Bracket.replace(text) { match in
            if let feature = FeatureLead.find(trimSpace(match.groupValue(1))) {
                featured += splitNames(feature.groupValue(1)).names
            }
            return " "
        }
        text = trimSpace(Whitespace.replace(text, " "))
        if key(text).isEmpty { text = trimSpace(Whitespace.replace(fold(raw), " ")) }

        // "Drake feat. Rihanna" names its guest after the separator; the names list keeps it.
        let split = splitNames(text)
        return SongArtists(raw: raw, display: text, names: split.names, featured: featured, pieces: split.pieces)
    }

    /// The artist a credit names first, as written: "Beyoncé" for "Beyoncé feat. Jay-Z",
    /// "Tyler, The Creator" for itself.
    public static func primaryArtist(_ artist: String?) -> String { parseArtists(artist).primary }

    // Every key a name can be matched by: itself, without a leading "the", and its alias.
    private static func keysOf(_ name: String, loose: Bool) -> [String] {
        let nameKey = loose ? looseKey(name) : key(name)
        if nameKey.isEmpty { return [] }
        var keys = [nameKey]
        let trimmed = fold(name)
        if trimmed.startsWith("the ", ignoreCase: true) {
            let rest = trimmed.utf16Slice(from: 4)
            let bare = loose ? looseKey(rest) : key(rest)
            if !bare.isEmpty { keys.append(bare) }
        }
        if let alias = Aliases[nameKey] { keys.append(alias) }
        return keys
    }

    private static func keys(_ names: [String], loose: Bool) -> Set<String> {
        var all = Set<String>()
        for name in names { all.formUnion(keysOf(name, loose: loose)) }
        return all
    }

    private struct Credit {
        let artists: SongArtists
        var all: [String] { artists.names + artists.featured + artists.pieces + [artists.display] }
        var primary: [String] { [artists.primary, artists.display] }
        var named: [String] { artists.names + artists.featured }
    }

    /// How two credits relate. `bCredits`, when a source lists its artists one by one, is used
    /// instead of splitting `b`.
    public static func compareArtists(_ a: String?, _ b: String?, bCredits: [String]? = nil) -> ArtistAgreement {
        compareArtists(parseArtists(a), withCredits(parseArtists(b), bCredits))
    }

    private static func withCredits(_ artists: SongArtists, _ credits: [String]?) -> SongArtists {
        guard let listed = credits?.map({ trimSpace($0) }).filter({ !key($0).isEmpty }), !listed.isEmpty else { return artists }
        let names = listed.map { parseArtists($0).display }
        var copy = artists
        copy.display = artists.isEmpty ? names.joined(separator: " & ") : artists.display
        copy.names = names + artists.names.filter { name in !names.contains { key($0) == key(name) } }
        return copy
    }

    public static func compareArtists(_ a: SongArtists, _ b: SongArtists) -> ArtistAgreement {
        if a.isEmpty || b.isEmpty { return .unknown }
        let left = Credit(artists: a)
        let right = Credit(artists: b)

        var found: ArtistAgreement?
        for loose in [false, true] {
            let allLeft = keys(left.all, loose: loose)
            let allRight = keys(right.all, loose: loose)
            if keys(left.primary, loose: loose).contains(where: { allRight.contains($0) })
                || keys(right.primary, loose: loose).contains(where: { allLeft.contains($0) }) {
                found = loose ? .loose : .agree
                break
            }
        }
        guard let found else { return .none }

        // "Bizarrap, Duki" against "Bizarrap & Rauw Alejandro": one artist in common, and each
        // names a guest the other does not. A name in another script is not counted, since it
        // may be one of the Latin names written its own way. Nor is a name that holds, or is held
        // in, one on the other side: "feat 2 Chainz B.O.B" never had a separator to split on.
        let leftKeys = left.named.filter { HasLatin.containsMatch(in: $0) }.map { keys([$0], loose: true) }
        let rightKeys = right.named.filter { HasLatin.containsMatch(in: $0) }.map { keys([$0], loose: true) }
        let onlyLeft = leftKeys.contains { !credited($0, right) }
        let onlyRight = rightKeys.contains { !credited($0, left) }
        return onlyLeft && onlyRight ? .conflict : found
    }

    // Whether a name is credited on the other side: one of its keys is one there, or holds or is
    // held in one of the other side's names (never its whole credit, which holds every name).
    private static func credited(_ keys: Set<String>, _ other: Credit) -> Bool {
        let all = Self.keys(other.all, loose: true)
        if keys.contains(where: { all.contains($0) }) { return true }
        let named = Self.keys(other.named + other.artists.pieces, loose: true)
        return keys.contains { key in
            named.contains { name in
                min(key.utf16.count, name.utf16.count) >= 3 && (key.utf16Contains(name) || name.utf16Contains(key))
            }
        }
    }

    /// The two credits share an artist and do not disagree about the guests.
    public static func artistsAgree(_ a: String?, _ b: String?, bCredits: [String]? = nil) -> Bool {
        let agreement = compareArtists(a, b, bCredits: bCredits)
        return agreement == .agree || agreement == .loose
    }

    // Whether a name is the artist, in any of the forms a credit is matched by.
    private static func namesArtist(_ name: String, _ artist: String) -> Bool {
        let candidate = [parseArtists(name).display]
        let credit = Credit(artists: parseArtists(artist))
        let exact = keys(credit.all, loose: false)
        let loose = keys(credit.all, loose: true)
        return keys(candidate, loose: false).contains { exact.contains($0) } || keys(candidate, loose: true).contains { loose.contains($0) }
    }

    // MARK: - ISRCs

    // Two letters of country, three of registrant, two digits of year, five of designation.
    private static let IsrcShape = TextPattern("^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$", whole: true)

    /// An ISRC in its one spelling, or nil when the value is not one. Sources write
    /// "USRC17607839", "US-RC1-76-07839", "us rc1 76 07839" and with dots, and all of those are
    /// one code. Anything that is still not twelve characters of the right shape once the
    /// separators are gone counts as no code at all.
    public static func normalizeIsrc(_ value: String?) -> String? {
        guard let value, !isBlank(value) else { return nil }
        let text = value.precomposedStringWithCompatibilityMapping
        var sb: [UInt16] = []
        sb.reserveCapacity(12)
        for ch in text.utf16 {
            if ch == 0x2D || ch == 0x2E || isSpace(unit: ch) { continue }
            // Each character raised on its own, as the server does, and a dotless i left as it
            // is.
            sb.append(ch == 0x131 ? ch : simpleUpper(ch))
        }
        let isrc = String(units: sb)
        return IsrcShape.matches(isrc) ? isrc : nil
    }

    /// Every valid ISRC among the values, in its one spelling.
    public static func isrcs(_ values: [String?]?) -> Set<String> {
        guard let values else { return [] }
        return Set(values.compactMap(normalizeIsrc))
    }

    /// Both sides carry a valid ISRC and at least one is on both.
    public static func sharesIsrc(_ a: [String?]?, _ b: [String?]?) -> Bool {
        let left = isrcs(a)
        return !left.isEmpty && isrcs(b).contains { left.contains($0) }
    }

    // MARK: - Comparing

    private enum TitleAgreement { case none, exact, loose, numbers }

    private static func compareKeys(_ a: SongTitle, _ b: SongTitle) -> TitleAgreement {
        if a.key.isEmpty || b.key.isEmpty { return .none }
        if a.key.utf16Equals(b.key) { return .exact }
        if a.looseKey.utf16Equals(b.looseKey) { return .loose }

        // Numbers compare as sets: "Vol. 53" is "Vol. 53/66", but "Shotta Flow" is never
        // "Shotta Flow 4".
        let lettersA = a.key.filterUnits(isLetterUnit)
        let lettersB = b.key.filterUnits(isLetterUnit)
        if lettersA.isEmpty || !lettersA.utf16Equals(lettersB) { return .none }
        let numbersA = numbersIn(a.keyed)
        let numbersB = numbersIn(b.keyed)
        if numbersA.isEmpty || numbersB.isEmpty { return .none }
        return numbersB.isSuperset(of: numbersA) || numbersA.isSuperset(of: numbersB) ? .numbers : .none
    }

    // Runs of decimal digits, one UTF-16 unit at a time.
    private static func numbersIn(_ text: String) -> Set<String> {
        let units = text.units
        var numbers = Set<String>()
        var i = 0
        while i < units.count {
            if !isDigit(units[i]) {
                i += 1
                continue
            }
            var end = i
            while end < units.count && isDigit(units[end]) { end += 1 }
            numbers.insert(String(units: units[i..<end]))
            i = end
        }
        return numbers
    }

    private static let CreditedVersions: Set<String> = ["remix", "mix", "dub", "edit"]

    /// Whether two titles are one song, and one version of it. Artists are not looked at.
    public static func sameTitle(_ a: String?, _ b: String?, options: SongMatchOptions = .Default) -> SongMatch {
        compareTitles(parseTitle(a), parseTitle(b), options)
    }

    private static func compareTitles(_ a: SongTitle, _ b: SongTitle, _ options: SongMatchOptions) -> SongMatch {
        let agreement = compareKeys(a, b)
        if agreement == .none {
            return SongMatch(
                .different,
                0.95,
                a.key.isEmpty || b.key.isEmpty ? "a title is empty" : "different titles ('\(a.core)' and '\(b.core)')"
            )
        }

        var confidence = 1.0
        var reasons: [String] = []
        if agreement == .loose {
            confidence -= 0.15
            reasons.append("the same title once stylized characters are read as letters")
        }
        if agreement == .numbers {
            confidence -= 0.1
            reasons.append("the same title with numbers that overlap")
        }

        let versionsA = distinctVersions(a, options: options)
        let versionsB = distinctVersions(b, options: options)
        if versionsA != versionsB {
            return SongMatch(.sameSongDifferentVersion, 0.9, "a different version (\(describe(versionsA)) against \(describe(versionsB)))")
        }

        if versionsA.contains(where: { CreditedVersions.contains($0) }) {
            if !a.remixers.isEmpty && !b.remixers.isEmpty && !a.remixers.contains(where: { b.remixers.contains($0) }) {
                return SongMatch(.sameSongDifferentVersion, 0.85, "remixes by different people")
            }
            if a.remixers.isEmpty != b.remixers.isEmpty {
                confidence -= 0.05
                reasons.append("only one says who made the remix")
            }
        }

        if !a.extras.isEmpty && !b.extras.isEmpty && !a.extras.contains(where: { b.extras.contains($0) }) {
            return SongMatch(.different, 0.7, "different subtitles")
        }
        if a.extras.isEmpty != b.extras.isEmpty {
            if options.extrasMustAgree { return SongMatch(.different, 0.7, "only one title has a subtitle") }
            confidence -= 0.1
            reasons.append("only one title has a subtitle")
        }

        return SongMatch(.same, round2(confidence), reasons.isEmpty ? "the same title" : reasons.joined(separator: "; "))
    }

    private static func describe(_ versions: Set<String>) -> String {
        versions.isEmpty ? "the original" : versions.sorted(by: utf16Less).joined(separator: " + ")
    }

    /// Whether two songs are the same recording. Both artists must be known: a title alone is
    /// not an identity.
    public static func same(_ a: SongRef, _ b: SongRef, options: SongMatchOptions = .Default) -> SongMatch {
        // First, and above the text: a romanised title and the same title in its own script
        // share no letter, and one ISRC still says they are one recording. Different ISRCs fall
        // through to the text, since a re-release can carry a new code for the same audio.
        if sharesIsrc(a.isrcs, b.isrcs) { return SongMatch(.same, 1.0, "same ISRC") }

        let titleA = parseTitle(a.title, artist: a.artist ?? "")
        let titleB = parseTitle(b.title, artist: b.artist ?? "")
        let title = compareTitles(titleA, titleB, options)
        if title.verdict == .different { return title }

        let artistA = creditOf(a.artist, titleA)
        let artistB = creditOf(b.artist, titleB)
        let artist = compareArtists(artistA, artistB)
        switch artist {
        case .unknown: return SongMatch(.different, 0.6, "no artist to compare")
        case .none: return SongMatch(.different, 0.9, "different artists ('\(artistA.display)' and '\(artistB.display)')")
        default: break
        }
        if title.verdict == .sameSongDifferentVersion { return title }
        if artist == .conflict { return SongMatch(.sameSongDifferentVersion, 0.75, "different guest artists") }

        var confidence = title.confidence
        var reasons: [String] = []
        if title.reason != "the same title" { reasons.append(title.reason) }
        if artist == .loose {
            confidence -= 0.1
            reasons.append("the same artist once stylized characters are read as letters")
        }

        if let tolerance = options.lengthToleranceSeconds {
            if let secondsA = a.seconds, secondsA > 0, let secondsB = b.seconds, secondsB > 0 {
                let apart = abs(secondsA - secondsB)
                if apart > Double(tolerance) {
                    return SongMatch(.sameSongDifferentVersion, 0.8, "lengths differ by \(oneDecimal(apart)) s")
                }
            } else {
                confidence -= 0.05
                reasons.append("a length is unknown")
            }
        }

        return SongMatch(.same, round2(confidence.clamped(0.0, 1.0)), reasons.isEmpty ? "the same song" : reasons.joined(separator: "; "))
    }

    public static func same(
        _ aTitle: String?, _ aArtist: String?, _ bTitle: String?, _ bArtist: String?, options: SongMatchOptions = .Default
    ) -> SongMatch {
        same(SongRef(title: aTitle, artist: aArtist), SongRef(title: bTitle, artist: bArtist), options: options)
    }

    // The artist credit of one side, with the guests its title names, and the artist an
    // "Artist - Title" title gave when the credit itself is empty.
    private static func creditOf(_ artist: String?, _ title: SongTitle) -> SongArtists {
        var credit = parseArtists(isBlank(artist) ? title.artistFromTitle : artist)
        if title.featured.isEmpty { return credit }
        credit.featured = credit.featured + title.featured
        return credit
    }

    /// Within the tolerance, or unknown on either side.
    public static func lengthFits(_ want: Int?, got: Double?, tolerance: Int = LENGTH_TOLERANCE_SECONDS) -> Bool {
        guard let want, want > 0, let got, got > 0 else { return true }
        return abs(got - Double(want)) <= Double(tolerance)
    }

    /// A key for "this song in this version", for deduplicating and for remembering songs across
    /// sources: the primary artist and the title keys, and the version markers that make a
    /// different recording. "Drake feat. Rihanna - Too Good" and "Drake - Too Good (feat.
    /// Rihanna)" share one; "Song (Live)" has its own.
    public static func matchKey(_ artist: String?, _ title: String?) -> String { songKeys(artist, title).matchKey }

    /// The two halves of matchKey, worked out once.
    public static func songKeys(_ artist: String?, _ title: String?) -> SongKeys {
        let parsed = parseTitle(title, artist: artist ?? "")
        let credit = parseArtists(isBlank(artist) ? parsed.artistFromTitle : artist)
        let primary = key(credit.primary)
        return SongKeys(artist: Aliases[primary] ?? primary, title: versionedKey(parsed))
    }

    /// The title part of matchKey, for songs already known to share an artist, such as the
    /// tracks of one album.
    public static func titleKey(_ title: String?) -> String { versionedKey(parseTitle(title)) }

    private static func versionedKey(_ parsed: SongTitle) -> String {
        let versions = distinctVersions(parsed).sorted(by: utf16Less)
        return versions.isEmpty ? parsed.key : "\(parsed.key)|\(versions.joined(separator: "+"))"
    }

    /// Every key two titles can agree on, for finding the songs worth comparing before comparing
    /// them: the key's letters (the key itself when it has none) and the loose key. Two titles
    /// `same` reads as one song always share one.
    public static func titleLookupKeys(_ title: String?, _ artist: String?) -> Set<String> {
        let parsed = parseTitle(title, artist: artist ?? "")
        if parsed.key.isEmpty { return [] }
        let letters = parsed.key.filterUnits(isLetterUnit)
        return [letters.isEmpty ? parsed.key : letters, parsed.looseKey]
    }

    /// Whether two names are one artist, whole: case, accents, a leading "The", stylized
    /// characters and the alias table ignored, but never split, so "Bob Marley" is not "Bob
    /// Marley & The Wailers". For an artist page, where a credit's guests do not belong.
    public static func sameArtistName(_ a: String?, _ b: String?) -> Bool {
        let left = [parseArtists(a).display]
        let right = [parseArtists(b).display]
        if key(left[0]).isEmpty || key(right[0]).isEmpty { return false }
        let exactRight = keys(right, loose: false)
        let looseRight = keys(right, loose: true)
        return keys(left, loose: false).contains { exactRight.contains($0) } || keys(left, loose: true).contains { looseRight.contains($0) }
    }

    // MARK: - Searching

    /// The queries to try against a search service, in order, stopping at the first that finds
    /// the song:
    ///
    /// 1. the title and artist as given;
    /// 2. the title without brackets, guests or version tails, and the credit without aliases;
    /// 3. the same with stylized characters read as letters ("suicideboys suicide");
    /// 4. the primary artist only;
    /// 5. the title alone, as a last resort.
    ///
    /// A variant that reads the same as an earlier one is left out, so a plain "Drake - Landed"
    /// has two. Whatever a variant finds must still pass `same` against the song as asked: a
    /// looser query never means a looser match.
    public static func queryVariants(_ title: String?, _ artist: String?) -> [SongQuery] {
        var variants: [SongQuery] = []
        func add(_ t: String, _ a: String) {
            let queryTitle = trimSpace(Whitespace.replace(t, " "))
            let queryArtist = trimSpace(Whitespace.replace(a, " "))
            if key(queryTitle).isEmpty { return }
            let seen = variants.contains {
                fold($0.title).equalsIgnoreCase(fold(queryTitle)) && fold($0.artist).equalsIgnoreCase(fold(queryArtist))
            }
            if !seen { variants.append(SongQuery(title: queryTitle, artist: queryArtist)) }
        }

        let parsed = parseTitle(title, artist: artist ?? "")
        let credit = parseArtists(isBlank(artist) ? parsed.artistFromTitle : artist)
        var cleanTitle = parsed.core
        let parts = Bracket.findAll(fold(title)).map { trimSpace($0.groupValue(1)) }.filter { PartNumber.containsMatch(in: $0) }
        if !parts.isEmpty { cleanTitle = "\(cleanTitle) \(parts.joined(separator: " "))" }

        add(trimSpace(title ?? ""), trimSpace(artist ?? ""))
        add(cleanTitle, credit.display)
        add(foldStylized(cleanTitle), foldStylized(credit.display))
        add(cleanTitle, credit.primary)
        add(cleanTitle, "")
        return variants
    }

    // MARK: - Reading text the way the server does

    // Patterns spell out what the server's engine means by a space, a digit and the edge of a
    // word, since engines read the short forms differently.
    static let S = #"[\t\n\u000B\f\r\u0085\p{Z}]"#
    private static let D = #"\p{Nd}"#
    static let W = #"[\p{L}\p{Mn}\p{Nd}\p{Pc}‌‍]"#
    private static let B = "(?<!\(W))"
    private static let E = "(?!\(W))"

    private static let Whitespace = rx("\(S)+")

    // Case is ignored for ASCII letters only (every pattern is ASCII, and the text is folded
    // first), and only "\n" ends a line, as on the server.
    private static func rx(_ pattern: String, ignoreCase: Bool = false) -> TextPattern {
        TextPattern(pattern, case: ignoreCase ? .ascii : .exact, unixLines: true)
    }

    private static func isLetterOrDigit(_ type: Unicode.GeneralCategory) -> Bool {
        isLetterCategory(type) || type == .decimalNumber
    }

    // The server's white space: the Unicode separators, and tab to carriage return and the
    // next-line control. Not the other control characters.
    private static func isSpace(_ point: UInt32) -> Bool {
        if (0x09...0x0D).contains(point) || point == 0x85 { return true }
        switch generalCategory(point: point) {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    private static func isSpace(unit: UInt16) -> Bool { isSpace(UInt32(unit)) }

    static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.utf16.allSatisfy { isSpace(unit: $0) }
    }

    static func trimSpace(_ value: String) -> String { value.trimUnits { isSpace(unit: $0) } }

    private static func isDigit(_ ch: UInt16) -> Bool { generalCategory(ch) == .decimalNumber }

    private static func isUpper(_ ch: UInt16) -> Bool { generalCategory(ch) == .uppercaseLetter }

    private static func isLetterOrMark(_ ch: UInt16) -> Bool {
        switch generalCategory(ch) {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .enclosingMark, .spacingMark:
            return true
        default:
            return false
        }
    }

    // Each character lowered on its own, as the server does: no final sigma, and a dotted
    // capital I is left as it is.
    private static func lowerInvariant(_ text: String) -> String {
        var sb = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let point = scalar.value
            sb.append(Unicode.Scalar(point == 0x130 ? point : simpleLower(point: point)) ?? scalar)
        }
        return String(sb)
    }

    // Split at any of the given units, keeping empty pieces.
    private static func splitUnits(_ text: String, _ separators: Set<UInt16>) -> [String] {
        var pieces: [String] = []
        var current: [UInt16] = []
        for unit in text.utf16 {
            if separators.contains(unit) {
                pieces.append(String(units: current))
                current.removeAll()
            } else {
                current.append(unit)
            }
        }
        pieces.append(String(units: current))
        return pieces
    }

    // The values in their first order, each once.
    private static func distinct(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    // UTF-16 order, as the server sorts.
    private static func utf16Less(_ a: String, _ b: String) -> Bool { a.utf16.lexicographicallyPrecedes(b.utf16) }

    // Rounded to two places, halves to even, as the server rounds.
    private static func round2(_ value: Double) -> Double { (value * 100).rounded(.toNearestOrEven) / 100 }

    // At most one decimal, a half rounded up, read from the shortest decimal form of the value.
    private static func oneDecimal(_ value: Double) -> String {
        let shortest = "\(value)"
        guard !shortest.contains("e"), !shortest.contains("E"), let decimal = Decimal(string: shortest) else {
            return String(format: "%.1f", value)
        }
        var input = decimal
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 1, .plain)
        var text = "\(rounded)"
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
