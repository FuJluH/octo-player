import Foundation

// Wrong lyrics are dealt with by the listener, one song at a time, in two ways. The lyrics menu
// can choose other lyrics: every copy the app can find for the song (the server's, the song
// file's, a .lrc file's, the online library's match and its search results, or a search typed by
// hand for a song whose tags are wrong), and the one picked is used for that song from then on,
// ahead of the usual order. Or it can hide the song's lyrics, for a song where no copy is right.
// Both are kept here, by song, and both can be undone from the same menu.

/// Lyrics the listener picked for a song: one of the song's own sources, one copy in the online
/// library, by its number, or a choice the server keeps for every app. This phone never keeps a
/// server choice as its own pick: the server keeps it.
public enum LyricsPick: Hashable, Sendable {
    case own(LyricsSource)
    case online(Int)
    /// "auto", or the id of one copy the server holds ("kugou:123").
    case onServer(String)

    /// How a pick is written: "own:Server", "online:12345" or "server:auto".
    public var encoded: String {
        switch self {
        case .own(let source): "own:\(source.rawValue)"
        case .online(let id): "online:\(id)"
        case .onServer(let choice): "server:\(choice)"
        }
    }
}

/// A kept pick, or nil for one this app cannot read.
public func decodePick(_ text: String?) -> LyricsPick? {
    guard let text else { return nil }
    let kind: String
    let value: String
    if let colon = text.firstIndex(of: ":") {
        kind = String(text[..<colon])
        value = String(text[text.index(after: colon)...])
    } else {
        kind = text
        value = ""
    }
    switch kind {
    case "own":
        guard let source = LyricsSource.allCases.first(where: { $0.rawValue == value && $0 != .online }) else { return nil }
        return .own(source)
    case "online":
        guard let number = Int(value) else { return nil }
        return .online(number)
    case "server":
        return value.isEmpty ? nil : .onServer(value)
    default:
        return nil
    }
}

/// Which pick these lyrics are, or nil when that cannot be told: online lyrics saved before the
/// library's number was kept.
public func pickOf(_ lyrics: Lyrics) -> LyricsPick? {
    switch lyrics.source {
    case .online: lyrics.onlineId.map(LyricsPick.online)
    default: .own(lyrics.source)
    }
}

/// What the listener said about one song's lyrics: the ones picked, if any, and whether they are
/// hidden.
public struct LyricsChoice: Equatable, Sendable {
    public var pick: LyricsPick?
    public var hidden: Bool

    public init(_ pick: LyricsPick? = nil, hidden: Bool = false) {
        self.pick = pick
        self.hidden = hidden
    }
}

/// Somewhere small values are kept by name, such as the phone's own settings.
public protocol KeptValues: AnyObject {
    func string(_ key: String) -> String?
    func bool(_ key: String) -> Bool?
    func int(_ key: String) -> Int?
    func set(_ key: String, _ value: Any)
    func remove(_ key: String)
    /// Every value kept, by name.
    func all() -> [String: Any]
}

/// Values kept in memory, for tests and for a phone with nowhere else to keep them.
public final class MemoryValues: KeptValues, @unchecked Sendable {
    private var values: [String: Any] = [:]
    private let lock = NSLock()

    public init() {}

    public func string(_ key: String) -> String? { locked { values[key] as? String } }
    public func bool(_ key: String) -> Bool? { locked { values[key] as? Bool } }
    public func int(_ key: String) -> Int? { locked { values[key] as? Int } }
    public func set(_ key: String, _ value: Any) { locked { values[key] = value } }
    public func remove(_ key: String) { locked { _ = values.removeValue(forKey: key) } }
    public func all() -> [String: Any] { locked { values } }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

private let PICK_PREFIX = "pick:"
private let HIDDEN_PREFIX = "hidden:"

/// Each song's lyrics choice, kept only for songs the listener changed, as `pick:<id>` and
/// `hidden:<id>`.
public final class LyricsChoices: @unchecked Sendable {
    private let store: KeptValues
    /// Bumped on every change, so a view can follow the choices.
    public private(set) var version = 0

    public init(_ store: KeptValues) {
        self.store = store
    }

    public func current(_ trackId: String) -> LyricsChoice {
        LyricsChoice(decodePick(store.string(PICK_PREFIX + trackId)), hidden: store.bool(HIDDEN_PREFIX + trackId) == true)
    }

    /// Uses these lyrics for the song from now on. Picking lyrics for a hidden song shows it again.
    public func pick(_ trackId: String, _ pick: LyricsPick) {
        store.set(PICK_PREFIX + trackId, pick.encoded)
        store.remove(HIDDEN_PREFIX + trackId)
        version += 1
    }

    /// The song shows no lyrics until they are shown again. The pick, if any, is kept for then.
    public func hide(_ trackId: String) {
        store.set(HIDDEN_PREFIX + trackId, true)
        version += 1
    }

    public func show(_ trackId: String) {
        store.remove(HIDDEN_PREFIX + trackId)
        version += 1
    }

    /// Forgets what this phone said about the song, so the server's choice stands alone. `hidden`
    /// keeps the song hidden here, as the server now has it.
    public func clear(_ trackId: String, hidden: Bool = false) {
        store.remove(PICK_PREFIX + trackId)
        if hidden { store.set(HIDDEN_PREFIX + trackId, true) } else { store.remove(HIDDEN_PREFIX + trackId) }
        version += 1
    }
}
