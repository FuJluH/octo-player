import Foundation

extension ReplayGain {
    /// The loudness values a source keeps for a song.
    public init(trackGain: Double?, trackPeak: Double?, albumGain: Double?, albumPeak: Double?) {
        self.trackGain = trackGain
        self.trackPeak = trackPeak
        self.albumGain = albumGain
        self.albumPeak = albumPeak
    }
}

/// Each song's place in its album among the songs of a list, by disc then track, so an album
/// played in order is told apart from songs of one album that only happen to sit together.
/// Nil for a song with no album or no track number.
public func albumOrders(_ songs: [Song]) -> [Int?] {
    var byAlbum: [String: [(disc: Int, track: Int)]] = [:]
    for song in songs {
        guard let album = song.albumId, let track = song.track else { continue }
        byAlbum[album, default: []].append((song.discNumber ?? 1, track))
    }
    var ranks: [String: [Int: Int]] = [:]
    for (album, places) in byAlbum {
        let keys = Set(places.map { $0.disc * 10_000 + $0.track }).sorted()
        var rank: [Int: Int] = [:]
        for (index, key) in keys.enumerated() { rank[key] = index }
        ranks[album] = rank
    }
    return songs.map { song in
        guard let album = song.albumId, let track = song.track else { return nil }
        return ranks[album]?[(song.discNumber ?? 1) * 10_000 + track]
    }
}

/// A server's song as the queue holds it: it streams from its server under a private address,
/// signed only as it opens. `quality` decides what the player will receive, for the badge.
public func queueItem(_ song: Song, sourceId: String?, quality: StreamQuality, source: QueueSource = .none,
                      albumOrder: Int? = nil) -> QueueItem {
    let bitrate = song.bitRate.flatMap { $0 > 0 ? $0 * 1_000 : nil }
    let mime = song.contentType?.isEmpty == false ? song.contentType : nil
    // A song found online has no file of its own on the server to tell apart.
    let ref = StreamRef(sourceId: sourceId, serverId: song.id, mimeType: mime, bitrate: bitrate,
                        size: song.isExternal ? nil : song.size)
    let loudness = song.replayGain.flatMap {
        ReplayGainTags.stored(trackGain: $0.trackGain, trackPeak: $0.trackPeak, albumGain: $0.albumGain, albumPeak: $0.albumPeak)
    }
    return QueueItem(
        trackId: song.id, uri: streamUri(ref), title: song.title, artist: song.byline, album: song.album ?? "",
        durationMs: max(0, song.duration) * 1_000, mimeType: phoneRequest(mime, bitrate, quality).mimeType(mime),
        fileMime: mime, trackNo: song.track, discNo: song.discNumber, year: song.year, artwork: song.coverArt,
        albumId: song.albumId, artistId: song.artistId, albumOrder: albumOrder,
        explicit: song.explicitStatus?.lowercased() == "explicit", genre: song.genre, loudness: loudness,
        source: source, isFind: song.isExternal, song: song)
}

/// A list of server songs as queue items, each knowing its place in its album.
public func queueItems(_ songs: [Song], sourceId: String?, quality: StreamQuality, source: QueueSource = .none) -> [QueueItem] {
    zip(songs, albumOrders(songs)).map { queueItem($0, sourceId: sourceId, quality: quality, source: source, albumOrder: $1) }
}

/// The song a queue item shows, made from the item when it carries none.
public func songOf(_ item: QueueItem) -> Song {
    if var song = item.song {
        if item.durationMs > 0, item.durationMs / 1_000 != song.duration { song.duration = (item.durationMs + 500) / 1_000 }
        return song
    }
    var song = Song(id: item.trackId, title: item.title, artist: item.artist, album: item.album.isEmpty ? nil : item.album,
                    albumId: item.albumId, duration: (item.durationMs + 500) / 1_000, coverArt: item.artwork)
    song.artistId = item.artistId
    song.track = item.trackNo
    song.discNumber = item.discNo
    song.year = item.year
    song.genre = item.genre
    song.isExternal = item.isFind
    song.contentType = item.fileMime
    return song
}
