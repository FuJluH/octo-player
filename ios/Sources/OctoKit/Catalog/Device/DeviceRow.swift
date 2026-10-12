import Foundation

/// One music file as the phone's media library lists it, with the media library's own reading of
/// its tags kept as a fallback.
public struct DeviceFile: Sendable, Equatable {
    public var id: Int64
    public var uri: String
    public var fileName: String
    /// The folder it sits in, like "Music/Kavinsky/Nightcall/".
    public var folder: String?
    public var modifiedAt: Int64
    public var sizeBytes: Int64
    public var durationMs: Int64
    /// When the file joined the collection, in seconds (see `fileAddedAt`).
    public var addedAtSeconds: Int64
    public var mimeType: String?
    public var fallback: FileTags
    /// Which storage it is on, like "external_primary" or a memory card's id. Nil is the main one.
    public var volume: String?

    public init(id: Int64, uri: String, fileName: String, folder: String?, modifiedAt: Int64, sizeBytes: Int64,
                durationMs: Int64, addedAtSeconds: Int64, mimeType: String?, fallback: FileTags, volume: String? = nil) {
        self.id = id
        self.uri = uri
        self.fileName = fileName
        self.folder = folder
        self.modifiedAt = modifiedAt
        self.sizeBytes = sizeBytes
        self.durationMs = durationMs
        self.addedAtSeconds = addedAtSeconds
        self.mimeType = mimeType
        self.fallback = fallback
        self.volume = volume
    }

    /// The file's path from the top of its storage, like "Music/Kavinsky/01 Nightcall.mp3".
    public var relativePath: String { relativeFile(folder, fileName) }

    /// One file as the media library lists it, its own readings cleaned up the way the library
    /// keeps them. `track` may hold the disc too, packed as disc times 1000 plus track (2003 is
    /// disc 2, track 3); a separate `disc` wins over the packed one. Times are in seconds, except
    /// `takenMs`. `nowSeconds` is the time of the scan.
    public static func scanned(
        id: Int64, uri: String, fileName: String, folder: String?, modifiedSeconds: Int64, sizeBytes: Int64,
        durationMs: Int64, addedSeconds: Int64, takenMs: Int64? = nil, nowSeconds: Int64, mimeType: String?,
        volume: String? = nil, title: String? = nil, artist: String? = nil, albumArtist: String? = nil,
        album: String? = nil, track: Int? = nil, disc: Int? = nil, year: Int? = nil, genre: String? = nil
    ) -> DeviceFile {
        DeviceFile(
            id: id,
            uri: uri,
            fileName: fileName,
            folder: folder,
            modifiedAt: modifiedSeconds,
            sizeBytes: sizeBytes,
            durationMs: durationMs,
            addedAtSeconds: fileAddedAt(modifiedSeconds: modifiedSeconds, addedSeconds: addedSeconds, takenMs: takenMs,
                                        nowSeconds: nowSeconds),
            mimeType: mimeType,
            fallback: libraryTags(title: title, artist: artist, albumArtist: albumArtist, album: album, track: track,
                                  disc: disc, year: year, genre: genre),
            volume: volume
        )
    }
}

/// The name the media library gives a file whose artist it does not know.
private let unknownLibraryArtist = "<unknown>"

/// The media library's own reading of a file's tags: blanks and its "<unknown>" artist dropped,
/// zero meaning not set, and a disc packed into the track number (2003 is disc 2, track 3) taken
/// apart when no disc is given on its own.
public func libraryTags(title: String?, artist: String?, albumArtist: String?, album: String?, track: Int?, disc: Int?,
                        year: Int?, genre: String?) -> FileTags {
    func shown(_ text: String?) -> String? {
        guard let text, !trimmed(text).isEmpty else { return nil }
        return text
    }
    let packedDisc = track.flatMap { $0 >= 1000 ? $0 / 1000 : nil }
    let trackNo = track.flatMap { packed -> Int? in
        let number = packed % 1000
        return number > 0 ? number : nil
    }
    return FileTags(
        title: shown(title),
        artist: shown(artist).flatMap { $0 == unknownLibraryArtist ? nil : $0 },
        albumArtist: shown(albumArtist),
        album: shown(album),
        trackNo: trackNo,
        discNo: disc.flatMap { positionNumber(String($0)) } ?? packedDisc,
        year: year.flatMap { $0 > 0 ? $0 : nil },
        genres: parseGenres(genre.map { [$0] } ?? [])
    )
}

