import Foundation

// The fuller shapes a library copy reads: everything a server says of a song, an album and an
// artist, OpenSubsonic extras included. Every field but the id has a default, so a server that
// leaves one out still decodes, and one odd field never stops a library from loading.

/// An artist as a song or album credits one.
public struct ArtistRef: Codable, Sendable, Hashable {
    public var id: String
    public var name: String

    public init(id: String = "", name: String = "") {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        name = c.string(.name) ?? ""
    }
}

/// A date an OpenSubsonic server sends in parts, any of which can be missing.
public struct ItemDate: Codable, Sendable, Hashable {
    public var year: Int?
    public var month: Int?
    public var day: Int?

    public init(year: Int? = nil, month: Int? = nil, day: Int? = nil) {
        self.year = year
        self.month = month
        self.day = day
    }

    enum CodingKeys: String, CodingKey { case year, month, day }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        year = c.int(.year)
        month = c.int(.month)
        day = c.int(.day)
    }
}

/// The name of one disc of an album, like "Live at Wembley".
public struct DiscTitle: Codable, Sendable, Hashable {
    public var disc: Int
    public var title: String

    public init(disc: Int = 0, title: String = "") {
        self.disc = disc
        self.title = title
    }

    enum CodingKeys: String, CodingKey { case disc, title }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        disc = c.int(.disc) ?? 0
        title = c.string(.title) ?? ""
    }
}

/// A song's loudness as an OpenSubsonic server sends it.
public struct SongReplayGain: Codable, Sendable, Hashable {
    public var trackGain: Float?
    public var albumGain: Float?
    public var trackPeak: Float?
    public var albumPeak: Float?
    public var baseGain: Float?
    public var fallbackGain: Float?

    public init(trackGain: Float? = nil, albumGain: Float? = nil, trackPeak: Float? = nil, albumPeak: Float? = nil,
                baseGain: Float? = nil, fallbackGain: Float? = nil) {
        self.trackGain = trackGain
        self.albumGain = albumGain
        self.trackPeak = trackPeak
        self.albumPeak = albumPeak
        self.baseGain = baseGain
        self.fallbackGain = fallbackGain
    }

    enum CodingKeys: String, CodingKey { case trackGain, albumGain, trackPeak, albumPeak, baseGain, fallbackGain }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func float(_ key: CodingKeys) -> Float? { (try? c.decodeIfPresent(Double.self, forKey: key)).flatMap { $0 }.map(Float.init) }
        trackGain = float(.trackGain)
        albumGain = float(.albumGain)
        trackPeak = float(.trackPeak)
        albumPeak = float(.albumPeak)
        baseGain = float(.baseGain)
        fallbackGain = float(.fallbackGain)
    }
}

