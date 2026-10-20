import Foundation
import OctoKit

/// Server songs played lately, kept on the phone so they play again without the network: a
/// rolling store that lets the least recently played go once it is full. Downloads are separate
/// and stay. Songs are kept under a stable name (the server, the song, its type, the request and
/// the size of its file on the server), never the signed address. Each song is one file on disk;
/// the list of them (`StreamCacheIndex`) is written beside them a moment after it changes, when a
/// song's fetch ends, and when the app goes to the background.
actor StreamCache {
    static let shared = StreamCache()

    private let folder: URL
    private let indexFile: URL
    private var index: StreamCacheIndex
    /// The room allowed, or nil until the setting is read: nothing is kept or let go before then.
    private var limit: Int64?
    private var dirty = false
    /// The write of the list that waits for changes to settle.
    private var saving: Task<Void, Never>?

    /// How long the list waits after a change before it is written.
    private static let saveAfter: Duration = .seconds(2)

    init() {
        folder = SettingsFeeds.cacheFolder
        indexFile = folder.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var entries: [String: StreamCacheEntry] = [:]
        if let data = try? Data(contentsOf: indexFile), let saved = try? JSONDecoder().decode([String: StreamCacheEntry].self, from: data) {
            // A song described but never saved is not kept from one run to the next.
            entries = saved.filter { !$0.value.pieces.isEmpty }
        }
        index = StreamCacheIndex(entries: entries)
    }

    /// Whether songs are kept at all: off until the setting is read, and off at size Off.
    var enabled: Bool { index.enabled }

    /// Applies the chosen size: Off clears everything at once; a new size applies at once,
    /// letting the oldest go.
    func setSize(_ size: CacheSize) {
        limit = size.bytes
        index.enabled = streamCacheEnabled(size)
        if !index.enabled {
            for key in index.entries.keys { try? FileManager.default.removeItem(at: file(key)) }
            index.removeAll()
            dirty = true
            save()
            return
        }
        evict(incoming: 0)
    }

    /// Whether the whole song is saved.
    func isFullySaved(_ key: String) -> Bool {
        dropIfGone(key)
        return index.isFullySaved(key)
    }

    /// Whether any of the song is saved.
    func isPartlySaved(_ key: String) -> Bool {
        dropIfGone(key)
        return index.isPartlySaved(key)
    }

    /// The name a server song's saved copy is read and written under for this request: see
    /// `savedCopyKey`. An older copy of a file the server has since swapped is let go here.
    func savedKey(_ sourceId: String, _ ref: StreamRef, _ request: StreamRequest) -> String {
        dropAllGone()
        let key = savedCopyKey(sourceId, ref, request, &index)
        settleDropped()
        return key
    }

    /// The request a server song loads with, by what is saved of it, and the name its saved copy
    /// is under: see `pickSavedRequest`.
    func pick(_ sourceId: String, _ ref: StreamRef, _ quality: StreamQuality) -> (request: StreamRequest, key: String) {
        dropAllGone()
        let picked = pickSavedRequest(sourceId, ref, quality, &index)
        settleDropped()
        return picked
    }

    /// The songs saved whole, as "<server>|<song id there>", for the offline marks.
    func fullySavedSongs() -> Set<String> {
        dropAllGone()
        return Set(index.fullySavedKeys().map(savedSongOf))
    }

    /// How much the saved songs take: their saved pieces, not the list of them.
    func usedBytes() -> Int64 {
        dropAllGone()
        return index.usedBytes()
    }

    /// Lets every saved song go at once.
    func clear() {
        for key in index.entries.keys { try? FileManager.default.removeItem(at: file(key)) }
        index.removeAll()
        dirty = true
        save()
        // Anything else left in the folder, such as a file whose song was already forgotten.
        for item in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        where item != indexFile {
            try? FileManager.default.removeItem(at: item)
        }
    }

    /// What is known of a saved song: its whole length and type.
    func info(_ key: String) -> (length: Int64?, mimeType: String?)? {
        dropIfGone(key)
        return index.entries[key].map { ($0.contentLength, $0.mimeType) }
    }

    /// How many bytes from `offset` on are saved without a gap.
    func savedRun(_ key: String, from offset: Int64) -> Int64 {
        dropIfGone(key)
        return index.savedRun(key, from: offset)
    }

    /// Saved bytes of a song, when that whole range is saved. Reading marks it played.
    func read(_ key: String, offset: Int64, length: Int) -> Data? {
        guard index.enabled, length > 0, savedRun(key, from: offset) >= Int64(length), let handle = try? FileHandle(forReadingFrom: file(key)) else { return nil }
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
        return (file(key), index.entries[key]?.mimeType)
    }

    /// The server answered for a saved song: a saved copy of another file (another type or whole
    /// length) goes, file and all, then the song is described as the server gave it. True when the
    /// saved copy went.
    @discardableResult
    func answered(_ key: String, contentLength: Int64?, mimeType: String?) -> Bool {
        guard index.enabled else { return false }
        let went = index.answered(key, StreamShape(type: mimeType, total: contentLength))
        if went { settleDropped() }
        describe(key, contentLength: contentLength, mimeType: mimeType)
        return went
    }

    /// Notes the whole length and type of a song as the server gave them, or the length a stream
    /// really had once it ended.
    func describe(_ key: String, contentLength: Int64?, mimeType: String?) {
        guard index.enabled else { return }
        index.describe(key, contentLength: contentLength, mimeType: mimeType, nowMs: epochMs())
        changed()
    }

    /// Saves bytes of a song at `offset`, letting the least recently played go to make room.
    func write(_ key: String, offset: Int64, data: Data) {
        guard index.enabled, !data.isEmpty else { return }
        evict(incoming: Int64(data.count), keeping: key)
        let url = file(key)
        let fresh = !FileManager.default.fileExists(atPath: url.path)
        if fresh {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
        } catch {
            return
        }
        index.wrote(key, offset: offset, count: Int64(data.count), freshFile: fresh, nowMs: epochMs())
        changed()
    }

    /// Marks a song as just played, so it is the last to go.
    func touch(_ key: String) {
        guard index.entries[key] != nil else { return }
        index.touch(key, nowMs: epochMs())
        changed()
    }

    /// Writes the list of saved songs now, when it changed.
    func save() {
        saving?.cancel()
        saving = nil
        guard dirty, let data = try? JSONEncoder().encode(index.entries) else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? data.write(to: indexFile, options: .atomic)
        dirty = false
    }

    /// The list changed: it is written once changes settle.
    private func changed() {
        dirty = true
        guard saving == nil else { return }
        saving = Task { [weak self] in
            try? await Task.sleep(for: Self.saveAfter)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    /// Lets the least recently played songs go until `incoming` more bytes fit. A song is let go
    /// whole, its file with it.
    private func evict(incoming: Int64, keeping: String? = nil) {
        let going = index.evictions(limitBytes: limit, incoming: incoming, keeping: keeping)
        guard !going.isEmpty else { return }
        for key in going { try? FileManager.default.removeItem(at: file(key)) }
        index.remove(going)
        dirty = true
        save()
    }

    /// Deletes the files of songs the list let go.
    private func settleDropped() {
        let dropped = index.takeDropped()
        guard !dropped.isEmpty else { return }
        for key in dropped { try? FileManager.default.removeItem(at: file(key)) }
        dirty = true
        save()
    }

    private func file(_ key: String) -> URL { folder.appendingPathComponent(Hashes.sha1Hex(key)) }

    /// Forgets a song whose file is no longer there, as after the system cleared the caches.
    private func dropIfGone(_ key: String) {
        guard index.entries[key] != nil, !FileManager.default.fileExists(atPath: file(key).path) else { return }
        index.fileGone(key)
        if index.entries[key] == nil { changed() }
    }

    private func dropAllGone() {
        for key in Array(index.entries.keys) { dropIfGone(key) }
    }

    private func epochMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
