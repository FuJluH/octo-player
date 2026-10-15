import Foundation

// Things the listener made: likes, ratings, plays, playlists, the saved queue, favorite albums
// and artists, and pins. None of these point at the library with a foreign key, since the
// library is rebuilt from its sources on every scan; each row keeps a relink key instead, so a
// song whose id changed can be found again.

public struct LikedTrack: TableRow, Hashable {
    public var trackId: String
    public var relinkKey: String
    public var likedAt: Int64

    public init(trackId: String, relinkKey: String, likedAt: Int64) {
        self.trackId = trackId
        self.relinkKey = relinkKey
        self.likedAt = likedAt
    }

    public static let table = "liked_track"
    public static let columns = ["trackId", "relinkKey", "likedAt"]
    public var values: [any SQLBindable] { [trackId, relinkKey, likedAt] }

    public init(row: SQLRow) {
        trackId = row.string("trackId")
        relinkKey = row.string("relinkKey")
        likedAt = row.int64("likedAt")
    }
}

/// A rating made on the phone, 1 to 5 stars. A song with no rating has no row.
public struct TrackRating: TableRow, Hashable {
    public var trackId: String
    public var relinkKey: String
    public var rating: Int
    public var ratedAt: Int64

    public init(trackId: String, relinkKey: String, rating: Int, ratedAt: Int64) {
        self.trackId = trackId
        self.relinkKey = relinkKey
        self.rating = rating
        self.ratedAt = ratedAt
    }

    public static let table = "track_rating"
    public static let columns = ["trackId", "relinkKey", "rating", "ratedAt"]
    public var values: [any SQLBindable] { [trackId, relinkKey, rating, ratedAt] }

    public init(row: SQLRow) {
        trackId = row.string("trackId")
        relinkKey = row.string("relinkKey")
        rating = row.int("rating")
        ratedAt = row.int64("ratedAt")
    }
}

/// One play: the song, its relink key, when it started, how much was heard and how long it is.
public struct PlayEvent: TableRow, Hashable {
    /// 0 for a play not stored yet.
    public var id: Int64
    public var trackId: String
    public var relinkKey: String
    public var startedAt: Int64
    public var playedMs: Int64
    public var durationMs: Int64

    public init(id: Int64 = 0, trackId: String, relinkKey: String, startedAt: Int64, playedMs: Int64, durationMs: Int64) {
        self.id = id
        self.trackId = trackId
        self.relinkKey = relinkKey
        self.startedAt = startedAt
        self.playedMs = playedMs
        self.durationMs = durationMs
    }

    public static let table = "play_event"
    public static let columns = ["trackId", "relinkKey", "startedAt", "playedMs", "durationMs"]
    public var values: [any SQLBindable] { [trackId, relinkKey, startedAt, playedMs, durationMs] }

    public init(row: SQLRow) {
        id = row.int64("id")
        trackId = row.string("trackId")
        relinkKey = row.string("relinkKey")
        startedAt = row.int64("startedAt")
        playedMs = row.int64("playedMs")
        durationMs = row.int64("durationMs")
    }
}

/// A playlist on the phone, maybe kept in step with one on a server.
public struct PlaylistRow: TableRow, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: Int64
    public var updatedAt: Int64
    /// The server playlist this one is kept with: its id there, and which server. One waiting to
    /// be made on the server has the server but no id yet. Both nil for a phone-only playlist.
    public var serverId: String?
    public var sourceId: String?
    /// What updatedAt was when both sides last agreed.
    public var syncedAt: Int64?
    /// The name both sides agreed on then, and the server's changed time and song count.
    public var syncedName: String?
    public var serverStamp: String?
    /// Which of Octo's notice lists the server copy is ("review", "duplicates").
    public var octoNotice: String?

    public init(id: String, name: String, createdAt: Int64, updatedAt: Int64, serverId: String? = nil,
                sourceId: String? = nil, syncedAt: Int64? = nil, syncedName: String? = nil, serverStamp: String? = nil,
                octoNotice: String? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.serverId = serverId
        self.sourceId = sourceId
        self.syncedAt = syncedAt
        self.syncedName = syncedName
        self.serverStamp = serverStamp
        self.octoNotice = octoNotice
    }

    public static let table = "playlist"
    public static let columns = ["id", "name", "createdAt", "updatedAt", "serverId", "sourceId", "syncedAt", "syncedName",
                                 "serverStamp", "octoNotice"]
    public var values: [any SQLBindable] {
        [id, name, createdAt, updatedAt, serverId, sourceId, syncedAt, syncedName, serverStamp, octoNotice]
    }

    public init(row: SQLRow) {
        id = row.string("id")
        name = row.string("name")
        createdAt = row.int64("createdAt")
        updatedAt = row.int64("updatedAt")
        serverId = row.optionalString("serverId")
        sourceId = row.optionalString("sourceId")
        syncedAt = row.optionalInt64("syncedAt")
        syncedName = row.optionalString("syncedName")
        serverStamp = row.optionalString("serverStamp")
        octoNotice = row.optionalString("octoNotice")
    }

    /// Whether this playlist shows while this server is in use (nil for none): a phone-only one
    /// always, one kept with a server while it is in use.
    public func shownWith(_ serverInUse: String?) -> Bool { sourceId == nil || sourceId == serverInUse }
}

