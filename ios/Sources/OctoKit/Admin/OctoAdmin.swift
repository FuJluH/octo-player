import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: What Octo's admin pages answer

/// What Octo says about itself or one service it works with.
public struct AdminHealth: Sendable, Equatable {
    public var ok = false
    public var detail = ""
    public var warning = false
    public var configured = true

    public init(ok: Bool = false, detail: String = "", warning: Bool = false, configured: Bool = true) {
        self.ok = ok
        self.detail = detail
        self.warning = warning
        self.configured = configured
    }

    init(_ json: Any?) {
        let object = json as? [String: Any] ?? [:]
        ok = AdminJSON.bool(object["ok"]) ?? false
        detail = AdminJSON.string(object["detail"]) ?? ""
        warning = AdminJSON.bool(object["warning"]) ?? false
        configured = AdminJSON.bool(object["configured"]) ?? true
    }
}

/// One service, by the key Octo gives it.
public struct AdminService: Sendable, Equatable {
    public let key: String
    public let health: AdminHealth

    public init(_ key: String, _ health: AdminHealth) {
        self.key = key
        self.health = health
    }
}

/// Octo's health and its services', the services in the order Octo lists them.
public struct AdminStatus: Sendable, Equatable {
    public var octo = AdminHealth()
    public var services: [AdminService] = []

    public init(octo: AdminHealth = AdminHealth(), services: [AdminService] = []) {
        self.octo = octo
        self.services = services
    }

    /// Reads the status page's answer, keeping the services in the order they were written.
    public static func read(_ data: Data) throws -> AdminStatus {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AdminJSON.notObject }
        let services = object["services"] as? [String: Any] ?? [:]
        let order = AdminJSON.keyOrder(data, of: "services").filter { services[$0] != nil }
        let keys = order.count == services.count ? order : order + services.keys.filter { !order.contains($0) }.sorted()
        return AdminStatus(octo: AdminHealth(object["octo"]), services: keys.map { AdminService($0, AdminHealth(services[$0])) })
    }
}

/// A song Octo downloaded into the library.
public struct DownloadRecord: Sendable, Equatable {
    public var artist = ""
    public var title = ""
    public var album = ""
    public var format = ""
    public var source = ""
    public var coverArtUrl: String?
    public var sizeBytes: Int64 = 0
    public var downloadedAt = ""
    public var requestedBy: [String] = []

    public init(artist: String = "", title: String = "", album: String = "", format: String = "", source: String = "",
                coverArtUrl: String? = nil, sizeBytes: Int64 = 0, downloadedAt: String = "", requestedBy: [String] = []) {
        self.artist = artist
        self.title = title
        self.album = album
        self.format = format
        self.source = source
        self.coverArtUrl = coverArtUrl
        self.sizeBytes = sizeBytes
        self.downloadedAt = downloadedAt
        self.requestedBy = requestedBy
    }

    init(_ json: Any?) {
        let object = json as? [String: Any] ?? [:]
        artist = AdminJSON.string(object["artist"]) ?? ""
        title = AdminJSON.string(object["title"]) ?? ""
        album = AdminJSON.string(object["album"]) ?? ""
        format = AdminJSON.string(object["format"]) ?? ""
        source = AdminJSON.string(object["source"]) ?? ""
        coverArtUrl = AdminJSON.string(object["coverArtUrl"])
        sizeBytes = AdminJSON.int(object["sizeBytes"]) ?? 0
        downloadedAt = AdminJSON.string(object["downloadedAt"]) ?? ""
        requestedBy = (object["requestedBy"] as? [Any])?.compactMap { AdminJSON.string($0) } ?? []
    }

    static func list(_ data: Data) throws -> [DownloadRecord] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AdminJSON.notObject }
        return (object["downloads"] as? [Any] ?? []).map(DownloadRecord.init)
    }
}

/// How far Octo's stations have learned one listener's taste.
public struct RadioLearning: Sendable, Equatable {
    public var plays = 0
    public var needed = 0
    public var refreshing = false
    public var lastRefreshSuccessUtc: String?
    public var lastRefreshError: String?

