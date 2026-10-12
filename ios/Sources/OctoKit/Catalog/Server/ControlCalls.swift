import Foundation

/// Whether the server is reading its music folders now, and how many songs it has counted so far.
public struct ServerScanStatus: Decodable, Sendable, Equatable {
    public var scanning: Bool
    public var count: Int64
    public var folderCount: Int64?
    public var lastScan: String?

    enum CodingKeys: String, CodingKey { case scanning, count, folderCount, lastScan }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scanning = c.looseBool(.scanning)
        count = c.int(.count).map(Int64.init) ?? 0
        folderCount = c.int(.folderCount).map(Int64.init)
        lastScan = c.string(.lastScan)
    }

    public init(scanning: Bool = false, count: Int64 = 0) {
        self.scanning = scanning
        self.count = count
    }
}

/// A link anyone can open to listen to some songs or an album.
public struct ServerShare: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var url: String
    public var description: String?
    public var username: String?
    public var created: String?
    public var expires: String?
    public var lastVisited: String?
    public var visitCount: Int
    public var entry: [Song]

    enum CodingKeys: String, CodingKey { case id, url, description, username, created, expires, lastVisited, visitCount, entry }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        url = c.string(.url) ?? ""
        description = c.string(.description)
        username = c.string(.username)
        created = c.string(.created)
        expires = c.string(.expires)
        lastVisited = c.string(.lastVisited)
        visitCount = c.int(.visitCount) ?? 0
        entry = (try? c.decodeIfPresent([Song].self, forKey: .entry)) ?? []
    }
}

/// A song someone is playing right now, who they are, how many minutes ago it started, and on
/// which player.
public struct ServerNowPlaying: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var artist: String?
    public var album: String?
    public var coverArt: String?
    public var username: String
    public var minutesAgo: Int
    public var playerId: String?
    public var playerName: String?

    enum CodingKeys: String, CodingKey { case id, title, artist, album, coverArt, username, minutesAgo, playerId, playerName }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        title = c.string(.title) ?? ""
        artist = c.string(.artist)
        album = c.string(.album)
        coverArt = c.string(.coverArt)
        username = c.string(.username) ?? ""
        minutesAgo = c.int(.minutesAgo) ?? 0
        playerId = c.string(.playerId)
        playerName = c.string(.playerName)
    }
}

/// An internet radio station with everything a server keeps about it, for editing.
public struct ServerStationDetails: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var streamUrl: String
    public var homePageUrl: String?
    public var coverArt: String?

    enum CodingKeys: String, CodingKey { case id, name, streamUrl, homePageUrl, coverArt }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        streamUrl = c.string(.streamUrl) ?? ""
        homePageUrl = c.string(.homePageUrl)
        coverArt = c.string(.coverArt)
    }
}

/// A library folder. Servers send its id as a number or as a string, so it is kept as text.
public struct ServerMusicFolder: Decodable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String

    enum CodingKeys: String, CodingKey { case id, name }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
    }
}

enum ScanStatusKey: PayloadName { static let name = "scanStatus" }
enum SharesKey: PayloadName { static let name = "shares" }
enum NowPlayingKey: PayloadName { static let name = "nowPlaying" }
enum StationsKey: PayloadName { static let name = "internetRadioStations" }
enum MusicFoldersKey: PayloadName { static let name = "musicFolders" }

struct SharesBody: Decodable {
    let share: [ServerShare]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        share = (try? c.decodeIfPresent([ServerShare].self, forKey: AnyKey("share"))) ?? []
    }
}

struct NowPlayingBody: Decodable {
    let entry: [ServerNowPlaying]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        entry = (try? c.decodeIfPresent([ServerNowPlaying].self, forKey: AnyKey("entry"))) ?? []
    }
}

struct StationDetailsBody: Decodable {
    let internetRadioStation: [ServerStationDetails]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        internetRadioStation = (try? c.decodeIfPresent([ServerStationDetails].self, forKey: AnyKey("internetRadioStation"))) ?? []
    }
}

