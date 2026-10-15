import Foundation

// The Subsonic and OpenSubsonic shapes the app reads, with Octo's own extras.
// Every field but the id has a default, so a server that leaves one out still
// decodes; ids that come as numbers are read as strings.

public struct ServerInfo: Decodable, Sendable, Equatable {
    public var version: String
    public var type: String?
    public var serverVersion: String?
    public var openSubsonic: Bool

    enum CodingKeys: String, CodingKey { case version, type, serverVersion, openSubsonic }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = c.string(.version) ?? ""
        type = c.string(.type)
        serverVersion = c.string(.serverVersion)
        openSubsonic = c.bool(.openSubsonic) ?? false
    }

    public init(version: String, type: String? = nil, serverVersion: String? = nil, openSubsonic: Bool = false) {
        self.version = version
        self.type = type
        self.serverVersion = serverVersion
        self.openSubsonic = openSubsonic
    }
}

public struct Extension: Decodable, Sendable, Equatable {
    public var name: String
    public var versions: [Int]

    enum CodingKeys: String, CodingKey { case name, versions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.string(.name) ?? ""
        versions = (try? c.decode([Int].self, forKey: .versions)) ?? []
    }
}

public struct ReplayGain: Codable, Sendable, Hashable {
    public var trackGain: Double?
    public var albumGain: Double?
    public var trackPeak: Double?
    public var albumPeak: Double?
    public var baseGain: Double?
    public var fallbackGain: Double?
}

public struct Song: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var album: String?
    public var albumId: String?
    public var artist: String?
    public var artistId: String?
    public var displayArtist: String?
    public var track: Int?
    public var discNumber: Int?
    public var year: Int?
    /// Seconds, 0 when the server does not know.
    public var duration: Int
    public var coverArt: String?
    public var suffix: String?
    public var contentType: String?
    public var bitRate: Int?
    public var samplingRate: Int?
    public var bitDepth: Int?
    /// The size of the song's file on the server, in bytes, when it says.
    public var size: Int64?
    public var starred: String?
    public var genre: String?
    public var replayGain: ReplayGain?
    public var explicitStatus: String?
    /// Octo: a song it found online rather than a file in the library.
    public var isExternal: Bool
    /// Octo: which of its radio sources suggested this song.
    public var octoSuggestedBy: String?

    enum CodingKeys: String, CodingKey {
        case id, title, album, albumId, artist, artistId, displayArtist, track, discNumber, year, duration
        case coverArt, suffix, contentType, bitRate, samplingRate, bitDepth, size, starred, genre, replayGain, explicitStatus
        case isExternal, octoSuggestedBy
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
        size = c.int64(.size)
        starred = c.string(.starred)
        genre = c.string(.genre)
        replayGain = try? c.decodeIfPresent(ReplayGain.self, forKey: .replayGain)
        explicitStatus = c.string(.explicitStatus)
        isExternal = c.bool(.isExternal) ?? false
        octoSuggestedBy = c.string(.octoSuggestedBy)
    }

    public init(id: String, title: String, artist: String? = nil, album: String? = nil, albumId: String? = nil,
                duration: Int = 0, coverArt: String? = nil, suffix: String? = nil, isExternal: Bool = false) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.albumId = albumId
        self.duration = duration
        self.coverArt = coverArt
        self.suffix = suffix
        self.isExternal = isExternal
    }

    /// Who the song is by, as the server would show it.
    public var byline: String { displayArtist ?? artist ?? "" }
    public var isStarred: Bool { starred != nil }

    static let lossless: Set<String> = ["flac", "alac", "wav", "aif", "aiff", "ape", "wv", "dsf", "dff"]

    public var isLossless: Bool { Self.lossless.contains(suffix?.lowercased() ?? "") }

    /// The player's quality badge: "HI-RES" for lossless above 48 kHz, "LOSSLESS", or the codec.
    public var qualityLabel: String? {
        guard let suffix = suffix?.lowercased(), !suffix.isEmpty else { return nil }
        if isLossless { return (samplingRate ?? 0) > 48_000 ? "HI-RES" : "LOSSLESS" }
        return suffix.uppercased()
    }

    /// The badge's full words: "FLAC · 24-bit · 96 kHz" or "MP3 · 320 kbps".
    public var qualityDetail: String? {
        guard let suffix = suffix?.uppercased(), !suffix.isEmpty else { return nil }
        var parts = [suffix]
        if isLossless {
            if let bitDepth { parts.append("\(bitDepth)-bit") }
            if let samplingRate {
                let khz = Double(samplingRate) / 1000
                parts.append(khz == khz.rounded() ? "\(Int(khz)) kHz" : String(format: "%.1f kHz", khz))
            }
        } else if let bitRate {
            parts.append("\(bitRate) kbps")
        }
        return parts.joined(separator: " · ")
    }
}

