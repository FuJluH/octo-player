import Foundation

// Library health: plain checks over the library's songs that find what is worth fixing in the
// files. Nothing is guessed from outside the library; the same songs always give the same
// report.

/// A tag the checks look for.
public enum HealthTag: CaseIterable, Sendable {
    case genre, year, albumArtist, trackNumber, cover
}

/// What the checks read from a song. Each app reads its own kind of song.
public struct HealthFields<T>: @unchecked Sendable {
    public var id: (T) -> String
    public var title: (T) -> String
    public var artist: (T) -> String?
    public var album: (T) -> String?
    public var albumId: (T) -> String?
    public var albumArtist: (T) -> String?
    public var genres: (T) -> [String]
    public var year: (T) -> Int?
    public var disc: (T) -> Int?
    public var track: (T) -> Int?
    public var seconds: (T) -> Int
    public var format: (T) -> String?
    public var lossless: (T) -> Bool
    /// Kilobits per second, bits per sample, samples per second.
    public var bitRate: (T) -> Int?
    public var bitDepth: (T) -> Int?
    public var sampleRate: (T) -> Int?
    /// Codes that name the recording: its ISRCs and its MusicBrainz recording id.
    public var isrcs: (T) -> [String]
    public var recordingId: (T) -> String?
    public var cover: (T) -> String?
    /// Every artist the song credits, and every album artist it names.
    public var artists: (T) -> [String]
    public var albumArtists: (T) -> [String]
    /// What names the release the song came out on, when the app keeps it.
    public var releaseId: (T) -> String?
    public var releaseGroupId: (T) -> String?
    public var barcode: (T) -> String?
    public var labels: (T) -> [String]
    /// Where the song is kept (a server, the phone). Copies in two places are not duplicates, and
    /// an album is never split across places.
    public var place: (T) -> String
    /// The tags this app can see at all. One it never keeps is never reported missing.
    public var seen: Set<HealthTag>

    public init(
        id: @escaping (T) -> String, title: @escaping (T) -> String, artist: @escaping (T) -> String?,
        album: @escaping (T) -> String?, albumId: @escaping (T) -> String?, albumArtist: @escaping (T) -> String?,
        genres: @escaping (T) -> [String], year: @escaping (T) -> Int?, disc: @escaping (T) -> Int?,
        track: @escaping (T) -> Int?, seconds: @escaping (T) -> Int, format: @escaping (T) -> String?,
        lossless: @escaping (T) -> Bool, bitRate: @escaping (T) -> Int?, bitDepth: @escaping (T) -> Int?,
        sampleRate: @escaping (T) -> Int?, isrcs: @escaping (T) -> [String], recordingId: @escaping (T) -> String?,
        cover: @escaping (T) -> String?, artists: ((T) -> [String])? = nil, albumArtists: ((T) -> [String])? = nil,
        releaseId: @escaping (T) -> String? = { _ in nil }, releaseGroupId: @escaping (T) -> String? = { _ in nil },
        barcode: @escaping (T) -> String? = { _ in nil }, labels: @escaping (T) -> [String] = { _ in [] },
        place: @escaping (T) -> String = { _ in "" }, seen: Set<HealthTag> = Set(HealthTag.allCases)
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.albumArtist = albumArtist
        self.genres = genres
        self.year = year
        self.disc = disc
        self.track = track
        self.seconds = seconds
        self.format = format
        self.lossless = lossless
        self.bitRate = bitRate
        self.bitDepth = bitDepth
        self.sampleRate = sampleRate
        self.isrcs = isrcs
        self.recordingId = recordingId
        self.cover = cover
        self.artists = artists ?? { song in artist(song).map { [$0] } ?? [] }
        self.albumArtists = albumArtists ?? { song in albumArtist(song).map { [$0] } ?? [] }
        self.releaseId = releaseId
        self.releaseGroupId = releaseGroupId
        self.barcode = barcode
        self.labels = labels
        self.place = place
        self.seen = seen
    }
}

/// Formats that are lossless; m4a and mp4 are lossless only with a known bit depth.
public func isLosslessKind(_ format: String?, bitDepth: Int? = nil) -> Bool {
    guard let kind = format?.lowercased() else { return false }
    if kind == "m4a" || kind == "mp4" { return (bitDepth ?? 0) > 0 }
    return ["flac", "alac", "wav", "wave", "aiff", "aif", "aifc", "pcm", "ape", "wv", "dsf", "dff", "tta"].contains(kind)
}

private func blank(_ text: String?) -> Bool { text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }

