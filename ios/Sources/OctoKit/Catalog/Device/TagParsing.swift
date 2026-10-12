import Foundation

/// The tags Octo uses from a file, already cleaned up.
public struct FileTags: Sendable, Equatable {
    public var title: String?
    /// Who the song is by as the file writes it, and each credited artist.
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var trackNo: Int?
    public var discNo: Int?
    /// This edition's year, and the year it first came out, when the file says.
    public var year: Int?
    public var compilation: Bool
    public var mbAlbumId: String?
    /// The first is the main one.
    public var genres: [String]
    public var originalYear: Int?
    public var artists: [String]
    public var composer: String?
    public var bpm: Int?
    public var comment: String?
    /// True when marked explicit, false when marked clean.
    public var explicit: Bool?
    public var discTitle: String?
    public var mbRecordingId: String?
    public var mbReleaseGroupId: String?
    public var mbArtistIds: [String]
    /// How the title, album and album artist are filed, like "Beatles, The".
    public var sortTitle: String?
    public var sortAlbum: String?
    public var sortAlbumArtist: String?
    /// Loudness, in decibels and where 1 is full scale.
    public var trackGain: Float?
    public var albumGain: Float?
    public var trackPeak: Float?
    public var albumPeak: Float?

    public init(title: String? = nil, artist: String? = nil, albumArtist: String? = nil, album: String? = nil,
                trackNo: Int? = nil, discNo: Int? = nil, year: Int? = nil, compilation: Bool = false,
                mbAlbumId: String? = nil, genres: [String] = [], originalYear: Int? = nil, artists: [String] = [],
                composer: String? = nil, bpm: Int? = nil, comment: String? = nil, explicit: Bool? = nil,
                discTitle: String? = nil, mbRecordingId: String? = nil, mbReleaseGroupId: String? = nil,
                mbArtistIds: [String] = [], sortTitle: String? = nil, sortAlbum: String? = nil,
                sortAlbumArtist: String? = nil, trackGain: Float? = nil, albumGain: Float? = nil,
                trackPeak: Float? = nil, albumPeak: Float? = nil) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.trackNo = trackNo
        self.discNo = discNo
        self.year = year
        self.compilation = compilation
        self.mbAlbumId = mbAlbumId
        self.genres = genres
        self.originalYear = originalYear
        self.artists = artists
        self.composer = composer
        self.bpm = bpm
        self.comment = comment
        self.explicit = explicit
        self.discTitle = discTitle
        self.mbRecordingId = mbRecordingId
        self.mbReleaseGroupId = mbReleaseGroupId
        self.mbArtistIds = mbArtistIds
        self.sortTitle = sortTitle
        self.sortAlbum = sortAlbum
        self.sortAlbumArtist = sortAlbumArtist
        self.trackGain = trackGain
        self.albumGain = albumGain
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
    }
}

