import Foundation

/// What a live list picks, in one quiet line under its name: "Added in the last month, lossless,
/// 42 songs". Rules met together are joined by commas, either-or rules by "or"; the order and a
/// limit follow, then how many songs it holds now (left out with no count, as in a list of lists).
public func liveListSummary(_ query: LibraryQuery, count: Int?, zone: TimeZone = .current) -> String {
    var parts: [String] = []
    let rules = query.rules.filter(\.complete).map { $0.label(zone: zone) }
    if !rules.isEmpty { parts.append(joinedRules(rules, match: query.match)) }
    let words = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !words.isEmpty { parts.append("with \u{201C}\(words)\u{201D}") }
    if parts.isEmpty { parts.append("Every song") }
    if let sort = query.sort, let words = sortWords(sort) { parts.append(words) }
    if let count {
        if let limit = query.limit, count >= limit {
            parts.append("the top \(songsWord(count))")
        } else {
            parts.append(songsWord(count))
        }
    } else if let limit = query.limit {
        parts.append("the top \(limit)")
    }
    return parts.enumerated().map { $0.offset == 0 ? upperFirst($0.element) : $0.element }.joined(separator: ", ")
}

/// A name for a list made from rules, until the listener gives it one: the rule, the first two
/// rules, or the words.
public func liveListName(_ query: LibraryQuery, zone: TimeZone = .current) -> String {
    let rules = query.rules.filter(\.complete).map { $0.label(zone: zone) }
    let words = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if rules.count == 1, words.isEmpty { return rules[0] }
    if !rules.isEmpty { return joinedRules(Array(rules.prefix(2)), match: query.match) }
    if !words.isEmpty { return upperFirst(words) }
    return "New live list"
}

/// Which way a live list runs, in words: "newest first", "most played first". Nil for an order
/// this version does not know.
public func sortWords(_ sort: QuerySort) -> String? {
    guard let by = sort.order else { return nil }
    let down = sort.descending
    switch by {
    case .title: return down ? "by title, Z to A" : "by title"
    case .artist: return down ? "by artist, Z to A" : "by artist"
    case .album: return down ? "by album, Z to A" : "by album"
    case .recentlyAdded: return down ? "newest first" : "oldest first"
    case .year: return down ? "latest year first" : "earliest year first"
    case .length: return down ? "longest first" : "shortest first"
    case .mostPlayed: return down ? "most played first" : "least played first"
    case .recentlyPlayed: return down ? "last played first" : "longest unplayed first"
    case .rating: return down ? "highest rated first" : "lowest rated first"
    case .liked, .dateLiked: return down ? "newest favorites first" : "oldest favorites first"
    case .folderOrder: return "in folder order"
    }
}

/// Over the editor's preview: "42 songs match right now".
public func matchWords(_ count: Int) -> String {
    count == 1 ? "1 song matches right now" : "\(LiveListDraft.grouped(count)) songs match right now"
}

/// A live list as the editor holds it until saved: the name typed and the rules picked.
public struct LiveListDraft: Sendable, Hashable {
    public var name: String
    public var query: LibraryQuery

    public init(name: String, query: LibraryQuery) {
        self.name = name
        self.query = query
    }

    public init(of list: LiveList) {
        self.init(name: list.name, query: list.query)
    }

    /// The name it is saved under: the one typed, else one from its rules.
    public var savedName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? liveListName(query) : typed
    }

    /// Whether saving would change `list`.
    public func changes(_ list: LiveList) -> Bool { savedName != list.name || query != list.query }

    /// A count with thousands set apart by commas: "1,204".
    static func grouped(_ count: Int) -> String {
        let digits = String(count.magnitude)
        var out = ""
        for (i, digit) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(digit)
        }
        return count < 0 ? "-" + out : out
    }
}

private func songsWord(_ count: Int) -> String { count == 1 ? "1 song" : "\(LiveListDraft.grouped(count)) songs" }

private func joinedRules(_ rules: [String], match: QueryMatch) -> String {
    rules.enumerated().map { $0.offset == 0 ? $0.element : lowerFirst($0.element) }
        .joined(separator: match == .any ? " or " : ", ")
}

/// "Genre is Rock" reads "genre is Rock" inside a line; "BPM" keeps its capitals.
private func lowerFirst(_ text: String) -> String {
    let start = Array(text.prefix(2))
    if start.count > 1, start[1].isUppercase { return text }
    guard let first = text.first else { return text }
    return first.lowercased() + text.dropFirst()
}

private func upperFirst(_ text: String) -> String {
    guard let first = text.first else { return text }
    return first.uppercased() + text.dropFirst()
}
