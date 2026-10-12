import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where plays go. The token is only ever sent here, over HTTPS.
public let listenBrainzAPI = URL(string: "https://api.listenbrainz.org/")!

/// Where the listener finds their token.
public let listenBrainzTokenPage = "https://listenbrainz.org/settings/"

/// ListenBrainz takes at most this many plays in one request.
public let maxListensPerRequest = 1_000

/// How many plays may wait. Past that the oldest are let go.
public let maxQueuedListens = 5_000

/// What the app calls itself to ListenBrainz.
public func listenBrainzUserAgent(version: String) -> String {
    "Octo/\(version) (iOS)"
}

/// One play as ListenBrainz hears it. `listenedAt` is when it started, in seconds; a length of
/// zero and a missing track number are left out. The MusicBrainz ids, where the song's tags or
/// server have them, let ListenBrainz link the play to the exact recording and release.
public struct Listen: Sendable, Hashable, Codable {
    public var listenedAt: Int64
    public var track: String
    public var artist: String
    public var album: String
    public var durationMs: Int64
    public var trackNumber: Int?
    public var recordingMbid: String?
    public var releaseMbid: String?
    public var releaseGroupMbid: String?
    public var artistMbids: [String]

    public init(listenedAt: Int64, track: String, artist: String, album: String = "", durationMs: Int64 = 0,
                trackNumber: Int? = nil, recordingMbid: String? = nil, releaseMbid: String? = nil,
                releaseGroupMbid: String? = nil, artistMbids: [String] = []) {
        self.listenedAt = listenedAt
        self.track = track
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.trackNumber = trackNumber
        self.recordingMbid = recordingMbid
        self.releaseMbid = releaseMbid
        self.releaseGroupMbid = releaseGroupMbid
        self.artistMbids = artistMbids
    }

    private enum CodingKeys: String, CodingKey {
        case listenedAt, track, artist, album, durationMs, trackNumber, recordingMbid, releaseMbid, releaseGroupMbid, artistMbids
    }

    /// Fields left out of the saved queue take their defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listenedAt = try c.decode(Int64.self, forKey: .listenedAt)
        track = try c.decode(String.self, forKey: .track)
        artist = try c.decode(String.self, forKey: .artist)
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        durationMs = try c.decodeIfPresent(Int64.self, forKey: .durationMs) ?? 0
        trackNumber = try c.decodeIfPresent(Int.self, forKey: .trackNumber)
        recordingMbid = try c.decodeIfPresent(String.self, forKey: .recordingMbid)
        releaseMbid = try c.decodeIfPresent(String.self, forKey: .releaseMbid)
        releaseGroupMbid = try c.decodeIfPresent(String.self, forKey: .releaseGroupMbid)
        artistMbids = try c.decodeIfPresent([String].self, forKey: .artistMbids) ?? []
    }

    /// Fields at their defaults are left out of the saved queue.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listenedAt, forKey: .listenedAt)
        try c.encode(track, forKey: .track)
        try c.encode(artist, forKey: .artist)
        if !album.isEmpty { try c.encode(album, forKey: .album) }
        if durationMs != 0 { try c.encode(durationMs, forKey: .durationMs) }
        try c.encodeIfPresent(trackNumber, forKey: .trackNumber)
        try c.encodeIfPresent(recordingMbid, forKey: .recordingMbid)
        try c.encodeIfPresent(releaseMbid, forKey: .releaseMbid)
        try c.encodeIfPresent(releaseGroupMbid, forKey: .releaseGroupMbid)
        if !artistMbids.isEmpty { try c.encode(artistMbids, forKey: .artistMbids) }
    }
}

/// What was played, as far as the app knows it, and whether the signed-in server hears the play too.
public struct PlayedSong: Sendable, Hashable {
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int64
    public var trackNumber: Int?
    public var reachesServer: Bool
    public var recordingMbid: String?
    public var releaseMbid: String?
    public var releaseGroupMbid: String?
    public var artistMbids: [String]

