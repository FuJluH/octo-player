import Foundation

/// What to do with a copy of a server song kept on the phone, a saved song or a download. The
/// server can swap a song's file for another (a better copy, say) and keep the song's id, so the
/// id alone never says the copy is still the song: the file's size does. `keptFor` is the server's
/// size for the file the copy was made from. A copy made before that was noted has none: it is
/// checked by its own size when it is the file as it is (`asIs`), and otherwise taken as it is,
/// since nothing tells. A song the server gives no size for keeps its copy.
public enum KeptCopyCheck: Sendable, Equatable {
    /// The copy is of the file the server has now.
    case keep
    /// Nothing says the file changed: note the server's size with the copy.
    case note
    /// The server's file is another one: fetch it again.
    case refetch
}

public func checkKeptCopy(keptFor: Int64?, serverSize: Int64?, copySize: Int64, asIs: Bool) -> KeptCopyCheck {
    guard let now = serverSize, now > 0 else { return .keep }
    if let noted = keptFor, noted > 0 { return noted == now ? .keep : .refetch }
    return !asIs || copySize == now ? .note : .refetch
}
