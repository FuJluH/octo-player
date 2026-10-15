import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Where plays go. The token is only ever sent here, over HTTPS.
public let listenBrainzAPI = URL(string: "https://api.listenbrainz.org/")!

/// Where the listener finds their token.
public let listenBrainzTokenPage = URL(string: "https://listenbrainz.org/settings/")!

/// ListenBrainz takes at most this many plays in one request.
public let maxListensPerRequest = 1_000

/// How many plays may wait. Past that the oldest are let go.
public let maxQueuedListens = 5_000

/// One play as ListenBrainz hears it. `listenedAt` is when it started, in seconds; a length of
/// zero and a missing track number are left out.
public struct Listen: Codable, Sendable, Hashable {
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

    public init(_ listenedAt: Int64, _ track: String, _ artist: String, album: String = "", durationMs: Int64 = 0,
                trackNumber: Int? = nil, recordingMbid: String? = nil, releaseMbid: String? = nil, releaseGroupMbid: String? = nil,
                artistMbids: [String] = []) {
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

    enum CodingKeys: String, CodingKey {
        case listenedAt, track, artist, album, durationMs, trackNumber, recordingMbid, releaseMbid, releaseGroupMbid, artistMbids
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listenedAt = try c.decode(Int64.self, forKey: .listenedAt)
        track = try c.decode(String.self, forKey: .track)
        artist = try c.decode(String.self, forKey: .artist)
        album = c.value(.album, or: "")
        durationMs = c.value(.durationMs, or: 0)
        trackNumber = (try? c.decodeIfPresent(Int.self, forKey: .trackNumber)) ?? nil
        recordingMbid = (try? c.decodeIfPresent(String.self, forKey: .recordingMbid)) ?? nil
        releaseMbid = (try? c.decodeIfPresent(String.self, forKey: .releaseMbid)) ?? nil
        releaseGroupMbid = (try? c.decodeIfPresent(String.self, forKey: .releaseGroupMbid)) ?? nil
        artistMbids = c.value(.artistMbids, or: [])
    }
}

/// What was played, as far as the app knows it, and whether the signed-in server hears the play.
public struct PlayedSong: Sendable, Equatable {
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

    public init(_ title: String, _ artist: String, _ album: String, durationMs: Int64, trackNumber: Int?, reachesServer: Bool,
                recordingMbid: String? = nil, releaseMbid: String? = nil, releaseGroupMbid: String? = nil, artistMbids: [String] = []) {
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

    /// Nil when the song has no title or artist, which ListenBrainz needs. `startedAtMs` is in ms.
    public func listen(startedAtMs: Int64) -> Listen? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty || artist.isEmpty { return nil }
        var mbids: [String] = []
        for id in artistMbids.compactMap(validMbid) where !mbids.contains(id) { mbids.append(id) }
        return Listen(
            startedAtMs / 1000, title, artist,
            album: album.trimmingCharacters(in: .whitespacesAndNewlines),
            durationMs: max(durationMs, 0),
            trackNumber: trackNumber.flatMap { $0 > 0 ? $0 : nil },
            recordingMbid: validMbid(recordingMbid),
            releaseMbid: validMbid(releaseMbid),
            releaseGroupMbid: validMbid(releaseGroupMbid),
            artistMbids: mbids
        )
    }
}

/// ListenBrainz refuses a whole request over one malformed id, so only well-formed ones go.
public func validMbid(_ text: String?) -> String? {
    guard let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return nil }
    let parts = clean.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.map(\.count) == [8, 4, 4, 4, 12] else { return nil }
    let hex = Set("0123456789abcdef")
    return parts.allSatisfy { $0.allSatisfy(hex.contains) } ? clean : nil
}

/// A play reaches the server when the song is one found online or has a copy on a server.
public func playReachesServer(isFind: Bool, copySources: [String]) -> Bool {
    isFind || copySources.contains { $0.hasPrefix("server:") }
}

