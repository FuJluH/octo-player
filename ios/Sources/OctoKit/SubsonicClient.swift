import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// How the app proves who it is to the server.
public enum AuthMode: String, Codable, Sendable {
    /// md5(password + salt) with a new salt each request; the password never travels.
    case token
    /// The password itself, hex encoded, for servers that check passwords against a directory.
    case legacyPassword
    /// A key made on the server, sent in place of a username and password. Only servers that
    /// list the apiKeyAuthentication extension take it.
    case apiKey
}

/// Who is signing in and the secret that proves it: the password, or for an API key the key.
/// With a key the username is only for showing, and may be empty until the server names it.
/// The secret is never printed.
public struct Credentials: Sendable, Equatable, CustomStringConvertible {
    public var username: String
    var secret: String
    public var mode: AuthMode

    public init(username: String, password: String, mode: AuthMode = .token) {
        self.username = username
        self.secret = password
        self.mode = mode
    }

    /// The query parameters that prove who is asking, fresh for each request.
    func authParams(salt: String = Credentials.newSalt()) -> [(String, String)] {
        switch mode {
        case .token: [("u", username), ("t", MD5.hex(secret + salt)), ("s", salt)]
        case .legacyPassword: [("u", username), ("p", "enc:" + secret.utf8.map { String(format: "%02x", $0) }.joined())]
        case .apiKey: [("apiKey", secret)]
        }
    }

    /// The same sign-in under the name the server gave it.
    public func named(_ name: String) -> Credentials {
        Credentials(username: name, password: secret, mode: mode)
    }

    static func newSalt() -> String {
        (0..<8).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    public var description: String { "Credentials(username: \(username), mode: \(mode))" }
}

/// This install as its own server knows it: an id made once and a name a person reads, so an
/// Octo server can tell one phone from another.
public struct DeviceIdentity: Sendable, Equatable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        let printable = id.unicodeScalars.filter { (0x21...0x7E).contains($0.value) }
        self.id = printable.isEmpty ? "unknown" : String(String.UnicodeScalarView(printable))
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed.isEmpty ? "Octo device" : String(trimmed.prefix(64))
    }

    /// The name as it travels in a header: UTF-8, percent-encoded.
    var headerName: String {
        name.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? name
    }

    public var headers: [String: String] {
        ["X-Octo-Device-Id": id, "X-Octo-Device-Name": headerName]
    }
}

public enum OctoError: Error, Equatable, LocalizedError {
    case wrongCredentials(String)
    case authUnsupported(code: Int, message: String)
    case notFound(String)
    case server(code: Int, message: String)
    case notSubsonic
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .wrongCredentials: "Wrong username or password."
        case .authUnsupported(_, let message): message.isEmpty ? "This server wants a different way of signing in." : message
        case .notFound(let message): message.isEmpty ? "Not found." : message
        case .server(_, let message): message
        case .notSubsonic: "That address answers, but not as a music server."
        case .http(let status): "The server answered \(status)."
        }
    }
}

/// One signed-in server: builds signed addresses and makes the calls the app needs.
public final class SubsonicClient: Sendable {
    public static let apiVersion = "1.16.1"
    public static let clientName = "Octo"

    public let baseURL: URL
    public let credentials: Credentials
    public let device: DeviceIdentity
    public let appVersion: String
    /// Headers the server needs on every request, such as an access token for a proxy in front
    /// of it. They go only to this server.
    public let customHeaders: [String: String]
    public let session: URLSession
    /// How long a call may take, when shorter than each call's own limit.
    let timeout: TimeInterval?
    /// The music folder the library is limited to, nil for all of them. Every album list,
    /// artist list, folder index and search carries it.
    public let musicFolderId: String?

    public init(baseURL: URL, credentials: Credentials, device: DeviceIdentity, appVersion: String,
                customHeaders: [String: String] = [:], session: URLSession = .shared, timeout: TimeInterval? = nil,
                musicFolderId: String? = nil) {
        self.baseURL = baseURL
        self.credentials = credentials
        self.device = device
        self.appVersion = appVersion
        self.customHeaders = customHeaders
        self.session = session
        self.timeout = timeout
        self.musicFolderId = musicFolderId
    }

    public var userAgent: String { octoUserAgent(appVersion) }

    /// The same server with other credentials.
    public func with(_ credentials: Credentials) -> SubsonicClient {
        SubsonicClient(baseURL: baseURL, credentials: credentials, device: device, appVersion: appVersion,
                       customHeaders: customHeaders, session: session, timeout: timeout, musicFolderId: musicFolderId)
    }