struct MusicFoldersBody: Decodable {
    let musicFolder: [ServerMusicFolder]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        musicFolder = (try? c.decodeIfPresent([ServerMusicFolder].self, forKey: AnyKey("musicFolder"))) ?? []
    }
}

/// What creating a share sends: the ids (songs, or one album), an optional description, and when
/// it expires, in milliseconds since 1970. No expiry means the link never expires.
public func serverShareParams(_ ids: [String], description: String?, expiresAtMs: Int64?) -> [(String, String)] {
    var params = ids.map { ("id", $0) }
    if let description, !trimmed(description).isEmpty { params.append(("description", description)) }
    if let expiresAtMs { params.append(("expires", "\(expiresAtMs)")) }
    return params
}

/// What adding or changing a radio station sends. A blank home page is left out.
public func serverStationParams(streamUrl: String, name: String, homepageUrl: String?) -> [(String, String)] {
    var params = [("streamUrl", trimmed(streamUrl)), ("name", trimmed(name))]
    if let homepageUrl, !trimmed(homepageUrl).isEmpty { params.append(("homepageUrl", trimmed(homepageUrl))) }
    return params
}

extension SubsonicClient {
    /// Asks the server to read its music folders again. Needs an admin.
    public func serverStartScan() async throws -> ServerScanStatus {
        try await get("startScan", key: nil, as: Lenient<ScanStatusKey, ServerScanStatus>.self).value ?? ServerScanStatus()
    }

    public func serverScanStatus() async throws -> ServerScanStatus {
        try await get("getScanStatus", key: nil, as: Lenient<ScanStatusKey, ServerScanStatus>.self).value ?? ServerScanStatus()
    }

    /// The signed-in user's shares.
    public func serverShares() async throws -> [ServerShare] {
        try await get("getShares", key: nil, as: Lenient<SharesKey, SharesBody>.self).value?.share ?? []
    }

    /// Makes a public link to songs or an album.
    public func serverCreateShare(_ ids: [String], description: String? = nil, expiresAtMs: Int64? = nil) async throws -> ServerShare {
        let body = try await get("createShare", serverShareParams(ids, description: description, expiresAtMs: expiresAtMs), key: nil,
                                 as: Lenient<SharesKey, SharesBody>.self)
        guard let share = body.value?.share.first else { throw OctoError.server(code: 0, message: "The server made no share") }
        return share
    }

    public func serverDeleteShare(_ id: String) async throws { try await call("deleteShare", [("id", id)]) }

    /// What everyone on the server is playing right now.
    public func serverNowPlaying() async throws -> [ServerNowPlaying] {
        try await get("getNowPlaying", key: nil, as: Lenient<NowPlayingKey, NowPlayingBody>.self).value?.entry ?? []
    }

    /// The radio stations with their home pages, for editing. Patient, as Octo builds its stations
    /// the first time they are asked for.
    public func serverStationDetails() async throws -> [ServerStationDetails] {
        try await get("getInternetRadioStations", key: nil, as: Lenient<StationsKey, StationDetailsBody>.self, timeout: 180)
            .value?.internetRadioStation ?? []
    }

    public func serverCreateStation(streamUrl: String, name: String, homepageUrl: String? = nil) async throws {
        try await call("createInternetRadioStation", serverStationParams(streamUrl: streamUrl, name: name, homepageUrl: homepageUrl))
    }

    public func serverUpdateStation(_ id: String, streamUrl: String, name: String, homepageUrl: String? = nil) async throws {
        try await call("updateInternetRadioStation", [("id", id)] + serverStationParams(streamUrl: streamUrl, name: name, homepageUrl: homepageUrl))
    }

    public func serverDeleteStation(_ id: String) async throws { try await call("deleteInternetRadioStation", [("id", id)]) }

    /// The library folders on the server. A server with several libraries lists each as a folder.
    public func serverMusicFolders() async throws -> [ServerMusicFolder] {
        try await get("getMusicFolders", key: nil, as: Lenient<MusicFoldersKey, MusicFoldersBody>.self).value?.musicFolder ?? []
    }
}
