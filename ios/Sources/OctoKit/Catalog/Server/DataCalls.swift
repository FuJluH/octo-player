import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The OpenSubsonic extension a server lists when it takes a call's params in a form body, so a
/// long list of songs fits in one call.
public let formPostExtension = "formPost"

/// How many song ids go in one call when they must fit in the address: 150 ids come to about
/// 5 KB, under the 8 KB most servers and proxies allow.
public let playlistSongsPerCall = 150

/// One call that changes a playlist. A param name may repeat.
public struct PlaylistCall: Sendable, Equatable {
    public var endpoint: String
    public var params: [Param]

    public struct Param: Sendable, Equatable {
        public var name: String
        public var value: String
        public init(_ name: String, _ value: String) {
            self.name = name
            self.value = value
        }
    }

    public init(_ endpoint: String, _ params: [Param]) {
        self.endpoint = endpoint
        self.params = params
    }
}

/// The songs split into the calls that carry them. With a form body they all go at once;
/// otherwise in batches. There is always at least one batch, so an empty list still makes its call.
public func songBatches(_ songIds: [String], formPost: Bool, perCall: Int = playlistSongsPerCall) -> [[String]] {
    if formPost || songIds.count <= perCall { return [songIds] }
    return songIds.catalogChunks(perCall).map(Array.init)
}

/// The calls that make a playlist's songs exactly these, in this order: createPlaylist with a
/// playlistId replaces the whole list; batches after the first are added with updatePlaylist.
public func replaceSongsCalls(_ playlistId: String, _ songIds: [String], formPost: Bool,
                              perCall: Int = playlistSongsPerCall) -> [PlaylistCall] {
    let batches = songBatches(songIds, formPost: formPost, perCall: perCall)
    let first = PlaylistCall("createPlaylist", [.init("playlistId", playlistId)] + batches[0].map { .init("songId", $0) })
    return [first] + addSongsCalls(playlistId, Array(batches.dropFirst()))
}

/// The calls that make a new playlist: the first batch goes with the name, and the rest are added
/// once the server says the new id.
public func createCalls(_ name: String, _ songIds: [String], formPost: Bool,
                        perCall: Int = playlistSongsPerCall) -> (first: PlaylistCall, rest: [[String]]) {
    let batches = songBatches(songIds, formPost: formPost, perCall: perCall)
    return (PlaylistCall("createPlaylist", [.init("name", name)] + batches[0].map { .init("songId", $0) }), Array(batches.dropFirst()))
}

/// One updatePlaylist call per batch, each adding its songs to the end.
public func addSongsCalls(_ playlistId: String, _ batches: [[String]]) -> [PlaylistCall] {
    batches.filter { !$0.isEmpty }.map { batch in
        PlaylistCall("updatePlaylist", [.init("playlistId", playlistId)] + batch.map { .init("songIdToAdd", $0) })
    }
}

/// The calls for updatePlaylist. Removals go by position in the list as it is before the call,
/// and may repeat; added songs go to the end. Songs past the first batch follow in calls of their own.
public func updateCalls(_ playlistId: String, name: String?, comment: String?, isPublic: Bool?, songIdsToAdd: [String],
                        songIndexesToRemove: [Int], formPost: Bool, perCall: Int = playlistSongsPerCall) -> [PlaylistCall] {
    let batches = songBatches(songIdsToAdd, formPost: formPost, perCall: perCall)
    var params: [PlaylistCall.Param] = [.init("playlistId", playlistId)]
    if let name { params.append(.init("name", name)) }
    if let comment { params.append(.init("comment", comment)) }
    if let isPublic { params.append(.init("public", isPublic ? "true" : "false")) }
    params += songIndexesToRemove.map { .init("songIndexToRemove", "\($0)") }
    params += batches[0].map { .init("songIdToAdd", $0) }
    return [PlaylistCall("updatePlaylist", params)] + addSongsCalls(playlistId, Array(batches.dropFirst()))
}

