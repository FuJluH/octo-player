import Foundation

// The library as the screens read it. Ids are "<source>:<native id>", so one library holds every
// source: the phone's songs and the server in use.

/// A library song, merged from every copy the sources have.
public struct LibraryTrack: TableRow, Hashable, Identifiable {
    public var id: String
    public var sourceId: String
    public var nativeId: String
    public var title: String
    public var searchKey: String
    public var sortKey: String
    public var artist: String
    public var artistId: String
    public var album: String
    public var albumId: String
    public var trackNo: Int?
    public var discNo: Int?
    public var year: Int?
    public var durationMs: Int64
    /// Seconds since 1970, 0 when unknown.
    public var addedAt: Int64
    public var mimeType: String?
    public var sizeBytes: Int64?
    public var artwork: String?
    /// Where the audio is, for a song on the phone.
    public var uri: String?
    /// Its place in its album, worked out when the library is built.
    public var albumOrder: Int
    /// Who, what and how long: finds this song again if its id changes.
    public var relinkKey: String
    /// The main genre, or empty.
    public var genre: String
    /// Whether a copy is on the phone. A song only on a server streams.
    public var onPhone: Bool
    /// 1 to 5 stars, 0 for none: the server's when it has one, else the phone's.
    public var rating: Int
    /// True when a copy is marked explicit, false when clean, nil when nothing says.
    public var explicit: Bool?

    public init(id: String, sourceId: String, nativeId: String, title: String, searchKey: String, sortKey: String,
                artist: String, artistId: String, album: String, albumId: String, trackNo: Int? = nil, discNo: Int? = nil,
                year: Int? = nil, durationMs: Int64, addedAt: Int64, mimeType: String? = nil, sizeBytes: Int64? = nil,
                artwork: String? = nil, uri: String? = nil, albumOrder: Int = 0, relinkKey: String = "", genre: String = "",
                onPhone: Bool = true, rating: Int = 0, explicit: Bool? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.nativeId = nativeId
        self.title = title
        self.searchKey = searchKey
        self.sortKey = sortKey
        self.artist = artist
        self.artistId = artistId
        self.album = album
        self.albumId = albumId
        self.trackNo = trackNo
        self.discNo = discNo
        self.year = year
        self.durationMs = durationMs
        self.addedAt = addedAt
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.artwork = artwork
        self.uri = uri
        self.albumOrder = albumOrder
        self.relinkKey = relinkKey
        self.genre = genre
        self.onPhone = onPhone
        self.rating = rating
        self.explicit = explicit
    }

    public static let table = "track"
    public static let columns = ["id", "sourceId", "nativeId", "title", "searchKey", "sortKey", "artist", "artistId", "album",
                                 "albumId", "trackNo", "discNo", "year", "durationMs", "addedAt", "mimeType", "sizeBytes",
                                 "artwork", "uri", "albumOrder", "relinkKey", "genre", "onPhone", "rating", "explicit"]

    public var values: [any SQLBindable] {
        [id, sourceId, nativeId, title, searchKey, sortKey, artist, artistId, album, albumId, trackNo, discNo, year, durationMs,
         addedAt, mimeType, sizeBytes, artwork, uri, albumOrder, relinkKey, genre, onPhone, rating, explicit]
    }

    public init(row: SQLRow) {
        id = row.string("id")
        sourceId = row.string("sourceId")
        nativeId = row.string("nativeId")
        title = row.string("title")
        searchKey = row.string("searchKey")
        sortKey = row.string("sortKey")
        artist = row.string("artist")
        artistId = row.string("artistId")
        album = row.string("album")
        albumId = row.string("albumId")
        trackNo = row.optionalInt("trackNo")
        discNo = row.optionalInt("discNo")
        year = row.optionalInt("year")
        durationMs = row.int64("durationMs")
        addedAt = row.int64("addedAt")
        mimeType = row.optionalString("mimeType")
        sizeBytes = row.optionalInt64("sizeBytes")
        artwork = row.optionalString("artwork")
        uri = row.optionalString("uri")
        albumOrder = row.int("albumOrder")
        relinkKey = row.string("relinkKey")
        genre = row.string("genre")
        onPhone = row.bool("onPhone")
        rating = row.int("rating")
        explicit = row.optionalBool("explicit")
    }
}

/// A library album.
public struct LibraryAlbum: TableRow, Hashable, Identifiable {
    public var id: String
    public var sourceId: String
    public var nativeId: String
    public var title: String
    public var searchKey: String
    public var sortKey: String
    public var artist: String
    public var artistId: String
    public var year: Int?
    public var songCount: Int
    public var durationMs: Int64
    /// Seconds since 1970, 0 when unknown.
    public var addedAt: Int64
    public var artwork: String?
    /// What kind of release it is, one word a line ("Album", "EP", "Live"), empty when nothing says.
    public var releaseTypes: String

