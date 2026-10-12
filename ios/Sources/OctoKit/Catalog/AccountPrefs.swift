import Foundation

// Small stores keep what belongs to one account under "<name>@<account>", the account being a
// kept server's id.

/// The key a value of one account is kept under.
public func accountKey(_ name: String, _ account: String) -> String { "\(name)@\(account)" }

/// The id a kept server has for an account an older single-server store wrote as
/// "user@address": the same key the server list gives it.
public func accountOfServerKey(_ serverKey: String) -> String {
    guard let at = serverKey.lastIndex(of: "@") else { return serverAccountKey(serverKey, serverKey) }
    return serverAccountKey(String(serverKey[..<at]), String(serverKey[serverKey.index(after: at)...]))
}

/// The keys among `keys` that belong to `account`, to forget when it is removed.
public func accountKeys(_ keys: some Sequence<String>, of account: String) -> [String] {
    keys.filter { $0.hasSuffix("@\(account)") }
}

/// Values kept under plain names moved to the account's own names, unless the account already
/// has its own: what to write, and the plain names to remove.
public func movedToAccount(_ plain: [String: String], existing: Set<String>, account: String) -> (write: [String: String], remove: [String]) {
    var write: [String: String] = [:]
    for (name, value) in plain where !existing.contains(accountKey(name, account)) {
        write[accountKey(name, account)] = value
    }
    return (write, Array(plain.keys))
}

extension StoredServer {
    /// The source this server's music is kept under, from its main address.
    public var sourceId: String { serverSourceId(address) }
}
