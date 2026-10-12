import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The octoImports extension: the signed-in user's Spotify sign-in, their imported lists with
// what the library has of each, the trickle that fetches the rest, and (version 2) the services
// to bring music from and file and text imports. Field names are the server's.

public let octoImports = "octoImports"
/// The version that adds the services list and file and text imports.
public let octoImportsFiles = 2
/// The largest file importFile takes.
public let importFileMaxBytes: Int64 = 64 * 1024 * 1024

/// The services a person can bring their music from, and whether the server can sign in to Spotify.
public struct ImportServices: Decodable, Sendable, Equatable {
    public var services: [ImportServiceLink] = []
    public var spotifyConnect = false

    public init(services: [ImportServiceLink] = [], spotifyConnect: Bool = false) {
        self.services = services
        self.spotifyConnect = spotifyConnect
    }

    enum CodingKeys: String, CodingKey { case services, spotifyConnect }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        services = c.list(.services)
        spotifyConnect = c.bool(.spotifyConnect) ?? false
    }
}

/// One service: its name, the page that exports its lists to a file, and the words on that
/// page's tile for it.
public struct ImportServiceLink: Decodable, Sendable, Equatable, Hashable, Identifiable {
    public var id = ""
    public var name = ""
    public var exportUrl = ""
    public var tile = ""

    public init(id: String, name: String, exportUrl: String, tile: String) {
        self.id = id
        self.name = name
        self.exportUrl = exportUrl
        self.tile = tile
    }

    enum CodingKeys: String, CodingKey { case id, name, exportUrl, tile }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        name = c.string(.name) ?? ""
        exportUrl = c.string(.exportUrl) ?? ""
        tile = c.string(.tile) ?? ""
    }
}

/// The service id the server gives Spotify.
public let spotifyService = "spotify"

/// Everything the import view shows for the signed-in user.
public struct ImportOverview: Decodable, Sendable, Equatable {
    public var spotify = SpotifyStatus()
    public var reading = ImportReading()
    public var lists: [ImportListSummary] = []
    public var trickle = TrickleStatus()
    /// Why the server cannot tell which songs the library has, when it cannot.
    public var libraryProblem: String?
    /// Set only for a family member whose missing songs wait for approval.
    public var approval: ImportApproval?

    public init(approval: ImportApproval? = nil) { self.approval = approval }

    enum CodingKeys: String, CodingKey { case spotify, reading, lists, trickle, libraryProblem, approval }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spotify = c.object(.spotify) ?? SpotifyStatus()
        reading = c.object(.reading) ?? ImportReading()
        lists = c.list(.lists)
        trickle = c.object(.trickle) ?? TrickleStatus()
        libraryProblem = c.string(.libraryProblem)
        approval = c.object(.approval)
    }

    /// Whether anything is moving on the server, so the view asks again soon.
    public var moving: Bool { reading.busy || trickle.queued > 0 || trickle.downloading > 0 }
}

/// Who approves a family member's downloads before Octo fetches them.
public struct ImportApproval: Decodable, Sendable, Equatable {
    public var needed = false
    public var by: String?

    public init(needed: Bool = false, by: String? = nil) {
        self.needed = needed
        self.by = by
    }

    enum CodingKeys: String, CodingKey { case needed, by }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        needed = c.bool(.needed) ?? false
        by = c.string(.by)
    }
}

public struct SpotifyStatus: Decodable, Sendable, Equatable {
    public var configured = false
    public var connected = false
    public var account: String?
    public var problem: String?
    public var redirectUri = ""
    public var redirectProblem: String?
    public var octoFinishes = false
    public var endsUtc: String?

    public init(configured: Bool = false, connected: Bool = false, account: String? = nil, problem: String? = nil, redirectUri: String = "",
                redirectProblem: String? = nil, octoFinishes: Bool = false, endsUtc: String? = nil) {
        self.configured = configured
        self.connected = connected
        self.account = account
        self.problem = problem
        self.redirectUri = redirectUri
        self.redirectProblem = redirectProblem
        self.octoFinishes = octoFinishes
        self.endsUtc = endsUtc
    }

    enum CodingKeys: String, CodingKey { case configured, connected, account, problem, redirectUri, redirectProblem, octoFinishes, endsUtc }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        configured = c.bool(.configured) ?? false
        connected = c.bool(.connected) ?? false
        account = c.string(.account)
        problem = c.string(.problem)
        redirectUri = c.string(.redirectUri) ?? ""
        redirectProblem = c.string(.redirectProblem)
        octoFinishes = c.bool(.octoFinishes) ?? false
        endsUtc = c.string(.endsUtc)
    }
}

