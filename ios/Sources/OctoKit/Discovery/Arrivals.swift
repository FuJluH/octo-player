import Foundation

/// What to say when downloads asked for in this run of the app reach the library: one line for a
/// song, and for an album one line once its last song lands, not one per song. Downloads asked
/// for before the app started arrive quietly.
public final class Arrivals: @unchecked Sendable {
    private final class AlbumAsk {
        let title: String
        var waiting: Set<String>
        var landed = Set<String>()
        var failed = Set<String>()

        init(title: String, waiting: Set<String>) {
            self.title = title
            self.waiting = waiting
        }
    }

    private let lock = NSLock()
    private var songs: [String: String] = [:]
    private var albums: [AlbumAsk] = []

    public init() {}

    /// One song was asked for. A song of an album already asked for counts with its album again.
    public func askedSong(_ findId: String, title: String) {
        lock.withLock {
            if let album = albums.first(where: { $0.failed.contains(findId) }) {
                album.failed.remove(findId)
                album.waiting.insert(findId)
            } else if !albums.contains(where: { $0.waiting.contains(findId) }) {
                songs[findId] = title
            }
        }
    }

    /// A whole album was asked for, with the songs from it still to come.
    public func askedAlbum(_ title: String, findIds: [String]) {
        guard !findIds.isEmpty else { return }
        lock.withLock {
            let ids = Set(findIds)
            for id in findIds { songs[id] = nil }
            for album in albums { album.waiting.subtract(ids) }
            albums.removeAll { $0.waiting.isEmpty && $0.landed.isEmpty }
            albums.append(AlbumAsk(title: title.trimmingCharacters(in: .whitespaces).isEmpty ? "The album" : title, waiting: ids))
        }
    }

    /// A song reached the library. Answers what to say, if anything.
    public func landed(_ findId: String) -> String? {
        lock.withLock {
            if let title = songs.removeValue(forKey: findId) { return "\(title) is in your library" }
            guard let album = albums.first(where: { $0.waiting.contains(findId) }) else { return nil }
            album.waiting.remove(findId)
            album.landed.insert(findId)
            return settle(album)
        }
    }

    /// A song could not be downloaded. A song on its own says nothing here, as the button shows
    /// it; the last song of an album settles the album.
    public func failed(_ findId: String) -> String? {
        lock.withLock {
            guard let album = albums.first(where: { $0.waiting.contains(findId) }) else { return nil }
            album.waiting.remove(findId)
            album.failed.insert(findId)
            return settle(album)
        }
    }

    private func settle(_ album: AlbumAsk) -> String? {
        guard album.waiting.isEmpty else { return nil }
        albums.removeAll { $0 === album }
        if album.landed.isEmpty { return nil }
        if album.failed.isEmpty { return "\(album.title) is in your library" }
        if album.failed.count == 1 { return "\(album.title) is in your library, but 1 song could not be downloaded" }
        return "\(album.title) is in your library, but \(album.failed.count) songs could not be downloaded"
    }
}
