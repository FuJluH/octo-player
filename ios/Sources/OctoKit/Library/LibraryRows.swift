import Foundation

/// One song in the library, with what its pages sort, filter and show by. `song` is what plays
/// and what rows draw; the rest is kept beside it.
public struct LibraryTrack: Sendable, Hashable, Identifiable {
    public var song: Song
    /// The title's sort key.
    public var sortKey: String
    /// The album artist's sort key, else the song artist lower-cased.
    public var artistKey: String
    /// The album's sort key, else the song's album lower-cased.
    public var albumKey: String
    /// Position within its album: disc, then track.
    public var albumOrder: Int
    /// When it came into the library, in milliseconds since 1970; 0 when unknown.
    public var addedAt: Int64
    /// The listener's rating, 1 to 5, or 0 for none.
    public var rating: Int
    /// Every genre it names, main one first.
    public var genres: [String]
    public var albumArtist: String?
    public var composer: String?
    public var bpm: Int?
    public var comment: String?
    public var size: Int64?
    public var path: String?
    public var musicBrainzId: String?
    public var isrc: [String]
    /// The year the recording first came out, when it says.
    public var originalYear: Int?
    /// Whether a copy is on the phone. A song only on a server streams.
    public var onPhone: Bool
    /// In a family, a song in the member's own library rather than the shared one.
    public var personal: Bool
    /// How often and how lately it was played, here and on the server together.
    public var plays: Int
    public var lastPlayedAt: Int64
    /// When it was liked, or nil when it is not.
    public var likedAt: Int64?

    public var id: String { song.id }
    public var title: String { song.title }
    public var artist: String { song.artist ?? "" }
    public var album: String { song.album ?? "" }
    public var albumId: String { song.albumId ?? "" }
    public var artistId: String { song.artistId ?? "" }
    public var year: Int? { song.year }
    public var durationMs: Int64 { Int64(song.duration) * 1_000 }
    public var liked: Bool { likedAt != nil }
    /// The song's main genre, or empty.
    public var genre: String { genres.first ?? song.genre ?? "" }

    public init(
        song: Song, sortKey: String? = nil, artistKey: String? = nil, albumKey: String? = nil, albumOrder: Int? = nil,
        addedAt: Int64 = 0, rating: Int = 0, genres: [String] = [], albumArtist: String? = nil, composer: String? = nil,
        bpm: Int? = nil, comment: String? = nil, size: Int64? = nil, path: String? = nil, musicBrainzId: String? = nil,
        isrc: [String] = [], originalYear: Int? = nil, onPhone: Bool = false, personal: Bool = false, plays: Int = 0,
        lastPlayedAt: Int64 = 0, likedAt: Int64? = nil
    ) {
        self.song = song
        self.sortKey = sortKey ?? OctoKit.sortKey(song.title)
        self.artistKey = artistKey ?? (albumArtist.map { OctoKit.sortKey($0) } ?? (song.artist ?? "").lowercased())
        self.albumKey = albumKey ?? OctoKit.sortKey(song.album ?? "")
        self.albumOrder = albumOrder ?? ((song.discNumber ?? 1) * 1_000 + (song.track ?? 0))
        self.addedAt = addedAt
        self.rating = rating
        self.genres = genres.isEmpty ? (song.genre.map { [$0] } ?? []) : genres
        self.albumArtist = albumArtist
        self.composer = composer
        self.bpm = bpm
        self.comment = comment
        self.size = size
        self.path = path
        self.musicBrainzId = musicBrainzId
        self.isrc = isrc
        self.originalYear = originalYear
        self.onPhone = onPhone
        self.personal = personal
        self.plays = plays
        self.lastPlayedAt = lastPlayedAt
        self.likedAt = likedAt
    }
}

/// One album in the library.
public struct LibraryAlbum: Sendable, Hashable, Identifiable {
    /// What opens its page and draws its card.
    public var album: Album
    public var sortKey: String
    /// The album artist's sort key, else the artist lower-cased.
    public var artistKey: String
    public var addedAt: Int64
    /// What kind of release it is ("Album", "EP", "Live"), as the server tags it.
    public var releaseTypes: [String]
    /// When it became a favorite, or nil.
    public var favoredAt: Int64?
    public var plays: Int
    public var lastPlayedAt: Int64

