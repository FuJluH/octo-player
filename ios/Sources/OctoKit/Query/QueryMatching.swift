import Foundation

private let dayMs: Int64 = 86_400_000

extension LibraryQuery {
    /// Any kind of song this query picks, read through `fields`, in its order, at most its limit.
    /// `now` is the time in milliseconds, for rules like "in the last 30 days". Each name is folded
    /// (lower case, accents gone) at most once a call, and only the fields a rule or the typed
    /// words look at are read.
    public func select<F: SongFields>(_ songs: [F.Item], now: Int64, fields: F) -> [F.Item] {
        var picked = matcher(now: now, fields: fields).map { songs.filter($0) } ?? songs
        if let sort, let order = sort.order { picked = sortSongsBy(picked, order, descending: sort.descending, fields: fields) }
        if let most = limit, most >= 0, picked.count > most { picked = Array(picked.prefix(most)) }
        return picked
    }

    /// The test a song must pass, or nil when every song does.
    public func matcher<F: SongFields>(now: Int64, fields: F) -> ((F.Item) -> Bool)? {
        let folds = Folds()
        let tests = rules.filter(\.complete).map { ruleTest($0, now: now, fields: fields, folds: folds) }
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map { foldText(String($0)) }
            .filter { !$0.isEmpty }
        let byRules: ((F.Item) -> Bool)?
        if tests.isEmpty {
            byRules = nil
        } else if tests.count == 1 {
            byRules = tests[0]
        } else if match == .all {
            byRules = { song in tests.allSatisfy { $0(song) } }
        } else {
            byRules = { song in tests.contains { $0(song) } }
        }
        let byWords: ((F.Item) -> Bool)? = words.isEmpty ? nil : { song in hasWords(song, words, fields, folds) }
        guard let byRules else { return byWords }
        guard let byWords else { return byRules }
        return { song in byRules(song) && byWords(song) }
    }
}

/// Every typed word is in one of the names the filter field searches.
private func hasWords<F: SongFields>(_ song: F.Item, _ words: [String], _ fields: F, _ folds: Folds) -> Bool {
    let title = foldText(fields.title(song))
    var artist: String?
    var album: String?
    var albumArtist: String?
    var genres: [String]?
    for word in words {
        if utf8Contains(title, word) { continue }
        let foldedArtist = artist ?? folds.of(fields.artist(song))
        artist = foldedArtist
        if utf8Contains(foldedArtist, word) { continue }
        let foldedAlbum = album ?? folds.of(fields.album(song))
        album = foldedAlbum
        if utf8Contains(foldedAlbum, word) { continue }
        let foldedAlbumArtist = albumArtist ?? folds.of(fields.albumArtist(song))
        albumArtist = foldedAlbumArtist
        if utf8Contains(foldedAlbumArtist, word) { continue }
        let foldedGenres = genres ?? fields.genres(song).map(folds.of)
        genres = foldedGenres
        if foldedGenres.contains(where: { utf8Contains($0, word) }) { continue }
        return false
    }
    return true
}

private func ruleTest<F: SongFields>(_ rule: QueryRule, now: Int64, fields: F, folds: Folds) -> (F.Item) -> Bool {
    switch rule.field.kind {
    case .text: return textTest(rule, fields, folds)
    case .number: return numberTest(rule, fields)
    case .date: return dateTest(rule, now, fields)
    case .flag:
        let wanted = rule.flag == true
        if rule.field == .lossless { return { song in fields.lossless(song) == wanted } }
        return { song in fields.favorite(song) == wanted }
    }
}

/// Words. A song with several genres passes a positive test when any genre does, and a negative
/// one ("is not", "does not contain") when none fails it.
private func textTest<F: SongFields>(_ rule: QueryRule, _ fields: F, _ folds: Folds) -> (F.Item) -> Bool {
    let value = foldText(rule.text ?? "")
    let values: (F.Item) -> [String]
    switch rule.field {
    case .genre: values = { song in fields.genres(song).map(folds.of) }
    case .title: values = { song in [foldText(fields.title(song))] }
    case .artist: values = { song in [folds.of(fields.artist(song))] }
    case .album: values = { song in [folds.of(fields.album(song))] }
    case .albumArtist: values = { song in [folds.of(fields.albumArtist(song))] }
    case .composer: values = { song in [folds.of(fields.composer(song))] }
    default: values = { song in [folds.of(fields.format(song))] }
    }
    switch rule.op {
    case .contains: return { song in values(song).contains { utf8Contains($0, value) } }
    case .is: return { song in values(song).contains { utf8Equal($0, value) } }
    case .startsWith: return { song in values(song).contains { $0.utf8.starts(with: value.utf8) } }
    case .isNot: return { song in !values(song).contains { utf8Equal($0, value) } }
    default: return { song in !values(song).contains { utf8Contains($0, value) } }
    }
}

