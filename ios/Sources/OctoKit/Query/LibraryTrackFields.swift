import Foundation

/// The library's songs, read the way the filters ask. Likes and plays live beside the songs, so
/// they come in: the liked song ids, and each song's listening (the phone's plays and the
/// server's). The library keeps no album artist, composer, bit rate or BPM, so a filter on those
/// matches nothing here.
public struct LibraryTrackFields: SongFields, Sendable {
    /// How much a song was listened to: how many plays, and when the last was (milliseconds since
    /// 1970, 0 for never).
    public struct Listening: Sendable, Hashable {
        public var plays: Int
        public var lastPlayedAt: Int64

        public init(plays: Int, lastPlayedAt: Int64) {
            self.plays = plays
            self.lastPlayedAt = lastPlayedAt
        }
    }

    public let liked: Set<String>
    public let listening: [String: Listening]

    public init(liked: Set<String> = [], listening: [String: Listening] = [:]) {
        self.liked = liked
        self.listening = listening
    }

    public func id(_ song: LibraryTrack) -> String { song.id }
    public func title(_ song: LibraryTrack) -> String { song.title }
    public func artist(_ song: LibraryTrack) -> String? { LibraryQuery.isBlank(song.artist) ? nil : song.artist }
    public func album(_ song: LibraryTrack) -> String? { LibraryQuery.isBlank(song.album) ? nil : song.album }
    public func albumId(_ song: LibraryTrack) -> String? { song.albumId }
    public func albumArtist(_ song: LibraryTrack) -> String? { nil }
    public func genres(_ song: LibraryTrack) -> [String] { LibraryQuery.isBlank(song.genre) ? [] : [song.genre] }
    public func composer(_ song: LibraryTrack) -> String? { nil }
    public func year(_ song: LibraryTrack) -> Int? { song.year }
    public func disc(_ song: LibraryTrack) -> Int? { song.discNo }
    public func track(_ song: LibraryTrack) -> Int? { song.trackNo }

    /// The library keeps seconds.
    public func addedAt(_ song: LibraryTrack) -> Int64? { song.addedAt > 0 ? song.addedAt * 1_000 : nil }

    public func lastPlayedAt(_ song: LibraryTrack) -> Int64? {
        guard let at = listening[song.id]?.lastPlayedAt, at > 0 else { return nil }
        return at
    }

    public func plays(_ song: LibraryTrack) -> Int64 { Int64(listening[song.id]?.plays ?? 0) }
    public func rating(_ song: LibraryTrack) -> Int { song.rating }
    public func favorite(_ song: LibraryTrack) -> Bool { liked.contains(song.id) }
    public func likedAt(_ song: LibraryTrack) -> Int64? { nil }
    public func seconds(_ song: LibraryTrack) -> Int { Int(song.durationMs / 1_000) }
    public func format(_ song: LibraryTrack) -> String? { Self.formatOf(song.mimeType) }

    public func lossless(_ song: LibraryTrack) -> Bool {
        isLosslessMimeType(song.mimeType) || isLosslessFormat(Self.formatOf(song.mimeType))
    }

    public func bitRate(_ song: LibraryTrack) -> Int? { nil }
    public func bpm(_ song: LibraryTrack) -> Int? { nil }

    /// A file's kind from its MIME type, in the words a server's suffix uses: "audio/flac" is flac,
    /// "audio/mpeg" mp3, "audio/mp4" m4a.
    public static func formatOf(_ mimeType: String?) -> String? {
        guard let mimeType else { return nil }
        let lower = mimeType.lowercased()
        guard let slash = lower.firstIndex(of: "/") else { return nil }
        var kind = String(lower[lower.index(after: slash)...])
        if let semicolon = kind.firstIndex(of: ";") { kind = String(kind[..<semicolon]) }
        kind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind.hasPrefix("x-") { kind = String(kind.dropFirst(2)) }
        switch kind {
        case "": return nil
        case "mpeg", "mp3", "mpeg3": return "mp3"
        case "mp4", "m4a": return "m4a"
        case "aac-adts": return "aac"
        case "wave", "vnd.wave": return "wav"
        case "aif": return "aiff"
        case "wavpack": return "wv"
        default: return kind
        }
    }
}

/// A sorted list of songs as `query` filters it, in the same order, its letter headings kept in
/// step with the songs left. The query's own order and limit are not used: the list keeps the
/// order the listener chose.
public func filteredSongs<F: SongFields>(_ all: Sorted<F.Item>, _ query: LibraryQuery, fields: F, now: Int64) -> Sorted<F.Item>
where F.Item: Sendable {
    guard query.filters, let passes = query.matcher(now: now, fields: fields) else { return all }
    var items: [F.Item] = []
    var headings: [String]? = all.headings == nil ? nil : []
    for (index, item) in all.items.enumerated() where passes(item) {
        items.append(item)
        if let named = all.headings, index < named.count { headings?.append(named[index]) }
    }
    return Sorted(items: items, order: all.order, headings: headings)
}

/// Each song's listening, by song id.
public func libraryListening(_ played: [PlayedTrack]) -> [String: LibraryTrackFields.Listening] {
    Dictionary(played.map { ($0.track.id, LibraryTrackFields.Listening(plays: $0.plays, lastPlayedAt: $0.lastPlayedAt)) },
               uniquingKeysWith: { _, later in later })
}

private let losslessMimeTypes: Set<String> = [
    "audio/flac", "audio/x-flac", "audio/alac", "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave",
    "audio/aiff", "audio/x-aiff", "audio/ape", "audio/x-ape", "audio/wavpack", "audio/x-wavpack",
]

/// Whether a file of this MIME type keeps every bit of the recording.
private func isLosslessMimeType(_ mimeType: String?) -> Bool {
    guard let mimeType else { return false }
    return losslessMimeTypes.contains(mimeType.lowercased())
}
