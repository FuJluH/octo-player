import Foundation

// The server's own controls beyond its library: who the user is, its folders, scans, who is
// listening, shared links and internet radio stations. Every field has a default, so a server
// that leaves one out still reads.

public struct ServerUser: Decodable, Sendable, Equatable {
    public var username: String
    public var adminRole: Bool
    /// Whether the user may change their own settings and password. A server that does not say lets them.
    public var settingsRole: Bool

    enum CodingKeys: String, CodingKey { case username, adminRole, settingsRole }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = c.string(.username) ?? ""
        adminRole = c.bool(.adminRole) ?? false
        settingsRole = c.bool(.settingsRole) ?? true
    }
}

/// A library folder. Servers send its id as a number or as a string, so it is kept as text.
public struct ServerFolder: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var name: String

    enum CodingKeys: String, CodingKey { case id, name }

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
    }
}

struct ServerFolders: Decodable {
    let musicFolder: [ServerFolder]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        musicFolder = c.list(AnyKey("musicFolder"))
    }
    init() { musicFolder = [] }
}

/// Whether the server is reading its music folders now, and how many songs it has counted.
public struct ScanStatus: Decodable, Sendable, Equatable {
    public var scanning: Bool
    public var count: Int64
    public var folderCount: Int64?
    public var lastScan: String?

    enum CodingKeys: String, CodingKey { case scanning, count, folderCount, lastScan }

    public init(scanning: Bool = false, count: Int64 = 0, folderCount: Int64? = nil, lastScan: String? = nil) {
        self.scanning = scanning
        self.count = count
        self.folderCount = folderCount
        self.lastScan = lastScan
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scanning = c.bool(.scanning) ?? false
        count = c.long(.count) ?? 0
        folderCount = c.long(.folderCount)
        lastScan = c.string(.lastScan)
    }
}

/// A song someone is playing right now, who they are, how many minutes ago it started, and on
/// which player.
public struct NowPlayingEntry: Decodable, Sendable, Equatable, Identifiable {
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

    public init(id: String, title: String = "", artist: String? = nil, username: String = "", minutesAgo: Int = 0,
                playerName: String? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.username = username
        self.minutesAgo = minutesAgo
        self.playerName = playerName
    }

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

struct NowPlayingList: Decodable {
    let entry: [NowPlayingEntry]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        entry = c.list(AnyKey("entry"))
    }
    init() { entry = [] }
}

/// A link anyone can open to listen to some songs or an album. `expires` is when it stops
/// working, missing for never; `visitCount` is how often it was opened.
public struct Share: Decodable, Sendable, Equatable, Identifiable {
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

    public init(id: String, url: String = "", description: String? = nil, expires: String? = nil, visitCount: Int = 0,
                entry: [Song] = []) {
        self.id = id
        self.url = url
        self.description = description
        self.expires = expires
        self.visitCount = visitCount
        self.entry = entry
    }

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
        entry = c.list(.entry)
    }
}

struct Shares: Decodable {
    let share: [Share]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        share = c.list(AnyKey("share"))
    }
    init() { share = [] }
}

/// An internet radio station with everything a server keeps about it, for editing.
public struct RadioStationDetails: Decodable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var streamUrl: String
    public var homePageUrl: String?
    public var coverArt: String?

    enum CodingKeys: String, CodingKey { case id, name, streamUrl, homePageUrl, coverArt }

    public init(id: String, name: String = "", streamUrl: String = "", homePageUrl: String? = nil, coverArt: String? = nil) {
        self.id = id
        self.name = name
        self.streamUrl = streamUrl
        self.homePageUrl = homePageUrl
        self.coverArt = coverArt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        streamUrl = c.string(.streamUrl) ?? ""
        homePageUrl = c.string(.homePageUrl)
        coverArt = c.string(.coverArt)
    }
}

struct RadioStationDetailsList: Decodable {
    let internetRadioStation: [RadioStationDetails]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        internetRadioStation = c.list(AnyKey("internetRadioStation"))
    }
    init() { internetRadioStation = [] }
}

/// The play queue a server keeps for the signed-in user. The older form names the current song
/// by id; the index-based form gives its place in the list.
public struct ServerPlayQueue: Decodable, Sendable, Equatable {
    public var entry: [Song]
    public var current: String?
    public var currentIndex: Int?
    public var position: Int64
    public var username: String?
    public var changed: String?
    public var changedBy: String?

    enum CodingKeys: String, CodingKey { case entry, current, currentIndex, position, username, changed, changedBy }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entry = c.list(.entry)
        current = c.string(.current)
        currentIndex = c.int(.currentIndex)
        position = c.long(.position) ?? 0
        username = c.string(.username)
        changed = c.string(.changed)
        changedBy = c.string(.changedBy)
    }

    init() {
        entry = []
        position = 0
    }
}

/// The OpenSubsonic extension for saving the queue by place in the list.
public let indexBasedQueue = "indexBasedQueue"