/// One file ready to be grouped: the file plus the best tags known for it.
public struct DeviceRow: Sendable, Equatable {
    public var id: Int64
    public var uri: String
    public var fileName: String
    public var folder: String?
    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var track: Int?
    public var disc: Int?
    public var year: Int?
    public var compilation: Bool
    public var mbAlbumId: String?
    public var genres: [String]
    public var durationMs: Int64
    public var addedAtSeconds: Int64
    public var mimeType: String?
    public var sizeBytes: Int64?
    /// Everything else the file's tags say; empty when they could not be read.
    public var tags: FileTags

    public init(id: Int64, uri: String, fileName: String, folder: String?, title: String?, artist: String?,
                albumArtist: String?, album: String?, track: Int?, disc: Int?, year: Int?, compilation: Bool = false,
                mbAlbumId: String? = nil, genres: [String] = [], durationMs: Int64, addedAtSeconds: Int64,
                mimeType: String?, sizeBytes: Int64?, tags: FileTags = FileTags()) {
        self.id = id
        self.uri = uri
        self.fileName = fileName
        self.folder = folder
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.album = album
        self.track = track
        self.disc = disc
        self.year = year
        self.compilation = compilation
        self.mbAlbumId = mbAlbumId
        self.genres = genres
        self.durationMs = durationMs
        self.addedAtSeconds = addedAtSeconds
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.tags = tags
    }
}

extension DeviceFile {
    /// Prefers the file's own tags, falling back to the media library's reading for anything the
    /// file did not say.
    public func toRow(_ tags: FileTags?) -> DeviceRow {
        DeviceRow(
            id: id,
            uri: uri,
            fileName: fileName,
            folder: folder,
            title: tags?.title ?? fallback.title,
            artist: tags?.artist ?? fallback.artist,
            albumArtist: tags?.albumArtist ?? fallback.albumArtist,
            album: tags?.album ?? fallback.album,
            track: tags?.trackNo ?? fallback.trackNo,
            disc: tags?.discNo ?? fallback.discNo,
            year: tags?.year ?? fallback.year,
            compilation: tags?.compilation ?? false,
            mbAlbumId: tags?.mbAlbumId,
            genres: tags.flatMap { $0.genres.isEmpty ? nil : $0.genres } ?? fallback.genres,
            durationMs: durationMs,
            addedAtSeconds: addedAtSeconds,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            tags: tags ?? FileTags()
        )
    }
}

/// Times before this (1 January 1990) are a clock that was never set, not when a song was really
/// got.
private let earliestRealSeconds: Int64 = 631_152_000

/// When a phone file joined the collection, in seconds since 1970.
///
/// The media library's own "added" time is when the file reached this phone, so a library copied
/// over in one go all looks added that day. The file's modified time usually survives the copy and
/// says when the song was really got, and a tag editor that touches a file later only moves it
/// forward. So the earliest real time wins: modified, added, or "taken", which a phone may fill in
/// for audio (in milliseconds). A time before 1990 or more than a day from now is a broken clock
/// and is passed over. With no real time at all, the added time is kept as it is.
public func fileAddedAt(modifiedSeconds: Int64, addedSeconds: Int64, takenMs: Int64?, nowSeconds: Int64) -> Int64 {
    let times = [modifiedSeconds, addedSeconds] + (takenMs.map { [$0 / 1000] } ?? [])
    let real = times.filter { $0 >= earliestRealSeconds && $0 <= nowSeconds + 86_400 }
    return real.min() ?? max(addedSeconds, 0)
}