public struct Album: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var artist: String
    public var artistId: String?
    public var displayArtist: String?
    public var coverArt: String?
    public var songCount: Int
    /// Seconds.
    public var duration: Int
    public var year: Int?
    public var genre: String?
    public var starred: String?
    public var isCompilation: Bool
    public var explicitStatus: String?
    /// Octo: an album found online, and how many of its songs the library has.
    public var isExternal: Bool
    public var ownedCount: Int?
    /// Only on `getAlbum`.
    public var song: [Song]
    /// Octo, only on `getAlbum`: the album's animated art, when the server already knows it.
    /// Missing says nothing either way; getAnimatedArt asks.
    public var animatedArt: AnimatedArt?

    enum CodingKeys: String, CodingKey {
        case id, name, artist, artistId, displayArtist, coverArt, songCount, duration, year, genre, starred
        case isCompilation, explicitStatus, isExternal, ownedCount, song, animatedArt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        artist = c.string(.artist) ?? ""
        artistId = c.string(.artistId)
        displayArtist = c.string(.displayArtist)
        coverArt = c.string(.coverArt)
        songCount = c.int(.songCount) ?? 0
        duration = c.int(.duration) ?? 0
        year = c.int(.year)
        genre = c.string(.genre)
        starred = c.string(.starred)
        isCompilation = c.bool(.isCompilation) ?? false
        explicitStatus = c.string(.explicitStatus)
        isExternal = c.bool(.isExternal) ?? false
        ownedCount = c.int(.ownedCount)
        song = (try? c.decodeIfPresent([Song].self, forKey: .song)) ?? []
        animatedArt = (try? c.decodeIfPresent(AnimatedArt.self, forKey: .animatedArt)) ?? nil
    }

    /// An album known only by what a song says of it, enough to open its page.
    public init(id: String, name: String, artist: String, coverArt: String? = nil) {
        self.id = id
        self.name = name
        self.artist = artist
        self.coverArt = coverArt
        songCount = 0
        duration = 0
        isCompilation = false
        isExternal = false
        song = []
    }

    public var byline: String { displayArtist ?? artist }
}

public struct Artist: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var coverArt: String?
    public var artistImageUrl: String?
    public var albumCount: Int
    public var starred: String?
    /// Only on `getArtist`.
    public var album: [Album]

    enum CodingKeys: String, CodingKey { case id, name, coverArt, artistImageUrl, albumCount, starred, album }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        coverArt = c.string(.coverArt)
        artistImageUrl = c.string(.artistImageUrl)
        albumCount = c.int(.albumCount) ?? 0
        starred = c.string(.starred)
        album = (try? c.decodeIfPresent([Album].self, forKey: .album)) ?? []
    }
}

public struct Playlist: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var comment: String?
    public var owner: String?
    public var songCount: Int
    public var duration: Int
    public var coverArt: String?
    public var readonly: Bool
    /// Octo: the kind of Made for you list this is.
    public var octoList: String?
    /// Octo: which notice list this is ("review", "duplicates").
    public var octoNotice: String?
    /// Octo: shorter words for the list's cover than its name.
    public var octoCoverTitle: String?
    /// Octo: what kind of list Octo made this ("genre", "decade", "year", "country", "artist",
    /// "chart", "forYou", "liked", "station"), for grouping its lists.
    public var octoGroup: String?
    /// Only on `getPlaylist`.
    public var entry: [Song]

    enum CodingKeys: String, CodingKey {
        case id, name, comment, owner, songCount, duration, coverArt, readonly, octoList, octoNotice, octoCoverTitle, octoGroup, entry
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        comment = c.string(.comment)
        owner = c.string(.owner)
        songCount = c.int(.songCount) ?? 0
        duration = c.int(.duration) ?? 0
        coverArt = c.string(.coverArt)
        readonly = c.bool(.readonly) ?? false
        octoList = c.string(.octoList)
        octoNotice = c.string(.octoNotice)
        octoCoverTitle = c.string(.octoCoverTitle)
        octoGroup = c.string(.octoGroup)
        entry = (try? c.decodeIfPresent([Song].self, forKey: .entry)) ?? []
    }
}

public struct SearchResult: Decodable, Sendable {
    public var artist: [Artist]
    public var album: [Album]
    public var song: [Song]

    enum CodingKeys: String, CodingKey { case artist, album, song }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist = (try? c.decodeIfPresent([Artist].self, forKey: .artist)) ?? []
        album = (try? c.decodeIfPresent([Album].self, forKey: .album)) ?? []
        song = (try? c.decodeIfPresent([Song].self, forKey: .song)) ?? []
    }

    public init(artist: [Artist] = [], album: [Album] = [], song: [Song] = []) {
        self.artist = artist
        self.album = album
        self.song = song
    }
}

/// The kinds of album list `getAlbumList2` takes.
public enum AlbumListType: String, Sendable {
    case newest, recent, frequent, random
    case alphabetical = "alphabeticalByName"
    case starred
}

/// The kinds of Made for you list, in the order Home shows them.
public let octoListKinds = ["liked", "newReleases", "rediscover", "deepCuts"]

// Lenient reads: a missing or mistyped field is nil rather than an error.
extension KeyedDecodingContainer {
    func string(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        return nil
    }

    func int(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s) }
        return nil
    }

    func int64(_ key: Key) -> Int64? {
        if let i = try? decodeIfPresent(Int64.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int64(exactly: d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int64(s) }
        return nil
    }

    func bool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s == "true" }
        return nil
    }

    func id(_ key: Key) throws -> String {
        guard let id = string(key) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "no id"))
        }
        return id
    }
}
