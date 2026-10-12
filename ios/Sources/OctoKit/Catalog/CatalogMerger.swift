import Foundation

/// Everything one source has.
public struct SourceCatalog: Sendable {
    public var sourceId: String
    /// Whether the source is the phone's own music.
    public var onPhone: Bool
    public var tracks: [SourceTrack]
    public var albums: [SourceAlbum]
    public var artists: [SourceArtist]

    public init(sourceId: String, onPhone: Bool, tracks: [SourceTrack], albums: [SourceAlbum], artists: [SourceArtist]) {
        self.sourceId = sourceId
        self.onPhone = onPhone
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
    }
}

/// The library as the screens read it, and which library song each source copy became.
public struct MergedCatalog: Sendable {
    public var tracks: [LibraryTrack]
    public var albums: [LibraryAlbum]
    public var artists: [LibraryArtist]
    public var mergedIds: [String: String]
}

/// Two copies of a song count as the same one if their lengths differ by no more than this.
private let sameLengthMs: Int64 = 3_000

/// Merges the sources into one library, so something on the phone and on a server shows once.
///
/// Artists match by name, albums by album artist and title, and songs by title and length within
/// an album (track numbers are not needed). The first source to have something gives it its id,
/// so the phone goes first and its songs keep their ids. A merged song or album takes the best of
/// its copies, asked in source order: added is the earliest real time; year is the first copy's
/// original year, else its own year; genre is the first copy's; artist is the fullest credit;
/// track and disc numbers and the rating are the first copy's; explicit is the first copy that
/// says. Anything only one source has is passed through as it was, apart from its year, which is
/// its original year when it has one.
public func mergeCatalogs(_ sources: [SourceCatalog]) -> MergedCatalog {
    // Artists and albums match only across sources: two a source keeps apart stay apart.
    let artistBases = acrossSources(sources, items: { $0.artists }, id: { $0.id }, key: { matchKey($0.name) })
    let artistIdFor = artistBases.idFor
    let albumBases = acrossSources(sources, items: { $0.albums }, id: { $0.id },
                                   key: { matchKey($0.artist) + "|" + matchKey($0.title) })
    let albumIdFor = albumBases.idFor

    // Songs, matched within each merged album, in the order albums were first met.
    var inAlbum: [String: [MergingSong]] = [:]
    var albumOrder: [String] = []
    // Every song so far by title and artist, for the second chance below.
    var everywhere: [String: [MergingSong]] = [:]
    var mergedIds: [String: String] = [:]
    // Each copy's keys, read once, and once for copies tagged alike.
    var keys: [String: SongKeys] = [:]
    var tagged: [String: SongKeys] = [:]
    func keysOf(_ track: SourceTrack) -> SongKeys {
        if let known = keys[track.id] { return known }
        let tag = track.artist + "\u{0}" + track.title
        let found = tagged[tag] ?? SongIdentity.songKeys(track.artist, track.title)
        tagged[tag] = found
        keys[track.id] = found
        return found
    }
    for source in sources {
        // A song matches at most one copy from each source.
        var taken = Set<String>()
        let ordered = source.tracks.enumerated().sorted { a, b in
            a.element.albumOrder != b.element.albumOrder ? a.element.albumOrder < b.element.albumOrder : a.offset < b.offset
        }.map(\.element)
        for track in ordered {
            let albumId = albumIdFor[track.albumId] ?? track.albumId
            let trackKeys = keysOf(track)
            func fits(_ song: MergingSong) -> Bool {
                !taken.contains(song.id) && !song.sources.contains(source.sourceId)
                    && keysOf(song.base).title == trackKeys.title
                    && abs(song.base.durationMs - track.durationMs) <= sameLengthMs
            }
            // First within the matched album. Failing that, the same song by the same artist
            // anywhere: sources often file an album under another album artist or edition name.
            let match = inAlbum[albumId]?.first(where: fits) ?? everywhere[trackKeys.matchKey]?.first(where: fits)
            if let match {
                match.add(track, source)
                taken.insert(match.id)
                mergedIds[track.id] = match.id
            } else {
                let song = MergingSong(track, source, albumId: albumId, artistId: artistIdFor[track.artistId] ?? track.artistId)
                if inAlbum[albumId] == nil { albumOrder.append(albumId) }
                inAlbum[albumId, default: []].append(song)
                everywhere[trackKeys.matchKey, default: []].append(song)
                mergedIds[track.id] = song.id
            }
        }
    }

    // Album order: an album filled from more than one source is put in track number order when
    // every song has one; otherwise its songs keep the order they came in. Single-source albums
    // keep their own order.
    var tracks: [LibraryTrack] = []
    tracks.reserveCapacity(mergedIds.count)
    for albumId in albumOrder {
        let songs = inAlbum[albumId] ?? []
        let mixed = Set(songs.flatMap(\.sources)).count > 1
        if !mixed {
            tracks += songs.map { $0.toTrack($0.base.albumOrder) }
        } else if songs.allSatisfy({ $0.trackNo != nil }) {
            let sorted = songs.enumerated().sorted { a, b in
                let da = a.element.discNo ?? 1, db = b.element.discNo ?? 1
                if da != db { return da < db }
                let ta = a.element.trackNo ?? 0, tb = b.element.trackNo ?? 0
                if ta != tb { return ta < tb }
                return a.offset < b.offset
            }.map(\.element)
            tracks += sorted.enumerated().map { index, song in song.toTrack(index) }
        } else {
            tracks += songs.enumerated().map { index, song in song.toTrack(index) }
        }
    }
    var tracksByAlbum: [String: [LibraryTrack]] = [:]
    for track in tracks { tracksByAlbum[track.albumId, default: []].append(track) }

    // An album whose songs all turned out to be copies of songs in another album has nothing
    // left, and is left out.
    let albums: [LibraryAlbum] = albumBases.bases.compactMap { base in
        guard let albumTracks = tracksByAlbum[base.id] else { return nil }
        let extras = albumBases.extras[base.id] ?? []
        // Counts are worked out again only for albums whose songs changed.
        let recount = !extras.isEmpty || albumTracks.count != base.songCount
        return LibraryAlbum(
            id: base.id,
            sourceId: base.sourceId,
            nativeId: base.nativeId,
            title: base.title,
            searchKey: base.searchKey,
            sortKey: base.sortKey,
            artist: base.artist,
            artistId: artistIdFor[base.artistId] ?? base.artistId,
            year: base.year ?? extras.lazy.compactMap(\.year).first,
            songCount: recount ? albumTracks.count : base.songCount,
            durationMs: recount ? albumTracks.reduce(0) { $0 + $1.durationMs } : base.durationMs,
            addedAt: earliestAdded([base.addedAt] + extras.map(\.addedAt)),
            artwork: base.artwork ?? extras.lazy.compactMap(\.artwork).first,
            releaseTypes: base.releaseTypes.isEmpty ? (extras.first { !$0.releaseTypes.isEmpty }?.releaseTypes ?? "") : base.releaseTypes
        )
    }

    // Artists from a later source with nothing left of their own are left out too; the first
    // source's artists always stay as they were.
    let firstSource = sources.first?.sourceId
    var albumsBy: [String: Int] = [:]
    for album in albums { albumsBy[album.artistId, default: 0] += 1 }
    var songsBy: [String: Int] = [:]
    for track in tracks { songsBy[track.artistId, default: 0] += 1 }
    let artists: [LibraryArtist] = artistBases.bases.compactMap { base in
        let several = !(artistBases.extras[base.id] ?? []).isEmpty
        let later = base.sourceId != firstSource
        let albumCount = albumsBy[base.id] ?? 0
        let songCount = songsBy[base.id] ?? 0
        if later && albumCount == 0 && songCount == 0 { return nil }
        return LibraryArtist(
            id: base.id,
            sourceId: base.sourceId,
            name: base.name,
            searchKey: base.searchKey,
            sortKey: base.sortKey,
            albumCount: several || later ? albumCount : base.albumCount,
            songCount: several || later ? songCount : base.songCount,
            artwork: base.artwork
        )
    }

    return MergedCatalog(tracks: tracks, albums: albums, artists: artists, mergedIds: mergedIds)
}

