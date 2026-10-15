import Foundation

// Server songs played lately, kept on the phone so they play again without the network: a
// rolling store that lets the least recently played go once it is full. Downloads are not kept
// here; they are real files that stay. The rules below decide what counts as saved and what
// goes; the store itself lives with the app.

/// One saved piece of a song: where in the song it starts, how long it is, and when it was last
/// played from.
public struct StreamCacheSpan: Sendable, Hashable {
    /// The name the song is saved under.
    public var key: String
    public var position: Int64
    public var length: Int64
    public var lastTouchedMs: Int64

    public init(key: String, position: Int64, length: Int64, lastTouchedMs: Int64) {
        self.key = key
        self.position = position
        self.length = length
        self.lastTouchedMs = lastTouchedMs
    }
}

/// Whether songs are kept at all at this size.
public func streamCacheEnabled(_ size: CacheSize) -> Bool { size != .off }

/// How many bytes from `position` on are saved without a gap.
public func streamCacheSavedRun(_ spans: [StreamCacheSpan], from position: Int64) -> Int64 {
    var end = position
    for span in spans.sorted(by: { $0.position < $1.position }) {
        if span.position + span.length <= end { continue }
        if span.position > end { break }
        end = span.position + span.length
    }
    return end - position
}

/// Whether all of a song is saved under its name: its length is known and its pieces cover it
/// from the start with no gap. Nothing counts while songs are not kept.
public func streamCacheIsFullySaved(enabled: Bool, contentLength: Int64?, spans: [StreamCacheSpan]) -> Bool {
    guard enabled, let contentLength, contentLength > 0 else { return false }
    return streamCacheSavedRun(spans, from: 0) >= contentLength
}

/// Whether any of a song is saved under its name.
public func streamCacheIsPartlySaved(enabled: Bool, spans: [StreamCacheSpan]) -> Bool { enabled && !spans.isEmpty }

/// The names of every song saved whole, from each name's known length and its pieces.
public func streamCacheFullySavedKeys(enabled: Bool, lengths: [String: Int64], spans: [StreamCacheSpan]) -> Set<String> {
    guard enabled else { return [] }
    var byKey: [String: [StreamCacheSpan]] = [:]
    for span in spans { byKey[span.key, default: []].append(span) }
    return Set(byKey.keys.filter { streamCacheIsFullySaved(enabled: true, contentLength: lengths[$0], spans: byKey[$0] ?? []) })
}

/// The pieces to let go so the store fits in `limitBytes` with `incomingBytes` more on the way:
/// the least recently played first. Nothing goes before the size is known (`limitBytes` nil).
/// Ties go by name, then by place in the song.
public func streamCacheEvictions(_ spans: [StreamCacheSpan], limitBytes: Int64?, incomingBytes: Int64 = 0) -> [StreamCacheSpan] {
    guard let limitBytes else { return [] }
    let oldestFirst = spans.sorted { a, b in
        if a.lastTouchedMs != b.lastTouchedMs { return a.lastTouchedMs < b.lastTouchedMs }
        if a.key != b.key { return a.key.utf16.lexicographicallyPrecedes(b.key.utf16) }
        return a.position < b.position
    }
    var total = spans.reduce(Int64(0)) { $0 + $1.length }
    var gone: [StreamCacheSpan] = []
    for span in oldestFirst {
        if total + incomingBytes <= limitBytes { break }
        gone.append(span)
        total -= span.length
    }
    return gone
}

/// How much the store holds: every saved piece, nothing else it keeps beside them.
public func streamCacheUsedBytes(_ spans: [StreamCacheSpan]) -> Int64 { spans.reduce(Int64(0)) { $0 + $1.length } }