/// Reading lists from Spotify, which runs on the server after a sign-in.
public struct ImportReading: Decodable, Sendable, Equatable {
    public var busy = false
    public var step: String?
    public var error: String?
    public var finishedUtc: String?

    public init() {}

    enum CodingKeys: String, CodingKey { case busy, step, error, finishedUtc }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        busy = c.bool(.busy) ?? false
        step = c.string(.step)
        error = c.string(.error)
        finishedUtc = c.string(.finishedUtc)
    }
}

/// Where a list came from.
public enum ImportSource: String, Sendable {
    case spotifyLiked, spotifyPlaylist, link, file, unknown = ""

    public static func of(_ text: String?) -> ImportSource {
        guard let text, let found = ImportSource(rawValue: text), found != .unknown else { return .unknown }
        return found
    }
}

public struct ImportListSummary: Decodable, Sendable, Equatable, Identifiable {
    public var id = ""
    public var name = ""
    public var source = ""
    public var by: String?
    public var imageUrl: String?
    public var total = 0
    public var have = 0
    public var missing = 0
    public var queued = 0
    public var downloading = 0
    public var done = 0
    public var notFound = 0
    public var skipped = 0
    public var keepPlaylist = false
    public var playlistId: String?
    public var playlistNote: String?
    public var getMissing = false
    public var partial: String?
    public var gone = false
    public var canRefresh = false
    public var readUtc: String?
    public var matchedUtc: String?

    public init(id: String = "", name: String = "", source: String = "", by: String? = nil, total: Int = 0, have: Int = 0, missing: Int = 0,
                queued: Int = 0, downloading: Int = 0, notFound: Int = 0, getMissing: Bool = false, playlistId: String? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.by = by
        self.total = total
        self.have = have
        self.missing = missing
        self.queued = queued
        self.downloading = downloading
        self.notFound = notFound
        self.getMissing = getMissing
        self.playlistId = playlistId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, source, by, imageUrl, total, have, missing, queued, downloading, done, notFound, skipped, keepPlaylist
        case playlistId, playlistNote, getMissing, partial, gone, canRefresh, readUtc, matchedUtc
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        name = c.string(.name) ?? ""
        source = c.string(.source) ?? ""
        by = c.string(.by)
        imageUrl = c.string(.imageUrl)
        total = c.int(.total) ?? 0
        have = c.int(.have) ?? 0
        missing = c.int(.missing) ?? 0
        queued = c.int(.queued) ?? 0
        downloading = c.int(.downloading) ?? 0
        done = c.int(.done) ?? 0
        notFound = c.int(.notFound) ?? 0
        skipped = c.int(.skipped) ?? 0
        keepPlaylist = c.bool(.keepPlaylist) ?? false
        playlistId = c.string(.playlistId)
        playlistNote = c.string(.playlistNote)
        getMissing = c.bool(.getMissing) ?? false
        partial = c.string(.partial)
        gone = c.bool(.gone) ?? false
        canRefresh = c.bool(.canRefresh) ?? false
        readUtc = c.string(.readUtc)
        matchedUtc = c.string(.matchedUtc)
    }

    public var origin: ImportSource { .of(source) }
    /// How much of it the library has, 0 to 1.
    public var fraction: Double { total <= 0 ? 0 : min(1, max(0, Double(have) / Double(total))) }
    /// Songs on their way: waiting in the trickle or being fetched.
    public var coming: Int { queued + downloading }
}

/// Where one song of a list stands.
public enum ImportTrackState: String, Sendable {
    case have, missing, queued, downloading, done, notFound, skipped, unknown = ""

    public static func of(_ text: String?) -> ImportTrackState {
        guard let text, let found = ImportTrackState(rawValue: text), found != .unknown else { return .unknown }
        return found
    }

    /// Can be asked for: it is not there and nothing is fetching it.
    public var askable: Bool { self == .missing || self == .notFound || self == .skipped }
}

public struct ImportTrack: Decodable, Sendable, Equatable {
    public var key = ""
    public var title = ""
    public var artist = ""
    public var album: String?
    public var seconds: Int?
    public var state = ""
    public var detail: String?
    public var libraryId: String?
    public var progress: Double?
    public var updatedUtc: String?

