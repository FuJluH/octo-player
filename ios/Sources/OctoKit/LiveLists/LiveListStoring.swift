import Foundation

/// Live lists kept as stored text: each account's lists as one lists value under its own key, so
/// signing in elsewhere shows that account's and keeps these for when it comes back.
public enum LiveListStoring {
    /// The lists kept while no server is signed in.
    public static let phoneAccount = "phone"

    /// The key an account's lists are stored under.
    public static func key(_ account: String) -> String { "lists:\(account)" }

    /// Whose lists these are for a signed-in server: its session id, else the account key of its
    /// user and address.
    public static func account(sessionId: String?, username: String, address: String) -> String {
        if let sessionId, !sessionId.isEmpty { return sessionId }
        return liveListAccountKey(username: username, address: address)
    }

    /// The stored lists with `list` saved, stamped as changed at `now` (and made now, when new),
    /// its name trimmed.
    public static func saving(_ list: LiveList, in stored: String?, now: Int64) -> (stored: String, saved: LiveList) {
        var stamped = list
        stamped.name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
        stamped.changed = now
        if stamped.created == 0 { stamped.created = now }
        return (encodeLiveLists(decodeLiveLists(stored).saving(stamped)), stamped)
    }

    public static func removing(_ id: String, in stored: String?) -> String {
        encodeLiveLists(decodeLiveLists(stored).removing(id))
    }

    /// The stored lists with one renamed, or nil when there is no such list, or the name is blank or
    /// the same.
    public static func renaming(_ id: String, to name: String, in stored: String?, now: Int64) -> (stored: String, renamed: LiveList)? {
        guard var list = decodeLiveLists(stored).first(where: { $0.id == id }), !LibraryQuery.isBlank(name),
              name.trimmingCharacters(in: .whitespacesAndNewlines) != list.name else { return nil }
        list.name = name
        let saved = saving(list, in: stored, now: now)
        return (saved.stored, saved.saved)
    }

    /// The stored lists with a copy of `list` just after it, named "<name> (copy)".
    public static func duplicating(_ list: LiveList, in stored: String?, now: Int64, id: String = UUID().uuidString.lowercased())
        -> (stored: String, copy: LiveList) {
        let (lists, copy) = decodeLiveLists(stored).duplicating(list, now: now, id: id)
        return (encodeLiveLists(lists), copy)
    }
}

/// Every account's live lists held in memory as their stored values, with the account in use.
public struct LiveListMemoryStore: Sendable, Hashable {
    /// The stored values, by key.
    public private(set) var values: [String: String]
    public var account: String

    public init(account: String, values: [String: String] = [:]) {
        self.account = account
        self.values = values
    }

    private var key: String { LiveListStoring.key(account) }

    /// The lists of the account in use, in the order they were made.
    public var lists: [LiveList] { decodeLiveLists(values[key]) }

    public func byId(_ id: String) -> LiveList? { lists.first { $0.id == id } }

    /// Saves a new list or a changed one, stamped as changed at `now`.
    @discardableResult
    public mutating func save(_ list: LiveList, now: Int64) -> LiveList {
        let (stored, saved) = LiveListStoring.saving(list, in: values[key], now: now)
        values[key] = stored
        return saved
    }

    public mutating func remove(_ id: String) { values[key] = LiveListStoring.removing(id, in: values[key]) }

    /// Ignores a blank name or the same name.
    public mutating func rename(_ id: String, to name: String, now: Int64) {
        if let renamed = LiveListStoring.renaming(id, to: name, in: values[key], now: now) { values[key] = renamed.stored }
    }

    /// A copy just after the list, named "<name> (copy)".
    @discardableResult
    public mutating func duplicate(_ list: LiveList, now: Int64, id: String = UUID().uuidString.lowercased()) -> LiveList {
        let (stored, copy) = LiveListStoring.duplicating(list, in: values[key], now: now, id: id)
        values[key] = stored
        return copy
    }

    /// Forgets the lists of a server taken off the list.
    public mutating func forget(_ account: String) { values[LiveListStoring.key(account)] = nil }
}