/// A server's songs, as a server lists them.
public let serverSongHealth = HealthFields<ServerSong>(
    id: \.id,
    title: \.title,
    artist: { $0.artist ?? $0.displayArtist },
    album: \.album,
    albumId: \.albumId,
    albumArtist: { song in blank(song.displayAlbumArtist) ? song.albumArtists.first?.name : song.displayAlbumArtist },
    genres: { song in song.genres.isEmpty ? (song.genre.flatMap { blank($0) ? nil : [$0] } ?? []) : song.genres },
    year: \.year,
    disc: \.discNumber,
    track: \.track,
    seconds: \.duration,
    format: { song in song.suffix.flatMap { blank($0) ? nil : $0.lowercased() } },
    lossless: { isLosslessKind($0.suffix, bitDepth: $0.bitDepth) },
    bitRate: \.bitRate,
    bitDepth: \.bitDepth,
    sampleRate: \.samplingRate,
    isrcs: \.isrc,
    recordingId: \.musicBrainzId,
    cover: \.coverArt,
    artists: { song in
        let names = song.artists.map(\.name).filter { !blank($0) }
        return names.isEmpty ? ((song.artist ?? song.displayArtist).map { [$0] } ?? []) : names
    },
    albumArtists: { song in
        let names = song.albumArtists.map(\.name).filter { !blank($0) }
        if !names.isEmpty { return names }
        let one = blank(song.displayAlbumArtist) ? song.albumArtists.first?.name : song.displayAlbumArtist
        return one.map { [$0] } ?? []
    })

/// What a server's album list says about one album's release.
public struct HealthAlbumFacts: Decodable, Sendable, Hashable {
    public var id: String
    public var musicBrainzId: String?
    public var labels: [String]

    enum CodingKeys: String, CodingKey { case id, musicBrainzId, recordLabels }
    private struct Label: Decodable { var name: String? }

    public init(id: String, musicBrainzId: String? = nil, labels: [String] = []) {
        self.id = id
        self.musicBrainzId = musicBrainzId
        self.labels = labels
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        musicBrainzId = c.string(.musicBrainzId)
        labels = ((try? c.decodeIfPresent([Label].self, forKey: .recordLabels)) ?? []).compactMap(\.name)
    }
}

/// A server's songs, with each album's release and record labels from the server's album list.
public func serverAlbumHealth(_ albums: [HealthAlbumFacts]) -> HealthFields<ServerSong> {
    var byId: [String: HealthAlbumFacts] = [:]
    for album in albums where byId[album.id] == nil { byId[album.id] = album }
    var fields = serverSongHealth
    fields.releaseId = { song in song.albumId.flatMap { byId[$0]?.musicBrainzId }.flatMap { blank($0) ? nil : $0 } }
    fields.labels = { song in song.albumId.flatMap { byId[$0]?.labels } ?? [] }
    return fields
}

/// Why copies were taken for one recording.
public enum DuplicateBasis: Sendable {
    /// Their tags name the same recording: an ISRC or a MusicBrainz id.
    case tags
    /// The same title and artist, in the same version, and lengths within a few seconds.
    case titleAndLength
}

/// Why the first copy of a set is the one to keep.
public enum BestReason: Sendable {
    case sound, tags, none
}

/// Copies of one recording, the best first.
public struct DuplicateGroup<T> {
    public var copies: [T]
    public var basis: DuplicateBasis
    public var bestReason: BestReason
    public var best: T { copies[0] }

    public init(copies: [T], basis: DuplicateBasis, bestReason: BestReason) {
        self.copies = copies
        self.basis = basis
        self.bestReason = bestReason
    }
}

/// One way the parts of a split album differ, with each part's value.
public enum AlbumDifference: Sendable {
    case title, albumArtist, year, other
}

public struct AlbumDifferenceValues: Equatable, Sendable {
    public var kind: AlbumDifference
    public var values: [String]
}

/// One album entry the server shows, and its songs in album order.
public struct AlbumPart<T> {
    public var albumId: String
    public var songs: [T]
}

/// Why parts of one name with different album artists are one album.
public enum SplitBasis: Sendable {
    case sharedArtist, sameRelease, sameReleaseGroup, sameBarcode, sameLabelAndYear
}

/// One reason, with what it rests on.
public struct SplitReason: Equatable, Sendable {
    public var basis: SplitBasis
    public var artist = ""
    public var other = ""
    public var song = ""
    public var value = ""

    public init(_ basis: SplitBasis, artist: String = "", other: String = "", song: String = "", value: String = "") {
        self.basis = basis
        self.artist = artist
        self.other = other
        self.song = song
        self.value = value
    }
}