/// One song of a playlist, at its place.
public struct PlaylistItem: TableRow, Hashable, Identifiable {
    /// 0 for a row not stored yet.
    public var id: Int64
    public var playlistId: String
    public var trackId: String
    public var relinkKey: String
    public var position: Int
    /// The server's id for this song when it came from the server's copy of the playlist.
    public var serverSongId: String?

    public init(id: Int64 = 0, playlistId: String, trackId: String, relinkKey: String, position: Int, serverSongId: String? = nil) {
        self.id = id
        self.playlistId = playlistId
        self.trackId = trackId
        self.relinkKey = relinkKey
        self.position = position
        self.serverSongId = serverSongId
    }

    public static let table = "playlist_item"
    /// The id is written too, so a row taken out comes back with its own id.
    public static let columns = ["id", "playlistId", "trackId", "relinkKey", "position", "serverSongId"]
    public var values: [any SQLBindable] { [id == 0 ? nil : id, playlistId, trackId, relinkKey, position, serverSongId] }

    public init(row: SQLRow) {
        id = row.int64("id")
        playlistId = row.string("playlistId")
        trackId = row.string("trackId")
        relinkKey = row.string("relinkKey")
        position = row.int("position")
        serverSongId = row.optionalString("serverSongId")
    }
}

/// The saved queue, one row per song in play order.
public struct QueueItemRow: TableRow, Hashable {
    public var position: Int
    public var trackId: String
    /// Where this song falls when shuffle is on.
    public var shuffledPosition: Int

    public init(position: Int, trackId: String, shuffledPosition: Int) {
        self.position = position
        self.trackId = trackId
        self.shuffledPosition = shuffledPosition
    }

    public static let table = "queue_item"
    public static let columns = ["position", "trackId", "shuffledPosition"]
    public var values: [any SQLBindable] { [position, trackId, shuffledPosition] }

    public init(row: SQLRow) {
        position = row.int("position")
        trackId = row.string("trackId")
        shuffledPosition = row.int("shuffledPosition")
    }
}

/// Where playback was in the saved queue. Always one row.
public struct QueueStateRow: TableRow, Hashable {
    public var currentIndex: Int
    public var positionMs: Int64
    public var repeatMode: Int
    public var shuffle: Bool
    public var savedAt: Int64

    public init(currentIndex: Int, positionMs: Int64, repeatMode: Int, shuffle: Bool, savedAt: Int64) {
        self.currentIndex = currentIndex
        self.positionMs = positionMs
        self.repeatMode = repeatMode
        self.shuffle = shuffle
        self.savedAt = savedAt
    }

    public static let table = "queue_state"
    public static let columns = ["id", "currentIndex", "positionMs", "repeatMode", "shuffle", "savedAt"]
    public var values: [any SQLBindable] { [0, currentIndex, positionMs, repeatMode, shuffle, savedAt] }

    public init(row: SQLRow) {
        currentIndex = row.int("currentIndex")
        positionMs = row.int64("positionMs")
        repeatMode = row.int("repeatMode")
        shuffle = row.bool("shuffle")
        savedAt = row.int64("savedAt")
    }
}

/// What a find's id starts with: "find:<server id>".
public let findPrefix = "find:"

public func findId(_ serverId: String) -> String { findPrefix + serverId }

public func isFind(_ trackId: String) -> Bool { trackId.hasPrefix(findPrefix) }