/// Things matched across sources: the first copy of each (the base, whose id the library uses),
/// the other copies of it, and which base every copy belongs to.
private struct Matched<T> {
    var bases: [T]
    var extras: [String: [T]]
    var idFor: [String: String]
}

private func acrossSources<T>(_ sources: [SourceCatalog], items: (SourceCatalog) -> [T], id: (T) -> String,
                              key: (T) -> String) -> Matched<T> {
    var bases: [T] = []
    var extras: [String: [T]] = [:]
    var idFor: [String: String] = [:]
    // Bases from earlier sources, by key, that no copy from the current source has claimed yet.
    var earlier: [String: [T]] = [:]
    for source in sources {
        var added: [String: [T]] = [:]
        var addedOrder: [String] = []
        for item in items(source) {
            let k = key(item)
            if var queue = earlier[k], !queue.isEmpty {
                let base = queue.removeFirst()
                earlier[k] = queue
                idFor[id(item)] = id(base)
                extras[id(base), default: []].append(item)
            } else {
                bases.append(item)
                idFor[id(item)] = id(item)
                if added[k] == nil { addedOrder.append(k) }
                added[k, default: []].append(item)
            }
        }
        for k in addedOrder { earlier[k, default: []] += added[k] ?? [] }
    }
    return Matched(bases: bases, extras: extras, idFor: idFor)
}

