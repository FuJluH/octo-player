import Foundation

/// How many past searches are kept.
public let recentSearchesKept = 10

/// A search as it is kept: trimmed, with runs of spaces made one.
public func tidySearch(_ query: String) -> String {
    query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// The recent searches with one more, newest first. Searching again for one already there
/// (whatever its case) moves it to the top rather than adding it twice, and only the newest ten
/// are kept.
public func withRecent(_ recent: [String], _ query: String) -> [String] {
    let tidy = tidySearch(query)
    if tidy.isEmpty { return recent }
    return Array(([tidy] + recent.filter { $0.caseInsensitiveCompare(tidy) != .orderedSame }).prefix(recentSearchesKept))
}

/// The recent searches without `query`, whatever its case.
public func withoutRecent(_ recent: [String], _ query: String) -> [String] {
    let tidy = tidySearch(query)
    return recent.filter { $0.caseInsensitiveCompare(tidy) != .orderedSame }
}

/// Kept as one search per line, newest first.
public func encodeRecent(_ recent: [String]) -> String { recent.joined(separator: "\n") }

public func decodeRecent(_ text: String?) -> [String] {
    Array((text ?? "").components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .prefix(recentSearchesKept))
}