    enum CodingKeys: String, CodingKey { case key, title, artist, album, seconds, state, detail, libraryId, progress, updatedUtc }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.string(.key) ?? ""
        title = c.string(.title) ?? ""
        artist = c.string(.artist) ?? ""
        album = c.string(.album)
        seconds = c.int(.seconds)
        state = c.string(.state) ?? ""
        detail = c.string(.detail)
        libraryId = c.string(.libraryId)
        progress = c.double(.progress)
        updatedUtc = c.string(.updatedUtc)
    }

    public var stage: ImportTrackState { .of(state) }
}

public struct ImportListDetail: Decodable, Sendable, Equatable {
    public var list = ImportListSummary()
    public var tracks: [ImportTrack] = []

    enum CodingKeys: String, CodingKey { case list, tracks }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        list = c.object(.list) ?? ImportListSummary()
        tracks = c.list(.tracks)
    }
}

/// What the trickle is doing for the signed-in user.
public enum TrickleState: String, Sendable {
    case idle, running, paused, off, yielding, waitingForSoulseek, unknown = ""

    public static func of(_ text: String?) -> TrickleState {
        guard let text, let found = TrickleState(rawValue: text), found != .unknown else { return .unknown }
        return found
    }
}

public struct TrickleStatus: Decodable, Sendable, Equatable {
    public var state = ""
    public var nextUtc: String?
    public var perHour = 0
    public var queued = 0
    public var downloading = 0
    public var done = 0
    public var notFound = 0
    public var skipped = 0
    public var current: ImportTrack?
    public var recent: [ImportTrack] = []
    public var next: [ImportTrack] = []

    public init(state: String = "", nextUtc: String? = nil, perHour: Int = 0, queued: Int = 0, done: Int = 0) {
        self.state = state
        self.nextUtc = nextUtc
        self.perHour = perHour
        self.queued = queued
        self.done = done
    }

    enum CodingKeys: String, CodingKey { case state, nextUtc, perHour, queued, downloading, done, notFound, skipped, current, recent, next }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = c.string(.state) ?? ""
        nextUtc = c.string(.nextUtc)
        perHour = c.int(.perHour) ?? 0
        queued = c.int(.queued) ?? 0
        downloading = c.int(.downloading) ?? 0
        done = c.int(.done) ?? 0
        notFound = c.int(.notFound) ?? 0
        skipped = c.int(.skipped) ?? 0
        current = c.object(.current)
        recent = c.list(.recent)
        next = c.list(.next)
    }

    public var stage: TrickleState { .of(state) }
}

/// What one import action did, in the server's words.
public struct ImportAnswer: Decodable, Sendable, Equatable {
    public var ok = false
    public var message = ""
    public var url: String?
    public var listId: String?
    public var count = 0

    public init(ok: Bool = false, message: String = "", url: String? = nil, listId: String? = nil) {
        self.ok = ok
        self.message = message
        self.url = url
        self.listId = listId
    }

    enum CodingKeys: String, CodingKey { case ok, message, url, listId, count }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = c.bool(.ok) ?? false
        message = c.string(.message) ?? ""
        url = c.string(.url)
        listId = c.string(.listId)
        count = c.int(.count) ?? 0
    }
}

/// The actions importAction knows.
public enum ImportActions {
    public static let connect = "connect"
    public static let finish = "finish"
    public static let disconnect = "disconnect"
    public static let read = "read"
    public static let addLink = "addLink"
    public static let playlist = "playlist"
    public static let fetch = "fetch"
    public static let songs = "songs"
    public static let refresh = "refresh"
    public static let remove = "remove"
    public static let pause = "pause"
    public static let resume = "resume"
    public static let retry = "retry"
    public static let skip = "skip"
    public static let clear = "clear"
}

/// The type a list file is sent as, by its name's ending.
public func importFileType(_ name: String) -> String {
    let ending = name.range(of: ".", options: .backwards).map { String(name[$0.upperBound...]).lowercased() } ?? ""
    switch ending {
    case "csv": return "text/csv"
    case "json": return "application/json"
    case "zip": return "application/zip"
    case "txt": return "text/plain"
    default: return "application/octet-stream"
    }
}

extension SubsonicClient {
    public func imports() async throws -> ImportOverview {
        try await answer("getImports", key: "imports", fallback: ImportOverview())
    }

    public func importList(_ id: String) async throws -> ImportListDetail {
        try await answer("getImport", [("id", id)], key: "import")
    }

    /// One import action, its parameters, and any song keys (the name repeats).
    public func importAction(_ action: String, _ params: [(String, String)] = [], keys: [String] = []) async throws -> ImportAnswer {
        try await answer("importAction", [("action", action)] + params + keys.map { ("key", $0) }, key: "importAction", fallback: ImportAnswer())
    }