public func shouldSend(_ mode: SendPlays, reachesServer: Bool) -> Bool {
    mode == .all || !reachesServer
}

extension Array where Element == Listen {
    /// Oldest first, each play once, and never more than the cap.
    public func plusListen(_ listen: Listen) -> [Listen] {
        // A play after the last one kept, the usual case, joins the end.
        if let last, listen.listenedAt > last.listenedAt, count < 2 || self[count - 2].listenedAt < last.listenedAt {
            var next = self
            next.append(listen)
            if next.count > maxQueuedListens { next.removeFirst(next.count - maxQueuedListens) }
            return next
        }
        let sorted = zip(self, dropFirst()).allSatisfy { $0.listenedAt <= $1.listenedAt }
        if !sorted { return Array(Self.ordered(self + [listen]).suffix(maxQueuedListens)) }
        let kept = Self.ordered(self)
        if kept.contains(where: { $0.listenedAt == listen.listenedAt && $0.track == listen.track && $0.artist == listen.artist }) {
            return Array(kept.suffix(maxQueuedListens))
        }
        var next = kept
        let at = next.lastIndex { $0.listenedAt <= listen.listenedAt }.map { $0 + 1 } ?? 0
        next.insert(listen, at: at)
        return Array(next.suffix(maxQueuedListens))
    }

    /// Each play once, keeping the first of any repeat, in start order (ties as they came).
    private static func ordered(_ items: [Listen]) -> [Listen] {
        // Plays already in order with no two at the same second cannot repeat.
        if zip(items, items.dropFirst()).allSatisfy({ pair in pair.0.listenedAt < pair.1.listenedAt }) { return items }
        var seen = Set<ListenKey>()
        let kept = items.filter { seen.insert(ListenKey($0)).inserted }
        let inOrder = zip(kept, kept.dropFirst()).allSatisfy { pair in pair.0.listenedAt <= pair.1.listenedAt }
        if inOrder { return kept }
        let numbered: [(Int, Listen)] = kept.enumerated().map { ($0.offset, $0.element) }
        let sorted = numbered.sorted { a, b in a.1.listenedAt != b.1.listenedAt ? a.1.listenedAt < b.1.listenedAt : a.0 < b.0 }
        return sorted.map { $0.1 }
    }
}

/// What makes two plays the same play.
private struct ListenKey: Hashable {
    let at: Int64
    let track: String
    let artist: String

    init(_ listen: Listen) {
        at = listen.listenedAt
        track = listen.track
        artist = listen.artist
    }
}

/// The plays the next request carries: the oldest, up to the limit.
public func nextBatch(_ queue: [Listen]) -> [Listen] { Array(queue.prefix(maxListensPerRequest)) }

/// "single" for one play, "import" for several.
public func listenType(_ count: Int) -> String { count == 1 ? "single" : "import" }

/// How long to wait after this many failures in a row: 30 seconds, doubling each time, and
/// never more than six hours.
public func retryDelayMs(_ failures: Int) -> Int64 {
    if failures <= 0 { return 0 }
    let steps = Int64(min(failures - 1, 20))
    return min(Int64(30_000) << steps, 6 * 60 * 60 * 1000)
}

/// The request body for these plays. Now playing carries no time.
public func listensJson(_ type: String, _ listens: [Listen], clientVersion: String) -> [String: Any] {
    [
        "listen_type": type,
        "payload": listens.map { listen -> [String: Any] in
            var item: [String: Any] = ["track_metadata": trackMetadata(listen, clientVersion: clientVersion)]
            if type != "playing_now" { item["listened_at"] = listen.listenedAt }
            return item
        },
    ]
}