/// Numbers. Plays and rating are 0 when there are none; a missing year, length, bit rate or BPM
/// passes only "is not".
private func numberTest<F: SongFields>(_ rule: QueryRule, _ fields: F) -> (F.Item) -> Bool {
    let value: (F.Item) -> Int64?
    switch rule.field {
    case .year: value = { song in fields.year(song).flatMap { $0 > 0 ? Int64($0) : nil } }
    case .plays: value = { song in fields.plays(song) }
    case .rating: value = { song in Int64(fields.rating(song)) }
    case .duration: value = { song in let s = fields.seconds(song); return s > 0 ? Int64(s) : nil }
    case .bitRate: value = { song in fields.bitRate(song).flatMap { $0 > 0 ? Int64($0) : nil } }
    default: value = { song in fields.bpm(song).flatMap { $0 > 0 ? Int64($0) : nil } }
    }
    let number = rule.number ?? 0
    let low = min(number, rule.to ?? number)
    let high = max(number, rule.to ?? number)
    switch rule.op {
    case .is: return { song in value(song) == number }
    case .isNot: return { song in value(song) != number }
    case .atLeast: return { song in value(song).map { $0 >= number } == true }
    case .atMost: return { song in value(song).map { $0 <= number } == true }
    default: return { song in value(song).map { (low...high).contains($0) } == true }
    }
}

/// Dates. A song never played counts as not played in any span; "before" and "after" split the
/// songs that have a date at `at`.
private func dateTest<F: SongFields>(_ rule: QueryRule, _ now: Int64, _ fields: F) -> (F.Item) -> Bool {
    let value: (F.Item) -> Int64? = rule.field == .added ? fields.addedAt : fields.lastPlayedAt
    let since = now - Int64(rule.days ?? 0) * dayMs
    let at = rule.at ?? 0
    switch rule.op {
    case .inTheLast: return { song in value(song).map { $0 >= since } == true }
    case .notInTheLast: return { song in value(song).map { $0 < since } ?? true }
    case .before: return { song in value(song).map { $0 < at } == true }
    case .after: return { song in value(song).map { $0 >= at } == true }
    default: return { song in value(song) == nil }
    }
}

/// Names folded for matching, each worked out once a call: artists, albums and genres repeat
/// across thousands of songs.
private final class Folds {
    private var known: [String: String] = [:]

    func of(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "" }
        if let folded = known[text] { return folded }
        let folded = foldText(text)
        known[text] = folded
        return folded
    }
}

/// Whether `part` appears in `text`, byte for byte.
private func utf8Contains(_ text: String, _ part: String) -> Bool {
    if part.isEmpty { return true }
    var hay = text
    var needle = part
    return hay.withUTF8 { h in
        needle.withUTF8 { n in
            let count = n.count
            guard count <= h.count else { return false }
            let first = n[0]
            var i = 0
            while i <= h.count - count {
                if h[i] == first {
                    var j = 1
                    while j < count, h[i + j] == n[j] { j += 1 }
                    if j == count { return true }
                }
                i += 1
            }
            return false
        }
    }
}

private func utf8Equal(_ a: String, _ b: String) -> Bool { a.utf8.elementsEqual(b.utf8) }

/// Lower case with accents gone, so "beyonce" finds "Beyoncé": the same as `searchKey`, with a
/// fast path for plain ASCII, which most names are.
public func foldText(_ text: String) -> String {
    var copy = text
    let ascii: String? = copy.withUTF8 { bytes in
        for byte in bytes where byte >= 128 { return nil }
        var start = 0
        var end = bytes.count
        while start < end, isAsciiSpace(bytes[start]) { start += 1 }
        while end > start, isAsciiSpace(bytes[end - 1]) { end -= 1 }
        var out = [UInt8]()
        out.reserveCapacity(end - start)
        for i in start..<end {
            let byte = bytes[i]
            out.append(byte >= 65 && byte <= 90 ? byte + 32 : byte)
        }
        return String(decoding: out, as: UTF8.self)
    }
    return ascii ?? searchKey(text)
}

/// Tab, line feed, vertical tab, form feed, carriage return and space.
private func isAsciiSpace(_ byte: UInt8) -> Bool { byte == 32 || (byte >= 9 && byte <= 13) }
