import Foundation

/// Which songs a list shows: rules like "Added in the last month" or "Genre is Electronic", met
/// all together or any one of them, plus the words typed in the list's filter field, then an
/// order and how many at most. Song list filters and live lists both use it.
public struct LibraryQuery: Sendable, Hashable {
    public var rules: [QueryRule]
    public var match: QueryMatch
    /// Words that must each appear in the title, artist, album, album artist or a genre, ignoring
    /// case and accents.
    public var text: String
    public var sort: QuerySort?
    public var limit: Int?

    public init(_ rules: [QueryRule] = [], match: QueryMatch = .all, text: String = "", sort: QuerySort? = nil,
                limit: Int? = nil) {
        self.rules = rules
        self.match = match
        self.text = text
        self.sort = sort
        self.limit = limit
    }

    /// Whether it leaves any song out: a rule, or typed words.
    public var filters: Bool { !rules.isEmpty || !Self.isBlank(text) }

    /// The rule in place of any other on the same field, as a filter bar does: picking "Added this
    /// month" replaces "Added this week".
    public func setting(_ rule: QueryRule) -> LibraryQuery {
        var next = self
        next.rules = rules.filter { $0.field != rule.field } + [rule]
        return next
    }

    /// Without the first rule equal to `rule`.
    public func without(_ rule: QueryRule) -> LibraryQuery {
        var next = self
        if let at = rules.firstIndex(of: rule) { next.rules.remove(at: at) }
        return next
    }

    /// No rules and no words; the order and limit stay.
    public func cleared() -> LibraryQuery {
        var next = self
        next.rules = []
        next.text = ""
        return next
    }

    /// The same query with other typed words.
    public func withText(_ text: String) -> LibraryQuery {
        var next = self
        next.text = text
        return next
    }

    /// The same query met all together or any one of its rules.
    public func matching(_ match: QueryMatch) -> LibraryQuery {
        var next = self
        next.match = match
        return next
    }

    /// The same query in another order, or in the library's own with nil.
    public func sorted(by sort: QuerySort?) -> LibraryQuery {
        var next = self
        next.sort = sort
        return next
    }

    /// The same query by another song order, running the way that order starts.
    public func sorted(by order: QuerySort.By) -> LibraryQuery {
        sorted(by: QuerySort(order, descending: order.startsDescending))
    }

    /// The same query kept to at most `limit` songs, or all with nil.
    public func limited(to limit: Int?) -> LibraryQuery {
        var next = self
        next.limit = limit
        return next
    }
}

/// All the rules must hold, or any one of them.
public enum QueryMatch: String, Sendable, Hashable, CaseIterable {
    case all
    case any
}

/// An order for the songs, by the song orders' saved ids.
public struct QuerySort: Sendable, Hashable {
    public var by: String
    public var descending: Bool

    public init(by: String, descending: Bool = false) {
        self.by = by
        self.descending = descending
    }

    public init(_ order: By, descending: Bool) {
        self.init(by: order.rawValue, descending: descending)
    }

    /// Nil when the id is not a song order this version knows.
    public var order: By? { By(rawValue: by) }

    /// The ways songs can be ordered. The raw values are what gets saved, so they never change
    /// once shipped.
    public enum By: String, Sendable, Hashable, CaseIterable {
        case title = "Title"
        case artist = "Artist"
        case album = "Album"
        case recentlyAdded = "RecentlyAdded"
        case year = "Year"
        case length = "Length"
        case mostPlayed = "MostPlayed"
        case recentlyPlayed = "RecentlyPlayed"
        case rating = "Rating"
        case liked = "Liked"
        case dateLiked = "DateLiked"
        /// As the folder lists them.
        case folderOrder = "FolderOrder"

        /// What a menu calls the order.
        public var label: String {
            switch self {
            case .title: "Title"
            case .artist: "Artist"
            case .album: "Album"
            case .recentlyAdded: "Recently added"
            case .year: "Year"
            case .length: "Length"
            case .mostPlayed: "Most played"
            case .recentlyPlayed: "Recently played"
            case .rating: "Rating"
            case .liked: "Liked"
            case .dateLiked: "Date liked"
            case .folderOrder: "Folder order"
            }
        }

