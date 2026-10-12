import Foundation

private let serverPrefix = "server"
private let unknownArtist = "Unknown artist"
private let unknownAlbum = "Unknown album"

/// The source a server's music is kept under: its host, and its port when that is not the usual
/// one for the address. Always made from the server's main address, so moving between home and
/// away keeps the same library.
public func serverSourceId(_ base: URL) -> String {
    let parts = URLComponents(url: base, resolvingAgainstBaseURL: false)
    let scheme = (parts?.scheme ?? base.scheme ?? "").lowercased()
    var host = (parts?.host ?? base.host ?? "").lowercased()
    if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
    let usual = scheme == "https" ? 443 : 80
    let port = parts?.port ?? base.port
    let shown = port == nil || port == usual ? "" : ":\(port!)"
    return "\(serverPrefix):\(host)\(shown)"
}

public func isServerSource(_ sourceId: String) -> Bool { sourceId.hasPrefix(serverPrefix + ":") }

/// What a server lists, as its source's rows.
public struct ServerCatalog: Sendable {
    public var tracks: [SourceTrack]
    public var albums: [SourceAlbum]
    public var artists: [SourceArtist]
}

/// Turns what a server lists into its source's rows, shaped like the phone's so the two merge: a
/// song's artist id is its album artist's, its keys come from the same functions, and times added
/// are in seconds.
public func buildServerCatalog(_ sourceId: String, _ library: ServerLibrary) -> ServerCatalog {
    func id(_ native: String) -> String { "\(sourceId):\(native)" }
    func art(_ coverId: String?, _ fallbackId: String? = nil) -> String? {
        guard let coverId, !coverId.isEmpty else { return nil }
        return ArtworkRef.server(sourceId: sourceId, coverId: coverId, fallbackId: fallbackId).encode()
    }

    // A library that changes while it is read can repeat a song across pages. A song the server
    // marks as outside the library is not a library song, so it is not kept.
    var seenSongs = Set<String>()
    let songs = library.songs.filter { !$0.isExternal && seenSongs.insert($0.id).inserted }

    // A song whose album was added after the album list was read still gets an album, made from
    // its songs.
    var listed: [String: ServerAlbum] = [:]
    var listedOrder: [String] = []
    for album in library.albums {
        if listed[album.id] == nil { listedOrder.append(album.id) }
        listed[album.id] = album
    }
    let groups = groupInOrder(songs, by: albumKey)
    var albumsByKey = listed
    var albumOrder = listedOrder
    for (key, group) in groups where listed[key] == nil {
        albumsByKey[key] = albumFromSongs(key, group)
        albumOrder.append(key)
    }
    // Each artist's MusicBrainz id, where the server knows it.
    var artistMusicIds: [String: String] = [:]
    for artist in library.artists { if let music = musicId(artist.musicBrainzId) { artistMusicIds[artist.id] = music } }

    // Each album's first song's own cover, drawn in place of the album's when the server answers
    // that with its stand-in picture.
    var firstSongCovers: [String: String?] = [:]
    for (key, group) in groups { firstSongCovers[key] = inAlbumOrder(group).first?.coverArt }

    var albumRows: [String: SourceAlbum] = [:]
    for key in albumOrder {
        guard let album = albumsByKey[key] else { continue }
        let title = blankOr(album.name, unknownAlbum)
        let artist = blankOr(album.artist, unknownArtist)
        let artistId = album.artistId.flatMap { $0.isEmpty ? nil : $0 } ?? "artist:\(searchKey(artist))"
        let years = albumYears(album)
        albumRows[key] = SourceAlbum(
            id: id(album.id),
            sourceId: sourceId,
            nativeId: album.id,
            title: title,
            searchKey: searchKey("\(title) \(artist)"),
            sortKey: sortKey(title),
            artist: artist,
            artistId: id(artistId),
            // The year it shows: the first edition's where known.
            year: years.original ?? years.year,
            songCount: album.songCount,
            durationMs: Int64(album.duration) * 1000,
            addedAt: epochSeconds(album.created) ?? 0,
            artwork: art(album.coverArt, firstSongCovers[album.id] ?? nil),
            releaseTypes: joinLines(album.releaseTypes.map(trimmed).filter { !$0.isEmpty })
        )
    }

    var tracks: [SourceTrack] = []
    for (key, group) in groups {
        guard let album = albumRows[key] else { continue }
        let listedAlbum = albumsByKey[key]
        let albumYear = listedAlbum.map(albumYears)
        for (index, song) in inAlbumOrder(group).enumerated() {
            let title = blankOr(song.title, "Untitled")
            let durationMs = Int64(song.duration) * 1000
            let year = positive(song.year) ?? albumYear?.year
            let genres = song.genres.isEmpty ? parseGenres([song.genre].compactMap { $0 }) : song.genres
            let disc = positive(song.discNumber)
            let trackNo = positive(song.track)
            let byline = [song.displayArtist, song.artist].compactMap { $0 }.first.flatMap { trimmed($0).isEmpty ? nil : $0 }
            tracks.append(SourceTrack(
                id: id(song.id),
                sourceId: sourceId,
                nativeId: song.id,
                title: title,
                searchKey: searchKey(title),
                sortKey: sortKey(title),
                artist: byline ?? album.artist,
                artistId: album.artistId,
                album: album.title,
                albumId: album.id,
                trackNo: trackNo,
                discNo: disc,
                year: year,
                durationMs: durationMs,
                addedAt: epochSeconds(song.created) ?? album.addedAt,
                mimeType: mimeFor(song.suffix) ?? song.contentType,
                sizeBytes: song.size,
                // The album's cover first, so an album's songs share one picture.
                artwork: album.artwork ?? art(song.coverArt),
                uri: nil,
                albumOrder: index,
                relinkKey: relinkKey(albumArtist: album.artist, album: album.title, disc: disc, track: trackNo, title: title,
                                     durationMs: durationMs),
                genre: genres.first ?? (song.genre.map(trimmed) ?? ""),
                bitrate: positive(song.bitRate).map { $0 * 1000 },
                sampleRate: positive(song.samplingRate),
                bitDepth: positive(song.bitDepth),
                playCount: song.playCount.map { Int($0) },
                lastPlayedAt: epochMs(song.played),
                starredAt: epochMs(song.starred),
                trackGain: finite(song.replayGain?.trackGain),
                albumGain: finite(song.replayGain?.albumGain),
                trackPeak: finite(song.replayGain?.trackPeak).flatMap { $0 > 0 ? $0 : nil },
                albumPeak: finite(song.replayGain?.albumPeak).flatMap { $0 > 0 ? $0 : nil },
                baseGain: finite(song.replayGain?.baseGain),
                fallbackGain: finite(song.replayGain?.fallbackGain),
                rating: song.userRating.map { min(max($0, 0), 5) },
                // The album's first-edition year, which cannot be after this one's.
                originalYear: albumYear?.original.flatMap { year == nil || $0 <= year! ? $0 : nil },
                genres: joinLines(genres),
                artists: joinLines(song.artists.map { trimmed($0.name) }.filter { !$0.isEmpty }),
                composer: blankNil(song.displayComposer),
                bpm: positive(song.bpm),
                comment: blankNil(song.comment),
                // The song's own mark only: an album is marked explicit when any one of its songs is.
                explicit: explicitOf(song.explicitStatus ?? ""),
                discTitle: blankNil(listedAlbum?.discTitles.first { $0.disc == (disc ?? 1) }?.title),
                mbRecordingId: musicId(song.musicBrainzId),
                mbAlbumId: musicId(listedAlbum?.musicBrainzId),
                mbArtistIds: joinLines(unique(song.artists.compactMap { artistMusicIds[$0.id] })),
                personal: song.octoPersonal
            ))
        }
    }

    // Artists are the album artists, named as the server's artist list names them.
    var listedArtists: [String: ServerArtist] = [:]
    for artist in library.artists { listedArtists[id(artist.id)] = artist }
    var songsBy: [String: Int] = [:]
    for track in tracks { songsBy[track.artistId, default: 0] += 1 }
    let albumList = albumOrder.compactMap { albumRows[$0] }
    let artists = groupInOrder(albumList, by: \.artistId).map { artistId, owned -> SourceArtist in
        let listedArtist = listedArtists[artistId]
        let name = listedArtist.flatMap { trimmed($0.name).isEmpty ? nil : $0.name } ?? owned[0].artist
        let newest = owned.enumerated().max { a, b in
            a.element.addedAt != b.element.addedAt ? a.element.addedAt < b.element.addedAt : a.offset > b.offset
        }!.element
        return SourceArtist(
            id: artistId,
            sourceId: sourceId,
            name: name,
            searchKey: searchKey(name),
            sortKey: sortKey(name),
            albumCount: owned.count,
            songCount: songsBy[artistId] ?? 0,
            artwork: newest.artwork ?? art(listedArtist?.coverArt)
        )
    }

    return ServerCatalog(tracks: tracks, albums: albumList, artists: artists)
}