/// A song with everything a library copy keeps.
public struct ServerSong: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String = ""
    public var album: String?
    public var albumId: String?
    public var artist: String?
    public var artistId: String?
    public var displayArtist: String?
    public var track: Int?
    public var discNumber: Int?
    public var year: Int?
    /// Seconds, 0 when unknown.
    public var duration: Int = 0
    public var coverArt: String?
    public var suffix: String?
    public var contentType: String?
    public var bitRate: Int?
    public var samplingRate: Int?
    public var bitDepth: Int?
    public var size: Int64?
    public var starred: String?
    public var displayAlbumArtist: String?
    public var genre: String?
    public var created: String?
    public var played: String?
    public var playCount: Int64?
    public var replayGain: SongReplayGain?
    public var userRating: Int?
    public var genres: [String] = []
    public var artists: [ArtistRef] = []
    public var albumArtists: [ArtistRef] = []
    public var sortName: String?
    public var musicBrainzId: String?
    public var bpm: Int?
    public var comment: String?
    public var displayComposer: String?
    public var explicitStatus: String?
    public var isrc: [String] = []
    public var parent: String?
    public var path: String?
    /// Octo: a song found online rather than a file in the library.
    public var isExternal: Bool = false
    /// Octo: which of its radio sources suggested this song.
    public var octoSuggestedBy: String?
    /// Octo, in a family: a song in the signed-in member's own library.
    public var octoPersonal: Bool = false

    public init(id: String, title: String = "", album: String? = nil, albumId: String? = nil, artist: String? = nil,
                artistId: String? = nil, displayArtist: String? = nil, track: Int? = nil, discNumber: Int? = nil,
                year: Int? = nil, duration: Int = 0, coverArt: String? = nil, suffix: String? = nil,
                contentType: String? = nil, bitRate: Int? = nil, samplingRate: Int? = nil, bitDepth: Int? = nil,
                size: Int64? = nil, starred: String? = nil, displayAlbumArtist: String? = nil, genre: String? = nil,
                created: String? = nil, played: String? = nil, playCount: Int64? = nil, replayGain: SongReplayGain? = nil,
                userRating: Int? = nil, genres: [String] = [], artists: [ArtistRef] = [], albumArtists: [ArtistRef] = [],
                sortName: String? = nil, musicBrainzId: String? = nil, bpm: Int? = nil, comment: String? = nil,
                displayComposer: String? = nil, explicitStatus: String? = nil, isrc: [String] = [], parent: String? = nil,
                path: String? = nil, isExternal: Bool = false, octoSuggestedBy: String? = nil, octoPersonal: Bool = false) {
        self.id = id
        self.title = title
        self.album = album
        self.albumId = albumId
        self.artist = artist
        self.artistId = artistId
        self.displayArtist = displayArtist
        self.track = track
        self.discNumber = discNumber
        self.year = year
        self.duration = duration
        self.coverArt = coverArt
        self.suffix = suffix
        self.contentType = contentType
        self.bitRate = bitRate
        self.samplingRate = samplingRate
        self.bitDepth = bitDepth
        self.size = size
        self.starred = starred
        self.displayAlbumArtist = displayAlbumArtist
        self.genre = genre
        self.created = created
        self.played = played
        self.playCount = playCount
        self.replayGain = replayGain
        self.userRating = userRating
        self.genres = genres
        self.artists = artists
        self.albumArtists = albumArtists
        self.sortName = sortName
        self.musicBrainzId = musicBrainzId
        self.bpm = bpm
        self.comment = comment
        self.displayComposer = displayComposer
        self.explicitStatus = explicitStatus
        self.isrc = isrc
        self.parent = parent
        self.path = path
        self.isExternal = isExternal
        self.octoSuggestedBy = octoSuggestedBy
        self.octoPersonal = octoPersonal
    }

    enum CodingKeys: String, CodingKey {
        case id, title, album, albumId, artist, artistId, displayArtist, track, discNumber, year, duration, coverArt, suffix
        case contentType, bitRate, samplingRate, bitDepth, size, starred, displayAlbumArtist, genre, created, played
        case playCount, replayGain, userRating, genres, artists, albumArtists, sortName, musicBrainzId, bpm, comment
        case displayComposer, explicitStatus, isrc, parent, path, isExternal, octoSuggestedBy, octoPersonal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        title = c.string(.title) ?? ""
        album = c.string(.album)
        albumId = c.string(.albumId)
        artist = c.string(.artist)
        artistId = c.string(.artistId)
        displayArtist = c.string(.displayArtist)
        track = c.int(.track)
        discNumber = c.int(.discNumber)
        year = c.int(.year)
        duration = c.int(.duration) ?? 0
        coverArt = c.string(.coverArt)
        suffix = c.string(.suffix)
        contentType = c.string(.contentType)
        bitRate = c.int(.bitRate)
        samplingRate = c.int(.samplingRate)
        bitDepth = c.int(.bitDepth)
        size = c.int(.size).map(Int64.init)
        starred = c.string(.starred)
        displayAlbumArtist = c.string(.displayAlbumArtist)
        genre = c.string(.genre)
        created = c.string(.created)
        played = c.string(.played)
        playCount = c.int(.playCount).map(Int64.init)
        replayGain = try? c.decodeIfPresent(SongReplayGain.self, forKey: .replayGain)
        userRating = c.int(.userRating)
        genres = c.genreNames(.genres)
        artists = (try? c.decodeIfPresent([ArtistRef].self, forKey: .artists)) ?? []
        albumArtists = (try? c.decodeIfPresent([ArtistRef].self, forKey: .albumArtists)) ?? []
        sortName = c.string(.sortName)
        musicBrainzId = c.string(.musicBrainzId)
        bpm = c.looseInt(.bpm)
        comment = c.string(.comment)
        displayComposer = c.string(.displayComposer)
        explicitStatus = c.string(.explicitStatus)
        isrc = c.looseStrings(.isrc)
        parent = c.string(.parent)
        path = c.string(.path)
        isExternal = c.looseBool(.isExternal)
        octoSuggestedBy = c.string(.octoSuggestedBy)
        octoPersonal = c.looseBool(.octoPersonal)
    }
}