/// An album the server shows as two or more, because its songs' tags do not agree. The first
/// part is the one the others join.
public struct SplitAlbum<T> {
    public var title: String
    public var artist: String
    public var parts: [AlbumPart<T>]
    public var differences: [AlbumDifferenceValues]
    public var reasons: [SplitReason] = []
}

/// What one check is about. The order is the order they are shown in.
public enum HealthCheck: String, CaseIterable, Sendable {
    case duplicates = "Duplicates"
    case splitAlbums = "SplitAlbums"
    case noLength = "NoLength"
    case noTrackNumber = "NoTrackNumber"
    case noAlbumArtist = "NoAlbumArtist"
    case noCover = "NoCover"
    case noYear = "NoYear"
    case noGenre = "NoGenre"

    public var tag: HealthTag? {
        switch self {
        case .noTrackNumber: .trackNumber
        case .noAlbumArtist: .albumArtist
        case .noCover: .cover
        case .noYear: .year
        case .noGenre: .genre
        default: nil
        }
    }
}

/// Everything the checks found.
public struct HealthReport<T> {
    /// How many songs were looked at.
    public var checked: Int
    public var duplicates: [DuplicateGroup<T>] = []
    public var splitAlbums: [SplitAlbum<T>] = []
    public var noLength: [T] = []
    /// Songs missing each tag, only the tags some song is missing.
    public var missing: [HealthTag: [T]] = [:]

    public init(checked: Int, duplicates: [DuplicateGroup<T>] = [], splitAlbums: [SplitAlbum<T>] = [], noLength: [T] = [],
                missing: [HealthTag: [T]] = [:]) {
        self.checked = checked
        self.duplicates = duplicates
        self.splitAlbums = splitAlbums
        self.noLength = noLength
        self.missing = missing
    }

    /// How many things a check found: sets of copies, albums, or songs.
    public func count(_ check: HealthCheck) -> Int {
        switch check {
        case .duplicates: duplicates.count
        case .splitAlbums: splitAlbums.count
        case .noLength: noLength.count
        default: check.tag.flatMap { missing[$0]?.count } ?? 0
        }
    }

    /// The checks that found something, in order.
    public var findings: [HealthCheck] { HealthCheck.allCases.filter { count($0) > 0 } }

    public var clean: Bool { findings.isEmpty }

    /// The songs a check is about, for a list.
    public func songs(_ check: HealthCheck) -> [T] {
        switch check {
        case .duplicates: duplicates.flatMap(\.copies)
        case .splitAlbums: splitAlbums.flatMap { $0.parts.flatMap(\.songs) }
        case .noLength: noLength
        default: check.tag.flatMap { missing[$0] } ?? []
        }
    }

    /// The report without some songs, as after they were removed from the library: a set left
    /// with one copy is no longer a duplicate.
    public func without(_ ids: Set<String>, fields: HealthFields<T>) -> HealthReport<T> {
        if ids.isEmpty { return self }
        let keep: (T) -> Bool = { !ids.contains(fields.id($0)) }
        var out = self
        out.duplicates = duplicates.compactMap { group in
            let left = group.copies.filter(keep)
            return left.count < 2 ? nil : DuplicateGroup(copies: left, basis: group.basis, bestReason: group.bestReason)
        }
        out.splitAlbums = splitAlbums.compactMap { album in
            let parts = album.parts.map { AlbumPart(albumId: $0.albumId, songs: $0.songs.filter(keep)) }.filter { !$0.songs.isEmpty }
            if parts.count < 2 { return nil }
            var changed = album
            changed.parts = parts
            return changed
        }
        out.noLength = noLength.filter(keep)
        out.missing = missing.mapValues { $0.filter(keep) }.filter { !$0.value.isEmpty }
        return out
    }
}

/// Lengths of copies of one recording may be this far apart, in seconds.
public let sameLengthSeconds = SongIdentity.LENGTH_TOLERANCE_SECONDS

/// A shared ISRC or MusicBrainz id counts only when the lengths are this close.
public let taggedLengthSeconds = 10

private let duplicateTitles = SongMatchOptions(lengthToleranceSeconds: sameLengthSeconds, extrasMustAgree: true)

/// Runs every check over the songs.
public func checkLibrary<T>(_ songs: [T], _ fields: HealthFields<T>) -> HealthReport<T> {
    HealthReport(
        checked: songs.count,
        duplicates: findDuplicates(songs, fields),
        splitAlbums: findSplitAlbums(songs, fields),
        noLength: songs.filter { fields.seconds($0) <= 0 },
        missing: findMissingTags(songs, fields))
}