/// A playlist as the server lists it, with its songs when asked for one.
public struct ServerPlaylistInfo: Decodable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var comment: String?
    public var owner: String?
    public var isPublic: Bool
    public var songCount: Int
    public var duration: Int
    public var coverArt: String?
    public var changed: String?
    public var created: String?
    public var readonly: Bool
    public var validUntil: String?
    public var octoList: String?
    public var octoNotice: String?
    public var octoCoverTitle: String?
    public var entry: [Song]

    public init(id: String, name: String = "", owner: String? = nil, songCount: Int = 0, changed: String? = nil,
                created: String? = nil, readonly: Bool = false, octoList: String? = nil, octoNotice: String? = nil,
                coverArt: String? = nil, entry: [Song] = []) {
        self.id = id
        self.name = name
        self.owner = owner
        isPublic = false
        self.songCount = songCount
        duration = 0
        self.coverArt = coverArt
        self.changed = changed
        self.created = created
        self.readonly = readonly
        self.octoList = octoList
        self.octoNotice = octoNotice
        self.entry = entry
    }

    enum CodingKeys: String, CodingKey {
        case id, name, comment, owner, songCount, duration, coverArt, changed, created, readonly, validUntil
        case octoList, octoNotice, octoCoverTitle, entry
        case isPublic = "public"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.id(.id)
        name = c.string(.name) ?? ""
        comment = c.string(.comment)
        owner = c.string(.owner)
        isPublic = c.looseBool(.isPublic)
        songCount = c.int(.songCount) ?? 0
        duration = c.int(.duration) ?? 0
        coverArt = c.string(.coverArt)
        changed = c.string(.changed)
        created = c.string(.created)
        readonly = c.looseBool(.readonly)
        validUntil = c.string(.validUntil)
        octoList = c.string(.octoList)
        octoNotice = c.string(.octoNotice)
        octoCoverTitle = c.string(.octoCoverTitle)
        entry = (try? c.decodeIfPresent([Song].self, forKey: .entry)) ?? []
    }
}

/// The signed-in user as the server knows them.
public struct ServerUser: Decodable, Sendable, Equatable {
    public var username: String
    public var adminRole: Bool
    public var settingsRole: Bool
    public var scrobblingEnabled: Bool
    public var streamRole: Bool

    enum CodingKeys: String, CodingKey { case username, adminRole, settingsRole, scrobblingEnabled, streamRole }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = c.string(.username) ?? ""
        adminRole = c.bool(.adminRole) ?? false
        settingsRole = c.bool(.settingsRole) ?? true
        scrobblingEnabled = c.bool(.scrobblingEnabled) ?? false
        streamRole = c.bool(.streamRole) ?? true
    }
}

enum PlaylistsKey: PayloadName { static let name = "playlists" }
enum PlaylistKey: PayloadName { static let name = "playlist" }

struct FullPlaylists: Decodable {
    let playlist: [ServerPlaylistInfo]
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        playlist = (try? c.decodeIfPresent([ServerPlaylistInfo].self, forKey: AnyKey("playlist"))) ?? []
    }
}

extension SubsonicClient {
    /// Stars songs for the signed-in user, several in one call.
    public func star(songIds: [String]) async throws { try await call("star", songIds.map { ("id", $0) }) }
    public func unstar(songIds: [String]) async throws { try await call("unstar", songIds.map { ("id", $0) }) }
    /// Stars whole albums. On Octo an album found online is downloaded.
    public func star(albumIds: [String]) async throws { try await call("star", albumIds.map { ("albumId", $0) }) }
    public func unstar(albumIds: [String]) async throws { try await call("unstar", albumIds.map { ("albumId", $0) }) }
    /// Stars whole artists, as favorites.
    public func star(artistIds: [String]) async throws { try await call("star", artistIds.map { ("artistId", $0) }) }
    public func unstar(artistIds: [String]) async throws { try await call("unstar", artistIds.map { ("artistId", $0) }) }

