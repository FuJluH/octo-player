import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Family on an Octo server: one owner, members with their own libraries and devices, and the
// abilities the owner gives each of them. The server lists the octoFamily extension only while
// the owner has Family on. Every field has a default, and a value this app does not know (from
// a newer server) reads as the default.

/// The OpenSubsonic extension an Octo server lists while Family is on.
public let octoFamily = "octoFamily"

/// Who an account is in the family. Owner and CoAdmin manage it; Unmanaged is an account the
/// family rules do not touch.
public enum FamilyRole: String, CaseIterable, Sendable {
    case owner = "Owner", coAdmin = "CoAdmin", member = "Member", listener = "Listener", kid = "Kid", unmanaged = "Unmanaged"
}

/// A role by the name the server gives it, or nil for one this app does not know.
public func familyRole(_ name: String) -> FamilyRole? { FamilyRole(rawValue: name) }

/// What adding an outside song does for this account.
public enum AddToLibrary: String, CaseIterable, Sendable {
    case direct = "Direct", request = "Request", saveOnly = "SaveOnly"
}

/// The quality a copy is asked in, lowest first, so a limit can be compared.
public enum RequestQuality: String, CaseIterable, Sendable, Comparable {
    case mp3 = "Mp3", flac = "Flac", best = "Best"

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (a: Self, b: Self) -> Bool { a.order < b.order }

    /// Whether asking in this quality is within a limit of `max`.
    public func allowedUnder(_ max: RequestQuality) -> Bool { order <= max.order }
}

/// Where a device listens from: on the home network or away from it.
public enum FamilyPlace: String, Sendable {
    case home = "Home", away = "Away"
}

public enum FamilyRequestKind: String, Sendable {
    case song = "Song", album = "Album", upgrade = "Upgrade", importList = "Import", playlistAdd = "PlaylistAdd"
}

public enum FamilyRequestState: String, CaseIterable, Sendable {
    case pending = "Pending", approved = "Approved", declined = "Declined", cancelled = "Cancelled", done = "Done", failed = "Failed"
}

/// How a request that is Done was met.
public enum FamilyRequestOutcome: String, Sendable {
    case downloaded = "Downloaded", alreadyShared = "AlreadyShared", addedFromFamily = "AddedFromFamily"
}

/// The platform an Octo app runs on, as a sign-in hand-over names it.
public enum FamilyPlatform: String, Sendable {
    case android = "Android", windows = "Windows", macOS = "macOS", linux = "Linux", iOS = "iOS"

    public var wire: String { rawValue }
}

extension KeyedDecodingContainer {
    /// A value of a string-backed enum, or `fallback` when missing or unknown.
    func choice<T: RawRepresentable>(_ key: Key, _ fallback: T) -> T where T.RawValue == String {
        string(key).flatMap(T.init(rawValue:)) ?? fallback
    }
}