        /// Which way it runs when first picked: newest, most or longest first for dates and
        /// counts, A to Z for names.
        public var startsDescending: Bool {
            switch self {
            case .title, .artist, .album, .folderOrder: false
            default: true
            }
        }
    }
}

/// What a rule looks at. The raw values are what gets saved, so they never change once shipped.
public enum QueryField: String, Sendable, Hashable, CaseIterable {
    case title
    case artist
    case album
    case albumArtist
    case genre
    case composer
    case format
    case year
    case plays
    case rating
    /// In seconds.
    case duration
    /// In kilobits per second.
    case bitRate
    case bpm
    case added
    case lastPlayed
    case favorite = "favourite"
    case lossless

    /// What kind of value a field holds, which decides the tests it offers.
    public enum Kind: Sendable, Hashable, CaseIterable {
        case text, number, date, flag
    }

    public var kind: Kind {
        switch self {
        case .title, .artist, .album, .albumArtist, .genre, .composer, .format: .text
        case .year, .plays, .rating, .duration, .bitRate, .bpm: .number
        case .added, .lastPlayed: .date
        case .favorite, .lossless: .flag
        }
    }
}

/// How a rule tests its field. Each kind of field offers its own few.
public enum QueryOp: String, Sendable, Hashable, CaseIterable {
    /// Words and numbers alike; a yes-or-no field only takes `is`.
    case `is`
    case isNot

    // Words.
    case contains
    case doesNotContain
    case startsWith

    // Numbers.
    case atLeast
    case atMost
    case between

    // Dates.
    case inTheLast
    case notInTheLast
    case before
    case after
    case never

    /// The tests each kind of field offers, in the order a menu lists them.
    public static func forKind(_ kind: QueryField.Kind) -> [QueryOp] {
        switch kind {
        case .text: [.contains, .is, .isNot, .startsWith, .doesNotContain]
        case .number: [.is, .isNot, .atLeast, .atMost, .between]
        case .date: [.inTheLast, .notInTheLast, .before, .after, .never]
        case .flag: [.is]
        }
    }
}

/// One rule: a field, a test, and the value the test needs. Words go in `text`; a number in
/// `number` (and the top of a range in `to`); a span in `days`; a moment in `at` (milliseconds
/// since 1970); yes or no in `flag`. A rule whose test does not suit its field, or lacks its value,
/// is left out when songs are picked.
public struct QueryRule: Sendable, Hashable {
    public var field: QueryField
    public var op: QueryOp
    public var text: String?
    public var number: Int64?
    public var to: Int64?
    public var days: Int?
    public var at: Int64?
    public var flag: Bool?

    public init(_ field: QueryField, _ op: QueryOp, text: String? = nil, number: Int64? = nil, to: Int64? = nil,
                days: Int? = nil, at: Int64? = nil, flag: Bool? = nil) {
        self.field = field
        self.op = op
        self.text = text
        self.number = number
        self.to = to
        self.days = days
        self.at = at
        self.flag = flag
    }

    /// Whether the test suits the field and has what it needs.
    public var complete: Bool {
        guard QueryOp.forKind(field.kind).contains(op) else { return false }
        switch op {
        case .contains, .doesNotContain, .startsWith:
            return !(text ?? "").isEmpty
        case .is, .isNot:
            switch field.kind {
            case .text: return text != nil
            case .number: return number != nil
            case .flag: return flag != nil
            case .date: return false
            }
        case .atLeast, .atMost:
            return number != nil
        case .between:
            return number != nil && to != nil
        case .inTheLast, .notInTheLast:
            guard let days else { return false }
            return days >= 0
        case .before, .after:
            return at != nil
        case .never:
            return true
        }
    }
}

extension LibraryQuery {
    /// Whether the text holds nothing but white space.
    static func isBlank(_ text: String) -> Bool { text.allSatisfy(\.isWhitespace) }
}

// MARK: - Saved form

// Saved compactly: values left at their defaults are not written, keys in a fixed order. Reading
// ignores keys it does not know, reads an unknown way of matching as `all`, and leaves out a rule
// it cannot read rather than failing the whole query.