private func albumKey(_ song: ServerSong) -> String {
    if let albumId = song.albumId, !albumId.isEmpty { return albumId }
    return "album:\(searchKey(song.album ?? ""))"
}

private func albumFromSongs(_ key: String, _ songs: [ServerSong]) -> ServerAlbum {
    let first = songs[0]
    let artist = [first.displayAlbumArtist, first.albumArtists.map { trimmed($0.name) }.joined(separator: ", "), first.artist]
        .compactMap { $0 }.first { !trimmed($0).isEmpty } ?? ""
    return ServerAlbum(
        id: key,
        name: first.album ?? "",
        artist: artist,
        coverArt: first.coverArt,
        songCount: songs.count,
        duration: songs.reduce(0) { $0 + $1.duration },
        year: songs.lazy.compactMap { positive($0.year) }.first,
        created: songs.compactMap(\.created).max()
    )
}

/// Disc, then track number, then title.
private func inAlbumOrder(_ songs: [ServerSong]) -> [ServerSong] {
    songs.enumerated().sorted { a, b in
        let da = positive(a.element.discNumber) ?? 1, db = positive(b.element.discNumber) ?? 1
        if da != db { return da < db }
        let ta = positive(a.element.track) ?? Int.max, tb = positive(b.element.track) ?? Int.max
        if ta != tb { return ta < tb }
        let sa = sortKey(a.element.title), sb = sortKey(b.element.title)
        if sa != sb { return sa < sb }
        return a.offset < b.offset
    }.map(\.element)
}