    public init(id: String, sourceId: String, nativeId: String, title: String, searchKey: String, sortKey: String,
                artist: String, artistId: String, year: Int? = nil, songCount: Int, durationMs: Int64, addedAt: Int64,
                artwork: String? = nil, releaseTypes: String = "") {
        self.id = id
        self.sourceId = sourceId
        self.nativeId = nativeId
        self.title = title
        self.searchKey = searchKey
        self.sortKey = sortKey
        self.artist = artist
        self.artistId = artistId
        self.year = year
        self.songCount = songCount
        self.durationMs = durationMs
        self.addedAt = addedAt
        self.artwork = artwork
        self.releaseTypes = releaseTypes
    }

    public static let table = "album"
    public static let columns = ["id", "sourceId", "nativeId", "title", "searchKey", "sortKey", "artist", "artistId", "year",
                                 "songCount", "durationMs", "addedAt", "artwork", "releaseTypes"]

    public var values: [any SQLBindable] {
        [id, sourceId, nativeId, title, searchKey, sortKey, artist, artistId, year, songCount, durationMs, addedAt, artwork,
         releaseTypes]
    }

    public init(row: SQLRow) {
        id = row.string("id")
        sourceId = row.string("sourceId")
        nativeId = row.string("nativeId")
        title = row.string("title")
        searchKey = row.string("searchKey")
        sortKey = row.string("sortKey")
        artist = row.string("artist")
        artistId = row.string("artistId")
        year = row.optionalInt("year")
        songCount = row.int("songCount")
        durationMs = row.int64("durationMs")
        addedAt = row.int64("addedAt")
        artwork = row.optionalString("artwork")
        releaseTypes = row.string("releaseTypes")
    }
}

/// A library artist: an album artist.
public struct LibraryArtist: TableRow, Hashable, Identifiable {
    public var id: String
    public var sourceId: String
    public var name: String
    public var searchKey: String
    public var sortKey: String
    public var albumCount: Int
    public var songCount: Int
    public var artwork: String?

    public init(id: String, sourceId: String, name: String, searchKey: String, sortKey: String, albumCount: Int,
                songCount: Int, artwork: String? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.name = name
        self.searchKey = searchKey
        self.sortKey = sortKey
        self.albumCount = albumCount
        self.songCount = songCount
        self.artwork = artwork
    }

    public static let table = "artist"
    public static let columns = ["id", "sourceId", "name", "searchKey", "sortKey", "albumCount", "songCount", "artwork"]

    public var values: [any SQLBindable] { [id, sourceId, name, searchKey, sortKey, albumCount, songCount, artwork] }

    public init(row: SQLRow) {
        id = row.string("id")
        sourceId = row.string("sourceId")
        name = row.string("name")
        searchKey = row.string("searchKey")
        sortKey = row.string("sortKey")
        albumCount = row.int("albumCount")
        songCount = row.int("songCount")
        artwork = row.optionalString("artwork")
    }
}

// What each source has, as it has it: the phone's files, or a server's library. Each source
// replaces its own rows; the library is merged from them.

/// One source's copy of a song.
public struct SourceTrack: TableRow, Hashable, Identifiable {
    public var id: String
    public var sourceId: String
    public var nativeId: String
    public var title: String
    public var searchKey: String
    public var sortKey: String
    public var artist: String
    public var artistId: String
    public var album: String
    public var albumId: String
    public var trackNo: Int?
    public var discNo: Int?
    public var year: Int?
    public var durationMs: Int64
    public var addedAt: Int64
    public var mimeType: String?
    public var sizeBytes: Int64?
    public var artwork: String?
    public var uri: String?
    public var albumOrder: Int
    public var relinkKey: String
    public var genre: String
    /// Bits per second, samples per second and bits per sample, where the source says.
    public var bitrate: Int?
    public var sampleRate: Int?
    public var bitDepth: Int?
    /// A server's own listening record for this copy.
    public var playCount: Int?
    public var lastPlayedAt: Int64?
    public var starredAt: Int64?
    /// Loudness in decibels, peaks where 1 is full scale.
    public var trackGain: Float?
    public var albumGain: Float?
    public var trackPeak: Float?
    public var albumPeak: Float?
    public var baseGain: Float?
    public var fallbackGain: Float?
    /// The listener's rating on the server, 1 to 5, or 0 for none.
    public var rating: Int?
    /// The library song this copy was merged into.
    public var mergedId: String
    public var originalYear: Int?
    /// Every genre and every credited artist, one per line, main one first.
    public var genres: String
    public var artists: String
    public var composer: String?
    public var bpm: Int?
    public var comment: String?
    public var explicit: Bool?
    public var discTitle: String?
    public var mbRecordingId: String?
    public var mbAlbumId: String?
    public var mbReleaseGroupId: String?
    /// One per line.
    public var mbArtistIds: String
    /// A server copy in the signed-in family member's own library.
    public var personal: Bool