/// What the owner lets an account do. A limit of 0 means no limit, and a stream cap of 0 the original file.
public struct FamilyAbilities: Decodable, Sendable, Equatable {
    public var addToLibrary: AddToLibrary = .direct
    public var requestQuality: RequestQuality = .best
    public var autoApprove = false
    public var weeklyRequestLimit = 0
    public var streamCap = 0
    public var awayCap = 0
    public var away = true
    public var devicesAtOnce = 0
    public var downloadFiles = true
    public var offlineCopies = true
    public var share = true
    public var importPlaylists = true
    public var cleanOnly = false
    public var familyPlaylistsEdit = true
    public var manageFamily = false
    public var approveRequests = false
    public var storageLimitGb = 0
    public var instantFromFamily = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case addToLibrary, requestQuality, autoApprove, weeklyRequestLimit, streamCap, awayCap, away, devicesAtOnce
        case downloadFiles, offlineCopies, share, importPlaylists, cleanOnly, familyPlaylistsEdit, manageFamily
        case approveRequests, storageLimitGb, instantFromFamily
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        addToLibrary = c.choice(.addToLibrary, .direct)
        requestQuality = c.choice(.requestQuality, .best)
        autoApprove = c.bool(.autoApprove) ?? false
        weeklyRequestLimit = c.int(.weeklyRequestLimit) ?? 0
        streamCap = c.int(.streamCap) ?? 0
        awayCap = c.int(.awayCap) ?? 0
        away = c.bool(.away) ?? true
        devicesAtOnce = c.int(.devicesAtOnce) ?? 0
        downloadFiles = c.bool(.downloadFiles) ?? true
        offlineCopies = c.bool(.offlineCopies) ?? true
        share = c.bool(.share) ?? true
        importPlaylists = c.bool(.importPlaylists) ?? true
        cleanOnly = c.bool(.cleanOnly) ?? false
        familyPlaylistsEdit = c.bool(.familyPlaylistsEdit) ?? true
        manageFamily = c.bool(.manageFamily) ?? false
        approveRequests = c.bool(.approveRequests) ?? false
        storageLimitGb = c.int(.storageLimitGb) ?? 0
        instantFromFamily = c.bool(.instantFromFamily) ?? true
    }
}

/// The signed-in account as the family sees it.
public struct FamilyMe: Decodable, Sendable, Equatable {
    public var username = ""
    public var displayName = ""
    /// The role as the server names it; `role` reads it when this app knows it.
    public var roleName = FamilyRole.unmanaged.rawValue
    public var managed = false
    public var abilities = FamilyAbilities()
    public var requestsThisWeek = 0
    public var storageUsedBytes: Int64 = 0
    public var place: FamilyPlace = .home
    /// Nil for the owner and for unmanaged accounts.
    public var deviceId: String?
    public var quality = AccountQuality()

    public init() {}

    /// Nil for a role a newer server has and this app does not know yet.
    public var role: FamilyRole? { familyRole(roleName) }

    enum CodingKeys: String, CodingKey {
        case username, displayName, role, managed, abilities, requestsThisWeek, storageUsedBytes, place, deviceId, quality
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = c.string(.username) ?? ""
        displayName = c.string(.displayName) ?? ""
        roleName = c.string(.role) ?? FamilyRole.unmanaged.rawValue
        managed = c.bool(.managed) ?? false
        abilities = c.object(.abilities) ?? FamilyAbilities()
        requestsThisWeek = c.int(.requestsThisWeek) ?? 0
        storageUsedBytes = c.long(.storageUsedBytes) ?? 0
        place = c.choice(.place, .home)
        deviceId = c.string(.deviceId)
        quality = c.object(.quality) ?? AccountQuality()
    }
}

/// One member, as a manager sees them.
public struct FamilyMember: Decodable, Sendable, Equatable, Identifiable {
    public var username = ""
    public var displayName = ""
    public var roleName = FamilyRole.member.rawValue
    public var suspended = false
    public var devices = 0
    public var playingNow = false
    public var pendingRequests = 0
    public var storageUsedBytes: Int64 = 0
    public var storageLimitGb = 0

    public var id: String { username }
    public var role: FamilyRole? { familyRole(roleName) }

    public init(username: String = "", displayName: String = "", roleName: String = FamilyRole.member.rawValue) {
        self.username = username
        self.displayName = displayName
        self.roleName = roleName
    }

    enum CodingKeys: String, CodingKey {
        case username, displayName, role, suspended, devices, playingNow, pendingRequests, storageUsedBytes, storageLimitGb
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = c.string(.username) ?? ""
        displayName = c.string(.displayName) ?? ""
        roleName = c.string(.role) ?? FamilyRole.member.rawValue
        suspended = c.bool(.suspended) ?? false
        devices = c.int(.devices) ?? 0
        playingNow = c.bool(.playingNow) ?? false
        pendingRequests = c.int(.pendingRequests) ?? 0
        storageUsedBytes = c.long(.storageUsedBytes) ?? 0
        storageLimitGb = c.int(.storageLimitGb) ?? 0
    }
}

