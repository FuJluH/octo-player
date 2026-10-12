import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Calls that read their answer the way every Octo app does: an error page is "HTTP <code> from
// <endpoint>", a missing key falls back to a default when there is one, and every failure is
// one of the SubsonicError kinds.
extension SubsonicClient {
    /// The part of the answer under `key` (the whole answer when nil), or `fallback` when the
    /// answer leaves it out. Without a fallback a missing key is an error.
    public func answer<T: Decodable>(_ endpoint: String, _ params: [(String, String)] = [], key: String?,
                                     fallback: T? = nil, timeout: TimeInterval = 30) async throws -> T {
        let data = try await exchange(request(url(endpoint, params), timeout: timeout), endpoint: endpoint)
        return try Self.read(data, key: key, fallback: fallback)
    }

    /// A call that answers only ok or an error.
    public func answerOK(_ endpoint: String, _ params: [(String, String)] = []) async throws {
        _ = try await exchange(request(url(endpoint, params)), endpoint: endpoint)
    }

    /// A call whose answer may leave its key out, or send null: nil then.
    public func answerIfAny<T: Decodable>(_ endpoint: String, _ params: [(String, String)] = [], key: String) async throws -> T? {
        let data = try await exchange(request(url(endpoint, params)), endpoint: endpoint)
        guard let found = try Self.payload(data, key: key) else { return nil }
        return try Self.decodeValue(found)
    }

    /// Sends the params in a form body rather than the address, which proxies and servers write
    /// to their logs. Only the sign-in is in the address.
    @discardableResult
    public func postForm(_ endpoint: String, _ params: [(String, String)], timeout: TimeInterval = 30) async throws -> Data {
        var request = request(url(endpoint), timeout: timeout)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formBody(params).utf8)
        return try await exchange(request, endpoint: endpoint)
    }

    /// The same server, headers and address signed in with another secret, for checking a
    /// password without touching this client.
    public func withSecret(_ secret: String) -> SubsonicClient {
        with(Credentials(username: credentials.username, password: secret, mode: credentials.mode))
    }

    /// What this client signs in with, for sealing into a hand-over to the same person's other
    /// device. Never logged or sent anywhere else.
    public func handOverSecret() -> String { credentials.secret }

    /// Runs one request and hands back its body once it is known to be an ok answer.
    func exchange(_ request: URLRequest, endpoint: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        } catch {
            throw SubsonicError(error)
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SubsonicError.notSubsonic("HTTP \(http.statusCode) from \(endpoint)", status: http.statusCode)
        }
        _ = try Self.payload(data, key: nil)
        return data
    }

    /// The `subsonic-response` object's part under `key`, after checking its status.
    static func payload(_ data: Data, key: String?) throws -> Any? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let root = object["subsonic-response"] as? [String: Any]
        else { throw SubsonicError.notSubsonic(SubsonicError.notSubsonicWords, status: nil) }
        if (root["status"] as? String) != "ok" {
            let error = root["error"] as? [String: Any]
            let code = JSONValue.int(error?["code"]) ?? 0
            let message = error?["message"] as? String ?? "Request failed"
            switch code {
            case 40, 44: throw SubsonicError.wrongCredentials(message)
            case 41, 42: throw SubsonicError.authNotSupported(code: code, message: message)
            case 70: throw SubsonicError.notFound(message)
            default: throw SubsonicError.server(code: code, message: message)
            }
        }
        guard let key else { return root }
        guard let value = root[key], !(value is NSNull) else { return nil }
        return value
    }

    static func read<T: Decodable>(_ data: Data, key: String?, fallback: T?) throws -> T {
        if let found = try payload(data, key: key) { return try decodeValue(found) }
        if let fallback { return fallback }
        throw SubsonicError.server(code: 0, message: "Missing \"\(key ?? "")\" in the answer")
    }

    static func decodeValue<T: Decodable>(_ value: Any) throws -> T {
        guard let json = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let decoded = try? JSONDecoder().decode(T.self, from: json)
        else { throw SubsonicError.notSubsonic(SubsonicError.notSubsonicWords, status: nil) }
        return decoded
    }

    /// A form body, every value percent-encoded.
    static func formBody(_ params: [(String, String)]) -> String {
        params.map { "\(formEncode($0.0))=\(formEncode($0.1))" }.joined(separator: "&")
    }

    static func formEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: formSafe) ?? text
    }

    static let formSafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")

    /// The server's own extensions as "name:version" strings, or nil when it could not be asked.
    public func extensionList() async throws -> [String] {
        let list: [Extension] = try await answer("getOpenSubsonicExtensions", key: "openSubsonicExtensions", fallback: [])
        return list.flatMap { e in e.versions.map { "\(e.name):\($0)" } }
    }

    /// Whether the server lists an extension at this version, or nil when it could not be
    /// asked: out of reach, a proxy answering while it restarts, a page that is not the
    /// server's, or the sign-in refused. A server that answers with an error, or has no such
    /// address (a 404), has no extensions to list, which is a no.
    public func supportsIfKnown(_ name: String, version: Int = 1) async -> Bool? {
        do {
            return try await extensionList().contains("\(name):\(version)")
        } catch let error as SubsonicError {
            switch error {
            case .unreachable, .wrongCredentials: return nil
            case .notSubsonic(_, let status): return status != nil && !error.serverBusy ? false : nil
            default: return false
            }
        } catch {
            return nil
        }
    }

    /// Pings the server and answers what it says about itself.
    public func ping() async throws -> ServerInfo {
        try await answer("ping", key: nil)
    }
}

/// Lenient reads of JSON values found by JSONSerialization.
enum JSONValue {
    static func int(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let double as Double: return double.isFinite ? Int(double) : nil
        case let number as NSNumber: return number.intValue
        case let text as String: return Int(text.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }
}

// Lenient reads for answers whose fields may be missing, null, or of another type.
extension KeyedDecodingContainer {
    func long(_ key: Key) -> Int64? {
        if let i = try? decodeIfPresent(Int64.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key), d.isFinite { return Int64(d) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int64(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    func double(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    /// A list that reads as empty when it is missing or of another shape.
    func list<T: Decodable>(_ key: Key, of type: T.Type = T.self) -> [T] {
        (try? decodeIfPresent([T].self, forKey: key)) ?? []
    }

    func object<T: Decodable>(_ key: Key, of type: T.Type = T.self) -> T? {
        try? decodeIfPresent(T.self, forKey: key)
    }

    /// Text that is a string or a list of strings, for fields servers send either way.
    func strings(_ key: Key) -> [String] {
        if let list = try? decodeIfPresent([String].self, forKey: key) { return list }
        if let one = string(key) { return [one] }
        return []
    }
}