    public init(title: String, artist: String, album: String, durationMs: Int64, trackNumber: Int?, reachesServer: Bool,
                recordingMbid: String? = nil, releaseMbid: String? = nil, releaseGroupMbid: String? = nil,
                artistMbids: [String] = []) {
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.trackNumber = trackNumber
        self.reachesServer = reachesServer
        self.recordingMbid = recordingMbid
        self.releaseMbid = releaseMbid
        self.releaseGroupMbid = releaseGroupMbid
        self.artistMbids = artistMbids
    }

    /// The play that started at `startedAtMs`. Nil when the song has no title or artist, which
    /// ListenBrainz needs.
    public func listenAt(_ startedAtMs: Int64) -> Listen? {
        if trimmed(title).isEmpty || trimmed(artist).isEmpty { return nil }
        var seen = Set<String>()
        return Listen(
            listenedAt: startedAtMs / 1000,
            track: trimmed(title),
            artist: trimmed(artist),
            album: trimmed(album),
            durationMs: max(durationMs, 0),
            trackNumber: trackNumber.flatMap { $0 > 0 ? $0 : nil },
            recordingMbid: validMbid(recordingMbid),
            releaseMbid: validMbid(releaseMbid),
            releaseGroupMbid: validMbid(releaseGroupMbid),
            artistMbids: artistMbids.compactMap(validMbid).filter { seen.insert($0).inserted }
        )
    }
}

/// ListenBrainz refuses a whole request over one malformed id, so only well-formed ones go: 32
/// lowercase hex digits in groups of 8, 4, 4, 4 and 12.
public func validMbid(_ text: String?) -> String? {
    guard let text else { return nil }
    let id = trimmed(text).lowercased()
    let units = Array(id.utf8)
    guard units.count == 36 else { return nil }
    for (index, unit) in units.enumerated() {
        if [8, 13, 18, 23].contains(index) {
            guard unit == UInt8(ascii: "-") else { return nil }
        } else {
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(unit) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(unit)
            else { return nil }
        }
    }
    return id
}

/// Which plays are sent: all of them, or only those the server never hears, so a server that
/// passes its own plays on does not count them twice. The raw values are the stored choice.
public enum SendPlays: String, Sendable, CaseIterable {
    case all = "All"
    case phoneOnly = "PhoneOnly"
}

/// A play reaches the server when the song is a server song found online or has a copy on the
/// server, the same rule the server's play queue follows.
public func playReachesServer(_ trackId: String, copySources: [String]) -> Bool {
    isFind(trackId) || copySources.contains { $0.hasPrefix("server:") }
}

public func shouldSend(_ mode: SendPlays, reachesServer: Bool) -> Bool {
    mode == .all || !reachesServer
}

/// What makes two plays the same one in the queue.
private struct ListenKey: Hashable {
    let listenedAt: Int64
    let track: String
    let artist: String

    init(_ listen: Listen) {
        listenedAt = listen.listenedAt
        track = listen.track
        artist = listen.artist
    }
}

extension Array where Element == Listen {
    /// The queue with one more play: oldest first, each play once, and never more than the cap.
    public func plusListen(_ listen: Listen) -> [Listen] {
        if let quick = insertedInOrder(listen) { return quick }
        var seen = Set<ListenKey>()
        let distinct = (self + [listen]).filter { seen.insert(ListenKey($0)).inserted }
        let ordered = distinct.enumerated().sorted { a, b in
            a.element.listenedAt != b.element.listenedAt ? a.element.listenedAt < b.element.listenedAt : a.offset < b.offset
        }.map(\.element)
        return Array(ordered.suffix(maxQueuedListens))
    }

    /// The same answer without sorting again, for a queue already oldest first with each play
    /// once; nil for any other list.
    private func insertedInOrder(_ listen: Listen) -> [Listen]? {
        var runStart = 0
        for index in indices.dropFirst() {
            let before = self[index - 1].listenedAt
            let at = self[index].listenedAt
            if before > at { return nil }
            if before < at {
                runStart = index
                continue
            }
            if index - runStart > 16 { return nil }
            let key = ListenKey(self[index])
            if self[runStart..<index].contains(where: { ListenKey($0) == key }) { return nil }
        }
        // After every play that started at the same time or earlier.
        var low = 0
        var high = count
        while low < high {
            let middle = (low + high) / 2
            if self[middle].listenedAt <= listen.listenedAt { low = middle + 1 } else { high = middle }
        }
        let key = ListenKey(listen)
        var check = low - 1
        while check >= 0 && self[check].listenedAt == listen.listenedAt {
            if ListenKey(self[check]) == key { return Array(suffix(maxQueuedListens)) }
            check -= 1
        }
        var next = self
        next.insert(listen, at: low)
        return Array(next.suffix(maxQueuedListens))
    }

