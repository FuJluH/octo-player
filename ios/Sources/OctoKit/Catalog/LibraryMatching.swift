import Foundation

/// What one song from the server is to the app: a song already in the library, or one found online.
public enum Resolved: Sendable, Hashable {
    case inLibrary(trackId: String)
    case found(OnlineSong)

    /// The id the app knows it by: the library song's, or the find's.
    public var id: String {
        switch self {
        case .inLibrary(let trackId): trackId
        case .found(let song): song.id
        }
    }
}

/// A find already downloaded into the library is the library song it became, while the library
/// still has it, so a list built from then on shows it once, as the library song.
public func asAdopted(_ resolved: Resolved, library: Set<String>) -> Resolved {
    if case .found(let song) = resolved, library.contains(song.adoptedId) { return .inLibrary(trackId: song.adoptedId) }
    return resolved
}

/// The same song by the same artist, and the same kind of recording. Lengths only count when both
/// are known.
public func sameSong(_ title: String, _ artist: String, _ lengthMs: Int64, _ track: LibraryTrack) -> Bool {
    sameSong(title, artist, lengthMs, track.title, track.artist, track.durationMs)
}

/// Which source each resolved song came from: a server song's `octoSuggestedBy` paired with the id
/// it became. A song that resolved to nothing, or carries no source, is left out.
public func suggestionsOf(_ ids: [String?], _ songs: [Song]) -> [String: String] {
    var found: [String: String] = [:]
    for (id, song) in zip(ids, songs) {
        guard let id, let by = song.octoSuggestedBy.map(trimmed), !by.isEmpty else { continue }
        found[id] = by
    }
    return found
}

extension Song {
    /// This song, found online, as the app keeps it.
    public func toFind(sourceId: String, now: Int64) -> OnlineSong {
        OnlineSong(
            id: findId(id),
            sourceId: sourceId,
            nativeId: id,
            title: title,
            artist: artist ?? "",
            album: album ?? "",
            albumId: albumId.flatMap { $0.isEmpty ? nil : $0 },
            artistId: artistId.flatMap { $0.isEmpty ? nil : $0 },
            durationMs: knownLengthMs(self),
            coverId: coverArt.flatMap { $0.isEmpty ? nil : $0 },
            mimeType: mimeTypeOf(contentType: contentType, suffix: suffix),
            bitrate: bitRate.flatMap { $0 > 0 ? $0 : nil },
            seenAt: now,
            explicit: explicitOf(explicitStatus ?? "")
        )
    }
}

extension OnlineSong {
    /// A found song shaped like a library song, so every list, menu and the player can show it. It
    /// has no album or artist in the library to open.
    public var asTrack: LibraryTrack {
        LibraryTrack(
            id: id, sourceId: sourceId, nativeId: nativeId, title: title, searchKey: searchKey(title), sortKey: sortKey(title),
            artist: artist, artistId: "", album: album, albumId: "", trackNo: nil, discNo: nil, year: nil,
            durationMs: durationMs, addedAt: 0, mimeType: mimeType, sizeBytes: nil, artwork: onlineArtwork(sourceId, coverId),
            uri: nil, onPhone: false, explicit: explicit
        )
    }

    /// The find as the downloads follower reads it.
    public var asFindSong: FindSong {
        FindSong(id: nativeId, sourceId: sourceId, title: title, artist: artist, album: album, albumId: albumId,
                 durationMs: durationMs, requestedAt: requestedAt, adoptedId: adoptedId)
    }
}

/// Sorts out what the server sent. A song the library has from the server is that library song,
/// unless the server marks it as outside the library. A song with the same title and artist as a
/// library song is that song too, so a copy on the phone plays instead of a stream. Anything else
/// was found online.
public func resolveSongs(_ songs: [Song], sourceId: String, links: [String: String], library: [LibraryTrack],
                         now: Int64) -> [Resolved] {
    let byTitle = TitleIndex(library, title: \.title, artist: \.artist)
    return songs.map { song in
        if !song.isExternal, let linked = links[song.id] { return .inLibrary(trackId: linked) }
        let length = knownLengthMs(song)
        let artist = song.artist ?? ""
        if let same = byTitle.candidates(song.title, artist).first(where: { sameSong(song.title, artist, length, $0) }) {
            return .inLibrary(trackId: same.id)
        }
        return .found(song.toFind(sourceId: sourceId, now: now))
    }
}