    public init(plays: Int = 0, needed: Int = 0, refreshing: Bool = false, lastRefreshSuccessUtc: String? = nil, lastRefreshError: String? = nil) {
        self.plays = plays
        self.needed = needed
        self.refreshing = refreshing
        self.lastRefreshSuccessUtc = lastRefreshSuccessUtc
        self.lastRefreshError = lastRefreshError
    }

    init(_ object: [String: Any]) {
        plays = Int(AdminJSON.int(object["plays"]) ?? 0)
        needed = Int(AdminJSON.int(object["needed"]) ?? 0)
        refreshing = AdminJSON.bool(object["refreshing"]) ?? false
        lastRefreshSuccessUtc = AdminJSON.string(object["lastRefreshSuccessUtc"])
        lastRefreshError = AdminJSON.string(object["lastRefreshError"])
    }
}

/// One of Octo's stations.
public struct AdminStation: Sendable, Equatable {
    public var id = ""
    public var name = ""
    public var kind = ""
    public var trackCount = 0
    public var validUntilUtc: String?

    public init(id: String = "", name: String = "", kind: String = "", trackCount: Int = 0, validUntilUtc: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.trackCount = trackCount
        self.validUntilUtc = validUntilUtc
    }

    init(_ json: Any?) {
        let object = json as? [String: Any] ?? [:]
        id = AdminJSON.string(object["id"]) ?? ""
        name = AdminJSON.string(object["name"]) ?? ""
        kind = AdminJSON.string(object["kind"]) ?? ""
        trackCount = Int(AdminJSON.int(object["trackCount"]) ?? 0)
        validUntilUtc = AdminJSON.string(object["validUntilUtc"])
    }
}

/// Octo's stations for one listener, and how far they have learned.
public struct RadioState: Sendable, Equatable {
    public var enabled = false
    public var selectedUser: String?
    public var learning: RadioLearning?
    public var stations: [AdminStation] = []

    public init(enabled: Bool = false, selectedUser: String? = nil, learning: RadioLearning? = nil, stations: [AdminStation] = []) {
        self.enabled = enabled
        self.selectedUser = selectedUser
        self.learning = learning
        self.stations = stations
    }

    static func read(_ data: Data) throws -> RadioState {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AdminJSON.notObject }
        return RadioState(enabled: AdminJSON.bool(object["enabled"]) ?? false,
                          selectedUser: AdminJSON.string(object["selectedUser"]),
                          learning: (object["learning"] as? [String: Any]).map(RadioLearning.init),
                          stations: (object["stations"] as? [Any] ?? []).map(AdminStation.init))
    }
}

/// Where downloads land, and whether that works.
public struct LibraryStatus: Sendable, Equatable {
    public var effectiveDownloadPath = ""
    public var writable = false
    public var visibleToOcto = false
    public var rescanAuthenticated = false

    public init(effectiveDownloadPath: String = "", writable: Bool = false, visibleToOcto: Bool = false, rescanAuthenticated: Bool = false) {
        self.effectiveDownloadPath = effectiveDownloadPath
        self.writable = writable
        self.visibleToOcto = visibleToOcto
        self.rescanAuthenticated = rescanAuthenticated
    }

    static func read(_ data: Data) throws -> LibraryStatus {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AdminJSON.notObject }
        return LibraryStatus(effectiveDownloadPath: AdminJSON.string(object["effectiveDownloadPath"]) ?? "",
                             writable: AdminJSON.bool(object["writable"]) ?? false,
                             visibleToOcto: AdminJSON.bool(object["visibleToOcto"]) ?? false,
                             rescanAuthenticated: AdminJSON.bool(object["rescanAuthenticated"]) ?? false)
    }
}

/// Why an admin call gave nothing; never shown as it is.
public struct AdminUnavailable: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// Lenient reading of the admin answers: a missing, null or wrong value is the default.
enum AdminJSON {
    struct NotObject: Error {}
    static let notObject = NotObject()

    static func bool(_ value: Any?) -> Bool? { value as? Bool }

    static func string(_ value: Any?) -> String? { value as? String }

    static func int(_ value: Any?) -> Int64? {
        guard !(value is Bool) else { return nil }
        return (value as? NSNumber)?.int64Value
    }