/// A join or invite link two ways: through the server's outside address, which works anywhere,
/// and through its home address. Never printed: it carries a code or an invite.
public struct FamilyLinkChoices: Decodable, Sendable, Equatable, CustomStringConvertible {
    public var anywhere: String?
    public var home: String?

    public init(anywhere: String? = nil, home: String? = nil) {
        self.anywhere = anywhere
        self.home = home
    }

    enum CodingKeys: String, CodingKey { case anywhere, home }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        anywhere = c.string(.anywhere)
        home = c.string(.home)
    }

    public var description: String { "FamilyLinkChoices(anywhere=\(anywhere != nil), home=\(home != nil))" }
}

/// What a manager sees of the whole family.
public struct FamilyManager: Decodable, Sendable, Equatable {
    public var members: [FamilyMember] = []
    public var pendingRequests = 0
    public var liveStreams = 0

    public init() {}

    enum CodingKeys: String, CodingKey { case members, pendingRequests, liveStreams }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        members = c.list(.members)
        pendingRequests = c.int(.pendingRequests) ?? 0
        liveStreams = c.int(.liveStreams) ?? 0
    }
}

/// getFamily's answer. `manager` is there only for accounts that manage the family.
public struct FamilyInfo: Decodable, Sendable, Equatable {
    public var me = FamilyMe()
    public var manager: FamilyManager?

    public init(me: FamilyMe = FamilyMe(), manager: FamilyManager? = nil) {
        self.me = me
        self.manager = manager
    }

    enum CodingKeys: String, CodingKey { case me, manager }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        me = c.object(.me) ?? FamilyMe()
        manager = c.object(.manager)
    }
}

/// One request for a copy: a song, an album, a better copy, an import list or a family playlist addition.
public struct FamilyRequest: Decodable, Sendable, Equatable, Identifiable {
    public var id = ""
    public var username = ""
    public var displayName = ""
    public var kind: FamilyRequestKind = .song
    public var target = ""
    public var title = ""
    public var artist = ""
    public var album = ""
    public var coverArt: String?
    public var quality: RequestQuality = .best
    public var state: FamilyRequestState = .pending
    public var created = ""
    public var decided: String?
    public var decidedBy: String?
    public var note = ""
    public var failure: String?
    public var librarySongId: String?
    /// Set once it is Done.
    public var outcome: FamilyRequestOutcome?

    public init(id: String = "", title: String = "", artist: String = "", target: String = "", state: FamilyRequestState = .pending,
                kind: FamilyRequestKind = .song, quality: RequestQuality = .best, note: String = "", failure: String? = nil,
                outcome: FamilyRequestOutcome? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.target = target
        self.state = state
        self.kind = kind
        self.quality = quality
        self.note = note
        self.failure = failure
        self.outcome = outcome
    }

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, kind, target, title, artist, album, coverArt, quality, state, created, decided, decidedBy
        case note, failure, librarySongId, outcome
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        username = c.string(.username) ?? ""
        displayName = c.string(.displayName) ?? ""
        kind = c.choice(.kind, .song)
        target = c.string(.target) ?? ""
        title = c.string(.title) ?? ""
        artist = c.string(.artist) ?? ""
        album = c.string(.album) ?? ""
        coverArt = c.string(.coverArt)
        quality = c.choice(.quality, .best)
        state = c.choice(.state, .pending)
        created = c.string(.created) ?? ""
        decided = c.string(.decided)
        decidedBy = c.string(.decidedBy)
        note = c.string(.note) ?? ""
        failure = c.string(.failure)
        librarySongId = c.string(.librarySongId)
        outcome = c.string(.outcome).flatMap(FamilyRequestOutcome.init(rawValue:))
    }
}

struct FamilyRequests: Decodable {
    let request: [FamilyRequest]
    init() { request = [] }
    init(from decoder: Decoder) throws {
        request = try decoder.container(keyedBy: AnyKey.self).list(AnyKey("request"))
    }
}