extension LibraryQuery {
    /// The query as saved: `{"rules":[...],"match":"any","text":"...","sort":{...},"limit":50}`.
    public func toJSON() -> String {
        var parts: [String] = []
        if !rules.isEmpty { parts.append("\"rules\":[" + rules.map(\.json).joined(separator: ",") + "]") }
        if match != .all { parts.append("\"match\":" + Self.jsonQuoted(match.rawValue)) }
        if !text.isEmpty { parts.append("\"text\":" + Self.jsonQuoted(text)) }
        if let sort { parts.append("\"sort\":" + sort.json) }
        if let limit { parts.append("\"limit\":\(limit)") }
        return "{" + parts.joined(separator: ",") + "}"
    }

    /// A saved query, or nil when the text is not one. Rules this version does not know (a field
    /// or test added later) are left out, and so are unknown keys.
    public static func fromJSON(_ text: String) -> LibraryQuery? {
        try? JSONDecoder().decode(LibraryQueryReading.self, from: Data(text.utf8)).query
    }

    /// A string as a JSON literal, escaped the way the saved form writes it.
    static func jsonQuoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if scalar.value < 0x20 {
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}

extension QueryRule {
    var json: String {
        var parts = ["\"field\":" + LibraryQuery.jsonQuoted(field.rawValue), "\"op\":" + LibraryQuery.jsonQuoted(op.rawValue)]
        if let text { parts.append("\"text\":" + LibraryQuery.jsonQuoted(text)) }
        if let number { parts.append("\"number\":\(number)") }
        if let to { parts.append("\"to\":\(to)") }
        if let days { parts.append("\"days\":\(days)") }
        if let at { parts.append("\"at\":\(at)") }
        if let flag { parts.append("\"flag\":\(flag)") }
        return "{" + parts.joined(separator: ",") + "}"
    }
}

extension QuerySort {
    var json: String {
        var parts = ["\"by\":" + LibraryQuery.jsonQuoted(by)]
        if descending { parts.append("\"descending\":true") }
        return "{" + parts.joined(separator: ",") + "}"
    }
}

/// A saved query read from JSON, as the lists file holds one too.
struct LibraryQueryReading: Decodable {
    let query: LibraryQuery

    private enum Key: String, CodingKey { case rules, match, text, sort, limit }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        // Rules that are not a list read as none; each rule that cannot be read is left out.
        let rules = (try? c.decodeIfPresent([SavedRule].self, forKey: .rules))?.compactMap(\.rule) ?? []
        let match = try c.decodeIfPresent(String.self, forKey: .match).map { QueryMatch(rawValue: $0) ?? .all } ?? .all
        let text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        let sort = try c.decodeIfPresent(SavedSort.self, forKey: .sort)?.sort
        let limit = try c.decodeIfPresent(Int32.self, forKey: .limit).map(Int.init)
        query = LibraryQuery(rules, match: match, text: text, sort: sort, limit: limit)
    }
}

/// One saved rule, or nil when it cannot be read.
private struct SavedRule: Decodable {
    let rule: QueryRule?

    private enum Key: String, CodingKey { case field, op, text, number, to, days, at, flag }

    init(from decoder: any Decoder) {
        rule = try? Self.read(decoder)
    }

    private static func read(_ decoder: any Decoder) throws -> QueryRule {
        let c = try decoder.container(keyedBy: Key.self)
        guard let field = QueryField(rawValue: try c.decode(String.self, forKey: .field)) else {
            throw DecodingError.dataCorruptedError(forKey: .field, in: c, debugDescription: "Unknown field")
        }
        guard let op = QueryOp(rawValue: try c.decode(String.self, forKey: .op)) else {
            throw DecodingError.dataCorruptedError(forKey: .op, in: c, debugDescription: "Unknown test")
        }
        return QueryRule(field, op,
                         text: try c.decodeIfPresent(String.self, forKey: .text),
                         number: try c.decodeIfPresent(Int64.self, forKey: .number),
                         to: try c.decodeIfPresent(Int64.self, forKey: .to),
                         days: try c.decodeIfPresent(Int32.self, forKey: .days).map(Int.init),
                         at: try c.decodeIfPresent(Int64.self, forKey: .at),
                         flag: try c.decodeIfPresent(Bool.self, forKey: .flag))
    }
}

private struct SavedSort: Decodable {
    let sort: QuerySort

    private enum Key: String, CodingKey { case by, descending }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        sort = QuerySort(by: try c.decode(String.self, forKey: .by),
                         descending: try c.decodeIfPresent(Bool.self, forKey: .descending) ?? false)
    }
}