    /// The keys of the object written under `name` at the top of `data`, in the order written.
    static func keyOrder(_ data: Data, of name: String) -> [String] {
        var scanner = KeyScanner(bytes: [UInt8](data))
        return scanner.keys(of: name) ?? []
    }
}

/// Walks raw JSON just far enough to list one object's keys in order.
private struct KeyScanner {
    let bytes: [UInt8]
    var at = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func keys(of name: String) -> [String]? {
        skipSpace()
        guard peek == UInt8(ascii: "{") else { return nil }
        at += 1
        while true {
            skipSpace()
            if peek == UInt8(ascii: "}") { return nil }
            guard let key = readString() else { return nil }
            skipSpace()
            guard peek == UInt8(ascii: ":") else { return nil }
            at += 1
            skipSpace()
            if key == name {
                guard peek == UInt8(ascii: "{") else { return nil }
                return objectKeys()
            }
            guard skipValue() else { return nil }
            skipSpace()
            if peek == UInt8(ascii: ",") { at += 1 } else { return nil }
        }
    }

    private mutating func objectKeys() -> [String]? {
        at += 1
        var keys: [String] = []
        while true {
            skipSpace()
            if peek == UInt8(ascii: "}") { return keys }
            guard let key = readString() else { return nil }
            keys.append(key)
            skipSpace()
            guard peek == UInt8(ascii: ":") else { return nil }
            at += 1
            skipSpace()
            guard skipValue() else { return nil }
            skipSpace()
            if peek == UInt8(ascii: ",") { at += 1 } else if peek == UInt8(ascii: "}") { return keys } else { return nil }
        }
    }

    private var peek: UInt8? { at < bytes.count ? bytes[at] : nil }

    private mutating func skipSpace() {
        while let byte = peek, byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09 { at += 1 }
    }

    private mutating func readString() -> String? {
        guard peek == UInt8(ascii: "\"") else { return nil }
        let start = at
        guard skipString() else { return nil }
        let raw = Data(bytes[start..<at])
        return (try? JSONSerialization.jsonObject(with: raw, options: .fragmentsAllowed)) as? String
    }

    private mutating func skipString() -> Bool {
        at += 1
        while let byte = peek {
            at += 1
            if byte == UInt8(ascii: "\\") { at += 1 } else if byte == UInt8(ascii: "\"") { return true }
        }
        return false
    }

    private mutating func skipValue() -> Bool {
        guard let byte = peek else { return false }
        switch byte {
        case UInt8(ascii: "\""): return skipString()
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            var depth = 0
            while let next = peek {
                if next == UInt8(ascii: "\"") {
                    guard skipString() else { return false }
                    continue
                }
                if next == UInt8(ascii: "{") || next == UInt8(ascii: "[") { depth += 1 }
                if next == UInt8(ascii: "}") || next == UInt8(ascii: "]") { depth -= 1 }
                at += 1
                if depth == 0 { return true }
            }
            return false
        default:
            while let next = peek, next != UInt8(ascii: ","), next != UInt8(ascii: "}"), next != UInt8(ascii: "]") { at += 1 }
            return true
        }
    }
}

// MARK: Finding the admin pages

/// An address reduced to its root: the same scheme, host and port, path "/", no query.
public func adminRoot(_ url: URL) -> URL? {
    guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.host != nil else { return nil }
    parts.percentEncodedPath = "/"
    parts.query = nil
    parts.fragment = nil
    parts.user = nil
    parts.password = nil
    return parts.url
}

/// What makes two roots the same: scheme, host and port, a default port written or not.
public func rootKey(_ url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { return nil }
    let port = url.port ?? (scheme == "https" ? 443 : scheme == "http" ? 80 : -1)
    return "\(scheme)://\(host):\(port)"
}

/// Whether an admin call may carry the sign-in: only to the server's own addresses, or to one
/// Octo itself announced for its stations. A saved address from another network could belong to
/// anything.
public func mayCarrySignIn(_ target: URL, trusted: Set<String>) -> Bool {
    guard let key = rootKey(target) else { return false }
    return trusted.contains(key)
}

/// Where the admin addresses found are kept, one per kept server.
public protocol AdminAddressStore: Sendable {
    func string(_ key: String) -> String?
    func set(_ value: String?, _ key: String)
}

