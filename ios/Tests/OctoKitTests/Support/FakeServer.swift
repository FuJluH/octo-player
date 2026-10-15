import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OctoKit

/// A server for tests, at its own made-up host: answers queued replies (or a router) and
/// keeps every request it was sent. Closing it makes every call fail to connect.
final class FakeServer: @unchecked Sendable {
    struct Request: Sendable {
        let method: String
        let url: URL
        let body: Data
        let headers: [String: String]

        var path: String { url.path }
        var endpoint: String { url.lastPathComponent }
        var query: [String: String] {
            Dictionary((URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
                       uniquingKeysWith: { _, last in last })
        }
        /// Every value of a query name, in order.
        func values(_ name: String) -> [String] {
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).filter { $0.name == name }.map { $0.value ?? "" }
        }
        var text: String { String(decoding: body, as: UTF8.self) }
    }

    struct Reply: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String] = ["Content-Type": "application/json"]
    }

    let host: String
    private let lock = NSLock()
    private var queued: [Reply] = []
    private var kept: [Request] = []
    private var routes: (@Sendable (Request) -> Reply?)?
    private var down = false

    init(scheme: String = "https") {
        host = "s" + UUID().uuidString.prefix(12).lowercased() + ".test"
        self.scheme = scheme
        FakeProtocol.register(self)
    }

    let scheme: String
    var base: URL { URL(string: "\(scheme)://\(host)")! }

    var requests: [Request] { lock.withLock { kept } }
    var requestCount: Int { requests.count }

    func route(_ handler: @escaping @Sendable (Request) -> Reply?) { lock.withLock { routes = handler } }

    func enqueue(status: Int = 200, _ body: String) {
        lock.withLock { queued.append(Reply(status: status, body: Data(body.utf8))) }
    }

    /// A Subsonic ok answer, with these fields beside the status.
    func ok(_ fields: String = "") {
        enqueue(Self.okBody(fields))
    }

    func error(_ code: Int, _ message: String = "No") {
        enqueue(#"{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":\#(code),"message":"\#(message)"}}}"#)
    }

    static func okBody(_ fields: String = "") -> String {
        #"{"subsonic-response":{"status":"ok","version":"1.16.1"\#(fields.isEmpty ? "" : "," + fields)}}"#
    }

    func close() { lock.withLock { down = true } }

    func client(username: String = "winters", password: String = "old", mode: AuthMode = .token) -> SubsonicClient {
        SubsonicClient(baseURL: base, credentials: Credentials(username: username, password: password, mode: mode),
                       device: DeviceIdentity(id: "test-device", name: "Test phone"), appVersion: "1.0", session: Self.session)
    }

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeProtocol.self]
        return URLSession(configuration: configuration)
    }()

    fileprivate func answer(_ request: Request) -> Reply? {
        let router: (@Sendable (Request) -> Reply?)? = lock.withLock {
            if down { return nil }
            kept.append(request)
            return routes
        }
        if lock.withLock({ down }) { return nil }
        if let router, let reply = router(request) { return reply }
        return lock.withLock { queued.isEmpty ? Reply(status: 500, body: Data("no reply queued".utf8)) : queued.removeFirst() }
    }
}

final class FakeProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var servers: [String: FakeServer] = [:]
    private static let lock = NSLock()

    static func register(_ server: FakeServer) { lock.withLock { servers[server.host] = server } }

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".test") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let host = url.host,
              let server = Self.lock.withLock({ Self.servers[host] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let seen = FakeServer.Request(method: request.httpMethod ?? "GET", url: url, body: body, headers: request.allHTTPHeaderFields ?? [:])
        guard let reply = server.answer(seen) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