/// What a device is playing now.
public struct FamilyDevicePlaying: Decodable, Sendable, Equatable {
    public var songId = ""
    public var title = ""
    public var artist = ""

    public init(title: String = "", artist: String = "") {
        self.title = title
        self.artist = artist
    }

    enum CodingKeys: String, CodingKey { case songId, title, artist }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        songId = c.string(.songId) ?? ""
        title = c.string(.title) ?? ""
        artist = c.string(.artist) ?? ""
    }
}

/// One device the account signed in from, noticed by the server.
public struct FamilyDevice: Decodable, Sendable, Equatable, Identifiable {
    public var id = ""
    public var username = ""
    public var name = ""
    public var app = ""
    public var firstSeen = ""
    public var lastSeen = ""
    public var place: FamilyPlace = .home
    /// Nil while idle.
    public var playing: FamilyDevicePlaying?
    /// The device asking.
    public var current = false
    /// Who picks its audio quality.
    public var quality: QualityFollows = .account

    public init(id: String = "", name: String = "", app: String = "", place: FamilyPlace = .home, playing: FamilyDevicePlaying? = nil,
                current: Bool = false, quality: QualityFollows = .account) {
        self.id = id
        self.name = name
        self.app = app
        self.place = place
        self.playing = playing
        self.current = current
        self.quality = quality
    }

    enum CodingKeys: String, CodingKey { case id, username, name, app, firstSeen, lastSeen, place, playing, current, quality }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        username = c.string(.username) ?? ""
        name = c.string(.name) ?? ""
        app = c.string(.app) ?? ""
        firstSeen = c.string(.firstSeen) ?? ""
        lastSeen = c.string(.lastSeen) ?? ""
        place = c.choice(.place, .home)
        playing = c.object(.playing)
        current = c.bool(.current) ?? false
        quality = c.choice(.quality, .account)
    }
}

struct FamilyDevices: Decodable {
    let device: [FamilyDevice]
    init() { device = [] }
    init(from decoder: Decoder) throws {
        device = try decoder.container(keyedBy: AnyKey.self).list(AnyKey("device"))
    }
}

/// A member's one login: the username, and the server's addresses. It works in any Subsonic app.
public struct FamilyLogin: Decodable, Sendable, Equatable {
    public var username = ""
    public var servers = FamilyLinkChoices()
    public var anywhereAvailable = true
    /// Whether this member may listen away from home at all.
    public var awayAllowed = true

    public init(username: String = "", servers: FamilyLinkChoices = FamilyLinkChoices(), anywhereAvailable: Bool = true, awayAllowed: Bool = true) {
        self.username = username
        self.servers = servers
        self.anywhereAvailable = anywhereAvailable
        self.awayAllowed = awayAllowed
    }

    enum CodingKeys: String, CodingKey { case username, servers, anywhereAvailable, awayAllowed }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = c.string(.username) ?? ""
        servers = c.object(.servers) ?? FamilyLinkChoices()
        anywhereAvailable = c.bool(.anywhereAvailable) ?? true
        awayAllowed = c.bool(.awayAllowed) ?? true
    }
}

/// A sign-in hand-over just started on this device: its token, when it ends, the family page's
/// address each way (`links`) and the server's address each way (`servers`). Never printed.
public struct FamilySignInStart: Decodable, Sendable, Equatable, CustomStringConvertible {
    public var token = ""
    public var expires: String?
    public var links = FamilyLinkChoices()
    public var servers = FamilyLinkChoices()
    public var anywhereAvailable = true

    public init(token: String = "", expires: String? = nil, links: FamilyLinkChoices = FamilyLinkChoices(),
                servers: FamilyLinkChoices = FamilyLinkChoices(), anywhereAvailable: Bool = true) {
        self.token = token
        self.expires = expires
        self.links = links
        self.servers = servers
        self.anywhereAvailable = anywhereAvailable
    }