    public init(id: String, sourceId: String, nativeId: String, title: String, searchKey: String, sortKey: String,
                artist: String, artistId: String, album: String, albumId: String, trackNo: Int? = nil, discNo: Int? = nil,
                year: Int? = nil, durationMs: Int64, addedAt: Int64, mimeType: String? = nil, sizeBytes: Int64? = nil,
                artwork: String? = nil, uri: String? = nil, albumOrder: Int = 0, relinkKey: String = "", genre: String = "",
                bitrate: Int? = nil, sampleRate: Int? = nil, bitDepth: Int? = nil, playCount: Int? = nil,
                lastPlayedAt: Int64? = nil, starredAt: Int64? = nil, trackGain: Float? = nil, albumGain: Float? = nil,
                trackPeak: Float? = nil, albumPeak: Float? = nil, baseGain: Float? = nil, fallbackGain: Float? = nil,
                rating: Int? = nil, mergedId: String = "", originalYear: Int? = nil, genres: String = "", artists: String = "",
                composer: String? = nil, bpm: Int? = nil, comment: String? = nil, explicit: Bool? = nil,
                discTitle: String? = nil, mbRecordingId: String? = nil, mbAlbumId: String? = nil,
                mbReleaseGroupId: String? = nil, mbArtistIds: String = "", personal: Bool = false) {
        self.id = id
        self.sourceId = sourceId
        self.nativeId = nativeId
        self.title = title
        self.searchKey = searchKey
        self.sortKey = sortKey
        self.artist = artist
        self.artistId = artistId
        self.album = album
        self.albumId = albumId
        self.trackNo = trackNo
        self.discNo = discNo
        self.year = year
        self.durationMs = durationMs
        self.addedAt = addedAt
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.artwork = artwork
        self.uri = uri
        self.albumOrder = albumOrder
        self.relinkKey = relinkKey
        self.genre = genre
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.playCount = playCount
        self.lastPlayedAt = lastPlayedAt
        self.starredAt = starredAt
        self.trackGain = trackGain
        self.albumGain = albumGain
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
        self.baseGain = baseGain
        self.fallbackGain = fallbackGain
        self.rating = rating
        self.mergedId = mergedId
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
        self.personal = personal
    }

    public static let table = "source_track"
    public static let columns = ["id", "sourceId", "nativeId", "title", "searchKey", "sortKey", "artist", "artistId", "album",
                                 "albumId", "trackNo", "discNo", "year", "durationMs", "addedAt", "mimeType", "sizeBytes",
                                 "artwork", "uri", "albumOrder", "relinkKey", "genre", "bitrate", "sampleRate", "bitDepth",
                                 "playCount", "lastPlayedAt", "starredAt", "trackGain", "albumGain", "trackPeak", "albumPeak",
                                 "baseGain", "fallbackGain", "rating", "mergedId", "originalYear", "genres", "artists",
                                 "composer", "bpm", "comment", "explicit", "discTitle", "mbRecordingId", "mbAlbumId",
                                 "mbReleaseGroupId", "mbArtistIds", "personal"]

    public var values: [any SQLBindable] {
        [id, sourceId, nativeId, title, searchKey, sortKey, artist, artistId, album, albumId, trackNo, discNo, year, durationMs,
         addedAt, mimeType, sizeBytes, artwork, uri, albumOrder, relinkKey, genre, bitrate, sampleRate, bitDepth, playCount,
         lastPlayedAt, starredAt, trackGain, albumGain, trackPeak, albumPeak, baseGain, fallbackGain, rating, mergedId,
         originalYear, genres, artists, composer, bpm, comment, explicit, discTitle, mbRecordingId, mbAlbumId,
         mbReleaseGroupId, mbArtistIds, personal]
    }

