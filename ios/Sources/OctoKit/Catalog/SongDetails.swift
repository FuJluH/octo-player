import Foundation

/// What the library knows about a song beyond what its lists show, gathered from every copy of
/// it: the song info sheet and ListenBrainz read this.
public struct SongDetails: Sendable, Equatable {
    /// This edition's year, and the year the song first came out.
    public var year: Int?
    public var originalYear: Int?
    public var genres: [String]
    public var artists: [String]
    public var composer: String?
    public var bpm: Int?
    public var comment: String?
    public var explicit: Bool?
    public var discTitle: String?
    public var mbRecordingId: String?
    public var mbAlbumId: String?
    public var mbReleaseGroupId: String?
    public var mbArtistIds: [String]

    public init(year: Int? = nil, originalYear: Int? = nil, genres: [String] = [], artists: [String] = [], composer: String? = nil,
                bpm: Int? = nil, comment: String? = nil, explicit: Bool? = nil, discTitle: String? = nil,
                mbRecordingId: String? = nil, mbAlbumId: String? = nil, mbReleaseGroupId: String? = nil, mbArtistIds: [String] = []) {
        self.year = year
        self.originalYear = originalYear
        self.genres = genres
        self.artists = artists
        self.composer = composer
        self.bpm = bpm
        self.comment = comment
        self.explicit = explicit
        self.discTitle = discTitle
        self.mbRecordingId = mbRecordingId
        self.mbAlbumId = mbAlbumId
        self.mbReleaseGroupId = mbReleaseGroupId
        self.mbArtistIds = mbArtistIds
    }
}

/// The details of a song from its copies, by the merge rules: the phone's copy is asked first,
/// then each server's; each detail comes from the first copy that has it, genres are every copy's
/// together, and the artists are the fullest credit any copy gives.
public func songDetails(_ copies: [SourceTrack]) -> SongDetails {
    let ordered = copies.enumerated().sorted { a, b in
        let ka = a.element.sourceId == deviceSource ? "" : a.element.sourceId
        let kb = b.element.sourceId == deviceSource ? "" : b.element.sourceId
        return ka != kb ? ka < kb : a.offset < b.offset
    }.map(\.element)
    func first<T>(_ pick: (SourceTrack) -> T?) -> T? { ordered.lazy.compactMap(pick).first }
    func text(_ value: String?) -> String? { value.flatMap { trimmed($0).isEmpty ? nil : $0 } }
    return SongDetails(
        year: first { $0.year },
        originalYear: first { $0.originalYear },
        genres: allGenres(ordered.map { copy in
            let lines = splitLines(copy.genres)
            return lines.isEmpty ? [copy.genre] : lines
        }),
        artists: fullestCredit(ordered.map { splitLines($0.artists) }),
        composer: first { text($0.composer) },
        bpm: first { $0.bpm.flatMap { $0 > 0 ? $0 : nil } },
        comment: first { text($0.comment) },
        explicit: first { $0.explicit },
        discTitle: first { text($0.discTitle) },
        mbRecordingId: first { text($0.mbRecordingId) },
        mbAlbumId: first { text($0.mbAlbumId) },
        mbReleaseGroupId: first { text($0.mbReleaseGroupId) },
        mbArtistIds: ordered.map { splitLines($0.mbArtistIds) }.first { !$0.isEmpty } ?? []
    )
}

/// Every genre in these lists, in order, each once: spellings of one genre count as one, and the
/// first spelling stays.
public func allGenres(_ lists: [[String]]) -> [String] {
    var seen = Set<String>()
    return lists.flatMap { $0 }.map(trimmed).filter { !$0.isEmpty }.filter { seen.insert(genreKey($0)).inserted }
}

/// The credit naming the most artists; the first of equals.
public func fullestCredit(_ lists: [[String]]) -> [String] {
    lists.reduce([String]()) { best, next in next.count > best.count ? next : best }
}