    enum CodingKeys: String, CodingKey { case token, expires, links, servers, anywhereAvailable }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = c.string(.token) ?? ""
        expires = c.string(.expires)
        links = c.object(.links) ?? FamilyLinkChoices()
        servers = c.object(.servers) ?? FamilyLinkChoices()
        anywhereAvailable = c.bool(.anywhereAvailable) ?? true
    }

    public var description: String { "FamilySignInStart(expires=\(expires ?? "null"))" }
}

/// A device that redeemed this device's hand-over and waits for an answer.
public struct FamilySignInPending: Decodable, Sendable, Equatable {
    public var id = ""
    public var deviceName = ""
    public var platform = ""

    public init(id: String = "", deviceName: String = "", platform: String = "") {
        self.id = id
        self.deviceName = deviceName
        self.platform = platform
    }

    enum CodingKeys: String, CodingKey { case id, deviceName, platform }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        deviceName = c.string(.deviceName) ?? ""
        platform = c.string(.platform) ?? ""
    }
}

struct FamilySignInRedeemed: Decodable {
    let id: String
    init(from decoder: Decoder) throws {
        id = (try? decoder.container(keyedBy: AnyKey.self))?.string(AnyKey("id")) ?? ""
    }
}

/// How a redeemed hand-over stands, from the new device's side.
public enum FamilySignInState: String, Sendable {
    case waiting = "Waiting", allowed = "Allowed", denied = "Denied", expired = "Expired"
}

public struct FamilySignInStatus: Decodable, Sendable, Equatable, CustomStringConvertible {
    public var state: FamilySignInState = .waiting
    public var box: String?

    public init(state: FamilySignInState = .waiting, box: String? = nil) {
        self.state = state
        self.box = box
    }

    enum CodingKeys: String, CodingKey { case state, box }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.choice(.state, .waiting)
        box = c.string(.box)
    }

    public var description: String { "FamilySignInStatus(state=\(state.rawValue))" }
}

// The family's Subsonic calls, each signed as every call this app makes.
extension SubsonicClient {
    /// The signed-in account's place in the family, with the whole family for a manager.
    public func family() async throws -> FamilyInfo {
        try await answer("getFamily", key: "family")
    }

    /// The signed-in account's requests, or with `all` every member's (managers only), optionally
    /// only those in one state.
    public func familyRequests(all: Bool = false, state: FamilyRequestState? = nil) async throws -> [FamilyRequest] {
        var params: [(String, String)] = []
        if all { params.append(("all", "true")) }
        if let state { params.append(("state", state.rawValue)) }
        let body: FamilyRequests = try await answer("getFamilyRequests", params, key: "familyRequests", fallback: FamilyRequests())
        return body.request
    }

    /// Asks for a copy of an outside song or album, or a better copy of a library song.
    public func requestCopy(_ id: String, quality: RequestQuality = .best, kind: FamilyRequestKind? = nil) async throws -> FamilyRequest {
        var params = [("id", id), ("quality", quality.rawValue)]
        if let kind { params.append(("kind", kind.rawValue)) }
        return try await answer("requestCopy", params, key: "familyRequest")
    }

    /// Takes back one of the signed-in account's own requests while it waits.
    public func cancelFamilyRequest(_ id: String) async throws -> FamilyRequest {
        try await answer("cancelFamilyRequest", [("id", id)], key: "familyRequest")
    }

    /// Approves or declines a member's request, with a note for them.
    public func decideFamilyRequest(_ id: String, approve: Bool, note: String? = nil) async throws -> FamilyRequest {
        var params = [("id", id), ("approve", approve ? "true" : "false")]
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { params.append(("note", note)) }
        return try await answer("decideFamilyRequest", params, key: "familyRequest")
    }

    /// The signed-in account's devices, or with `all` every member's (managers only).
    public func familyDevices(all: Bool = false) async throws -> [FamilyDevice] {
        let body: FamilyDevices = try await answer("getFamilyDevices", all ? [("all", "true")] : [], key: "familyDevices", fallback: FamilyDevices())
        return body.device
    }