/// Every name a tag goes by in the files Octo reads, compared without case, spaces or
/// punctuation, so "ALBUM ARTIST", "ALBUMARTIST" and "album_artist" are one name.
private enum Names {
    static let title = names("TITLE", "TIT2", "©NAM")
    static let artist = names("ARTIST", "TPE1", "©ART")
    static let artists = names("ARTISTS")
    static let albumArtist = names("ALBUMARTIST", "TPE2", "AART")
    static let albumArtists = names("ALBUMARTISTS")
    static let album = names("ALBUM", "TALB", "©ALB")
    static let track = names("TRACKNUMBER", "TRACK", "TRCK", "TRKN")
    static let trackTotal = names("TRACKTOTAL", "TOTALTRACKS")
    static let disc = names("DISCNUMBER", "DISC", "TPOS", "DISK")
    static let discTotal = names("DISCTOTAL", "TOTALDISCS")
    static let date = names("DATE", "TDRC", "YEAR", "TYER", "©DAY", "RELEASEDATE", "TDRL", "RELEASEYEAR")
    static let originalDate = names("ORIGINALDATE", "TDOR", "ORIGINALYEAR", "TORY", "ORIGYEAR", "ORIGINALRELEASEDATE")
    static let genre = names("GENRE", "TCON", "©GEN", "GNRE")
    static let compilation = names("COMPILATION", "TCMP", "CPIL")
    static let titleSort = names("TITLESORT", "TSOT", "SONM")
    static let artistSort = names("ARTISTSORT", "TSOP", "SOAR")
    static let albumSort = names("ALBUMSORT", "TSOA", "SOAL")
    static let albumArtistSort = names("ALBUMARTISTSORT", "TSO2", "SOAA")
    static let recordingId = names("MUSICBRAINZ_TRACKID", "MUSICBRAINZ TRACK ID", "MUSICBRAINZ_RECORDINGID", "UFID:HTTP://MUSICBRAINZ.ORG")
    static let albumId = names("MUSICBRAINZ_ALBUMID", "MUSICBRAINZ ALBUM ID")
    static let releaseGroupId = names("MUSICBRAINZ_RELEASEGROUPID", "MUSICBRAINZ RELEASE GROUP ID")
    static let artistId = names("MUSICBRAINZ_ARTISTID", "MUSICBRAINZ ARTIST ID")
    static let bpm = names("BPM", "TBPM", "TMPO")
    static let comment = names("COMMENT", "COMM", "©CMT", "DESCRIPTION")
    static let composer = names("COMPOSER", "TCOM", "©WRT")
    static let discTitle = names("DISCSUBTITLE", "TSST", "SETSUBTITLE")
    static let explicit = names("ITUNESADVISORY", "RTNG", "EXPLICIT")
    static let loudness = [
        "REPLAYGAIN_TRACK_GAIN", "REPLAYGAIN_TRACK_PEAK", "REPLAYGAIN_ALBUM_GAIN", "REPLAYGAIN_ALBUM_PEAK",
        "R128_TRACK_GAIN", "R128_ALBUM_GAIN",
    ]

    private static func names(_ all: String...) -> [String] { all.map(tagName) }
}

/// A letter or a decimal digit, as the tag rules read characters.
func isLetterOrDigit(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber: true
    default: false
    }
}

private func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.isWhitespace || (0x1C...0x1F).contains(scalar.value)
}

/// Text without surrounding whitespace, the way the tag rules trim.
func trimmed(_ text: some StringProtocol) -> String {
    let scalars = text.unicodeScalars
    guard let start = scalars.firstIndex(where: { !isWhitespace($0) }),
          let end = scalars.lastIndex(where: { !isWhitespace($0) })
    else { return "" }
    return String(String.UnicodeScalarView(scalars[start...end]))
}

/// A tag's name for comparing: upper case, with no byte-order mark, no "----:com.apple.iTunes:"
/// or "TXXX:" in front, and only letters, digits and the © that MP4 names start with.
public func tagName(_ raw: String) -> String {
    var name = trimmed(raw.replacingOccurrences(of: "\u{FEFF}", with: "")).uppercased()
    if name.hasPrefix("----:"), let colon = name.lastIndex(of: ":") { name = String(name[name.index(after: colon)...]) }
    if name.hasPrefix("TXXX:") { name.removeFirst(5) }
    return String(String.UnicodeScalarView(name.unicodeScalars.filter { isLetterOrDigit($0) || $0 == "©" }))
}

