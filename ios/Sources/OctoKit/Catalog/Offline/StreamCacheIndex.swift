import Foundation

/// What the phone knows of one saved song: its whole length and type once the server said, the
/// pieces of it saved so far (start and length, merged where they touch), when it was last played
/// from, and the server's size for the file it was saved from, once noted.
public struct StreamCacheEntry: Codable, Sendable, Equatable {
    public var contentLength: Int64?
    public var mimeType: String?
    public var pieces: [[Int64]]
    public var lastTouchedMs: Int64
    public var fileSize: Int64?

    public init(contentLength: Int64? = nil, mimeType: String? = nil, pieces: [[Int64]] = [], lastTouchedMs: Int64,
                fileSize: Int64? = nil) {
        self.contentLength = contentLength
        self.mimeType = mimeType
        self.pieces = pieces
        self.lastTouchedMs = lastTouchedMs
        self.fileSize = fileSize
    }
}

/// The list of saved songs, kept beside their files: what each name holds, what counts as saved,
/// and what goes when room runs out. The files themselves live with the app; the names of songs
/// let go by `drop` wait in `dropped` for it to delete their files.
public struct StreamCacheIndex: Sendable, Equatable {
    public private(set) var entries: [String: StreamCacheEntry]
    /// Whether songs are kept at all. Nothing counts as saved while they are not.
    public var enabled = false
    /// Songs let go by `drop` whose files are still to delete.
    public private(set) var dropped: [String] = []

    public init(entries: [String: StreamCacheEntry] = [:], enabled: Bool = false) {
        self.entries = entries
        self.enabled = enabled
    }

    // MARK: Reading

    public func spans(_ key: String) -> [StreamCacheSpan] {
        guard let entry = entries[key] else { return [] }
        return entry.pieces.map { StreamCacheSpan(key: key, position: $0[0], length: $0[1], lastTouchedMs: entry.lastTouchedMs) }
    }

    public func spans() -> [StreamCacheSpan] { entries.keys.flatMap { spans($0) } }

    /// Whether the whole song is saved.
    public func isFullySaved(_ key: String) -> Bool {
        streamCacheIsFullySaved(enabled: enabled, contentLength: entries[key]?.contentLength, spans: spans(key))
    }

    /// Whether any of the song is saved.
    public func isPartlySaved(_ key: String) -> Bool { streamCacheIsPartlySaved(enabled: enabled, spans: spans(key)) }

    /// How many bytes from `offset` on are saved without a gap.
    public func savedRun(_ key: String, from offset: Int64) -> Int64 {
        enabled ? streamCacheSavedRun(spans(key), from: offset) : 0
    }

    /// The names of every song saved whole.
    public func fullySavedKeys() -> Set<String> {
        var lengths: [String: Int64] = [:]
        for (key, entry) in entries { if let length = entry.contentLength { lengths[key] = length } }
        return streamCacheFullySavedKeys(enabled: enabled, lengths: lengths, spans: spans())
    }

    /// How much the saved songs take: their saved pieces, not the list of them.
    public func usedBytes() -> Int64 { streamCacheUsedBytes(spans()) }

    // MARK: Changing

    /// Notes the whole length and type of a song as the server gave them. A song may be described
    /// before any of it is saved, and a stream that ended short of what it said is described again
    /// with the length it really had.
    public mutating func describe(_ key: String, contentLength: Int64?, mimeType: String?, nowMs: Int64) {
        guard enabled else { return }
        var entry = entries[key] ?? StreamCacheEntry(lastTouchedMs: nowMs)
        if let contentLength, contentLength > 0 { entry.contentLength = contentLength }
        if let mimeType { entry.mimeType = mimeType }
        entries[key] = entry
    }

    /// Notes `count` bytes saved at `offset`. `freshFile` says the song's file was just made, so
    /// pieces listed for a file that is gone no longer count.
    public mutating func wrote(_ key: String, offset: Int64, count: Int64, freshFile: Bool, nowMs: Int64) {
        guard enabled, count > 0 else { return }
        var entry = entries[key] ?? StreamCacheEntry(lastTouchedMs: nowMs)
        if freshFile { entry.pieces = [] }
        entry.pieces = Self.merged(entry.pieces + [[offset, count]])
        entry.lastTouchedMs = nowMs
        entries[key] = entry
    }