/// The signed-in server the admin pages are looked for on.
public struct AdminSignIn: Sendable {
    /// The kept server's id.
    public let server: String
    public let client: SubsonicClient
    /// The server's main address, whichever one calls go to.
    public let primary: URL
    /// How many servers are kept on the phone.
    public let keptServers: Int

    public init(server: String, client: SubsonicClient, primary: URL, keptServers: Int) {
        self.server = server
        self.client = client
        self.primary = primary
        self.keptServers = keptServers
    }
}

/// Octo's own admin pages, which answer only on the home network. The app finds them at the
/// address it signed in with, at the one it last found, or at the address Octo gives its
/// stations, and remembers what worked.
public final class OctoAdmin: @unchecked Sendable {
    private let store: AdminAddressStore
    private let probeTimeout: TimeInterval
    private let callTimeout: TimeInterval
    private let stationsWaitMs: Int
    private let lock = NSLock()
    /// The roots trusted with the sign-in, from the last look, and the kept server they were
    /// found for: only that server's sign-in ever goes to them.
    private var trusted: (server: String, roots: Set<String>)?

    public init(store: AdminAddressStore, probeTimeout: TimeInterval = 4, callTimeout: TimeInterval = 30, stationsWaitMs: Int = 5_000) {
        self.store = store
        self.probeTimeout = probeTimeout
        self.callTimeout = callTimeout
        self.stationsWaitMs = stationsWaitMs
    }

    static let addressKey = "address"
    static func addressKey(_ server: String) -> String { "address@\(server)" }

    /// Where the admin pages answer right now, or nil when away from home or not signed in.
    public func locate(_ signIn: AdminSignIn?) async -> URL? {
        guard let signIn else { return nil }
        let client = signIn.client
        var tried = Set<String>()
        let own = [client.baseURL, signIn.primary].compactMap(adminRoot)
        let ownKeys = Set(own.compactMap(rootKey))
        setTrust(signIn.server, ownKeys)
        let saved = lastFound(signIn)
        var found = await first([client.baseURL, signIn.primary] + [saved].compactMap { $0 }, tried: &tried, session: client.session)
        if found == nil {
            // The station addresses cost a server call, so they are only asked for last.
            let announced = await stationHosts(client).compactMap(adminRoot)
            setTrust(signIn.server, ownKeys.union(announced.compactMap(rootKey)))
            found = await first(announced, tried: &tried, session: client.session)
        }
        guard let found else { return nil }
        store.set(found.absoluteString, Self.addressKey(signIn.server))
        store.set(nil, Self.addressKey)
        return found
    }

    /// Forgets where a server taken off the list had its admin pages.
    public func forget(server: String) {
        store.set(nil, Self.addressKey(server))
    }

    /// The address last found for a kept server. An older version kept one for its only server,
    /// which stays that server's while it is the only one kept.
    private func lastFound(_ signIn: AdminSignIn) -> URL? {
        let older = signIn.keptServers == 1 ? store.string(Self.addressKey) : nil
        return (store.string(Self.addressKey(signIn.server)) ?? older).flatMap(URL.init(string:))
    }

    private func first(_ candidates: [URL], tried: inout Set<String>, session: URLSession) async -> URL? {
        for candidate in candidates {
            guard let root = adminRoot(candidate), let key = rootKey(root), tried.insert(key).inserted else { continue }
            if await answers(root, session: session) { return root }
        }
        return nil
    }

    private func setTrust(_ server: String, _ roots: Set<String>) {
        lock.withLock { trusted = (server, roots) }
    }

    /// Whether Octo's status page answers at a root: unsigned, since it asks addresses that may
    /// not be Octo.
    private func answers(_ root: URL, session: URLSession) async -> Bool {
        let request = URLRequest(url: Self.api(root, "status"), timeoutInterval: probeTimeout)
        let answered = try? await Self.within(probeTimeout) { () async throws -> Bool in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            return object["octo"] != nil
        }
        return answered ?? false
    }