    /// The queue without plays that were sent (or refused).
    public func removingListens(_ done: [Listen]) -> [Listen] {
        let gone = Set(done)
        return filter { !gone.contains($0) }
    }
}

/// The plays the next request carries: the oldest, up to the limit.
public func nextBatch(_ queue: [Listen]) -> [Listen] {
    Array(queue.prefix(maxListensPerRequest))
}

/// "single" for one play, "import" for several.
public func listenType(_ count: Int) -> String {
    count == 1 ? "single" : "import"
}

/// How long to wait after this many failures in a row: 30 seconds, doubling each time, and never
/// more than six hours.
public func retryDelayMs(_ failures: Int) -> Int64 {
    if failures <= 0 { return 0 }
    let steps = Swift.min(failures - 1, 20)
    return Swift.min(Int64(30_000) << Int64(steps), 6 * 60 * 60 * 1000)
}

private struct ListensBody: Encodable {
    let listenType: String
    let payload: [ListenEntry]

    enum CodingKeys: String, CodingKey {
        case listenType = "listen_type"
        case payload
    }
}

private struct ListenEntry: Encodable {
    let listenedAt: Int64?
    let trackMetadata: TrackMetadata

    enum CodingKeys: String, CodingKey {
        case listenedAt = "listened_at"
        case trackMetadata = "track_metadata"
    }
}

private struct TrackMetadata: Encodable {
    let artistName: String
    let trackName: String
    let releaseName: String?
    let additionalInfo: AdditionalInfo

    enum CodingKeys: String, CodingKey {
        case artistName = "artist_name"
        case trackName = "track_name"
        case releaseName = "release_name"
        case additionalInfo = "additional_info"
    }
}

private struct AdditionalInfo: Encodable {
    let mediaPlayer: String
    let mediaPlayerVersion: String
    let submissionClient: String
    let submissionClientVersion: String
    let durationMs: Int64?
    /// A string, as ListenBrainz documents it.
    let trackNumber: String?
    let recordingMbid: String?
    let releaseMbid: String?
    let releaseGroupMbid: String?
    let artistMbids: [String]?

    enum CodingKeys: String, CodingKey {
        case mediaPlayer = "media_player"
        case mediaPlayerVersion = "media_player_version"
        case submissionClient = "submission_client"
        case submissionClientVersion = "submission_client_version"
        case durationMs = "duration_ms"
        case trackNumber = "tracknumber"
        case recordingMbid = "recording_mbid"
        case releaseMbid = "release_mbid"
        case releaseGroupMbid = "release_group_mbid"
        case artistMbids = "artist_mbids"
    }
}

/// The request body for these plays, as JSON. Now playing carries no time.
public func listensJSON(type: String, listens: [Listen], clientVersion: String) -> Data {
    let body = ListensBody(listenType: type, payload: listens.map { listen in
        ListenEntry(
            listenedAt: type != "playing_now" ? listen.listenedAt : nil,
            trackMetadata: TrackMetadata(
                artistName: listen.artist,
                trackName: listen.track,
                releaseName: trimmed(listen.album).isEmpty ? nil : listen.album,
                additionalInfo: AdditionalInfo(
                    mediaPlayer: "Octo",
                    mediaPlayerVersion: clientVersion,
                    submissionClient: "Octo",
                    submissionClientVersion: clientVersion,
                    durationMs: listen.durationMs > 0 ? listen.durationMs : nil,
                    trackNumber: listen.trackNumber.map { String($0) },
                    recordingMbid: listen.recordingMbid,
                    releaseMbid: listen.releaseMbid,
                    releaseGroupMbid: listen.releaseGroupMbid,
                    artistMbids: listen.artistMbids.isEmpty ? nil : listen.artistMbids
                )
            )
        )
    })
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    return (try? encoder.encode(body)) ?? Data()
}

