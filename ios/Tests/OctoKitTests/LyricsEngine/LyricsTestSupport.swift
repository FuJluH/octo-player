import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OctoKit

/// Whether `actual` is `expected` within `delta`, or exactly it (infinities and NaN included).
func near(_ expected: Double, _ actual: Double, _ delta: Double) -> Bool {
    if expected == actual || (expected.isNaN && actual.isNaN) { return true }
    return abs(expected - actual) <= delta
}

/// Whether two lists of numbers are the same length and each pair is `near`.
func near(_ expected: [Double], _ actual: [Double], _ delta: Double) -> Bool {
    expected.count == actual.count && zip(expected, actual).allSatisfy { near($0, $1, delta) }
}

/// A query parameter of an address, decoded; nil when it is not there.
func queryParameter(_ url: URL, _ name: String) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

/// How many query parameters an address has.
func querySize(_ url: URL) -> Int {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.count ?? 0
}

/// An address's path as it was written, escapes and all.
func encodedPath(_ url: URL) -> String {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
}

/// A local stand-in for the online lyrics library: it answers in the order answers were queued
/// and keeps every request. Each one has its own host, so stand-ins never see each other's
/// requests, and nothing ever reaches the real library.
final class StubLibrary: @unchecked Sendable {
    let host = "lib-\(UUID().uuidString.lowercased()).stub"
    let session: URLSession
    private var taken = 0

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LibraryStubProtocol.self]
        session = URLSession(configuration: configuration)
    }

    /// The address the library is reached at, like a server's root.
    var base: URL { URL(string: "http://\(host)/")! }

    func answer(_ body: String, code: Int = 200) {
        LibraryStubProtocol.enqueue(host: host, code: code, body: body)
    }

    /// The next request the library was sent, in order.
    func takeRequest() -> URL {
        let requests = LibraryStubProtocol.requests(host: host)
        defer { taken += 1 }
        return requests[taken]
    }

    var requestCount: Int { LibraryStubProtocol.requests(host: host).count }
}

final class LibraryStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: [(code: Int, body: String)]] = [:]
    nonisolated(unsafe) private static var received: [String: [URL]] = [:]

    static func enqueue(host: String, code: Int, body: String) {
        lock.lock()
        answers[host, default: []].append((code, body))
        lock.unlock()
    }

    static func requests(host: String) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return received[host] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".stub") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let host = url.host!
        Self.lock.lock()
        Self.received[host, default: []].append(url)
        var queue = Self.answers[host] ?? []
        let answer = queue.isEmpty ? (code: 500, body: "nothing queued") : queue.removeFirst()
        Self.answers[host] = queue
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: answer.code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
