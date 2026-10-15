import Foundation

private let articles = ["the ", "a ", "an "]

/// For matching what someone types: lowercase, accents gone.
public func searchKey(_ text: String) -> String {
    let decomposed = text.trimmingCharacters(in: .whitespacesAndNewlines).decomposedStringWithCanonicalMapping
    var kept = String.UnicodeScalarView()
    for scalar in decomposed.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark { kept.append(scalar) }
    return String(kept).lowercased()
}

/// A song's identity apart from its id: album artist, album, disc, track, title and length in
/// seconds. Used to find a liked or played song again after the phone gives its file a new id.
public func relinkKey(albumArtist: String, album: String, disc: Int?, track: Int?, title: String, durationMs: Int64) -> String {
    searchKey([albumArtist, album, disc.map(String.init) ?? "", track.map(String.init) ?? "", title, String(durationMs / 1_000)]
        .joined(separator: "|"))
}

/// For ordering lists: like `searchKey`, with a leading article dropped so "The Beatles" sorts
/// under B.
public func sortKey(_ text: String) -> String {
    let key = searchKey(text)
    if let article = articles.first(where: { key.hasPrefix($0) && key.count > $0.count }) {
        return String(key.dropFirst(article.count))
    }
    return key
}

/// Wide enough for any number in a title or a year.
private let numberWidth = 12

/// Like `sortKey`, with numbers ordered by value: "Vol. 2" before "Vol. 10".
public func naturalSortKey(_ text: String) -> String {
    let key = sortKey(text)
    var out = ""
    var digits = ""
    func flush() {
        guard !digits.isEmpty else { return }
        var trimmed = Substring(digits)
        while trimmed.first == "0" { trimmed = trimmed.dropFirst() }
        out += String(repeating: "0", count: max(0, numberWidth - trimmed.count)) + trimmed
        digits = ""
    }
    for ch in key {
        if ch.isASCII, ch.isNumber { digits.append(ch) } else {
            flush()
            out.append(ch)
        }
    }
    flush()
    return out
}