/// This edition's year and the first edition's, as an album gives them.
private struct AlbumYears {
    var year: Int?
    var original: Int?
}

private func albumYears(_ album: ServerAlbum) -> AlbumYears {
    let year = positive(album.year) ?? positive(album.releaseDate?.year)
    let original = positive(album.originalReleaseDate?.year)
    return AlbumYears(year: year, original: original.flatMap { year == nil || $0 <= year! ? $0 : nil })
}

/// Groups items by a key, groups in the order their first item came, items in their order.
func groupInOrder<T>(_ items: [T], by key: (T) -> String) -> [(String, [T])] {
    var groups: [String: [T]] = [:]
    var order: [String] = []
    for item in items {
        let k = key(item)
        if groups[k] == nil { order.append(k) }
        groups[k, default: []].append(item)
    }
    return order.map { ($0, groups[$0]!) }
}

func unique(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.filter { seen.insert($0).inserted }
}

private func blankOr(_ text: String, _ fallback: String) -> String { trimmed(text).isEmpty ? fallback : text }

private func blankNil(_ text: String?) -> String? {
    guard let text else { return nil }
    let clean = trimmed(text)
    return clean.isEmpty ? nil : clean
}

/// A MusicBrainz id when the text is one, in lower case.
private func musicId(_ text: String?) -> String? { musicIds([text].compactMap { $0 }).first }

/// Servers send 0 for a number they do not know.
func positive(_ value: Int?) -> Int? { value.flatMap { $0 > 0 ? $0 : nil } }

private func finite(_ value: Float?) -> Float? { value.flatMap { $0.isFinite ? $0 : nil } }

/// The kind of file, from its extension.
public func mimeFor(_ suffix: String?) -> String? {
    switch suffix?.lowercased() {
    case "flac": "audio/flac"
    case "mp3": "audio/mpeg"
    case "m4a", "m4b", "mp4", "alac": "audio/mp4"
    case "aac": "audio/aac"
    case "ogg", "oga", "opus": "audio/ogg"
    case "wav": "audio/wav"
    case "aif", "aiff": "audio/aiff"
    case "wv": "audio/x-wavpack"
    case "ape": "audio/x-ape"
    case "dsf": "audio/x-dsf"
    default: nil
    }
}