/// ListenBrainz asks for no more than one call a second, and says in each answer how many calls
/// are left and when the count starts over. Times are in milliseconds from `clock`.
public final class RateLimits: @unchecked Sendable {
    private static let minGapMs: Int64 = 1_000

    private let clock: @Sendable () -> Int64
    private let lock = NSLock()
    private var lastCallAt = Int64.min / 2
    private var blockedUntil: Int64 = 0

    public init(clock: @escaping @Sendable () -> Int64 = { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }) {
        self.clock = clock
    }

    /// How long to wait before the next call.
    public func waitMs() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return waitLocked(clock())
    }

    /// How long until the current window ends, when no calls are left in it.
    public func blockedMs() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return Swift.max(blockedUntil &- clock(), 0)
    }

    public func called() {
        lock.lock()
        defer { lock.unlock() }
        lastCallAt = clock()
    }

    /// What an answer said. Nothing left means waiting for the window to end.
    public func heard(remaining: Int?, resetInSeconds: Int64?) {
        lock.lock()
        defer { lock.unlock() }
        if let remaining, remaining <= 0, let resetInSeconds { blockedUntil = clock() &+ resetInSeconds &* 1000 }
    }

    /// A 429: nothing more until the window ends.
    public func refused(retryInMs: Int64) {
        lock.lock()
        defer { lock.unlock() }
        blockedUntil = clock() &+ retryInMs
    }

    /// Takes the next turn at calling: how long to wait first. The call counts as made once that
    /// wait is over, so calls taking turns at once still go out a second apart.
    func takeTurn() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let now = clock()
        let wait = waitLocked(now)
        lastCallAt = now &+ wait
        return wait
    }

    private func waitLocked(_ now: Int64) -> Int64 {
        Swift.max(lastCallAt &+ Self.minGapMs &- now, blockedUntil &- now, 0)
    }
}

/// Whether a token is good, and whose it is.
public enum TokenCheck: Sendable, Equatable {
    case valid(user: String)
    case invalid
    case unreachable
}

/// What came of sending plays.
public enum SubmitResult: Sendable, Equatable {
    case sent
    /// The token is no longer accepted.
    case unauthorized
    /// ListenBrainz refused what was sent; sending it again would not help.
    case rejected
    /// Too many calls; try again after this long.
    case rateLimited(retryInMs: Int64)
    /// Could not reach ListenBrainz, or it had a problem of its own.
    case failed
}

/// Why a ListenBrainz call was not made.
public enum ListenBrainzError: Error, Equatable {
    /// The address is not ListenBrainz's, so the token would have gone somewhere else.
    case notListenBrainz
    /// A request holds 1 to 1 000 plays.
    case batchSize(Int)
}

/// A token is letters, digits and dashes. Anything else is not one, and would not be a valid
/// header either.
public func looksLikeToken(_ token: String) -> Bool {
    let units = token.utf16
    guard (8...128).contains(units.count) else { return false }
    return units.allSatisfy { unit in
        (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit) || unit == 0x2D
    }
}

/// A pasted token without the spaces around it.
public func cleanListenBrainzToken(_ text: String) -> String {
    trimmed(text)
}

private func listenBrainzAddress(_ path: String, _ base: URL) -> URL {
    URL(string: path, relativeTo: base)?.absoluteURL ?? base.appendingPathComponent(path)
}

/// The request that asks whether a token is good. The token goes in a header, never the address.
public func listenBrainzValidateRequest(token: String, base: URL = listenBrainzAPI) -> URLRequest {
    var request = URLRequest(url: listenBrainzAddress("1/validate-token", base))
    request.httpMethod = "GET"
    request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
    return request
}

/// The request that sends plays, with a body from `listensJSON`.
public func listenBrainzSubmitRequest(token: String, body: Data, base: URL = listenBrainzAPI) -> URLRequest {
    var request = URLRequest(url: listenBrainzAddress("1/submit-listens", base))
    request.httpMethod = "POST"
    request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return request
}