/// Reads a file's tag map. Where several tags can hold a value, the more specific one wins:
/// ARTISTS over ARTIST for the list of artists.
public func parseTags(_ raw: [(String, [String])]) -> FileTags {
    // Values by comparable name, cleaned, in the order the file had them.
    var map: [String: [String]] = [:]
    for (key, values) in raw {
        map[tagName(key), default: []] += values.map(cleanValue).filter { !$0.isEmpty }
    }

    func values(_ names: [String]) -> [String]? {
        for name in names { if let found = map[name], !found.isEmpty { return found } }
        return nil
    }
    func first(_ names: [String]) -> String? {
        guard let value = values(names)?.first else { return nil }
        let head = value.split(separator: "\u{0}", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? value
        let text = trimmed(head)
        return text.isEmpty ? nil : text
    }
    // Several values can also arrive joined by a null in one value.
    func list(_ names: [String]) -> [String]? {
        guard let found = values(names) else { return nil }
        var seen = Set<String>()
        let items = found.flatMap { $0.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init) }
            .map(trimmed).filter { !$0.isEmpty }.filter { seen.insert($0).inserted }
        return items.isEmpty ? nil : items
    }

    let artistValues = list(Names.artist)
    let albumArtistValues = list(Names.albumArtist)
    let track = position(first(Names.track))
    let disc = position(first(Names.disc))
    let year = yearOf(first(Names.date))
    let originalYear = yearOf(first(Names.originalDate))
    let gains = ReplayGainTags.fromTags(Names.loudness.flatMap { name in (map[tagName(name)] ?? []).map { (name, $0) } })

    return FileTags(
        title: first(Names.title),
        artist: artistValues?.joined(separator: ", ") ?? list(Names.artists)?.joined(separator: ", "),
        albumArtist: albumArtistValues?.joined(separator: ", ") ?? list(Names.albumArtists)?.joined(separator: ", "),
        album: first(Names.album),
        trackNo: track.number,
        discNo: disc.number,
        year: year,
        compilation: first(Names.compilation).map(isYes) ?? false,
        mbAlbumId: musicIds(values(Names.albumId)).first,
        genres: parseGenres(values(Names.genre) ?? []),
        // An original release cannot come after this edition; one that says so is a mistake.
        originalYear: originalYear.flatMap { year == nil || $0 <= year! ? $0 : nil },
        artists: list(Names.artists) ?? artistValues ?? [],
        composer: list(Names.composer)?.joined(separator: ", "),
        bpm: first(Names.bpm).flatMap(bpmOf),
        comment: first(Names.comment),
        explicit: first(Names.explicit).flatMap(explicitOf),
        discTitle: first(Names.discTitle),
        mbRecordingId: musicIds(values(Names.recordingId)).first,
        mbReleaseGroupId: musicIds(values(Names.releaseGroupId)).first,
        mbArtistIds: musicIds(values(Names.artistId)),
        sortTitle: first(Names.titleSort),
        sortAlbum: first(Names.albumSort),
        // With no album-artist tag, the album is filed under its artist.
        sortAlbumArtist: first(Names.albumArtistSort) ?? (albumArtistValues == nil ? first(Names.artistSort) : nil),
        trackGain: gains?.trackGain.map(Float.init),
        albumGain: gains?.albumGain.map(Float.init),
        trackPeak: gains?.trackPeak.map(Float.init),
        albumPeak: gains?.albumPeak.map(Float.init)
    )
}

/// A value without a byte-order mark, surrounding spaces or trailing nulls.
func cleanValue(_ value: String) -> String {
    let text = value.replacingOccurrences(of: "\u{FEFF}", with: "")
    let scalars = text.unicodeScalars
    let keep: (Unicode.Scalar) -> Bool = { !isWhitespace($0) && $0 != "\u{0}" }
    guard let start = scalars.firstIndex(where: keep), let end = scalars.lastIndex(where: keep) else { return "" }
    return String(String.UnicodeScalarView(scalars[start...end]))
}

/// A place in a set and the set's size, either of which may be unknown.
public struct Position: Sendable, Equatable {
    public var number: Int?
    public var total: Int?

    public init(number: Int?, total: Int?) {
        self.number = number
        self.total = total
    }
}