/// An album with everything a library copy keeps.
public struct ServerAlbum: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String = ""
    public var artist: String = ""
    public var artistId: String?
    public var displayArtist: String?
    public var artists: [ArtistRef] = []
    public var coverArt: String?
    public var songCount: Int = 0
    public var duration: Int = 0
    public var year: Int?
    public var genre: String?
    public var created: String?
    public var played: String?
    public var playCount: Int64 = 0
    public var starred: String?
    public var isCompilation: Bool = false
    public var genres: [String] = []
    public var musicBrainzId: String?
    public var sortName: String?
    public var discTitles: [DiscTitle] = []
    public var originalReleaseDate: ItemDate?
    public var releaseDate: ItemDate?
    public var explicitStatus: String?
    public var releaseTypes: [String] = []
    public var isExternal: Bool = false
    public var ownedCount: Int?
    /// Only on `getAlbum`.
    public var song: [ServerSong] = []

    public init(id: String, name: String = "", artist: String = "", artistId: String? = nil, displayArtist: String? = nil,
                artists: [ArtistRef] = [], coverArt: String? = nil, songCount: Int = 0, duration: Int = 0, year: Int? = nil,
                genre: String? = nil, created: String? = nil, played: String? = nil, playCount: Int64 = 0,
                starred: String? = nil, isCompilation: Bool = false, genres: [String] = [], musicBrainzId: String? = nil,
                sortName: String? = nil, discTitles: [DiscTitle] = [], originalReleaseDate: ItemDate? = nil,
                releaseDate: ItemDate? = nil, explicitStatus: String? = nil, releaseTypes: [String] = [],
                isExternal: Bool = false, ownedCount: Int? = nil, song: [ServerSong] = []) {
        self.id = id
        self.name = name
        self.artist = artist
        self.artistId = artistId
        self.displayArtist = displayArtist
        self.artists = artists
        self.coverArt = coverArt
        self.songCount = songCount
        self.duration = duration
        self.year = year
        self.genre = genre
        self.created = created
        self.played = played
        self.playCount = playCount
        self.starred = starred
        self.isCompilation = isCompilation
        self.genres = genres
        self.musicBrainzId = musicBrainzId
        self.sortName = sortName
        self.discTitles = discTitles
        self.originalReleaseDate = originalReleaseDate
        self.releaseDate = releaseDate
        self.explicitStatus = explicitStatus
        self.releaseTypes = releaseTypes
        self.isExternal = isExternal
        self.ownedCount = ownedCount
        self.song = song
    }

    enum CodingKeys: String, CodingKey {
        case id, name, artist, artistId, displayArtist, artists, coverArt, songCount, duration, year, genre, created, played
        case playCount, starred, isCompilation, genres, musicBrainzId, sortName, discTitles, originalReleaseDate
        case releaseDate, explicitStatus, releaseTypes, isExternal, ownedCount, song
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        artist = c.string(.artist) ?? ""
        artistId = c.string(.artistId)
        displayArtist = c.string(.displayArtist)
        artists = (try? c.decodeIfPresent([ArtistRef].self, forKey: .artists)) ?? []
        coverArt = c.string(.coverArt)
        songCount = c.int(.songCount) ?? 0
        duration = c.int(.duration) ?? 0
        year = c.int(.year)
        genre = c.string(.genre)
        created = c.string(.created)
        played = c.string(.played)
        playCount = c.int(.playCount).map(Int64.init) ?? 0
        starred = c.string(.starred)
        isCompilation = c.looseBool(.isCompilation)
        genres = c.genreNames(.genres)
        musicBrainzId = c.string(.musicBrainzId)
        sortName = c.string(.sortName)
        discTitles = (try? c.decodeIfPresent([DiscTitle].self, forKey: .discTitles)) ?? []
        originalReleaseDate = try? c.decodeIfPresent(ItemDate.self, forKey: .originalReleaseDate)
        releaseDate = try? c.decodeIfPresent(ItemDate.self, forKey: .releaseDate)
        explicitStatus = c.string(.explicitStatus)
        releaseTypes = c.looseStrings(.releaseTypes)
        isExternal = c.looseBool(.isExternal)
        ownedCount = c.int(.ownedCount)
        song = (try? c.decodeIfPresent([ServerSong].self, forKey: .song)) ?? []
    }
}