/// What a queue save sends: every song id in order, and where playback is. In the index-based
/// form the current song is its place in the list; otherwise it is the song's id. An empty
/// queue sends no current song.
public func queueSaveParams(_ ids: [String], currentIndex: Int, positionMs: Int64, indexBased: Bool) -> [(String, String)] {
    var params = ids.map { ("id", $0) }
    guard ids.indices.contains(currentIndex) else { return params }
    params.append(indexBased ? ("currentIndex", "\(currentIndex)") : ("current", ids[currentIndex]))
    params.append(("position", "\(max(0, positionMs))"))
    return params
}

/// What creating a share sends: the ids (songs, or one album), an optional description, and
/// when it expires, in milliseconds since 1970. No expiry means the link never expires.
public func shareParams(_ ids: [String], description: String?, expiresAtMs: Int64?) -> [(String, String)] {
    var params = ids.map { ("id", $0) }
    if let description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        params.append(("description", description))
    }
    if let expiresAtMs { params.append(("expires", "\(expiresAtMs)")) }
    return params
}

/// What adding or changing a radio station sends. A blank home page is left out.
public func stationParams(streamUrl: String, name: String, homepageUrl: String?) -> [(String, String)] {
    var params = [("streamUrl", streamUrl.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ("name", name.trimmingCharacters(in: .whitespacesAndNewlines))]
    if let home = homepageUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !home.isEmpty {
        params.append(("homepageUrl", home))
    }
    return params
}

extension SubsonicClient {
    public func user(_ username: String) async throws -> ServerUser {
        try await answer("getUser", [("username", username)], key: "user")
    }

    public func musicFolders() async throws -> [ServerFolder] {
        let folders: ServerFolders = try await answer("getMusicFolders", key: "musicFolders", fallback: ServerFolders())
        return folders.musicFolder
    }

    /// Asks the server to read its music folders again. Needs an admin.
    public func startScan() async throws -> ScanStatus {
        try await answer("startScan", key: "scanStatus", fallback: ScanStatus())
    }

    public func scanStatus() async throws -> ScanStatus {
        try await answer("getScanStatus", key: "scanStatus", fallback: ScanStatus())
    }

    /// What everyone on the server is playing right now.
    public func nowPlaying() async throws -> [NowPlayingEntry] {
        let list: NowPlayingList = try await answer("getNowPlaying", key: "nowPlaying", fallback: NowPlayingList())
        return list.entry
    }

    /// Makes a public link to songs or an album. A server with sharing switched off answers with an error.
    public func createShare(_ ids: [String], description: String? = nil, expiresAtMs: Int64? = nil) async throws -> Share {
        let shares: Shares = try await answer("createShare", shareParams(ids, description: description, expiresAtMs: expiresAtMs),
                                              key: "shares", fallback: Shares())
        guard let first = shares.share.first else { throw SubsonicError.server(code: 0, message: "The server made no share") }
        return first
    }

    /// The signed-in user's shares.
    public func shares() async throws -> [Share] {
        let shares: Shares = try await answer("getShares", key: "shares", fallback: Shares())
        return shares.share
    }

    public func deleteShare(_ id: String) async throws {
        try await answerOK("deleteShare", [("id", id)])
    }

    /// The radio stations with their home pages, for editing. Octo builds its stations the
    /// first time they are asked for after it starts, so the answer may take minutes.
    public func radioStationDetails() async throws -> [RadioStationDetails] {
        let list: RadioStationDetailsList = try await answer("getInternetRadioStations", key: "internetRadioStations",
                                                             fallback: RadioStationDetailsList(), timeout: 180)
        return list.internetRadioStation
    }

    public func createRadioStation(streamUrl: String, name: String, homepageUrl: String?) async throws {
        try await answerOK("createInternetRadioStation", stationParams(streamUrl: streamUrl, name: name, homepageUrl: homepageUrl))
    }

    public func updateRadioStation(id: String, streamUrl: String, name: String, homepageUrl: String?) async throws {
        try await answerOK("updateInternetRadioStation",
                           [("id", id)] + stationParams(streamUrl: streamUrl, name: name, homepageUrl: homepageUrl))
    }

    public func deleteRadioStation(_ id: String) async throws {
        try await answerOK("deleteInternetRadioStation", [("id", id)])
    }

    /// Gives a user a new password, in a form body, never in the address.
    public func changePassword(username: String, password: String) async throws {
        try await postForm("changePassword", [("username", username), ("password", password)])
    }

    /// A family member's own password, which the server checks against the current one. Every
    /// other app and device then needs the new one.
    public func changeFamilyPassword(current: String, next: String) async throws {
        try await postForm("changeFamilyPassword", [("current", current), ("next", next)])
    }

    /// The queue saved on the server, or nil when none is.
    public func playQueue(indexBased: Bool) async throws -> ServerPlayQueue? {
        let queue: ServerPlayQueue = try await answer(indexBased ? "getPlayQueueByIndex" : "getPlayQueue",
                                                key: indexBased ? "playQueueByIndex" : "playQueue", fallback: ServerPlayQueue())
        return queue.entry.isEmpty ? nil : queue
    }

    /// Saves the queue on the server.
    public func savePlayQueue(_ ids: [String], currentIndex: Int, positionMs: Int64, indexBased: Bool) async throws {
        try await answerOK(indexBased ? "savePlayQueueByIndex" : "savePlayQueue",
                           queueSaveParams(ids, currentIndex: currentIndex, positionMs: positionMs, indexBased: indexBased))
    }
}