    /// Octo builds each station's stream address from where it thinks it lives, which is
    /// usually its home network address.
    private func stationHosts(_ client: SubsonicClient) async -> [URL] {
        let stations = (try? await Self.within(Double(stationsWaitMs) / 1_000) { try await client.stations() }) ?? []
        return stations.compactMap { $0.streamUrl.flatMap(URL.init(string:)) }.filter { $0.host != nil }
    }

    // MARK: Calls

    public func status(_ base: URL, _ signIn: AdminSignIn?) async throws -> AdminStatus {
        try await get(base, "status", signIn) { try AdminStatus.read($0) }
    }

    public func downloads(_ base: URL, _ signIn: AdminSignIn?) async throws -> [DownloadRecord] {
        try await get(base, "downloads", signIn) { try DownloadRecord.list($0) }
    }

    public func radio(_ base: URL, _ signIn: AdminSignIn?) async throws -> RadioState {
        let user = signIn?.client.credentials.username ?? ""
        return try await get(base, "lastfm/radio", signIn, query: user.isEmpty ? [] : [("user", user)]) { try RadioState.read($0) }
    }

    public func library(_ base: URL, _ signIn: AdminSignIn?) async throws -> LibraryStatus {
        try await get(base, "library-status", signIn) { try LibraryStatus.read($0) }
    }

    /// Asks Octo to build the signed-in listener's stations again.
    public func refreshStations(_ base: URL, _ signIn: AdminSignIn?) async throws {
        guard let signIn, !signIn.client.credentials.username.isEmpty else { throw AdminUnavailable("Not signed in") }
        let body = try JSONSerialization.data(withJSONObject: ["user": signIn.client.credentials.username])
        var request = URLRequest(url: sign(Self.api(base, "lastfm/radio/refresh"), signIn), timeoutInterval: callTimeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("1", forHTTPHeaderField: "X-Octo-Admin")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers(for: request.url, signIn).forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let response: URLResponse
        do {
            (_, response) = try await (signIn.client.session).data(for: request)
        } catch {
            throw AdminUnavailable("Octo did not answer")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AdminUnavailable("HTTP \(http.statusCode) from lastfm/radio/refresh")
        }
    }

    /// The full admin pages, for everything the app does not show.
    public static func pageUrl(_ base: URL) -> URL? {
        guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        parts.percentEncodedPath = "/admin/"
        return parts.url
    }

    private func get<T>(_ base: URL, _ path: String, _ signIn: AdminSignIn?, query: [(String, String)] = [],
                        read: (Data) throws -> T) async throws -> T {
        var address = Self.api(base, path)
        if !query.isEmpty, var parts = URLComponents(url: address, resolvingAgainstBaseURL: false) {
            parts.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
            address = parts.url ?? address
        }
        var request = URLRequest(url: sign(address, signIn), timeoutInterval: callTimeout)
        headers(for: request.url, signIn).forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let session = signIn?.client.session ?? .shared
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AdminUnavailable("Octo did not answer")
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 403 { throw AdminUnavailable("Needs a Navidrome admin account") }
            if !(200..<300).contains(http.statusCode) { throw AdminUnavailable("HTTP \(http.statusCode) from \(path)") }
        }
        do {
            return try read(data)
        } catch {
            throw AdminUnavailable("Octo answered in a way the app does not understand")
        }
    }

    static func api(_ base: URL, _ path: String) -> URL {
        var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents()
        parts.percentEncodedPath = "/api/admin/\(path)"
        parts.query = nil
        return parts.url ?? base
    }

    /// Admin pages ask who is calling; the app answers with its own sign-in, but only to an
    /// address it already trusts with it, and never another kept server's.
    func sign(_ url: URL, _ signIn: AdminSignIn?) -> URL {
        guard let signIn, carries(url, signIn) else { return url }
        return signIn.client.signed(url)
    }

    /// The server's own headers go where its sign-in goes; elsewhere only who is asking.
    private func headers(for url: URL?, _ signIn: AdminSignIn?) -> [String: String] {
        guard let signIn else { return [:] }
        guard let url, carries(url, signIn) else { return ["User-Agent": signIn.client.userAgent] }
        return signIn.client.headers
    }

    private func carries(_ url: URL, _ signIn: AdminSignIn) -> Bool {
        guard let trust = lock.withLock({ trusted }), trust.server == signIn.server else { return false }
        return mayCarrySignIn(url, trusted: trust.roots)
    }

