import Foundation

// The phone's library health: the shared checks, read the phone's way.
//
// Copies of one recording are looked for among each source's own copies (a server's two files of a
// song), since the phone joins a song it holds with the server's copy on purpose and that is no
// problem. Everything else is checked on the library as the phone shows it. The phone keeps no
// ISRC, so copies are matched by their MusicBrainz recording, then their title, artist and length.

/// A file's kind from its MIME type, in the words a server's suffix uses: "audio/flac" is flac,
/// "audio/mpeg" mp3, "audio/mp4" m4a.
public func formatOf(_ mimeType: String?) -> String? {
    guard let mime = mimeType?.lowercased(), let slash = mime.firstIndex(of: "/") else { return nil }
    var kind = String(mime[mime.index(after: slash)...])
    if let semicolon = kind.firstIndex(of: ";") { kind = String(kind[..<semicolon]) }
    kind = kind.trimmingCharacters(in: .whitespaces)
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

private func nonBlank(_ text: String) -> String? { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text }

/// A source's copy of a song, as the checks read it.
public let sourceCopyHealth = HealthFields<SourceTrack>(
    id: \.id,
    title: \.title,
    artist: { nonBlank($0.artist) },
    album: { nonBlank($0.album) },
    albumId: \.albumId,
    albumArtist: { _ in nil },
    genres: { copy in
        let all = splitLines(copy.genres)
        return all.isEmpty ? [copy.genre].filter { nonBlank($0) != nil } : all
    },
    year: { $0.originalYear ?? $0.year },
    disc: \.discNo,
    track: \.trackNo,
    seconds: { Int($0.durationMs / 1_000) },
    format: { formatOf($0.mimeType) },
    lossless: { downloadIsLossless($0.mimeType) || isLosslessKind(formatOf($0.mimeType), bitDepth: $0.bitDepth) },
    bitRate: { downloadBitrate($0).map { $0 / 1_000 } },
    bitDepth: \.bitDepth,
    sampleRate: \.sampleRate,
    isrcs: { _ in [] },
    recordingId: \.mbRecordingId,
    cover: \.artwork,
    place: \.sourceId,
    seen: [.genre, .year, .trackNumber, .cover])

/// A source's copy as its server knows it: by its id there. The copies of one set are all in one
/// place, so that id tells them apart.
public let serverCopyHealth: HealthFields<SourceTrack> = {
    var fields = sourceCopyHealth
    fields.id = \.nativeId
    return fields
}()

/// The library's songs as the phone shows them. An album's artist is the album's own; the phone
/// keeps none per song. A source's copy of a song (by library song) adds every artist it credits
/// and the MusicBrainz release it came out on.
public func trackHealth(albumArtists: [String: String] = [:], copies: [String: SourceTrack] = [:]) -> HealthFields<LibraryTrack> {
    let artist: (LibraryTrack) -> String? = { nonBlank($0.artist) }
    return HealthFields<LibraryTrack>(
        id: \.id,
        title: \.title,
        artist: artist,
        album: { nonBlank($0.album) },
        albumId: \.albumId,
        albumArtist: { albumArtists[$0.albumId].flatMap(nonBlank) },
        genres: { [$0.genre].filter { nonBlank($0) != nil } },
        year: \.year,
        disc: \.discNo,
        track: \.trackNo,
        seconds: { Int($0.durationMs / 1_000) },
        format: { formatOf($0.mimeType) },
        lossless: { downloadIsLossless($0.mimeType) || isLosslessKind(formatOf($0.mimeType)) },
        bitRate: { _ in nil },
        bitDepth: { _ in nil },
        sampleRate: { _ in nil },
        isrcs: { _ in [] },
        recordingId: { _ in nil },
        cover: \.artwork,
        artists: { song in
            var names: [String] = []
            for name in [artist(song)].compactMap({ $0 }) + splitLines(copies[song.id]?.artists ?? "") where !names.contains(name) {
                names.append(name)
            }
            return names
        },
        releaseId: { copies[$0.id]?.mbAlbumId.flatMap(nonBlank) },
        releaseGroupId: { copies[$0.id]?.mbReleaseGroupId.flatMap(nonBlank) },
        seen: [.genre, .year, .trackNumber, .cover])
}

/// One line of a check's list: a heading over a set of copies or a split album, or a song with a
/// note under it.
public enum HealthLine: Equatable, Sendable {
    case heading(title: String, detail: String)
    case song(LibraryTrack, note: String?)
}

/// What the checks found, ready for the pages.
public struct PhoneHealth: @unchecked Sendable {
    public var report: HealthReport<LibraryTrack>
    /// Each set of copies' heading and summary, in the report's order.
    var duplicateWords: [(String, String)] = []
    /// How each copy in a set sounds, by library song.
    var quality: [String: String] = [:]
    /// Each set of copies as the source keeps them, in the report's order: the files a fix keeps
    /// and removes.
    public var copyGroups: [DuplicateGroup<SourceTrack>] = []
    /// Every library song and every source's copy, as checked.
    public var tracks: [LibraryTrack] = []
    public var copies: [SourceTrack] = []
    public var fields: HealthFields<LibraryTrack> = trackHealth()

    public init(report: HealthReport<LibraryTrack>) { self.report = report }

    /// A check's list: headings and songs.
    public func lines(_ check: HealthCheck) -> [HealthLine] {
        switch check {
        case .duplicates:
            return report.duplicates.enumerated().flatMap { index, group -> [HealthLine] in
                let words = duplicateWords.indices.contains(index) ? duplicateWords[index] : (group.heading(fields), group.summary(fields))
                return [.heading(title: words.0, detail: words.1)] + group.copies.map { track in
                    let note = [quality[track.id], nonBlank(track.album)].compactMap { $0 }.joined(separator: " • ")
                    return .song(track, note: note.isEmpty ? nil : note)
                }
            }
        case .splitAlbums:
            return report.splitAlbums.flatMap { album -> [HealthLine] in
                [.heading(title: album.heading, detail: album.summary)] + album.parts.flatMap { $0.songs.map { .song($0, note: nil) } }
            }
        default:
            return report.songs(check).map { .song($0, note: nil) }
        }
    }

    /// A check's songs, in the list's order, for playing from one of them.
    public func songs(_ check: HealthCheck) -> [LibraryTrack] {
        lines(check).compactMap { if case .song(let track, _) = $0 { track } else { nil } }
    }
}

/// Runs the checks: copies among each source's own, the rest on the library as shown.
public func phoneHealth(_ tracks: [LibraryTrack], albums: [LibraryAlbum], copies: [SourceTrack]) -> PhoneHealth {
    var byId: [String: LibraryTrack] = [:]
    for track in tracks where byId[track.id] == nil { byId[track.id] = track }
    var albumArtists: [String: String] = [:]
    for album in albums { albumArtists[album.id] = album.artist }
    var merged: [String: SourceTrack] = [:]
    for copy in copies where !copy.mergedId.isEmpty { merged[copy.mergedId] = copy }
    let fields = trackHealth(albumArtists: albumArtists, copies: merged)
    var groups: [DuplicateGroup<LibraryTrack>] = []
    var sourceGroups: [DuplicateGroup<SourceTrack>] = []
    var words: [(String, String)] = []
    var quality: [String: String] = [:]
    for group in findDuplicates(copies, sourceCopyHealth) {
        var mapped: [LibraryTrack] = []
        for copy in group.copies {
            guard let track = byId[copy.mergedId] else { continue }
            quality[track.id] = qualityText(copy, sourceCopyHealth)
            if !mapped.contains(where: { $0.id == track.id }) { mapped.append(track) }
        }
        if mapped.count < 2 { continue }
        groups.append(DuplicateGroup(copies: mapped, basis: group.basis, bestReason: group.bestReason))
        sourceGroups.append(group)
        words.append((group.heading(sourceCopyHealth), group.summary(sourceCopyHealth)))
    }
    let report = HealthReport(
        checked: tracks.count,
        duplicates: groups,
        splitAlbums: findSplitAlbums(tracks, fields),
        noLength: tracks.filter { fields.seconds($0) <= 0 },
        missing: findMissingTags(tracks, fields))
    var health = PhoneHealth(report: report)
    health.duplicateWords = words
    health.quality = quality
    health.copyGroups = sourceGroups
    health.tracks = tracks
    health.copies = copies
    health.fields = fields
    return health
}