/// Songs that are the same recording, in sets. A set's copies are all in one place. Songs whose
/// tags name one recording go together first; then songs by the same artist whose titles read
/// the same, version and all, whose albums name no different versions, and whose lengths are
/// within a few seconds.
public func findDuplicates<T>(_ songs: [T], _ fields: HealthFields<T>) -> [DuplicateGroup<T>] {
    let sets = UnionSets(songs.count)
    var byTag: [String: Int] = [:]
    var byTitle: [String: [Int]] = [:]
    var byTitleOrder: [String] = []
    let keys = matchKeys(songs, fields)
    var tagged = [Bool](repeating: false, count: songs.count)

    for (index, song) in songs.enumerated() {
        let place = fields.place(song)
        var codes = SongIdentity.isrcs(fields.isrcs(song)).sorted().map { "i:\($0)" }
        if let mbid = fields.recordingId(song)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !mbid.isEmpty {
            codes.append("m:\(mbid)")
        }
        for code in codes {
            let key = "\(place)\u{0}\(code)"
            if let first = byTag[key] {
                if lengthsClose(fields.seconds(songs[first]), fields.seconds(song), taggedLengthSeconds), sets.join(first, index) {
                    tagged[first] = true
                    tagged[index] = true
                }
            } else {
                byTag[key] = index
            }
        }
        let match = keys[index]
        // A title with nothing to read in it is never matched on its words.
        if let bar = match.firstIndex(of: "|"), !match[match.index(after: bar)...].isEmpty {
            let key = "\(place)\u{0}\(match)"
            if byTitle[key] == nil { byTitleOrder.append(key) }
            byTitle[key, default: []].append(index)
        }
    }

    var versionsAt = [Set<String>?](repeating: nil, count: songs.count)
    func albumVersionsOf(_ index: Int) -> Set<String> {
        if let known = versionsAt[index] { return known }
        let read = albumVersions(songs[index], fields)
        versionsAt[index] = read
        return read
    }

    for key in byTitleOrder {
        guard let bucket = byTitle[key], bucket.count >= 2 else { continue }
        for i in bucket.indices {
            let a = songs[bucket[i]]
            let refA = refOf(a, fields)
            for j in (i + 1)..<bucket.count {
                if sets.same(bucket[i], bucket[j]) { continue }
                let b = songs[bucket[j]]
                if !lengthsClose(fields.seconds(a), fields.seconds(b), sameLengthSeconds) { continue }
                if albumVersionsOf(bucket[i]) != albumVersionsOf(bucket[j]) { continue }
                if SongIdentity.same(refA, refOf(b, fields), options: duplicateTitles).isSame { _ = sets.join(bucket[i], bucket[j]) }
            }
        }
    }

    var groups: [Int: [Int]] = [:]
    var rootsInOrder: [Int] = []
    for index in songs.indices where sets.size(index) > 1 {
        let root = sets.root(index)
        if groups[root] == nil { rootsInOrder.append(root) }
        groups[root, default: []].append(index)
    }
    let better: (T, T) -> Bool = { a, b in
        let sa = soundOf(a, fields), sb = soundOf(b, fields)
        if sa != sb { return sa > sb }
        let ta = tagsOf(a, fields), tb = tagsOf(b, fields)
        if ta != tb { return ta > tb }
        return fields.id(a) < fields.id(b)
    }
    let found = rootsInOrder.map { root -> DuplicateGroup<T> in
        let members = groups[root] ?? []
        let copies = members.map { songs[$0] }.sorted(by: better)
        let basis: DuplicateBasis = members.contains { tagged[$0] } ? .tags : .titleAndLength
        return DuplicateGroup(copies: copies, basis: basis, bestReason: bestReason(copies, fields))
    }
    return found.sorted { a, b in
        let aa = plainKey(fields.artist(a.best)), ab = plainKey(fields.artist(b.best))
        if aa != ab { return aa < ab }
        let ta = plainKey(fields.title(a.best)), tb = plainKey(fields.title(b.best))
        if ta != tb { return ta < tb }
        return fields.id(a.best) < fields.id(b.best)
    }
}

/// The versions a song's album names beyond what its title says. Two songs of one title whose
/// albums name different versions are different recordings: "Let's Get Lost" on "Let's Get Lost
/// Remixes" is a remix tagged plainly, not a copy of the one on the studio album, however close
/// their lengths.
private func albumVersions<T>(_ song: T, _ fields: HealthFields<T>) -> Set<String> {
    guard let album = fields.album(song) else { return [] }
    let inTitle = VersionVariant.requested(fields.title(song), nil)
    return VersionVariant.inFolder(album, fields.artist(song)).subtracting(inTitle)
}