    public func importServices() async throws -> ImportServices {
        try await answer("getImportServices", key: "importServices", fallback: ImportServices())
    }

    /// Sends a list file as a multipart form, its type by its name's ending.
    public func importFile(name: String, bytes: Data) async throws -> ImportAnswer {
        let boundary = "octo-" + UUID().uuidString
        var body = Data()
        let disposition = "Content-Disposition: form-data; name=\"file\"; filename=\"\(name.replacingOccurrences(of: "\"", with: "%22"))\""
        body.append(Data("--\(boundary)\r\n\(disposition)\r\nContent-Type: \(importFileType(name))\r\n\r\n".utf8))
        body.append(bytes)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = request(url("importFile", [("name", name)]), timeout: 180)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data = try await exchange(request, endpoint: "importFile")
        return try Self.read(data, key: "importAction", fallback: ImportAnswer())
    }

    /// Sends a typed or pasted list in a form body.
    public func importText(name: String, text: String) async throws -> ImportAnswer {
        let data = try await postForm("importText", [("name", name), ("text", text)], timeout: 180)
        return try Self.read(data, key: "importAction", fallback: ImportAnswer())
    }
}

// MARK: The loopback page that catches Spotify's answer

/// What a sign-in page sent the browser back with.
public struct LoopbackAnswer: Sendable, Equatable {
    public var code: String?
    public var state: String?
    public var error: String?

    public init(code: String?, state: String?, error: String?) {
        self.code = code
        self.state = state
        self.error = error
    }
}

/// The rules of the page on this device that catches a sign-in's answer.
public enum LoopbackRules {
    /// The host and path of a registered redirect a phone can catch: http, no port, a loopback
    /// address that is not called "localhost". Nil for any other.
    public static func usable(_ registered: String) -> (host: String, path: String)? {
        guard let parts = URLComponents(string: registered.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "http", parts.port == nil, let host = parts.host, !host.isEmpty,
              host.lowercased() != "localhost"
        else { return nil }
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard isLoopback(bare) else { return nil }
        return (host, parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath)
    }

    static func isLoopback(_ host: String) -> Bool {
        if host == "::1" || host == "0:0:0:0:0:0:0:1" { return true }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil } && parts.first == "127"
    }

    /// The answer in a request target like /callback?code=a&state=b, or nil for any other address.
    public static func parse(_ target: String, path: String) -> LoopbackAnswer? {
        let at = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard String(at[0]) == path else { return nil }
        var values: [String: String] = [:]
        if at.count > 1 {
            for part in at[1].split(separator: "&") where !part.isEmpty {
                let pieces = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                values[String(pieces[0])] = pieces.count > 1 ? decodeComponent(String(pieces[1])) : ""
            }
        }
        guard values["code"] != nil || values["error"] != nil else { return nil }
        return LoopbackAnswer(code: values["code"], state: values["state"], error: values["error"])
    }

    /// The whole HTTP answer for one browser request: the found answer, or nil for any other address.
    public static func respond(to requestLine: String, path: String) -> (answer: LoopbackAnswer?, response: Data) {
        let target = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
        let found = parse(target, path: path)
        let body = Data((found == nil ? notHere : (found?.error != nil ? refused : done)).utf8)
        let status = found == nil ? "404 Not Found" : "200 OK"
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return (found, Data(head.utf8) + body)
    }

    static func page(_ title: String, _ text: String) -> String {
        "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
            + "<title>\(title)</title><style>body{font:16px system-ui,sans-serif;background:#0d0f14;color:#e8e8ef;"
            + "display:grid;place-items:center;min-height:100vh;margin:0}main{max-width:26rem;padding:2rem}</style></head>"
            + "<body><main><h1>\(title)</h1><p>\(text)</p></main></body></html>"
    }

    static let done = page("Back to Octo", "Octo has Spotify's answer and is finishing the sign-in. You can close this page and go back to Octo.")
    static let refused = page("Spotify said no", "Spotify did not let Octo in. Go back to Octo to try again.")
    static let notHere = page("Nothing here", "This page only catches Spotify's answer for Octo.")
}

/// A page on this device catching a sign-in's answer, made by the app.
public protocol LoopbackCatcher: Sendable {
    /// The redirect to ask for: the registered one with this catcher's port added.
    var redirectUri: String { get }
    /// Waits for the browser to come back; nil when nothing came in time.
    func await(timeoutMs: Int) async -> LoopbackAnswer?
    func close()
}