/// A song the server found online that is not in the library: in search, radio and stations.
/// Kept so a queue holding one still plays after a restart, and so a download asked for can be
/// followed until it arrives.
public struct OnlineSong: TableRow, Hashable, Identifiable {
    /// "find:<server id>", the id it has in the queue.
    public var id: String
    public var sourceId: String
    public var nativeId: String
    public var title: String
    public var artist: String
    /// Empty when the server did not say.
    public var album: String
    public var albumId: String?
    public var artistId: String?
    /// 0 when the server only guessed the length; a length learned by playing it otherwise.
    public var durationMs: Int64
    public var coverId: String?
    public var mimeType: String?
    /// Kilobits a second, as the server says.
    public var bitrate: Int?
    public var seenAt: Int64
    /// When a download was asked for, or 0.
    public var requestedAt: Int64
    /// The library song it became once downloaded, or empty.
    public var adoptedId: String
    public var explicit: Bool?

    public init(id: String, sourceId: String, nativeId: String, title: String, artist: String, album: String = "",
                albumId: String? = nil, artistId: String? = nil, durationMs: Int64 = 0, coverId: String? = nil,
                mimeType: String? = nil, bitrate: Int? = nil, seenAt: Int64, requestedAt: Int64 = 0, adoptedId: String = "",
                explicit: Bool? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.nativeId = nativeId
        self.title = title
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.artistId = artistId
        self.durationMs = durationMs
        self.coverId = coverId
        self.mimeType = mimeType
        self.bitrate = bitrate
        self.seenAt = seenAt
        self.requestedAt = requestedAt
        self.adoptedId = adoptedId
        self.explicit = explicit
    }

    public static let table = "online_song"
    public static let columns = ["id", "sourceId", "nativeId", "title", "artist", "album", "albumId", "artistId", "durationMs",
                                 "coverId", "mimeType", "bitrate", "seenAt", "requestedAt", "adoptedId", "explicit"]
    public var values: [any SQLBindable] {
        [id, sourceId, nativeId, title, artist, album, albumId, artistId, durationMs, coverId, mimeType, bitrate, seenAt,
         requestedAt, adoptedId, explicit]
    }

    public init(row: SQLRow) {
        id = row.string("id")
        sourceId = row.string("sourceId")
        nativeId = row.string("nativeId")
        title = row.string("title")
        artist = row.string("artist")
        album = row.string("album")
        albumId = row.optionalString("albumId")
        artistId = row.optionalString("artistId")
        durationMs = row.int64("durationMs")
        coverId = row.optionalString("coverId")
        mimeType = row.optionalString("mimeType")
        bitrate = row.optionalInt("bitrate")
        seenAt = row.int64("seenAt")
        requestedAt = row.int64("requestedAt")
        adoptedId = row.string("adoptedId")
        explicit = row.optionalBool("explicit")
    }
}

/// A favorite album. The relink key is the album's search key.
public struct LikedAlbumRow: TableRow, Hashable {
    public var albumId: String
    public var relinkKey: String
    public var likedAt: Int64

    public init(albumId: String, relinkKey: String, likedAt: Int64) {
        self.albumId = albumId
        self.relinkKey = relinkKey
        self.likedAt = likedAt
    }

    public static let table = "liked_album"
    public static let columns = ["albumId", "relinkKey", "likedAt"]
    public var values: [any SQLBindable] { [albumId, relinkKey, likedAt] }

    public init(row: SQLRow) {
        albumId = row.string("albumId")
        relinkKey = row.string("relinkKey")
        likedAt = row.int64("likedAt")
    }
}

/// A favorite artist. The relink key is the artist's search key.
public struct LikedArtistRow: TableRow, Hashable {
    public var artistId: String
    public var relinkKey: String
    public var likedAt: Int64

    public init(artistId: String, relinkKey: String, likedAt: Int64) {
        self.artistId = artistId
        self.relinkKey = relinkKey
        self.likedAt = likedAt
    }

    public static let table = "liked_artist"
    public static let columns = ["artistId", "relinkKey", "likedAt"]
    public var values: [any SQLBindable] { [artistId, relinkKey, likedAt] }

    public init(row: SQLRow) {
        artistId = row.string("artistId")
        relinkKey = row.string("relinkKey")
        likedAt = row.int64("likedAt")
    }
}

/// Something pinned to the front of Home, at its place in the row (0 first).
public struct PinnedItem: TableRow, Hashable {
    public var kind: String
    public var itemId: String
    public var relinkKey: String
    public var position: Int