/// Each song's key for "this song in this version". Each artist and title pair is read once,
/// across every core.
private func matchKeys<T>(_ songs: [T], _ fields: HealthFields<T>) -> [String] {
    var pairs: [ArtistTitle: Int] = [:]
    var distinct: [ArtistTitle] = []
    let at = songs.map { song -> Int in
        let pair = ArtistTitle(artist: fields.artist(song), title: fields.title(song))
        if let index = pairs[pair] { return index }
        pairs[pair] = distinct.count
        distinct.append(pair)
        return distinct.count - 1
    }
    let read = KeySlots(distinct)
    DispatchQueue.concurrentPerform(iterations: distinct.count) { i in read.fill(i) }
    let keys = read.keys
    return at.map { keys[$0] }
}

private struct ArtistTitle: Hashable, Sendable {
    let artist: String?
    let title: String
}

/// One slot per artist and title pair; each slot is written by one worker only.
private final class KeySlots: @unchecked Sendable {
    private let pairs: [ArtistTitle]
    private let slots: UnsafeMutableBufferPointer<String>

    init(_ pairs: [ArtistTitle]) {
        self.pairs = pairs
        slots = .allocate(capacity: pairs.count)
        _ = slots.initialize(from: repeatElement("", count: pairs.count))
    }

    deinit {
        _ = slots.deinitialize()
        slots.deallocate()
    }

    func fill(_ i: Int) { slots[i] = SongIdentity.matchKey(pairs[i].artist, pairs[i].title) }

    var keys: [String] { Array(slots) }
}

private func refOf<T>(_ song: T, _ fields: HealthFields<T>) -> SongRef {
    let seconds = fields.seconds(song)
    return SongRef(title: fields.title(song), artist: fields.artist(song), seconds: seconds > 0 ? Double(seconds) : nil,
                   isrcs: fields.isrcs(song))
}

/// Within `tolerance` seconds, or a length unknown on either side.
private func lengthsClose(_ a: Int, _ b: Int, _ tolerance: Int) -> Bool { a <= 0 || b <= 0 || abs(a - b) <= tolerance }

/// How good a copy sounds, as one number that sorts: lossless first, then more bits per sample,
/// a higher sample rate, and a higher bit rate. The bit rate of two lossless copies of one depth
/// counts only when the depth is unknown.
public func soundOf<T>(_ song: T, _ fields: HealthFields<T>) -> Int64 {
    let lossless = fields.lossless(song)
    let depth = min(max(fields.bitDepth(song) ?? 0, 0), 63)
    let rate = min(max((fields.sampleRate(song) ?? 0) / 100, 0), 65_535)
    let bits = lossless && depth > 0 ? 0 : min(max(fields.bitRate(song) ?? 0, 0), 65_535)
    return (Int64(lossless ? 1 : 0) << 48) | (Int64(depth) << 40) | (Int64(rate) << 20) | Int64(bits)
}

/// How many of the tags the checks look for a song has.
public func tagsOf<T>(_ song: T, _ fields: HealthFields<T>) -> Int {
    [
        fields.genres(song).contains { !blank($0) },
        (fields.year(song) ?? 0) > 0,
        !blank(fields.albumArtist(song)),
        (fields.track(song) ?? 0) > 0,
        !blank(fields.cover(song)),
    ].filter { $0 }.count
}

private func bestReason<T>(_ copies: [T], _ fields: HealthFields<T>) -> BestReason {
    let best = copies[0], next = copies[1]
    if soundOf(best, fields) > soundOf(next, fields) { return .sound }
    if tagsOf(best, fields) > tagsOf(next, fields) { return .tags }
    return .none
}

/// What the split check reads of one album part.
private struct PartFacts {
    var id: String
    var size: Int
    var artist: String
    var artistKey: String
    /// Every artist the album artist names, by key, as written, in first-seen order.
    var albumArtists: [(key: String, name: String)]
    var albumArtistKeys: Set<String>
    /// Every artist the songs credit, by key, with one song of theirs.
    var credits: [String: String]
    var years: Set<Int>
    var releases: Set<String>
    var groups: Set<String>
    var barcodes: Set<String>
    var labels: [(key: String, name: String)]
}

