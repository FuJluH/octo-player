import Foundation

/// A list of songs picked by rules rather than by hand: "Added in the last month, lossless". It is
/// worked out from the library each time it is shown, so it keeps up as songs are added, played
/// and liked. Kept on the device, per account, in the shared lists shape.
public struct LiveList: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var query: LibraryQuery
    /// Milliseconds since 1970.
    public var created: Int64
    public var changed: Int64

    public init(id: String, name: String, query: LibraryQuery = LibraryQuery(), created: Int64 = 0, changed: Int64 = 0) {
        self.id = id
        self.name = name
        self.query = query
        self.created = created
        self.changed = changed
    }

    /// A list made now, its name trimmed.
    public static func new(name: String, query: LibraryQuery, now: Int64, id: String = UUID().uuidString.lowercased()) -> LiveList {
        LiveList(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), query: query, created: now, changed: now)
    }

    /// The library's songs this list picks, in its order, at most its limit.
    public func songs<F: SongFields>(of library: [F.Item], now: Int64, fields: F) -> [F.Item] {
        query.select(library, now: now, fields: fields)
    }
}

// MARK: - Stored form

/// The lists as a file or a stored value keeps them: `{"version":1,"lists":[...]}`.
public func encodeLiveLists(_ lists: [LiveList]) -> String {
    let items = lists.map { list in
        var parts = ["\"id\":" + LibraryQuery.jsonQuoted(list.id), "\"name\":" + LibraryQuery.jsonQuoted(list.name),
                     "\"query\":" + list.query.toJSON()]
        if list.created != 0 { parts.append("\"created\":\(list.created)") }
        if list.changed != 0 { parts.append("\"changed\":\(list.changed)") }
        return "{" + parts.joined(separator: ",") + "}"
    }
    return "{\"version\":1,\"lists\":[" + items.joined(separator: ",") + "]}"
}

/// The lists in the text, or none when it is not a lists file. A list that cannot be read is left
/// out rather than losing the others, a rule this version does not know is dropped from its list
/// only, and of two lists with one id the first is kept.
public func decodeLiveLists(_ text: String?) -> [LiveList] {
    guard let text, !LibraryQuery.isBlank(text),
          let read = try? JSONDecoder().decode(StoredLiveLists.self, from: Data(text.utf8)) else { return [] }
    var seen = Set<String>()
    return read.lists.filter { seen.insert($0.id).inserted }
}

private struct StoredLiveLists: Decodable {
    let lists: [LiveList]

    private enum Key: String, CodingKey { case lists }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        lists = ((try? c.decodeIfPresent([StoredLiveList].self, forKey: .lists)) ?? []).compactMap(\.list)
    }
}

/// One stored list, or nil when it has no id or name.
private struct StoredLiveList: Decodable {
    let list: LiveList?

    private enum Key: String, CodingKey { case id, name, query, created, changed }

    init(from decoder: any Decoder) {
        guard let c = try? decoder.container(keyedBy: Key.self),
              let id = Self.text(c, .id), !LibraryQuery.isBlank(id),
              let name = Self.text(c, .name) else {
            list = nil
            return
        }
        let query = (try? c.decodeIfPresent(LibraryQueryReading.self, forKey: .query))?.query ?? LibraryQuery()
        list = LiveList(id: id, name: name, query: query, created: Self.long(c, .created) ?? 0, changed: Self.long(c, .changed) ?? 0)
    }

    /// A plain value as text: a string as it is, a number or yes-or-no as written.
    private static func text(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> String? {
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return text }
        if let number = try? c.decodeIfPresent(Int64.self, forKey: key) { return String(number) }
        if let number = try? c.decodeIfPresent(Double.self, forKey: key) { return String(number) }
        if let flag = try? c.decodeIfPresent(Bool.self, forKey: key) { return String(flag) }
        return nil
    }

    /// A whole number, written as a number or as text.
    private static func long(_ c: KeyedDecodingContainer<Key>, _ key: Key) -> Int64? {
        if let number = try? c.decodeIfPresent(Int64.self, forKey: key) { return number }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Int64(text) }
        return nil
    }
}

// MARK: - Changes

extension Array where Element == LiveList {
    /// The lists with `list` saved: in its place when it is there, else at the end.
    public func saving(_ list: LiveList) -> [LiveList] {
        contains { $0.id == list.id } ? map { $0.id == list.id ? list : $0 } : self + [list]
    }

    public func removing(_ id: String) -> [LiveList] { filter { $0.id != id } }

    /// A copy of `list` named "<name> (copy)", placed right after it.
    public func duplicating(_ list: LiveList, now: Int64, id: String = UUID().uuidString.lowercased())
        -> (lists: [LiveList], copy: LiveList) {
        let copy = LiveList.new(name: "\(list.name.trimmingCharacters(in: .whitespacesAndNewlines)) (copy)", query: list.query,
                                now: now, id: id)
        guard let at = firstIndex(where: { $0.id == list.id }) else { return (self + [copy], copy) }
        var lists = self
        lists.insert(copy, at: at + 1)
        return (lists, copy)
    }
}

/// Which account's lists these are: the first 8 bytes of SHA-256 of "username@address", in hex,
/// the same name an account's plays and queue are kept under.
public func liveListAccountKey(username: String, address: String) -> String {
    Hashes.hex(Hashes.sha256(Array("\(username)@\(address)".utf8)).prefix(8))
}