    public init(kind: String, itemId: String, relinkKey: String, position: Int) {
        self.kind = kind
        self.itemId = itemId
        self.relinkKey = relinkKey
        self.position = position
    }

    public static let table = "pinned_item"
    public static let columns = ["kind", "itemId", "relinkKey", "position"]
    public var values: [any SQLBindable] { [kind, itemId, relinkKey, position] }

    public init(row: SQLRow) {
        kind = row.string("kind")
        itemId = row.string("itemId")
        relinkKey = row.string("relinkKey")
        position = row.int("position")
    }
}

/// Where a download is.
public enum DownloadStatus: String, Sendable, Codable, CaseIterable {
    case queued = "Queued"
    case downloading = "Downloading"
    case done = "Done"
    case failed = "Failed"
}

/// A server song kept on the phone as a real file, held for one or more reasons; once none is
/// left, the file goes. Keyed by the server's song, which never changes; `trackId` is the library
/// song it is, kept up to date after each sync.
public struct KeptDownload: TableRow, Hashable {
    public var trackId: String
    public var sourceId: String
    public var serverId: String
    /// The finished file, or empty until there is one.
    public var path: String
    public var sizeBytes: Int64
    /// What the file is: the server's type, or MP3 when a smaller one was asked for.
    public var format: String?
    public var state: DownloadStatus
    /// From 0 to 1 while it downloads.
    public var progress: Float
    public var addedAt: Int64
    /// Why it is kept, as `DownloadReasons` writes it.
    public var reason: String
    public var title: String
    public var artist: String
    /// The server's size for the file the download was made from, so a new file under the same id
    /// is told apart. Downloads made before it was noted have none until the first check after a
    /// sync.
    public var fileSize: Int64?

    public init(trackId: String, sourceId: String, serverId: String, path: String = "", sizeBytes: Int64 = 0,
                format: String? = nil, state: DownloadStatus = .queued, progress: Float = 0, addedAt: Int64, reason: String,
                title: String, artist: String, fileSize: Int64? = nil) {
        self.trackId = trackId
        self.sourceId = sourceId
        self.serverId = serverId
        self.path = path
        self.sizeBytes = sizeBytes
        self.format = format
        self.state = state
        self.progress = progress
        self.addedAt = addedAt
        self.reason = reason
        self.title = title
        self.artist = artist
        self.fileSize = fileSize
    }

    public static let table = "download"
    public static let columns = ["trackId", "sourceId", "serverId", "path", "sizeBytes", "format", "state", "progress",
                                 "addedAt", "reason", "title", "artist", "fileSize"]
    public var values: [any SQLBindable] {
        [trackId, sourceId, serverId, path, sizeBytes, format, state.rawValue, progress, addedAt, reason, title, artist, fileSize]
    }

    public init(row: SQLRow) {
        trackId = row.string("trackId")
        sourceId = row.string("sourceId")
        serverId = row.string("serverId")
        path = row.string("path")
        sizeBytes = row.int64("sizeBytes")
        format = row.optionalString("format")
        state = DownloadStatus(rawValue: row.string("state")) ?? .queued
        progress = row.float("progress")
        addedAt = row.int64("addedAt")
        reason = row.string("reason")
        title = row.string("title")
        artist = row.string("artist")
        fileSize = row.optionalInt64("fileSize")
    }
}

/// Tags read from one file on the phone, kept so a rescan only reads files that changed. Stale
/// when the file's modified time or size moves.
public struct FileTagsRow: TableRow, Hashable {
    public var mediaId: Int64
    public var modifiedAt: Int64
    public var size: Int64
    /// False when the file could not be read; the media library's own tags are used then.
    public var readOk: Bool
    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var trackNo: Int?
    public var discNo: Int?
    public var year: Int?
    public var compilation: Bool
    public var mbAlbumId: String?
    /// One per line, main one first.
    public var genres: String
    /// Which way of reading tags wrote this row.
    public var tagsVersion: Int
    public var originalYear: Int?
    public var artists: String
    public var composer: String?
    public var bpm: Int?
    public var comment: String?
    public var explicit: Bool?
    public var discTitle: String?
    public var mbRecordingId: String?
    public var mbReleaseGroupId: String?
    public var mbArtistIds: String
    public var sortTitle: String?
    public var sortAlbum: String?
    public var sortAlbumArtist: String?
    public var trackGain: Float?
    public var albumGain: Float?
    public var trackPeak: Float?
    public var albumPeak: Float?