private func trackMetadata(_ listen: Listen, clientVersion: String) -> [String: Any] {
    var info: [String: Any] = [
        "media_player": "Octo",
        "media_player_version": clientVersion,
        "submission_client": "Octo",
        "submission_client_version": clientVersion,
    ]
    if listen.durationMs > 0 { info["duration_ms"] = listen.durationMs }
    if let number = listen.trackNumber { info["tracknumber"] = String(number) }
    if let id = listen.recordingMbid { info["recording_mbid"] = id }
    if let id = listen.releaseMbid { info["release_mbid"] = id }
    if let id = listen.releaseGroupMbid { info["release_group_mbid"] = id }
    if !listen.artistMbids.isEmpty { info["artist_mbids"] = listen.artistMbids }
    var meta: [String: Any] = ["artist_name": listen.artist, "track_name": listen.track, "additional_info": info]
    if !listen.album.trimmingCharacters(in: .whitespaces).isEmpty { meta["release_name"] = listen.album }
    return meta
}

/// ListenBrainz asks for no more than one call a second, and says in each answer how many calls
/// are left and when the count starts over.
public final class RateLimits: @unchecked Sendable {
    private let clock: @Sendable () -> Int64
    private let lock = NSLock()
    private var lastCallAt = Int64.min / 2
    private var blockedUntil: Int64 = 0
    static let minGapMs: Int64 = 1_000

    public init(clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.clock = clock
    }

    /// How long to wait before the next call.
    public func waitMs() -> Int64 {
        lock.withLock {
            let now = clock()
            return max(lastCallAt + Self.minGapMs - now, blockedUntil - now, 0)
        }
    }

    /// How long until the current window ends, when no calls are left in it.
    public func blockedMs() -> Int64 { lock.withLock { max(blockedUntil - clock(), 0) } }

    public func called() { lock.withLock { lastCallAt = clock() } }

    /// What an answer said. Nothing left means waiting for the window to end.
    public func heard(remaining: Int?, resetInSeconds: Int64?) {
        lock.withLock {
            if let remaining, remaining <= 0, let resetInSeconds { blockedUntil = clock() + resetInSeconds * 1000 }
        }
    }

    /// A 429: nothing more until the window ends.
    public func refused(retryInMs: Int64) { lock.withLock { blockedUntil = clock() + retryInMs } }
}

public enum TokenCheck: Sendable, Equatable {
    case valid(user: String)
    case invalid
    case unreachable
}

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

/// A token is letters, digits and dashes. Anything else is not one, and would not be a valid
/// header either.
public func looksLikeToken(_ token: String) -> Bool {
    (8...128).contains(token.count) && token.unicodeScalars.allSatisfy {
        ($0.isASCII && (CharacterSet.alphanumerics.contains($0))) || $0 == "-"
    }
}

/// An answer from ListenBrainz: its status, body and the rate headers.
public struct ListenBrainzAnswer: Sendable {
    public var status: Int
    public var body: Data
    public var headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
}