/// One library song while its copies are gathered.
private final class MergingSong {
    let base: SourceTrack
    let albumId: String
    let artistId: String
    var id: String { base.id }
    var sources: [String]
    var onPhone: Bool
    var trackNo: Int?
    var discNo: Int?
    var year: Int?
    var originalYear: Int?
    var genre: String
    var rating: Int?
    var explicit: Bool?
    var addedAt: Int64
    var artist: String
    var credits: Int

    init(_ base: SourceTrack, _ source: SourceCatalog, albumId: String, artistId: String) {
        self.base = base
        self.albumId = albumId
        self.artistId = artistId
        sources = [source.sourceId]
        onPhone = source.onPhone
        trackNo = base.trackNo
        discNo = base.discNo
        year = base.year
        originalYear = base.originalYear
        genre = base.genre
        rating = base.rating.flatMap { (1...5).contains($0) ? $0 : nil }
        explicit = base.explicit
        addedAt = base.addedAt
        artist = base.artist
        credits = splitLines(base.artists).count
    }

    func add(_ copy: SourceTrack, _ source: SourceCatalog) {
        sources.append(source.sourceId)
        onPhone = onPhone || source.onPhone
        trackNo = trackNo ?? copy.trackNo
        discNo = discNo ?? copy.discNo
        year = year ?? copy.year
        originalYear = originalYear ?? copy.originalYear
        if genre.isEmpty { genre = copy.genre }
        rating = rating ?? copy.rating.flatMap { (1...5).contains($0) ? $0 : nil }
        explicit = explicit ?? copy.explicit
        addedAt = earliestAdded([addedAt, copy.addedAt])
        let copyCredits = splitLines(copy.artists).count
        if copyCredits > credits && !copy.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            artist = copy.artist
            credits = copyCredits
        }
    }

    func toTrack(_ order: Int) -> LibraryTrack {
        LibraryTrack(
            id: base.id,
            sourceId: base.sourceId,
            nativeId: base.nativeId,
            title: base.title,
            searchKey: base.searchKey,
            sortKey: base.sortKey,
            artist: artist,
            artistId: artistId,
            album: base.album,
            albumId: albumId,
            trackNo: trackNo,
            discNo: discNo,
            year: originalYear ?? year,
            durationMs: base.durationMs,
            addedAt: addedAt,
            mimeType: base.mimeType,
            sizeBytes: base.sizeBytes,
            artwork: base.artwork,
            uri: base.uri,
            albumOrder: order,
            relinkKey: base.relinkKey,
            genre: genre,
            onPhone: onPhone,
            rating: rating ?? 0,
            explicit: explicit
        )
    }
}

/// The earliest of some times added, leaving out unknown ones (0 or less).
public func earliestAdded(_ times: [Int64]) -> Int64 { times.filter { $0 > 0 }.min() ?? 0 }

private let bracketed = try! NSRegularExpression(pattern: #"\s*[(\[][^)\]]*[)\]]"#)

/// A name for matching across sources as a whole, such as an album or an artist: case, accents,
/// punctuation, spacing, lookalike letters and bracketed extras such as "(Deluxe)" are ignored,
/// and "&" reads as "and".
public func matchKey(_ name: String) -> String {
    let range = NSRange(name.startIndex..., in: name)
    return SongIdentity.key(bracketed.stringByReplacingMatches(in: name, range: range, withTemplate: " "))
}

/// A list kept as text, one value per line, and back.
public func joinLines(_ values: [String]?) -> String { (values ?? []).joined(separator: "\n") }

public func splitLines(_ text: String) -> [String] {
    text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}