/// Albums the server shows as more than one: one title, in one place, under two or more album
/// ids, with years that do not tell them apart. Parts by the same album artist belong together;
/// parts by different album artists only when something shows they are one release.
public func findSplitAlbums<T>(_ songs: [T], _ fields: HealthFields<T>) -> [SplitAlbum<T>] {
    var byAlbum: [String: [T]] = [:]
    var albumOrder: [String] = []
    for song in songs {
        guard let id = fields.albumId(song), !id.isEmpty else { continue }
        if byAlbum[id] == nil { albumOrder.append(id) }
        byAlbum[id, default: []].append(song)
    }
    var buckets: [String: [PartFacts]] = [:]
    var bucketOrder: [String] = []
    for id in albumOrder {
        guard let members = byAlbum[id], let first = members.first else { continue }
        let title = SongIdentity.key(fields.album(first))
        if title.isEmpty { continue }
        guard let facts = partFacts(id, members, fields) else { continue }
        let key = "\(fields.place(first))\u{0}\(title)"
        if buckets[key] == nil { bucketOrder.append(key) }
        buckets[key, default: []].append(facts)
    }
    var found: [SplitAlbum<T>] = []
    for bucket in bucketOrder {
        guard let parts = buckets[bucket], parts.count >= 2 else { continue }
        let title = String(bucket[bucket.index(after: bucket.firstIndex(of: "\u{0}")!)...])
        let sets = UnionSets(parts.count)
        var reasons: [(Int, SplitReason)] = []
        for i in parts.indices {
            for j in (i + 1)..<parts.count {
                let a = parts[i], b = parts[j]
                if !yearsAgree(a.years, b.years) { continue }
                if a.artistKey == b.artistKey {
                    _ = sets.join(i, j)
                    continue
                }
                guard let reason = sameRelease(a, b) ?? sharedArtist(a, b, title) else { continue }
                _ = sets.join(i, j)
                reasons.append((i, reason))
            }
        }
        var together: [Int: [Int]] = [:]
        var rootOrder: [Int] = []
        for index in parts.indices {
            let root = sets.root(index)
            if together[root] == nil { rootOrder.append(root) }
            together[root, default: []].append(index)
        }
        for root in rootOrder {
            guard let members = together[root], members.count > 1 else { continue }
            let bySize = members.sorted { x, y in parts[x].size != parts[y].size ? parts[x].size > parts[y].size : parts[x].id < parts[y].id }
            let artists = Set(members.map { parts[$0].artistKey })
            let lead = (artists.count > 1 ? bySize.first { i in artists.allSatisfy(parts[i].albumArtistKeys.contains) } : nil) ?? bySize[0]
            let ordered = ([lead] + bySize.filter { $0 != lead }).map { i in
                AlbumPart(albumId: parts[i].id, songs: (byAlbum[parts[i].id] ?? []).sorted(by: albumOrdering(fields)))
            }
            let leadSongs = ordered[0].songs
            var seenReasons: [SplitReason] = []
            for (index, reason) in reasons where sets.root(index) == root && !seenReasons.contains(reason) { seenReasons.append(reason) }
            found.append(SplitAlbum(
                title: fields.album(leadSongs[0]) ?? "",
                artist: albumArtistOf(leadSongs, fields),
                parts: ordered,
                differences: differencesOf(ordered, fields),
                reasons: seenReasons))
        }
    }
    return found.sorted { a, b in
        let aa = plainKey(a.artist), ab = plainKey(b.artist)
        if aa != ab { return aa < ab }
        let ta = plainKey(a.title), tb = plainKey(b.title)
        if ta != tb { return ta < tb }
        return a.parts[0].albumId < b.parts[0].albumId
    }
}