/// An artist with what a library copy keeps.
public struct ServerArtist: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String = ""
    public var coverArt: String?
    public var albumCount: Int = 0
    public var starred: String?
    public var musicBrainzId: String?
    public var sortName: String?

    public init(id: String, name: String = "", coverArt: String? = nil, albumCount: Int = 0, starred: String? = nil,
                musicBrainzId: String? = nil, sortName: String? = nil) {
        self.id = id
        self.name = name
        self.coverArt = coverArt
        self.albumCount = albumCount
        self.starred = starred
        self.musicBrainzId = musicBrainzId
        self.sortName = sortName
    }

    enum CodingKeys: String, CodingKey { case id, name, coverArt, albumCount, starred, musicBrainzId, sortName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        coverArt = c.string(.coverArt)
        albumCount = c.int(.albumCount) ?? 0
        starred = c.string(.starred)
        musicBrainzId = c.string(.musicBrainzId)
        sortName = c.string(.sortName)
    }
}

/// Everything on a server, as it lists it.
public struct ServerLibrary: Sendable {
    public var songs: [ServerSong]
    public var albums: [ServerAlbum]
    public var artists: [ServerArtist]

    public init(_ songs: [ServerSong], _ albums: [ServerAlbum], _ artists: [ServerArtist]) {
        self.songs = songs
        self.albums = albums
        self.artists = artists
    }
}

extension ServerSong {
    /// The plain song the rest of the app plays and shows.
    public var plain: Song {
        var song = Song(id: id, title: title, artist: artist, album: album, albumId: albumId, duration: duration,
                        coverArt: coverArt, suffix: suffix, isExternal: isExternal)
        song.artistId = artistId
        song.displayArtist = displayArtist
        song.track = track
        song.discNumber = discNumber
        song.year = year
        song.contentType = contentType
        song.bitRate = bitRate
        song.samplingRate = samplingRate
        song.bitDepth = bitDepth
        song.starred = starred
        song.genre = genre
        song.explicitStatus = explicitStatus
        song.octoSuggestedBy = octoSuggestedBy
        return song
    }
}

extension KeyedDecodingContainer {
    /// Genre names, as OpenSubsonic sends them ([{"name": "Rock"}]) or as a plain list of names.
    func genreNames(_ key: Key) -> [String] {
        if let objects = try? decodeIfPresent([NamedValue].self, forKey: key) {
            return objects.compactMap { $0.name.map(trimmed) }.filter { !$0.isEmpty }
        }
        if let one = try? decodeIfPresent(NamedValue.self, forKey: key) {
            return [one.name].compactMap { $0.map(trimmed) }.filter { !$0.isEmpty }
        }
        return []
    }

    /// Text sent as a list or as one value. Blanks are dropped; anything else reads as nothing.
    func looseStrings(_ key: Key) -> [String] {
        if let list = try? decodeIfPresent([LooseText].self, forKey: key) {
            return list.compactMap(\.text).map(trimmed).filter { !$0.isEmpty }
        }
        if let one = try? decodeIfPresent(LooseText.self, forKey: key), let text = one.text {
            let clean = trimmed(text)
            return clean.isEmpty ? [] : [clean]
        }
        return []
    }

    /// A yes or no sent as a boolean or as text ("true"). Anything else reads as no.
    func looseBool(_ key: Key) -> Bool {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let text = try? decodeIfPresent(String.self, forKey: key) { return trimmed(text).lowercased() == "true" }
        return false
    }

    /// A whole number sent as a number or as text ("120", "120.5"), rounded. Anything that is not
    /// one reads as 0.
    func looseInt(_ key: Key) -> Int? {
        guard contains(key) else { return nil }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite { return Int(value.rounded()) }
        if let text = try? decodeIfPresent(String.self, forKey: key), let value = Double(trimmed(text)), value.isFinite {
            return Int(value.rounded())
        }
        return 0
    }
}

/// One genre object or a plain name.
private struct NamedValue: Decodable {
    let name: String?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            name = text
            return
        }
        let c = try decoder.container(keyedBy: AnyKey.self)
        name = try? c.decodeIfPresent(String.self, forKey: AnyKey("name"))
    }
}

/// A list item kept only when it is text.
private struct LooseText: Decodable {
    let text: String?

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        text = try? single.decode(String.self)
    }
}