    /// The same server reached at another address, like its home network address.
    public func at(_ address: URL) -> SubsonicClient {
        SubsonicClient(baseURL: address, credentials: credentials, device: device, appVersion: appVersion,
                       customHeaders: customHeaders, session: session, timeout: timeout, musicFolderId: musicFolderId)
    }

    /// The same server with its library limited to one music folder, nil for all of them.
    public func limited(to folderId: String?) -> SubsonicClient {
        SubsonicClient(baseURL: baseURL, credentials: credentials, device: device, appVersion: appVersion,
                       customHeaders: customHeaders, session: session, timeout: timeout, musicFolderId: folderId)
    }

    /// A signed address for an endpoint. Every call gets a fresh salt, so never use one as a
    /// cache key.
    public func url(_ endpoint: String, _ params: [(String, String)] = []) -> URL {
        var parts = URLComponents(url: baseURL.appendingPathComponent("rest").appendingPathComponent(endpoint),
                                  resolvingAgainstBaseURL: false)!
        let query = credentials.authParams()
            + [("v", Self.apiVersion), ("c", Self.clientName), ("f", "json")]
            + params
        parts.percentEncodedQueryItems = query.map {
            URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: Self.queryValue))
        }
        return parts.url!
    }

    /// Signs an address outside /rest, such as Octo's admin pages, the same way. A fresh salt each time.
    public func signed(_ address: URL) -> URL {
        var parts = URLComponents(url: address, resolvingAgainstBaseURL: false)!
        let query = credentials.authParams() + [("v", Self.apiVersion), ("c", Self.clientName)]
        parts.percentEncodedQueryItems = (parts.percentEncodedQueryItems ?? []) + query.map {
            URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: Self.queryValue))
        }
        return parts.url!
    }

    /// Query values with `+`, `&` and `=` escaped too, so a password or a search survives.
    static let queryValue: CharacterSet = .urlQueryAllowed.subtracting(.init(charactersIn: "+&=?/"))

    /// The headers every request to this server carries.
    public var headers: [String: String] {
        customHeaders.merging(device.headers) { $1 }.merging(["User-Agent": userAgent]) { $1 }
    }

    func request(_ url: URL, timeout: TimeInterval = 30) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: min(timeout, self.timeout ?? timeout))
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    /// Calls an endpoint and decodes the part of the answer under `key`, or the whole answer
    /// when `key` is nil.
    public func get<T: Decodable>(_ endpoint: String, _ params: [(String, String)] = [], key: String?,
                                  as type: T.Type = T.self, timeout: TimeInterval = 30) async throws -> T {
        let (data, response) = try await session.data(for: request(url(endpoint, params), timeout: timeout))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OctoError.http(http.statusCode)
        }
        return try Self.decode(data, key: key)
    }

    /// Calls an endpoint that answers with nothing but its status.
    public func call(_ endpoint: String, _ params: [(String, String)] = []) async throws {
        let _: Empty = try await get(endpoint, params, key: nil)
    }

    static func decode<T: Decodable>(_ data: Data, key: String?) throws -> T {
        let decoder = JSONDecoder()
        decoder.userInfo[.payloadKey] = key ?? ""
        let body: Envelope<T>
        do {
            body = try decoder.decode(Envelope<T>.self, from: data)
        } catch {
            throw OctoError.notSubsonic
        }
        let answer = body.response
        if answer.status != "ok" {
            let code = answer.error?.code ?? 0
            let message = answer.error?.message ?? ""
            switch code {
            case 40, 44: throw OctoError.wrongCredentials(message)
            case 41, 42: throw OctoError.authUnsupported(code: code, message: message)
            case 70: throw OctoError.notFound(message)
            default: throw OctoError.server(code: code, message: message)
            }
        }
        guard let value = answer.value else { throw OctoError.notSubsonic }
        return value
    }
}

struct Empty: Decodable {}

extension CodingUserInfoKey {
    static let payloadKey = CodingUserInfoKey(rawValue: "octo.payloadKey")!
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

struct Envelope<T: Decodable>: Decodable {
    let response: Answer<T>

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        response = try c.decode(Answer<T>.self, forKey: AnyKey("subsonic-response"))
    }
}

struct Answer<T: Decodable>: Decodable {
    struct Failure: Decodable { let code: Int?; let message: String? }
    let status: String
    let error: Failure?
    let value: T?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyKey.self)
        status = (try? c.decode(String.self, forKey: AnyKey("status"))) ?? ""
        error = try? c.decodeIfPresent(Failure.self, forKey: AnyKey("error"))
        let key = decoder.userInfo[.payloadKey] as? String ?? ""
        if status != "ok" {
            value = nil
        } else if key.isEmpty {
            value = try? T(from: decoder)
        } else {
            value = try? c.decodeIfPresent(T.self, forKey: AnyKey(key))
        }
    }
}