private func partFacts<T>(_ id: String, _ members: [T], _ fields: HealthFields<T>) -> PartFacts? {
    let artist = albumArtistOf(members, fields)
    let artistKey = SongIdentity.key(SongIdentity.primaryArtist(artist))
    if artistKey.isEmpty { return nil }
    var albumArtists: [(key: String, name: String)] = []
    var albumArtistKeys = Set<String>()
    var named: [String] = []
    for credit in members.flatMap(fields.albumArtists) where !blank(credit) && !named.contains(credit) { named.append(credit) }
    if named.isEmpty { named = [artist] }
    for credit in named {
        for name in namesIn(credit) where albumArtistKeys.insert(SongIdentity.key(name)).inserted {
            albumArtists.append((SongIdentity.key(name), name))
        }
    }
    var credits: [String: String] = [:]
    for song in members {
        for credit in fields.artists(song) {
            for name in namesIn(credit) where credits[SongIdentity.key(name)] == nil { credits[SongIdentity.key(name)] = fields.title(song) }
        }
    }
    func codes(_ of: (T) -> String?, _ clean: (String) -> String) -> Set<String> {
        Set(members.compactMap { of($0).map(clean) }.filter { !$0.isEmpty })
    }
    var labels: [(key: String, name: String)] = []
    for song in members {
        for label in fields.labels(song) {
            let key = SongIdentity.key(label)
            if !key.isEmpty, !labels.contains(where: { $0.key == key }) {
                labels.append((key, label.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }
    let trimLower: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    return PartFacts(
        id: id, size: members.count, artist: artist, artistKey: artistKey, albumArtists: albumArtists,
        albumArtistKeys: albumArtistKeys, credits: credits,
        years: Set(members.compactMap { fields.year($0).flatMap { $0 > 0 ? $0 : nil } }),
        releases: codes(fields.releaseId, trimLower), groups: codes(fields.releaseGroupId, trimLower),
        barcodes: codes(fields.barcode) { code in String(code.filter(\.isNumber).drop { $0 == "0" }) },
        labels: labels)
}

/// The artists a credit names, a guest in brackets left out.
private func namesIn(_ credit: String) -> [String] {
    SongIdentity.parseArtists(credit).names.filter { !SongIdentity.key($0).isEmpty }
}

/// Years that do not tell two parts apart: the same year, or none on one side.
private func yearsAgree(_ a: Set<Int>, _ b: Set<Int>) -> Bool { a.isEmpty || b.isEmpty || !a.isDisjoint(with: b) }

/// The same release by its codes, or by its label and year.
private func sameRelease(_ a: PartFacts, _ b: PartFacts) -> SplitReason? {
    if !a.releases.isDisjoint(with: b.releases) { return SplitReason(.sameRelease) }
    if !a.groups.isDisjoint(with: b.groups) { return SplitReason(.sameReleaseGroup) }
    if let code = a.barcodes.sorted().first(where: b.barcodes.contains) { return SplitReason(.sameBarcode, value: code) }
    guard let label = a.labels.first(where: { mine in b.labels.contains { $0.key == mine.key } }),
          let year = a.years.filter(b.years.contains).min()
    else { return nil }
    return SplitReason(.sameLabelAndYear, value: "\(label.name), \(year)")
}

/// One part's album artist credited on the other part: a song there by them, or else both album
/// artists naming them. Never for a title many artists use, or one that is an artist's own name.
private func sharedArtist(_ a: PartFacts, _ b: PartFacts, _ title: String) -> SplitReason? {
    if isCommonTitle(title) || a.albumArtistKeys.contains(title) || b.albumArtistKeys.contains(title) { return nil }
    var named: SplitReason?
    for (mine, theirs) in [(a, b), (b, a)] {
        for (key, name) in mine.albumArtists {
            if theirs.albumArtistKeys.contains(key) {
                if named == nil {
                    named = SplitReason(.sharedArtist, artist: name, other: mine.artistKey == key ? theirs.artist : mine.artist)
                }
                continue
            }
            if let song = theirs.credits[key] { return SplitReason(.sharedArtist, artist: name, other: theirs.artist, song: song) }
        }
    }
    return named
}

/// Album titles many artists use, by key: sharing one says nothing about being one album.
private let commonTitles: Set<String> = [
    "album", "thealbum", "untitled", "unknown", "unknownalbum", "single", "singles", "thesingles", "ep", "theep",
    "live", "unplugged", "acoustic", "demo", "demos", "remixes", "theremixes", "bsides", "rarities", "hits", "thehits",
    "collection", "thecollection", "essentials", "anthology", "mixtape", "soundtrack", "originalsoundtrack", "ost",
    "christmas", "christmasalbum", "achristmasalbum", "lovesongs", "covers", "instrumentals", "deluxe", "deluxeedition",
    "remastered", "nonalbumsingle", "nonalbumsingles", "greatest", "thebest",
]

private let commonTitleStarts = [
    "greatesthits", "thegreatesthits", "bestof", "thebestof", "theverybestof", "theessential", "essential",
    "liveat", "livein", "livefrom", "mtvunplugged", "unplugged",
]

private func isCommonTitle(_ title: String) -> Bool { commonTitles.contains(title) || commonTitleStarts.contains { title.hasPrefix($0) } }

/// The album artist most of an album's songs name, or their artist.
private func albumArtistOf<T>(_ songs: [T], _ fields: HealthFields<T>) -> String {
    let named = songs.compactMap { fields.albumArtist($0) }.filter { !blank($0) }
    let pool = named.isEmpty ? songs.compactMap { fields.artist($0) }.filter { !blank($0) } : named
    var counts: [String: Int] = [:]
    for name in pool { counts[name, default: 0] += 1 }
    return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key > b.key }?.key ?? ""
}

/// What the parts disagree on, as each part says it.
private func differencesOf<T>(_ parts: [AlbumPart<T>], _ fields: HealthFields<T>) -> [AlbumDifferenceValues] {
    var found: [AlbumDifferenceValues] = []
    func check(_ kind: AlbumDifference, _ of: ([T]) -> String) {
        let values = parts.map { of($0.songs) }
        if Set(values).count > 1 { found.append(AlbumDifferenceValues(kind: kind, values: values)) }
    }
    check(.title) { fields.album($0[0]) ?? "" }
    check(.albumArtist) { songs in
        Array(Set(songs.compactMap { fields.albumArtist($0) }.filter { !blank($0) })).sorted().joined(separator: ", ")
    }
    check(.year) { songs in
        Array(Set(songs.compactMap { fields.year($0).flatMap { $0 > 0 ? $0 : nil } })).sorted().map(String.init).joined(separator: ", ")
    }
    if found.isEmpty { found.append(AlbumDifferenceValues(kind: .other, values: [])) }
    return found
}

/// Songs missing each tag the app can see. A track number and an album artist matter only on an
/// album of two or more songs.
public func findMissingTags<T>(_ songs: [T], _ fields: HealthFields<T>) -> [HealthTag: [T]] {
    var albumSizes: [String: Int] = [:]
    for song in songs { if let id = fields.albumId(song) { albumSizes[id, default: 0] += 1 } }
    func onAlbum(_ song: T) -> Bool { (fields.albumId(song).flatMap { albumSizes[$0] } ?? 0) > 1 }
    var found: [HealthTag: [T]] = [:]
    let order = albumOrderingAcross(fields)
    for tag in HealthTag.allCases where fields.seen.contains(tag) {
        let missing = songs.filter { song in
            switch tag {
            case .genre: !fields.genres(song).contains { !blank($0) }
            case .year: (fields.year(song) ?? 0) <= 0
            case .albumArtist: onAlbum(song) && blank(fields.albumArtist(song))
            case .trackNumber: onAlbum(song) && (fields.track(song) ?? 0) <= 0
            case .cover: blank(fields.cover(song))
            }
        }
        if !missing.isEmpty { found[tag] = missing.sorted(by: order) }
    }
    return found
}

/// Songs of one album in its order: disc, track, then title.
private func albumOrdering<T>(_ fields: HealthFields<T>) -> (T, T) -> Bool {
    { a, b in
        let da = fields.disc(a) ?? 0, db = fields.disc(b) ?? 0
        if da != db { return da < db }
        let ta = fields.track(a).flatMap { $0 > 0 ? $0 : nil } ?? Int.max
        let tb = fields.track(b).flatMap { $0 > 0 ? $0 : nil } ?? Int.max
        if ta != tb { return ta < tb }
        let ka = plainKey(fields.title(a)), kb = plainKey(fields.title(b))
        if ka != kb { return ka < kb }
        return fields.id(a) < fields.id(b)
    }
}

/// Songs from many albums: by artist, then album, then album order.
private func albumOrderingAcross<T>(_ fields: HealthFields<T>) -> (T, T) -> Bool {
    let inAlbum = albumOrdering(fields)
    return { a, b in
        let aa = plainKey(fields.albumArtist(a) ?? fields.artist(a)), ab = plainKey(fields.albumArtist(b) ?? fields.artist(b))
        if aa != ab { return aa < ab }
        let la = plainKey(fields.album(a)), lb = plainKey(fields.album(b))
        if la != lb { return la < lb }
        let ia = fields.albumId(a) ?? "", ib = fields.albumId(b) ?? ""
        if ia != ib { return ia < ib }
        return inAlbum(a, b)
    }
}

private func plainKey(_ text: String?) -> String { (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

/// Sets of songs joined as they are found to belong together, by index.
private final class UnionSets {
    private var parent: [Int]
    private var sizes: [Int]

    init(_ count: Int) {
        parent = Array(0..<count)
        sizes = [Int](repeating: 1, count: count)
    }

    func root(_ i: Int) -> Int {
        var at = i
        while parent[at] != at {
            parent[at] = parent[parent[at]]
            at = parent[at]
        }
        return at
    }

    func same(_ a: Int, _ b: Int) -> Bool { root(a) == root(b) }

    func size(_ i: Int) -> Int { sizes[root(i)] }

    /// Joins the two sets; false when they were one already.
    func join(_ a: Int, _ b: Int) -> Bool {
        let x = root(a), y = root(b)
        if x == y { return false }
        if sizes[x] < sizes[y] {
            parent[x] = y
            sizes[y] += sizes[x]
        } else {
            parent[y] = x
            sizes[x] += sizes[y]
        }
        return true
    }
}