/// A JSON value read loosely, for the few fields an answer is checked for.
private enum LooseJSON: Decodable {
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case null
    case other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let value = try? c.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? c.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? c.decode(Double.self) {
            self = .number(value)
        } else if let value = try? c.decode(String.self) {
            self = .string(value)
        } else {
            self = .other
        }
    }

    /// The value as text, nil for null or for an object or list.
    var text: String? {
        switch self {
        case .bool(let value): "\(value)"
        case .integer(let value): "\(value)"
        case .number(let value): "\(value)"
        case .string(let value): value
        case .null, .other: nil
        }
    }
}

/// What a validate-token answer says: whose the token is when ListenBrainz knows it, invalid when
/// it does not, unreachable when it could not say.
public func tokenCheckOf(status: Int, body: Data) -> TokenCheck {
    switch status {
    case 200:
        let fields = try? JSONDecoder().decode([String: LooseJSON].self, from: body)
        let valid = fields?["valid"]?.text == "true"
        let user = fields?["user_name"]?.text
        if valid, let user, !trimmed(user).isEmpty { return .valid(user: user) }
        return .invalid
    case 400, 401:
        return .invalid
    default:
        return .unreachable
    }
}

/// What a submit-listens answer says to do next.
public func submitResultOf(status: Int, retryInMs: Int64) -> SubmitResult {
    switch status {
    case 200..<300: .sent
    case 401: .unauthorized
    case 400, 413: .rejected
    case 429: .rateLimited(retryInMs: retryInMs)
    default: .failed
    }
}

/// How long to wait after a refusal: the time ListenBrainz gave, else 10 seconds, kept between
/// 1 second and an hour.
public func listenBrainzRetryInMs(resetInSeconds: Int64?) -> Int64 {
    Swift.min(Swift.max(resetInSeconds ?? 10, 1), 60 * 60) * 1000
}

/// The rate limit headers of an answer: calls left in the window, and seconds until it ends.
public struct RateLimitHeaders: Sendable, Equatable {
    public var remaining: Int?
    public var resetInSeconds: Int64?

    public init(remaining: Int?, resetInSeconds: Int64?) {
        self.remaining = remaining
        self.resetInSeconds = resetInSeconds
    }

    public init(_ response: HTTPURLResponse) {
        remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap { kotlinInt(trimmed($0)) }
        resetInSeconds = response.value(forHTTPHeaderField: "X-RateLimit-Reset-In").flatMap { headerLong(trimmed($0)) }
    }
}

/// A whole number written plainly, with an optional sign.
private func headerLong(_ text: String) -> Int64? {
    var digits = Substring(text)
    if digits.first == "+" || digits.first == "-" { digits = digits.dropFirst() }
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return Int64(text)
}

/// Pauses for `ms` milliseconds.
@usableFromInline
func listeningPauseMs(_ ms: Int64) async throws {
    try await Task.sleep(nanoseconds: UInt64(Swift.min(Swift.max(ms, 0), Int64.max / 1_000_000)) * 1_000_000)
}

/// Refuses to follow a redirect, so a request never goes anywhere it was not sent; the redirect
/// answer itself comes back instead.
final class ListenBrainzNoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// The connection to ListenBrainz, apart from the one to the signed-in server: none of its extra
/// headers, cookies, stored credentials or client certificate. It only ever talks to `allowed`
/// (scheme, host and port), never follows a redirect, and names the app in User-Agent.
public final class ListenBrainzClient: Sendable {
    public let userAgent: String
    public let allowed: URL
    let session: URLSession