private let positionText = try! NSRegularExpression(pattern: #"^[^\p{L}0-9]*([0-9]+)\s*(?:(?:/|of)\s*([0-9]+))?"#,
                                                    options: [.caseInsensitive])

/// "3", "03", "3/12", "3 of 12" and "(3)" all mean 3. Zero means not set. A vinyl side like "A1"
/// is not a number in the whole album, so it is not one.
public func position(_ text: String?) -> Position {
    guard let text else { return Position(number: nil, total: nil) }
    let clean = cleanValue(text)
    guard let match = positionText.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)) else {
        return Position(number: nil, total: nil)
    }
    func group(_ index: Int) -> Int? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: clean) else { return nil }
        guard let value = Int(clean[swiftRange]), value > 0 else { return nil }
        return value
    }
    return Position(number: group(1), total: group(2))
}

public func positionNumber(_ text: String?) -> Int? { position(text).number }

private let leadingYear = try! NSRegularExpression(pattern: #"^[^0-9]*([0-9]{4})"#)
private let anyYear = try! NSRegularExpression(pattern: #"(?<![0-9])([0-9]{4})(?![0-9])"#)

/// The year in a date, however it is written: "2017", "2017-06-16", "20170616", "(2017)", and a
/// year at the end, as in "16/06/2017". 1000 to 2999 only.
public func yearOf(_ text: String?) -> Int? {
    guard let text else { return nil }
    let clean = cleanValue(text)
    let range = NSRange(clean.startIndex..., in: clean)
    guard let found = leadingYear.firstMatch(in: clean, range: range) ?? anyYear.firstMatch(in: clean, range: range),
          let digits = Range(found.range(at: 1), in: clean), let year = Int(clean[digits])
    else { return nil }
    return (1000...2999).contains(year) ? year : nil
}

/// "1", "true" and "yes" all mean yes.
private func isYes(_ text: String) -> Bool {
    text == "1" || text.lowercased() == "true" || text.lowercased() == "yes"
}

private let bpmNumber = try! NSRegularExpression(pattern: #"[0-9]+(?:[.,][0-9]+)?"#)

/// Beats per minute, rounded: "120", "120.5", "128 BPM". 1 to 999 only.
public func bpmOf(_ text: String) -> Int? {
    guard let found = bpmNumber.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(found.range, in: text),
          let value = Double(text[range].replacingOccurrences(of: ",", with: "."))
    else { return nil }
    // Rounded half up. A number too large for a tempo is left out before it becomes a whole number.
    let rounded = (value + 0.5).rounded(.down)
    guard rounded >= 1, rounded <= 999 else { return nil }
    return Int(rounded)
}

/// The explicit mark: iTunes writes 1 or 4 for explicit and 2 for clean; others write the word.
public func explicitOf(_ text: String) -> Bool? {
    switch trimmed(text).lowercased() {
    case "1", "4", "explicit", "e", "true", "yes": true
    case "2", "clean", "c": false
    default: nil
    }
}

private let musicId = try! NSRegularExpression(pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")

/// Every MusicBrainz id in some values, however they are joined, in lower case.
public func musicIds(_ values: [String]?) -> [String] {
    var seen = Set<String>()
    var found: [String] = []
    for value in values ?? [] {
        for match in musicId.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let range = Range(match.range, in: value) else { continue }
            let id = value[range].lowercased()
            if seen.insert(id).inserted { found.append(id) }
        }
    }
    return found
}

private let genreSeparators = try! NSRegularExpression(pattern: "[;/,]")
private let spaces = try! NSRegularExpression(pattern: "[ \\t\\n\\x0B\\f\\r]+")
/// Stands in for a name set aside while a value is split.
private let keptWhole = try! NSRegularExpression(pattern: "\u{0}([0-9]+)\u{0}")

/// Genre names that are commonly written with a separator inside them.
private let wholeGenres: [NSRegularExpression] = ["Folk, World, & Country", "Hip-Hop/Rap", "R&B/Soul", "Singer/Songwriter"].map {
    try! NSRegularExpression(pattern: "(?<![^;/,\\s])" + NSRegularExpression.escapedPattern(for: $0) + "(?![^;/,\\s])",
                             options: [.caseInsensitive])
}

/// A genre tag as clean names: several values, or one value joined by ";", "/" or ",", become a
/// list in the order written. A number is an old-style genre number ("17" is Rock). Repeats that
/// differ only in case are dropped.
public func parseGenres(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.map(id3Genre).flatMap(splitGenres)
        .map { piece -> String in
            let named = id3Genre(piece)
            return trimmed(spaces.stringByReplacingMatches(in: named, range: NSRange(named.startIndex..., in: named), withTemplate: " "))
        }
        .filter { !$0.isEmpty }
        .filter { seen.insert($0.lowercased()).inserted }
}

/// Splits one value, first setting aside the names that must stay whole.
private func splitGenres(_ value: String) -> [String] {
    var kept: [String] = []
    // A null inside a value joins several values, so it splits like ";".
    var marked = cleanValue(value).replacingOccurrences(of: "\u{0}", with: ";")
    for name in wholeGenres {
        var out = ""
        var last = marked.startIndex
        for match in name.matches(in: marked, range: NSRange(marked.startIndex..., in: marked)) {
            guard let range = Range(match.range, in: marked) else { continue }
            out += marked[last..<range.lowerBound]
            kept.append(String(marked[range]))
            out += "\u{0}\(kept.count - 1)\u{0}"
            last = range.upperBound
        }
        out += marked[last...]
        marked = out
    }
    return splitOn(genreSeparators, marked).map { piece in
        var out = ""
        var last = piece.startIndex
        for match in keptWhole.matches(in: piece, range: NSRange(piece.startIndex..., in: piece)) {
            guard let range = Range(match.range, in: piece), let digits = Range(match.range(at: 1), in: piece),
                  let index = Int(piece[digits]), index < kept.count
            else { continue }
            out += piece[last..<range.lowerBound]
            out += kept[index]
            last = range.upperBound
        }
        out += piece[last...]
        return out
    }
}

/// Splits text on every match of a pattern, keeping empty pieces, including those at either end.
func splitOn(_ pattern: NSRegularExpression, _ text: String) -> [String] {
    var pieces: [String] = []
    var last = text.startIndex
    for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
        guard let range = Range(match.range, in: text) else { continue }
        pieces.append(String(text[last..<range.lowerBound]))
        last = range.upperBound
    }
    pieces.append(String(text[last...]))
    return pieces
}

private let numberedGenres = try! NSRegularExpression(pattern: #"^\s*((?:\((?:[0-9]{1,3}|RX|CR)\))+)(.*)$"#)
private let genreNumber = try! NSRegularExpression(pattern: #"\(([0-9]{1,3}|RX|CR)\)"#)

/// An old-style genre: "17" and "(17)" are Rock, "(RX)" is Remix, and in "(17)Rock and Roll" the
/// words after the number win. Anything else is kept.
public func id3Genre(_ value: String) -> String {
    let text = cleanValue(value)
    if let number = kotlinInt(text) { return number >= 0 && number < id3Genres.count ? id3Genres[number] : text }
    guard let match = numberedGenres.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let numbersRange = Range(match.range(at: 1), in: text), let restRange = Range(match.range(at: 2), in: text)
    else { return text }
    let rest = String(text[restRange])
    if !trimmed(rest).isEmpty { return trimmed(rest) }
    let numbers = String(text[numbersRange])
    return genreNumber.matches(in: numbers, range: NSRange(numbers.startIndex..., in: numbers)).compactMap { found -> String? in
        guard let range = Range(found.range(at: 1), in: numbers) else { return nil }
        switch numbers[range] {
        case "RX": return "Remix"
        case "CR": return "Cover"
        default:
            guard let index = Int(numbers[range]), index < id3Genres.count else { return nil }
            return id3Genres[index]
        }
    }.joined(separator: ";")
}

/// A whole number written plainly in ASCII digits, with an optional sign; nil for anything else.
func kotlinInt(_ text: String) -> Int? {
    guard !text.isEmpty else { return nil }
    var digits = Substring(text)
    if digits.first == "+" || digits.first == "-" { digits = digits.dropFirst() }
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return Int(text)
}

/// The genre numbers older MP3 tags use, 0 to 191.
private let id3Genres = [
    "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal",
    "New Age", "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial",
    "Alternative", "Ska", "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz-Funk",
    "Fusion", "Trance", "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise",
    "Alternative Rock", "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
    "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy", "Cult", "Gangsta",
    "Top 40", "Christian Rap", "Pop-Funk", "Jungle", "Native American", "Cabaret", "New Wave", "Psychedelic", "Rave", "Showtunes",
    "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro", "Musical", "Rock & Roll", "Hard Rock",
    "Folk", "Folk Rock", "National Folk", "Swing", "Fast Fusion", "Bebop", "Latin", "Revival", "Celtic", "Bluegrass",
    "Avant-garde", "Gothic Rock", "Progressive Rock", "Psychedelic Rock", "Symphonic Rock", "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic",
    "Humour", "Speech", "Chanson", "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus", "Porn Groove",
    "Satire", "Slow Jam", "Club", "Tango", "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle",
    "Duet", "Punk Rock", "Drum Solo", "A Cappella", "Euro-House", "Dancehall", "Goa", "Drum & Bass", "Club-House", "Hardcore Techno",
    "Terror", "Indie", "Britpop", "Worldbeat", "Polsk Punk", "Beat", "Christian Gangsta Rap", "Heavy Metal", "Black Metal", "Crossover",
    "Contemporary Christian", "Christian Rock", "Merengue", "Salsa", "Thrash Metal", "Anime", "J-Pop", "Synth-pop", "Abstract", "Art Rock",
    "Baroque", "Bhangra", "Big Beat", "Breakbeat", "Chillout", "Downtempo", "Dub", "EBM", "Eclectic", "Electro",
    "Electroclash", "Emo", "Experimental", "Garage", "Global", "IDM", "Illbient", "Industro-Goth", "Jam Band", "Krautrock",
    "Leftfield", "Lounge", "Math Rock", "New Romantic", "Nu-Breakz", "Post-Punk", "Post-Rock", "Psytrance", "Shoegaze", "Space Rock",
    "Trop Rock", "World Music", "Neoclassical", "Audiobook", "Audio Theatre", "Neue Deutsche Welle", "Podcast", "Indie Rock", "G-Funk", "Dubstep",
    "Garage Rock", "Psybient",
]

/// Which genre a name belongs to, so the ways of writing one genre fold together. Case, spaces
/// and punctuation are ignored, "&" counts as "and", and a few genres commonly written several
/// ways share one key.
public func genreKey(_ name: String) -> String {
    let lowered = name.lowercased().replacingOccurrences(of: "&", with: "and")
    let bare = String(String.UnicodeScalarView(lowered.unicodeScalars.filter(isLetterOrDigit)))
    return genreFamilies[bare] ?? bare
}

private let genreFamilies: [String: String] = {
    let families: [(String, [String])] = [
        ("hiphop", ["hiphoprap", "raphiphop", "rap", "hiphopandrap", "rapandhiphop"]),
        ("randb", ["rnb", "rhythmandblues", "randbsoul", "rnbsoul"]),
        ("electronic", ["electronica", "électronique"]),
        ("alternative", ["alternativeandindie", "indieandalternative", "alternativeindie", "indiealternative", "alternatifetindé"]),
    ]
    var map: [String: String] = [:]
    for (key, names) in families { for name in names { map[name] = key } }
    return map
}()