    /// Marks a song as just played, so it is the last to go.
    public mutating func touch(_ key: String, nowMs: Int64) {
        guard entries[key] != nil else { return }
        entries[key]?.lastTouchedMs = nowMs
    }

    /// Forgets a song whose file is no longer there, as after the whole cache was cleared. A song
    /// only described so far, waiting for its first bytes, has no file yet and stays.
    public mutating func fileGone(_ key: String) {
        guard let entry = entries[key], !entry.pieces.isEmpty else { return }
        entries[key] = nil
    }

    /// Forgets these songs.
    public mutating func remove(_ keys: some Sequence<String>) {
        for key in keys { entries[key] = nil }
    }

    public mutating func removeAll() { entries = [:] }

    /// The songs to let go so `incoming` more bytes fit in `limitBytes`, least recently played
    /// first; a song goes whole. Never `keeping`, the song being saved now.
    public func evictions(limitBytes: Int64?, incoming: Int64, keeping: String? = nil) -> Set<String> {
        var going = Set(streamCacheEvictions(spans(), limitBytes: limitBytes, incomingBytes: incoming).map(\.key))
        if let keeping { going.remove(keeping) }
        return going
    }

    /// The names of songs let go by `drop` since the last time, for their files to be deleted.
    public mutating func takeDropped() -> [String] {
        defer { dropped = [] }
        return dropped
    }

    private static func merged(_ pieces: [[Int64]]) -> [[Int64]] {
        var out: [[Int64]] = []
        for piece in pieces.sorted(by: { $0[0] < $1[0] }) {
            if let last = out.last, piece[0] <= last[0] + last[1] {
                out[out.count - 1][1] = max(last[0] + last[1], piece[0] + piece[1]) - last[0]
            } else {
                out.append(piece)
            }
        }
        return out
    }
}

/// The saved songs as picking a song's saved name sees them: see `savedCopyKey`.
extension StreamCacheIndex: SavedCopies {
    public func has(_ key: String) -> Bool { isPartlySaved(key) }

    /// The whole length the server gave, or else how much is saved from the start (a song whose
    /// length was never noted).
    public func length(_ key: String) -> Int64? {
        if let length = entries[key]?.contentLength, length > 0 { return length }
        let run = savedRun(key, from: 0)
        return run > 0 ? run : nil
    }

    public func notedSize(_ key: String) -> Int64? { entries[key]?.fileSize.flatMap { $0 > 0 ? $0 : nil } }

    /// Notes the server's size for the file a song was saved from. A song whose length was never
    /// noted and whose bytes from the start come to that size is the file as it is, saved whole.
    public mutating func note(_ key: String, size: Int64) {
        guard entries[key] != nil else { return }
        entries[key]?.fileSize = size
        if entries[key]?.contentLength == nil, savedRun(key, from: 0) == size { entries[key]?.contentLength = size }
    }

    public mutating func drop(_ key: String) {
        guard entries[key] != nil else { return }
        entries[key] = nil
        dropped.append(key)
    }
}

/// The request a server song loads with and the name its saved copy is under, picked together from
/// what is saved: see `chooseRequest` and `savedCopyKey`. Every size the song could load in is
/// looked up under its saved name first, so an older copy of a file the server has since swapped
/// is let go whichever size it was saved in.
public func pickSavedRequest(_ sourceId: String, _ ref: StreamRef, _ quality: StreamQuality,
                             _ index: inout StreamCacheIndex) -> (request: StreamRequest, key: String) {
    var keys: [StreamRequest: String] = [:]
    let asked = ref.pinned.map { [$0] } ?? [phoneRequest(ref.mimeType, ref.bitrate, quality)] + requestVariants(ref)
    for request in asked where keys[request] == nil { keys[request] = savedCopyKey(sourceId, ref, request, &index) }
    let saved = index
    let request = chooseRequest(sourceId, ref, quality, fullySaved: { saved.isFullySaved($0) },
                                partlySaved: { saved.isPartlySaved($0) },
                                keyOf: { keys[$0] ?? streamCacheKey(sourceId, ref, $0) })
    return (request, keys[request] ?? savedCopyKey(sourceId, ref, request, &index))
}
