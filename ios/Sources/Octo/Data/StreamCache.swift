import Foundation
import OctoKit

/// Server songs played lately, kept on the phone so they play again without the network: a
/// rolling store that lets the least recently played go once it is full. Downloads are separate
/// and stay. Songs are kept under a stable key (the server, the song, its type and the request),
/// never the signed address. Each song is one file on disk; the pieces of it saved so far are
/// listed beside it.
actor StreamCache {
    static let shared = StreamCache()

    private struct Entry: Codable {
        var contentLength: Int64?
        var mimeType: String?
        /// Saved pieces, merged where they touch: start and length.
        var pieces: [[Int64]]
        var lastTouchedMs: Int64
    }

    private let folder: URL
    private let indexFile: URL
    private var entries: [String: Entry] = [:]
    /// The room allowed, or nil until the setting is read: nothing is kept or let go before then.
    private var limit: Int64?
    private var dirty = false

    init() {
        folder = SettingsFeeds.cacheFolder
        indexFile = folder.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: indexFile), let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = saved
        }
    }

    /// Whether songs are kept at all: off until the setting is read, and off at size Off.
    var enabled: Bool { (limit ?? 0) > 0 }

    /// Applies the chosen size: Off clears everything at once; a new size applies at once,
    /// letting the oldest go.
    func setSize(_ size: CacheSize) {
        limit = size.bytes
        if !streamCacheEnabled(size) {
            for key in entries.keys { try? FileManager.default.removeItem(at: file(key)) }
            entries = [:]
            save()
            return
        }
        evict(incoming: 0)
    }

    private func spans() -> [StreamCacheSpan] {
        entries.flatMap { key, entry in
            entry.pieces.map { StreamCacheSpan(key: key, position: $0[0], length: $0[1], lastTouchedMs: entry.lastTouchedMs) }
        }
    }

    private func spans(_ key: String) -> [StreamCacheSpan] {
        guard let entry = entries[key] else { return [] }
        return entry.pieces.map { StreamCacheSpan(key: key, position: $0[0], length: $0[1], lastTouchedMs: entry.lastTouchedMs) }
    }

    /// Whether the whole song is saved.
    func isFullySaved(_ key: String) -> Bool {
        dropIfGone(key)
        return streamCacheIsFullySaved(enabled: enabled, contentLength: entries[key]?.contentLength, spans: spans(key))
    }

    /// Whether any of the song is saved.
    func isPartlySaved(_ key: String) -> Bool {
        dropIfGone(key)
        return streamCacheIsPartlySaved(enabled: enabled, spans: spans(key))
    }

    /// The songs saved whole, as "<server>|<song id there>", for the offline marks.
    func fullySavedSongs() -> Set<String> {
        for key in Array(entries.keys) { dropIfGone(key) }
        var lengths: [String: Int64] = [:]
        for (key, entry) in entries { if let length = entry.contentLength { lengths[key] = length } }
        return Set(streamCacheFullySavedKeys(enabled: enabled, lengths: lengths, spans: spans()).map(savedSongOf))
    }

    /// What is known of a saved song: its whole length and type.
    func info(_ key: String) -> (length: Int64?, mimeType: String?)? {
        dropIfGone(key)
        return entries[key].map { ($0.contentLength, $0.mimeType) }
    }

    /// How many bytes from `offset` on are saved without a gap.
    func savedRun(_ key: String, from offset: Int64) -> Int64 {
        guard enabled else { return 0 }
        dropIfGone(key)
        return streamCacheSavedRun(spans(key), from: offset)
    }

    /// Saved bytes of a song, when that whole range is saved. Reading marks it played.
    func read(_ key: String, offset: Int64, length: Int) -> Data? {
        guard enabled, savedRun(key, from: offset) >= Int64(length), let handle = try? FileHandle(forReadingFrom: file(key)) else { return nil }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.read(upToCount: length), data.count == length else { return nil }
        touch(key)
        return data
    }

    /// The whole song's file and type, when it is saved whole, for playing directly (open it with
    /// `AVURLAssetOverrideMIMETypeKey` set to the type, since the file has no extension).
    func savedFile(_ key: String) -> (url: URL, mimeType: String?)? {
        guard isFullySaved(key) else { return nil }
        touch(key)
        return (file(key), entries[key]?.mimeType)
    }

    /// Notes the whole length and type of a song as the server gave them.
    func describe(_ key: String, contentLength: Int64?, mimeType: String?) {
        guard enabled else { return }
        var entry = entries[key] ?? Entry(pieces: [], lastTouchedMs: epochMs())
        if let contentLength, contentLength > 0 { entry.contentLength = contentLength }
        if let mimeType { entry.mimeType = mimeType }
        entries[key] = entry
        dirty = true
    }

    /// Saves bytes of a song at `offset`, letting the least recently played go to make room.
    func write(_ key: String, offset: Int64, data: Data) {
        guard enabled, !data.isEmpty else { return }
        evict(incoming: Int64(data.count), keeping: key)
        let url = file(key)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            entries[key]?.pieces = []
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(offset))
        try? handle.write(contentsOf: data)
        var entry = entries[key] ?? Entry(pieces: [], lastTouchedMs: epochMs())
        entry.pieces = merged(entry.pieces + [[offset, Int64(data.count)]])
        entry.lastTouchedMs = epochMs()
        entries[key] = entry
        dirty = true
        if Int.random(in: 0..<16) == 0 { save() }
    }

    /// Marks a song as just played, so it is the last to go.
    func touch(_ key: String) {
        guard entries[key] != nil else { return }
        entries[key]?.lastTouchedMs = epochMs()
        dirty = true
    }

    /// Writes the list of saved pieces, when it changed.
    func save() {
        guard dirty, let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: indexFile, options: .atomic)
        dirty = false
    }

    /// Lets the least recently played songs go until `incoming` more bytes fit. A song is let go
    /// whole, its file with it.
    private func evict(incoming: Int64, keeping: String? = nil) {
        let going = Set(streamCacheEvictions(spans(), limitBytes: limit, incomingBytes: incoming).map(\.key)).subtracting([keeping].compactMap { $0 })
        guard !going.isEmpty else { return }
        for key in going {
            entries[key] = nil
            try? FileManager.default.removeItem(at: file(key))
        }
        dirty = true
        save()
    }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(Hashes.sha1Hex(key)) }

    /// Forgets a song whose file is no longer there, as after the whole cache was cleared.
    private func dropIfGone(_ key: String) {
        guard entries[key] != nil, !FileManager.default.fileExists(atPath: file(key).path) else { return }
        entries[key] = nil
        dirty = true
    }

    private func merged(_ pieces: [[Int64]]) -> [[Int64]] {
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

    private func epochMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