    /// Runs `work`, giving up after `seconds`.
    static func within<T: Sendable>(_ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw AdminUnavailable("Timed out")
            }
            guard let first = try await group.next() else { throw AdminUnavailable("Timed out") }
            group.cancelAll()
            return first
        }
    }
}

// MARK: Words

/// How a service's health is drawn.
public enum HealthDot: Sendable, Equatable {
    case ok, warning, down, notSetUp
}

public func healthDot(_ health: AdminHealth) -> HealthDot {
    if !health.configured { return .notSetUp }
    if !health.ok { return .down }
    if health.warning { return .warning }
    return .ok
}

/// What each of the server's services is called on screen. Anything new shows by its key.
public func serviceName(_ key: String) -> String {
    switch key {
    case "navidrome": "Navidrome"
    case "slskd": "Soulseek"
    case "lidarr": "Lidarr"
    case "ytDlpShim": "Streaming helper"
    case "lastfm": "Last.fm"
    default: key
    }
}

/// How long ago, the way a person says it: "Just now", "5 min ago", "Yesterday", then the date.
public func adminAgo(thenMs: Int64, nowMs: Int64, zone: TimeZone = .current, locale: Locale = .current) -> String {
    let minutes = (nowMs - thenMs) / 60_000
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let then = Date(timeIntervalSince1970: Double(thenMs) / 1_000)
    let now = Date(timeIntervalSince1970: Double(nowMs) / 1_000)
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: then), to: calendar.startOfDay(for: now)).day ?? 0
    if nowMs - thenMs < 60_000 { return "Just now" }
    if minutes < 60 { return "\(minutes) min ago" }
    if days == 0 || minutes < 6 * 60 { return "\(minutes / 60) hr ago" }
    if days == 1 { return "Yesterday" }
    if days < 7 { return "\(days) days ago" }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = zone
    formatter.dateFormat = calendar.component(.year, from: then) == calendar.component(.year, from: now) ? "d MMM" : "d MMM yyyy"
    return formatter.string(from: then)
}

/// How long ago a time from Octo was (one written without a zone is UTC), or nil when it cannot be read.
public func adminAgo(_ text: String?, nowMs: Int64, zone: TimeZone = .current, locale: Locale = .current) -> String? {
    epochMs(text).map { adminAgo(thenMs: $0, nowMs: nowMs, zone: zone, locale: locale) }
}

/// How far the stations have learned the listener's taste.
public func learningLine(_ learning: RadioLearning) -> String {
    if learning.needed <= 0 || learning.plays >= learning.needed {
        return "Learned from \(plays(learning.plays))"
    }
    return "Learning your taste: \(SettingsSummaries.grouped(Int(learning.plays))) of \(plays(learning.needed))"
}

private func plays(_ count: Int) -> String {
    count == 1 ? "1 play" : "\(SettingsSummaries.grouped(Int(count))) plays"
}

/// The last refresh's error in words fit for the screen. Anything that reads like a program's
/// output gets a plain sentence instead.
public func refreshProblem(_ error: String?) -> String? {
    let text = (error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = text.first else { return nil }
    let technical = "{[<".contains(first) || text.contains("\n") || text.contains("Exception") || text.count > 160
    return technical ? "The last refresh did not finish." : "The last refresh did not finish: \(text)"
}

/// What stops downloads reaching the library, if anything.
public func libraryProblems(_ status: LibraryStatus) -> [String] {
    var problems: [String] = []
    if !status.writable { problems.append("Octo cannot write to this folder") }
    if !status.rescanAuthenticated { problems.append("Octo cannot ask Navidrome to rescan") }
    return problems
}

/// The line under a download's title: who it is by and what kind of file.
public func downloadLine(_ record: DownloadRecord) -> String {
    [record.artist, record.format.uppercased()].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " · ")
}

/// The words under a station: how many songs it holds.
public func stationSongs(_ count: Int) -> String { count == 1 ? "1 song" : "\(count) songs" }

/// What a section that could not load says; the reason is never shown.
public func adminLoadFailed(_ what: String) -> String { "Couldn't load \(what) just now. Pull down to try again." }