    /// Rates a song, 1 to 5 stars; 0 takes the rating off.
    public func setRating(_ id: String, rating: Int) async throws {
        try await call("setRating", [("id", id), ("rating", "\(min(max(rating, 0), 5))")])
    }

    /// Tells the server a song was played (submission) or is playing now. The time is when it
    /// started, in milliseconds.
    public func scrobble(_ id: String, timeMs: Int64, submission: Bool) async throws {
        try await call("scrobble", [("id", id), ("time", "\(timeMs)"), ("submission", submission ? "true" : "false")])
    }

    /// The server's playlists with every field the phone keeps in step.
    public func fullPlaylists() async throws -> [ServerPlaylistInfo] {
        let body = try await get("getPlaylists", key: nil, as: Lenient<PlaylistsKey, FullPlaylists>.self)
        return body.value?.playlist ?? []
    }

    /// One playlist with its songs.
    public func fullPlaylist(_ id: String) async throws -> ServerPlaylistInfo {
        try await get("getPlaylist", [("id", id)], key: "playlist")
    }

    /// Makes a playlist with these songs in this order, and answers with it as the server now has
    /// it (nil from a server older than API 1.14, which sends nothing back).
    public func makePlaylist(name: String, songIds: [String], formPost: Bool = false) async throws -> ServerPlaylistInfo? {
        let (first, rest) = createCalls(name, songIds, formPost: formPost)
        let made = try await run(first, formPost: formPost, as: Lenient<PlaylistKey, ServerPlaylistInfo>.self).value
        if !rest.isEmpty {
            guard let id = made?.id else { throw OctoError.server(code: 0, message: "The server did not say the new playlist's id") }
            for call in addSongsCalls(id, rest) { try await runCall(call, formPost: formPost) }
        }
        return made
    }

    /// Makes a playlist's songs exactly these, in this order.
    public func replacePlaylistSongs(_ id: String, songIds: [String], formPost: Bool = false) async throws {
        for call in replaceSongsCalls(id, songIds, formPost: formPost) { try await runCall(call, formPost: formPost) }
    }

    /// Changes a playlist's details, takes songs out by their place (a place may repeat) and adds
    /// songs to the end. Only what is given changes.
    public func updatePlaylist(_ id: String, name: String? = nil, comment: String? = nil, isPublic: Bool? = nil,
                               songIdsToAdd: [String] = [], songIndexesToRemove: [Int] = [], formPost: Bool = false) async throws {
        for call in updateCalls(id, name: name, comment: comment, isPublic: isPublic, songIdsToAdd: songIdsToAdd,
                                songIndexesToRemove: songIndexesToRemove, formPost: formPost) {
            try await runCall(call, formPost: formPost)
        }
    }

    public func deletePlaylist(_ id: String) async throws { try await call("deletePlaylist", [("id", id)]) }

    /// The signed-in user, as the server knows them.
    public func user(_ username: String) async throws -> ServerUser {
        try await get("getUser", [("username", username)], key: "user")
    }

    private func runCall(_ call: PlaylistCall, formPost: Bool) async throws {
        _ = try await run(call, formPost: formPost, as: Empty.self)
    }

    /// Runs one playlist call, with its params in the address or in a form body.
    private func run<T: Decodable>(_ call: PlaylistCall, formPost: Bool, as type: T.Type) async throws -> T {
        let params = call.params.map { ($0.name, $0.value) }
        if !formPost { return try await get(call.endpoint, params, key: nil, as: type) }
        var post = request(url(call.endpoint))
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.httpBody = Data(params.map { name, value in
            "\(name.addingPercentEncoding(withAllowedCharacters: Self.queryValue) ?? name)="
                + (value.addingPercentEncoding(withAllowedCharacters: Self.queryValue) ?? value)
        }.joined(separator: "&").utf8)
        let (data, response) = try await session.data(for: post)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw OctoError.http(http.statusCode) }
        return try Self.decode(data, key: nil)
    }
}