    public init(mediaId: Int64, modifiedAt: Int64, size: Int64, readOk: Bool, title: String? = nil, artist: String? = nil,
                albumArtist: String? = nil, album: String? = nil, trackNo: Int? = nil, discNo: Int? = nil, year: Int? = nil,
                compilation: Bool = false, mbAlbumId: String? = nil, genres: String = "", tagsVersion: Int = 0,
                originalYear: Int? = nil, artists: String = "", composer: String? = nil, bpm: Int? = nil,
                comment: String? = nil, explicit: Bool? = nil, discTitle: String? = nil, mbRecordingId: String? = nil,
                mbReleaseGroupId: String? = nil, mbArtistIds: String = "", sortTitle: String? = nil,
                sortAlbum: String? = nil, sortAlbumArtist: String? = nil, trackGain: Float? = nil, albumGain: Float? = nil,
                trackPeak: Float? = nil, albumPeak: Float? = nil) {
        self.mediaId = mediaId
        self.modifiedAt = modifiedAt
        self.size = size
        self.readOk = readOk
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.trackNo = trackNo
        self.discNo = discNo
        self.year = year
        self.compilation = compilation
        self.mbAlbumId = mbAlbumId
        self.genres = genres
        self.tagsVersion = tagsVersion
        self.originalYear = originalYear
        self.artists = artists
        self.composer = composer
        self.bpm = bpm
        self.comment = comment
        self.explicit = explicit
        self.discTitle = discTitle
        self.mbRecordingId = mbRecordingId
        self.mbReleaseGroupId = mbReleaseGroupId
        self.mbArtistIds = mbArtistIds
        self.sortTitle = sortTitle
        self.sortAlbum = sortAlbum
        self.sortAlbumArtist = sortAlbumArtist
        self.trackGain = trackGain
        self.albumGain = albumGain
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
    }

    public static let table = "file_tags"
    public static let columns = ["mediaId", "modifiedAt", "size", "readOk", "title", "artist", "albumArtist", "album",
                                 "trackNo", "discNo", "year", "compilation", "mbAlbumId", "genres", "tagsVersion",
                                 "originalYear", "artists", "composer", "bpm", "comment", "explicit", "discTitle",
                                 "mbRecordingId", "mbReleaseGroupId", "mbArtistIds", "sortTitle", "sortAlbum",
                                 "sortAlbumArtist", "trackGain", "albumGain", "trackPeak", "albumPeak"]
    public var values: [any SQLBindable] {
        [mediaId, modifiedAt, size, readOk, title, artist, albumArtist, album, trackNo, discNo, year, compilation, mbAlbumId,
         genres, tagsVersion, originalYear, artists, composer, bpm, comment, explicit, discTitle, mbRecordingId,
         mbReleaseGroupId, mbArtistIds, sortTitle, sortAlbum, sortAlbumArtist, trackGain, albumGain, trackPeak, albumPeak]
    }

    public init(row: SQLRow) {
        mediaId = row.int64("mediaId")
        modifiedAt = row.int64("modifiedAt")
        size = row.int64("size")
        readOk = row.bool("readOk")
        title = row.optionalString("title")
        artist = row.optionalString("artist")
        albumArtist = row.optionalString("albumArtist")
        album = row.optionalString("album")
        trackNo = row.optionalInt("trackNo")
        discNo = row.optionalInt("discNo")
        year = row.optionalInt("year")
        compilation = row.bool("compilation")
        mbAlbumId = row.optionalString("mbAlbumId")
        genres = row.string("genres")
        tagsVersion = row.int("tagsVersion")
        originalYear = row.optionalInt("originalYear")
        artists = row.string("artists")
        composer = row.optionalString("composer")
        bpm = row.optionalInt("bpm")
        comment = row.optionalString("comment")
        explicit = row.optionalBool("explicit")
        discTitle = row.optionalString("discTitle")
        mbRecordingId = row.optionalString("mbRecordingId")
        mbReleaseGroupId = row.optionalString("mbReleaseGroupId")
        mbArtistIds = row.string("mbArtistIds")
        sortTitle = row.optionalString("sortTitle")
        sortAlbum = row.optionalString("sortAlbum")
        sortAlbumArtist = row.optionalString("sortAlbumArtist")
        trackGain = row.optionalFloat("trackGain")
        albumGain = row.optionalFloat("albumGain")
        trackPeak = row.optionalFloat("trackPeak")
        albumPeak = row.optionalFloat("albumPeak")
    }
}