    public init(row: SQLRow) {
        id = row.string("id")
        sourceId = row.string("sourceId")
        nativeId = row.string("nativeId")
        title = row.string("title")
        searchKey = row.string("searchKey")
        sortKey = row.string("sortKey")
        artist = row.string("artist")
        artistId = row.string("artistId")
        album = row.string("album")
        albumId = row.string("albumId")
        trackNo = row.optionalInt("trackNo")
        discNo = row.optionalInt("discNo")
        year = row.optionalInt("year")
        durationMs = row.int64("durationMs")
        addedAt = row.int64("addedAt")
        mimeType = row.optionalString("mimeType")
        sizeBytes = row.optionalInt64("sizeBytes")
        artwork = row.optionalString("artwork")
        uri = row.optionalString("uri")
        albumOrder = row.int("albumOrder")
        relinkKey = row.string("relinkKey")
        genre = row.string("genre")
        bitrate = row.optionalInt("bitrate")
        sampleRate = row.optionalInt("sampleRate")
        bitDepth = row.optionalInt("bitDepth")
        playCount = row.optionalInt("playCount")
        lastPlayedAt = row.optionalInt64("lastPlayedAt")
        starredAt = row.optionalInt64("starredAt")
        trackGain = row.optionalFloat("trackGain")
        albumGain = row.optionalFloat("albumGain")
        trackPeak = row.optionalFloat("trackPeak")
        albumPeak = row.optionalFloat("albumPeak")
        baseGain = row.optionalFloat("baseGain")
        fallbackGain = row.optionalFloat("fallbackGain")
        rating = row.optionalInt("rating")
        mergedId = row.string("mergedId")
        originalYear = row.optionalInt("originalYear")
        genres = row.string("genres")
        artists = row.string("artists")
        composer = row.optionalString("composer")
        bpm = row.optionalInt("bpm")
        comment = row.optionalString("comment")
        explicit = row.optionalBool("explicit")
        discTitle = row.optionalString("discTitle")
        mbRecordingId = row.optionalString("mbRecordingId")
        mbAlbumId = row.optionalString("mbAlbumId")
        mbReleaseGroupId = row.optionalString("mbReleaseGroupId")
        mbArtistIds = row.string("mbArtistIds")
        personal = row.bool("personal")
    }
}

/// One source's copy of an album.
public struct SourceAlbum: TableRow, Hashable, Identifiable {
    public var id: String
    public var sourceId: String
    public var nativeId: String
    public var title: String
    public var searchKey: String
    public var sortKey: String
    public var artist: String
    public var artistId: String
    public var year: Int?
    public var songCount: Int
    public var durationMs: Int64
    public var addedAt: Int64
    public var artwork: String?
    public var releaseTypes: String

    public init(id: String, sourceId: String, nativeId: String, title: String, searchKey: String, sortKey: String,
                artist: String, artistId: String, year: Int? = nil, songCount: Int, durationMs: Int64, addedAt: Int64,
                artwork: String? = nil, releaseTypes: String = "") {
        self.id = id
        self.sourceId = sourceId
        self.nativeId = nativeId
        self.title = title
        self.searchKey = searchKey
        self.sortKey = sortKey
        self.artist = artist
        self.artistId = artistId
        self.year = year
        self.songCount = songCount
        self.durationMs = durationMs
        self.addedAt = addedAt
        self.artwork = artwork
        self.releaseTypes = releaseTypes
    }

    public static let table = "source_album"
    public static let columns = LibraryAlbum.columns

    public var values: [any SQLBindable] {
        [id, sourceId, nativeId, title, searchKey, sortKey, artist, artistId, year, songCount, durationMs, addedAt, artwork,
         releaseTypes]
    }

    public init(row: SQLRow) {
        let album = LibraryAlbum(row: row)
        self.init(album)
    }

    public init(_ album: LibraryAlbum) {
        self.init(id: album.id, sourceId: album.sourceId, nativeId: album.nativeId, title: album.title,
                  searchKey: album.searchKey, sortKey: album.sortKey, artist: album.artist, artistId: album.artistId,
                  year: album.year, songCount: album.songCount, durationMs: album.durationMs, addedAt: album.addedAt,
                  artwork: album.artwork, releaseTypes: album.releaseTypes)
    }
}

/// One source's copy of an artist.
public struct SourceArtist: TableRow, Hashable, Identifiable {
    public var id: String
    public var sourceId: String
    public var name: String
    public var searchKey: String
    public var sortKey: String
    public var albumCount: Int
    public var songCount: Int
    public var artwork: String?

    public init(id: String, sourceId: String, name: String, searchKey: String, sortKey: String, albumCount: Int,
                songCount: Int, artwork: String? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.name = name
        self.searchKey = searchKey
        self.sortKey = sortKey
        self.albumCount = albumCount
        self.songCount = songCount
        self.artwork = artwork
    }

    public static let table = "source_artist"
    public static let columns = LibraryArtist.columns

    public var values: [any SQLBindable] { [id, sourceId, name, searchKey, sortKey, albumCount, songCount, artwork] }

    public init(row: SQLRow) {
        let artist = LibraryArtist(row: row)
        self.init(artist)
    }

    public init(_ artist: LibraryArtist) {
        self.init(id: artist.id, sourceId: artist.sourceId, name: artist.name, searchKey: artist.searchKey,
                  sortKey: artist.sortKey, albumCount: artist.albumCount, songCount: artist.songCount, artwork: artist.artwork)
    }
}

extension LibraryAlbum {
    /// The same album as a source's row.
    public var asSource: SourceAlbum { SourceAlbum(self) }
}

extension LibraryArtist {
    public var asSource: SourceArtist { SourceArtist(self) }
}