    /// Takes a device off the account's list. It comes back if it signs in again.
    public func forgetFamilyDevice(_ id: String) async throws {
        try await answerOK("forgetFamilyDevice", [("id", id)])
    }

    /// The signed-in member's login, for the Your login card.
    public func familyLogin() async throws -> FamilyLogin {
        try await answer("getFamilyLogin", key: "familyLogin")
    }

    /// Takes a song out of the signed-in member's own library. The server refuses songs of the shared library.
    public func removeFromMyLibrary(_ id: String) async throws {
        try await answerOK("removeFromMyLibrary", [("id", id)])
    }

    /// Makes a family playlist every member can add to. `approveAdditions` (managers only) holds
    /// additions for a manager to approve.
    public func createFamilyPlaylist(name: String, approveAdditions: Bool = false) async throws -> Playlist {
        var params = [("name", name.trimmingCharacters(in: .whitespacesAndNewlines))]
        if approveAdditions { params.append(("approveAdditions", "true")) }
        return try await answer("createFamilyPlaylist", params, key: "playlist")
    }

    /// Starts handing this device's sign-in to the same person's other device.
    public func startFamilySignIn() async throws -> FamilySignInStart {
        try await answer("startFamilySignIn", key: "familySignIn")
    }

    /// The device that redeemed the token, or nil while none has.
    public func familySignInPending(token: String) async throws -> FamilySignInPending? {
        let pending: FamilySignInPending? = try await answerIfAny("getFamilySignInPending", [("token", token)], key: "familySignInPending")
        return pending.flatMap { $0.id.isEmpty ? nil : $0 }
    }

    /// Allows or denies the device that redeemed the token.
    public func decideFamilySignIn(token: String, allow: Bool) async throws {
        _ = try await exchange(request(url("decideFamilySignIn", [("token", token), ("allow", allow ? "true" : "false")])),
                               endpoint: "decideFamilySignIn")
    }

    /// The sealed sign-in for the allowed device, in a form body; the server cannot open it.
    public func putFamilySignInBox(token: String, box: String) async throws {
        try await postForm("putFamilySignInBox", [("token", token), ("box", box)])
    }
}

/// The new device's open calls: no sign-in goes with them.
public enum FamilyOpenCalls {
    /// Redeems the token from the QR code, naming this device, and answers the id to wait on.
    public static func redeem(server: URL, session: URLSession, token: String, deviceName: String, platform: FamilyPlatform,
                              headers: [String: String] = [:]) async throws -> String {
        let redeemed: FamilySignInRedeemed = try await openCall(
            server, session, "redeemFamilySignIn",
            [("token", token), ("deviceName", deviceName.trimmingCharacters(in: .whitespacesAndNewlines)), ("platform", platform.wire)],
            key: "familySignInRedeemed", headers: headers)
        return redeemed.id
    }

    /// How the redeemed hand-over stands, with the sealed sign-in once allowed.
    public static func status(server: URL, session: URLSession, id: String, headers: [String: String] = [:]) async throws -> FamilySignInStatus {
        try await openCall(server, session, "getFamilySignInRedeem", [("id", id)], key: "familySignInRedeem", headers: headers)
    }

    static func openCall<T: Decodable>(_ server: URL, _ session: URLSession, _ endpoint: String, _ params: [(String, String)],
                                       key: String, headers: [String: String]) async throws -> T {
        var parts = URLComponents(url: server.appendingPathComponent("rest").appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        let query = [("v", SubsonicClient.apiVersion), ("c", SubsonicClient.clientName), ("f", "json")] + params
        parts.percentEncodedQueryItems = query.map {
            URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: SubsonicClient.queryValue))
        }
        var request = URLRequest(url: parts.url!, timeoutInterval: 20)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SubsonicError(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.notSubsonic("HTTP \(http.statusCode) from \(endpoint)", status: http.statusCode)
        }
        return try SubsonicClient.read(data, key: key, fallback: nil)
    }
}