/// Talks to ListenBrainz. Tokens are passed in for each call and never kept, printed or put in
/// an address. `send` makes one request, nil when it could not be made.
public actor ListenBrainzApi {
    public typealias Send = @Sendable (URLRequest) async -> ListenBrainzAnswer?

    private let send: Send
    private let base: URL
    private let limits: RateLimits
    private let sleep: @Sendable (Int64) async -> Void
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    static let defaultRetrySeconds: Int64 = 10
    static let maxRetrySeconds: Int64 = 60 * 60

    public init(send: @escaping Send, base: URL = listenBrainzAPI, limits: RateLimits = RateLimits(),
                sleep: @escaping @Sendable (Int64) async -> Void = { ms in try? await Task.sleep(for: .milliseconds(ms)) }) {
        self.send = send
        self.base = base
        self.limits = limits
        self.sleep = sleep
    }

    /// Whether the token is good, and whose it is.
    public func validate(_ token: String) async -> TokenCheck {
        guard looksLikeToken(token) else { return .invalid }
        var request = URLRequest(url: base.appendingPathComponent("1/validate-token"))
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        guard let answer = await call(request) else { return .unreachable }
        switch answer.status {
        case 200:
            let body = (try? JSONSerialization.jsonObject(with: answer.body)) as? [String: Any]
            let valid = body?["valid"] as? Bool == true
            let user = body?["user_name"] as? String
            if valid, let user, !user.trimmingCharacters(in: .whitespaces).isEmpty { return .valid(user: user) }
            return .invalid
        case 400, 401: return .invalid
        default: return .unreachable
        }
    }

    /// Sends finished plays: one as "single", more as "import". More than one request holds is
    /// never sent.
    public func submit(_ token: String, _ listens: [Listen], clientVersion: String) async -> SubmitResult {
        guard (1...maxListensPerRequest).contains(listens.count) else { return .rejected }
        return await post(token, listensJson(listenType(listens.count), listens, clientVersion: clientVersion))
    }

    /// Says what is playing now. Skipped rather than held back when no calls are left.
    public func playingNow(_ token: String, _ listen: Listen, clientVersion: String) async -> SubmitResult {
        let blocked = limits.blockedMs()
        if blocked > 0 { return .rateLimited(retryInMs: blocked) }
        return await post(token, listensJson("playing_now", [listen], clientVersion: clientVersion))
    }

    private func post(_ token: String, _ body: [String: Any]) async -> SubmitResult {
        guard looksLikeToken(token) else { return .unauthorized }
        var request = URLRequest(url: base.appendingPathComponent("1/submit-listens"))
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let answer = await call(request) else { return .failed }
        switch answer.status {
        case 200..<300: return .sent
        case 401: return .unauthorized
        case 400, 413: return .rejected
        case 429: return .rateLimited(retryInMs: retryIn(answer))
        default: return .failed
        }
    }

    private func retryIn(_ answer: ListenBrainzAnswer) -> Int64 {
        let resetIn = header(answer, "X-RateLimit-Reset-In").flatMap { Int64($0) }
        return min(max(resetIn ?? Self.defaultRetrySeconds, 1), Self.maxRetrySeconds) * 1000
    }

    private func header(_ answer: ListenBrainzAnswer, _ name: String) -> String? {
        answer.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value.trimmingCharacters(in: .whitespaces)
    }

    /// Makes one call once the rate allows it; nil when it could not be made. Calls take turns
    /// at the rate check, so two never go out together.
    private func call(_ request: URLRequest) async -> ListenBrainzAnswer? {
        await takeTurn()
        let wait = limits.waitMs()
        if wait > 0 { await sleep(wait) }
        limits.called()
        endTurn()
        guard let answer = await send(request) else { return nil }
        let resetIn = header(answer, "X-RateLimit-Reset-In").flatMap { Int64($0) }
        limits.heard(remaining: header(answer, "X-RateLimit-Remaining").flatMap { Int($0) }, resetInSeconds: resetIn)
        if answer.status == 429 { limits.refused(retryInMs: retryIn(answer)) }
        return answer
    }

    private func takeTurn() async {
        if busy {
            await withCheckedContinuation { waiting.append($0) }
        } else {
            busy = true
        }
    }

    private func endTurn() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }
}

/// Makes requests only to ListenBrainz: same scheme, host and port as `allowed`, no redirects,
/// the system's own certificate checks, no cookies or caches, and none of the signed-in server's
/// headers. Anything else is refused before it is sent, so the token cannot go anywhere else.
public final class ListenBrainzTransport: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let allowed: URL
    private let userAgent: String
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.httpAdditionalHeaders = [:]
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    public init(userAgent: String, allowed: URL = listenBrainzAPI) {
        self.userAgent = userAgent
        self.allowed = allowed
    }

    /// Whether a request is for ListenBrainz.
    public func allows(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == allowed.scheme && url.host?.lowercased() == allowed.host?.lowercased() && url.port == allowed.port
    }

    public func send(_ request: URLRequest) async -> ListenBrainzAnswer? {
        guard allows(request.url) else { return nil }
        var request = request
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return nil }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return ListenBrainzAnswer(status: http.statusCode, body: data, headers: headers)
    }

    /// Never follows a redirect anywhere.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