    public init(userAgent: String, allowed: URL = listenBrainzAPI, configuration: URLSessionConfiguration = .ephemeral) {
        self.userAgent = userAgent
        self.allowed = allowed
        let own = (configuration.copy() as? URLSessionConfiguration) ?? .ephemeral
        own.httpAdditionalHeaders = nil
        own.httpCookieStorage = nil
        own.httpShouldSetCookies = false
        own.urlCredentialStorage = nil
        own.urlCache = nil
        own.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: own, delegate: ListenBrainzNoRedirects(), delegateQueue: nil)
    }

    deinit {
        session.finishTasksAndInvalidate()
    }

    /// Whether an address is the one this client talks to.
    public func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(),
              scheme == allowed.scheme?.lowercased(), host == allowed.host?.lowercased() else { return false }
        return Self.port(of: url) == Self.port(of: allowed)
    }

    private static func port(of url: URL) -> Int {
        if let port = url.port { return port }
        switch url.scheme?.lowercased() {
        case "https": return 443
        case "http": return 80
        default: return -1
        }
    }

    /// Makes one request, refused before anything is sent when it is not for `allowed`.
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, isAllowed(url) else { throw ListenBrainzError.notListenBrainz }
        var outgoing = request
        outgoing.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: outgoing)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if let landed = http.url, !isAllowed(landed) { throw ListenBrainzError.notListenBrainz }
        return (data, http)
    }
}

/// Talks to ListenBrainz. Tokens are passed in for each call and never kept, printed or put in an
/// address. Calls take turns at the rate check, so two never go out together. Each call throws
/// only when the work is stopped, or for a batch of the wrong size.
public final class ListenBrainzApi: Sendable {
    public let client: ListenBrainzClient
    public let base: URL
    public let limits: RateLimits
    private let pause: @Sendable (Int64) async throws -> Void

    public init(client: ListenBrainzClient, base: URL = listenBrainzAPI, limits: RateLimits = RateLimits(),
                pause: @escaping @Sendable (Int64) async throws -> Void = { try await listeningPauseMs($0) }) {
        self.client = client
        self.base = base
        self.limits = limits
        self.pause = pause
    }

    /// Whether the token is good, and whose it is.
    public func validate(_ token: String) async throws -> TokenCheck {
        guard looksLikeToken(token) else { return .invalid }
        guard let answer = try await call(listenBrainzValidateRequest(token: token, base: base)) else { return .unreachable }
        return tokenCheckOf(status: answer.status, body: answer.body)
    }

    /// Sends finished plays: one as "single", more as "import".
    public func submit(_ token: String, _ listens: [Listen], clientVersion: String) async throws -> SubmitResult {
        guard (1...maxListensPerRequest).contains(listens.count) else { throw ListenBrainzError.batchSize(listens.count) }
        return try await post(token, listensJSON(type: listenType(listens.count), listens: listens, clientVersion: clientVersion))
    }

    /// Says what is playing now. Skipped rather than held back when no calls are left, since it is
    /// soon out of date anyway.
    public func playingNow(_ token: String, _ listen: Listen, clientVersion: String) async throws -> SubmitResult {
        let blocked = limits.blockedMs()
        if blocked > 0 { return .rateLimited(retryInMs: blocked) }
        return try await post(token, listensJSON(type: "playing_now", listens: [listen], clientVersion: clientVersion))
    }

    private func post(_ token: String, _ body: Data) async throws -> SubmitResult {
        guard looksLikeToken(token) else { return .unauthorized }
        guard let answer = try await call(listenBrainzSubmitRequest(token: token, body: body, base: base)) else { return .failed }
        return submitResultOf(status: answer.status, retryInMs: answer.retryInMs)
    }

    private struct Answer {
        let status: Int
        let body: Data
        let retryInMs: Int64
    }

    /// Makes one call once the rate allows it; nil when it could not be made.
    private func call(_ request: URLRequest) async throws -> Answer? {
        let wait = limits.takeTurn()
        if wait > 0 { try await pause(wait) }
        do {
            let (data, response) = try await client.send(request)
            let headers = RateLimitHeaders(response)
            limits.heard(remaining: headers.remaining, resetInSeconds: headers.resetInSeconds)
            let retryIn = listenBrainzRetryInMs(resetInSeconds: headers.resetInSeconds)
            if response.statusCode == 429 { limits.refused(retryInMs: retryIn) }
            return Answer(status: response.statusCode, body: data, retryInMs: retryIn)
        } catch {
            if isCancellation(error) { throw error }
            return nil
        }
    }
}