    public var id: String { album.id }
    public var title: String { album.name }
    public var artist: String { album.byline }
    public var artistId: String { album.artistId ?? "" }
    public var year: Int? { album.year }
    public var songCount: Int { album.songCount }
    public var durationMs: Int64 { Int64(album.duration) * 1_000 }
    public var coverArt: String? { album.coverArt }

    public init(album: Album, sortKey: String? = nil, artistKey: String? = nil, addedAt: Int64 = 0, releaseTypes: [String] = [],
                favoredAt: Int64? = nil, plays: Int = 0, lastPlayedAt: Int64 = 0) {
        self.album = album
        self.sortKey = sortKey ?? OctoKit.sortKey(album.name)
        self.artistKey = artistKey ?? OctoKit.sortKey(album.byline)
        self.addedAt = addedAt
        self.releaseTypes = releaseTypes
        self.favoredAt = favoredAt
        self.plays = plays
        self.lastPlayedAt = lastPlayedAt
    }
}

/// One artist in the library.
public struct LibraryArtist: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var sortKey: String
    public var albumCount: Int
    public var songCount: Int
    public var coverArt: String?
    /// When the newest song of theirs came into the library.
    public var addedAt: Int64
    public var favoredAt: Int64?
    public var plays: Int
    public var lastPlayedAt: Int64

    public init(id: String, name: String, sortKey: String? = nil, albumCount: Int = 0, songCount: Int = 0, coverArt: String? = nil,
                addedAt: Int64 = 0, favoredAt: Int64? = nil, plays: Int = 0, lastPlayedAt: Int64 = 0) {
        self.id = id
        self.name = name
        self.sortKey = sortKey ?? OctoKit.sortKey(name)
        self.albumCount = albumCount
        self.songCount = songCount
        self.coverArt = coverArt
        self.addedAt = addedAt
        self.favoredAt = favoredAt
        self.plays = plays
        self.lastPlayedAt = lastPlayedAt
    }
}

/// A playlist as the Playlists page lists it.
public struct LibraryPlaylist: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var songCount: Int
    public var durationMs: Int64
    public var createdAt: Int64
    public var updatedAt: Int64
    public var coverArt: String?
    /// Kept with the server in use, not only on the phone.
    public var onServer: Bool
    /// The server's notice kind for its own lists ("review", "duplicates"), if any.
    public var notice: String?
    public var readonly: Bool
    /// The server's playlist, when it has one.
    public var server: Playlist?

    public init(id: String, name: String, songCount: Int = 0, durationMs: Int64 = 0, createdAt: Int64 = 0, updatedAt: Int64 = 0,
                coverArt: String? = nil, onServer: Bool = true, notice: String? = nil, readonly: Bool = false, server: Playlist? = nil) {
        self.id = id
        self.name = name
        self.songCount = songCount
        self.durationMs = durationMs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.coverArt = coverArt
        self.onServer = onServer
        self.notice = notice
        self.readonly = readonly
        self.server = server
    }
}

/// One row of a playlist: the song and its own id in the list, since a song can be there twice.
public struct PlaylistRow: Sendable, Hashable, Identifiable {
    public var itemId: Int64
    public var track: LibraryTrack
    /// A song the playlist names that this library does not hold.
    public var missing: Bool

    public var id: Int64 { itemId }

    public init(itemId: Int64, track: LibraryTrack, missing: Bool = false) {
        self.itemId = itemId
        self.track = track
        self.missing = missing
    }
}

/// A genre on the Genres page: its name, how many songs, and a cover from one of its songs.
public struct LibraryGenre: Sendable, Hashable, Identifiable {
    public var name: String
    public var songCount: Int
    public var albumCount: Int
    public var coverArt: String?
    public var id: String { name }

    public init(name: String, songCount: Int, albumCount: Int = 0, coverArt: String? = nil) {
        self.name = name
        self.songCount = songCount
        self.albumCount = albumCount
        self.coverArt = coverArt
    }
}
