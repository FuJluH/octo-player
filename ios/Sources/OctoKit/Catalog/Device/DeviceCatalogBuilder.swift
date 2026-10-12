import Foundation

private let deviceUnknownArtist = "Unknown artist"
private let deviceUnknownAlbum = "Unknown album"
private let deviceVariousArtists = "Various Artists"

/// The phone's music as its source's rows.
public struct DeviceCatalog: Sendable {
    public var tracks: [SourceTrack]
    public var albums: [SourceAlbum]
    public var artists: [SourceArtist]

    public init(tracks: [SourceTrack], albums: [SourceAlbum], artists: [SourceArtist]) {
        self.tracks = tracks
        self.albums = albums
        self.artists = artists
    }
}

/// A leading track number in a file name: "04 Title", "04. Title", "04 - Title".
private let fileNumber = try! NSRegularExpression(
    pattern: #"^[ \t\n\x0B\f\r]*([0-9]{1,3})(?=[ \t\n\x0B\f\r]*[-._)]|[ \t\n\x0B\f\r])"#)

/// The text when it holds more than whitespace.
private func shownText(_ text: String?) -> String? {
    guard let text, !trimmed(text).isEmpty else { return nil }
    return text
}

/// Turns the phone's files into albums and artists.
///
/// Albums are grouped by name, not by the media library's album id, which can follow the folder
/// when a file has no album-artist tag and so split one album kept in two folders. A same-named
/// group is only split apart when every file in it says which release it belongs to (a MusicBrainz
/// id) or who the album is by (an album artist); a partly tagged group stays together.
public func buildDeviceCatalog(_ rows: [DeviceRow]) -> DeviceCatalog {
    var groups: [(nameKey: String, splitKey: String, group: [DeviceRow])] = []
    for (nameKey, cluster) in groupInOrder(rows, by: { searchKey(deviceAlbumName($0)) }) {
        for (splitKey, group) in splitCluster(cluster) { groups.append((nameKey, splitKey, group)) }
    }

    var tracks: [SourceTrack] = []
    var albums: [SourceAlbum] = []
    let genreNames = genreSpellings(rows)
    func spelled(_ genre: String) -> String { genreNames[genreKey(genre)] ?? genre }

    for (nameKey, splitKey, group) in groups {
        let nativeId = stableId("\(nameKey)|\(splitKey)")
        let albumId = "\(deviceSource):album:\(nativeId)"
        let title = mostCommon(group.map(deviceAlbumName))
        let artist = deviceAlbumArtist(group)
        let artistId = deviceArtistId(artist)
        let ordered = inDeviceAlbumOrder(group)
        let artwork = ArtworkRef.device(key: "album:\(albumId)", uri: ordered.first?.row.uri ?? "").encode()

        for (index, entry) in ordered.enumerated() {
            let row = entry.row
            let number = entry.number
            let trackTitle = shownText(row.title) ?? untitled(row.fileName)
            let tags = row.tags
            var genres: [String] = []
            for genre in row.genres.map(spelled) where !genres.contains(genre) { genres.append(genre) }
            tracks.append(SourceTrack(
                id: "\(deviceSource):\(row.id)",
                sourceId: deviceSource,
                nativeId: String(row.id),
                title: trackTitle,
                searchKey: searchKey(trackTitle),
                sortKey: sortKey(shownText(tags.sortTitle) ?? trackTitle),
                artist: shownText(row.artist) ?? artist,
                artistId: artistId,
                album: title,
                albumId: albumId,
                trackNo: number,
                discNo: row.disc,
                year: row.year,
                durationMs: row.durationMs,
                addedAt: row.addedAtSeconds,
                mimeType: row.mimeType,
                sizeBytes: row.sizeBytes,
                artwork: artwork,
                uri: row.uri,
                albumOrder: index,
                relinkKey: relinkKey(albumArtist: artist, album: title, disc: row.disc, track: number, title: trackTitle,
                                     durationMs: row.durationMs),
                genre: row.genres.first.map(spelled) ?? "",
                trackGain: tags.trackGain,
                albumGain: tags.albumGain,
                trackPeak: tags.trackPeak,
                albumPeak: tags.albumPeak,
                originalYear: tags.originalYear,
                genres: joinLines(genres),
                artists: joinLines(tags.artists),
                composer: tags.composer,
                bpm: tags.bpm,
                comment: tags.comment,
                explicit: tags.explicit,
                discTitle: tags.discTitle,
                mbRecordingId: tags.mbRecordingId,
                mbAlbumId: row.mbAlbumId,
                mbReleaseGroupId: tags.mbReleaseGroupId,
                mbArtistIds: joinLines(tags.mbArtistIds)
            ))
        }

        albums.append(SourceAlbum(
            id: albumId,
            sourceId: deviceSource,
            nativeId: nativeId,
            title: title,
            searchKey: searchKey("\(title) \(artist)"),
            sortKey: sortKey(group.lazy.compactMap { shownText($0.tags.sortAlbum) }.first ?? title),
            artist: artist,
            artistId: artistId,
            // The year it shows: the original release year where known.
            year: group.compactMap { $0.tags.originalYear ?? $0.year }.max(),
            songCount: group.count,
            durationMs: group.reduce(0) { $0 + $1.durationMs },
            addedAt: group.map(\.addedAtSeconds).max() ?? 0,
            artwork: artwork
        ))
    }

    // How each album artist is filed, where a file says ("Beatles, The"). A later album's word wins.
    var artistSorts: [String: String] = [:]
    for (_, _, group) in groups {
        if let sort = group.lazy.compactMap({ shownText($0.tags.sortAlbumArtist) }).first {
            artistSorts[deviceArtistId(deviceAlbumArtist(group))] = sort
        }
    }

    let artists = groupInOrder(albums, by: \.artistId).map { id, owned in
        let name = mostCommon(owned.map(\.artist))
        return SourceArtist(
            id: id,
            sourceId: deviceSource,
            name: name,
            searchKey: searchKey(name),
            sortKey: sortKey(artistSorts[id] ?? name),
            albumCount: owned.count,
            songCount: owned.reduce(0) { $0 + $1.songCount },
            artwork: newestAlbum(owned)?.artwork
        )
    }

    return DeviceCatalog(tracks: tracks, albums: albums, artists: artists)
}

/// A file's name without its extension, or "Untitled" when that is blank.
private func untitled(_ fileName: String) -> String {
    let base = fileName.lastIndex(of: ".").map { String(fileName[..<$0]) } ?? fileName
    return trimmed(base).isEmpty ? "Untitled" : base
}

/// The album a file belongs to by name; with no album tag, its folder's name.
private func deviceAlbumName(_ row: DeviceRow) -> String {
    if let album = shownText(row.album) { return album }
    if let folder = row.folder {
        var path = Substring(folder)
        while path.last == "/" { path = path.dropLast() }
        let last = path.lastIndex(of: "/").map { String(path[path.index(after: $0)...]) } ?? String(path)
        if let name = shownText(last) { return name }
    }
    return deviceUnknownAlbum
}

/// Splits one same-named group only when every file in it can say which album it is. Otherwise
/// the whole group is one album.
private func splitCluster(_ cluster: [DeviceRow]) -> [(String, [DeviceRow])] {
    if cluster.allSatisfy({ shownText($0.mbAlbumId) != nil }) {
        return groupInOrder(cluster) { "mb:" + ($0.mbAlbumId ?? "").lowercased() }
    }
    if cluster.allSatisfy({ shownText($0.albumArtist) != nil }) {
        return groupInOrder(cluster) { "by:" + searchKey($0.albumArtist ?? "") }
    }
    return [("", cluster)]
}

/// Who the album is by: its album-artist tag, "Various Artists" for a compilation, otherwise
/// whoever appears on most of its tracks.
private func deviceAlbumArtist(_ group: [DeviceRow]) -> String {
    let tagged = group.compactMap { shownText($0.albumArtist) }
    if !tagged.isEmpty { return mostCommon(tagged) }
    if group.contains(where: \.compilation) { return deviceVariousArtists }
    let credited = group.compactMap { shownText($0.artist) }
    return credited.isEmpty ? deviceUnknownArtist : mostCommon(credited)
}

/// One spelling per genre across the library, the most common one, so "Hip Hop", "hip-hop" and
/// "Hip-Hop/Rap" are the same genre.
private func genreSpellings(_ rows: [DeviceRow]) -> [String: String] {
    var spellings: [String: String] = [:]
    for (key, names) in groupInOrder(rows.flatMap(\.genres), by: genreKey) { spellings[key] = mostCommon(names) }
    return spellings
}

private func deviceArtistId(_ name: String) -> String { "\(deviceSource):artist:\(searchKey(name))" }

/// Orders an album's files: disc, then track number, then file name. Where the tags have no track
/// numbers, numbers at the start of the file names are used, but only when every file has one and
/// no two are the same; otherwise a name like "50 Cent - In Da Club" would read as track 50.
private func inDeviceAlbumOrder(_ group: [DeviceRow]) -> [(row: DeviceRow, number: Int?)] {
    let fromNames: [Int?] = group.map { row in
        let range = NSRange(row.fileName.startIndex..., in: row.fileName)
        guard let match = fileNumber.firstMatch(in: row.fileName, range: range),
              let digits = Range(match.range(at: 1), in: row.fileName) else { return nil }
        return Int(row.fileName[digits])
    }
    let namesUsable = group.count > 1 && !fromNames.contains(where: { $0 == nil }) && Set(fromNames).count == group.count
    let numbered = group.enumerated().map { index, row in
        (row: row, number: row.track ?? (namesUsable ? fromNames[index] : nil), place: index, name: Array(row.fileName.lowercased().utf16))
    }
    return numbered.sorted { a, b in
        let discA = a.row.disc ?? 1, discB = b.row.disc ?? 1
        if discA != discB { return discA < discB }
        let numberA = a.number ?? Int.max, numberB = b.number ?? Int.max
        if numberA != numberB { return numberA < numberB }
        if a.name != b.name { return a.name.lexicographicallyPrecedes(b.name) }
        return a.place < b.place
    }.map { (row: $0.row, number: $0.number) }
}

/// The value seen most often; on a tie the longer one, then the one seen first.
private func mostCommon(_ values: [String]) -> String {
    var best: (value: String, count: Int)?
    for (value, same) in groupInOrder(values, by: { $0 }) {
        guard let current = best else {
            best = (value, same.count)
            continue
        }
        if same.count > current.count || (same.count == current.count && value.utf16.count > current.value.utf16.count) {
            best = (value, same.count)
        }
    }
    return best?.value ?? ""
}

/// The most recently added album, the first one on a tie.
private func newestAlbum(_ albums: [SourceAlbum]) -> SourceAlbum? {
    var newest: SourceAlbum?
    for album in albums {
        if let current = newest, album.addedAt <= current.addedAt { continue }
        newest = album
    }
    return newest
}

/// A short id that stays the same for the same input across scans: the first 8 bytes of its SHA-1,
/// in hex.
private func stableId(_ text: String) -> String {
    Hashes.hex(Hashes.sha1(Array(text.utf8)).prefix(8))
}
