import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import OctoKit

/// A library song for the listening tests, with only an id and a length that matter.
func listeningTrack(_ id: String, durationMs: Int64 = 0) -> LibraryTrack {
    LibraryTrack(id: id, sourceId: "device", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                 album: "", albumId: "", trackNo: nil, discNo: nil, year: nil, durationMs: durationMs, addedAt: 0, mimeType: nil,
                 sizeBytes: nil, artwork: nil, uri: nil)
}

/// A library album for the listening tests.
func listeningAlbum(_ id: String) -> LibraryAlbum {
    LibraryAlbum(id: id, sourceId: "device", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                 year: nil, songCount: 1, durationMs: 0, addedAt: 0, artwork: nil)
}

/// Milliseconds since 1970 for a wall clock time in `zone`.
func listeningTime(_ zone: TimeZone, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Int64 {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
}

/// A calendar day.
func listeningDay(_ year: Int, _ month: Int, _ day: Int) -> DateComponents {
    DateComponents(year: year, month: month, day: day)
}

/// A JSON value, read back from what was built or sent.
indirect enum ListeningJSON: Decodable, Equatable {
    case object([String: ListeningJSON])
    case array([ListeningJSON])
    case string(String)
    case integer(Int64)
    case number(Double)
    case bool(Bool)
    case null

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
        } else if let value = try? c.decode([ListeningJSON].self) {
            self = .array(value)
        } else {
            self = .object(try c.decode([String: ListeningJSON].self))
        }
    }

    static func parse(_ data: Data) -> ListeningJSON? {
        try? JSONDecoder().decode(ListeningJSON.self, from: data)
    }

    subscript(_ key: String) -> ListeningJSON? {
        if case .object(let fields) = self { return fields[key] }
        return nil
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var integer: Int64? {
        if case .integer(let value) = self { return value }
        return nil
    }

    var array: [ListeningJSON]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var isString: Bool { string != nil }

    /// The only entry of the "payload" list.
    var onlyPayload: ListeningJSON? {
        guard let payload = self["payload"]?.array, payload.count == 1 else { return nil }
        return payload[0]
    }
}

/// Time that only moves when a pause asks it to, so waits take no real time.
final class ListeningClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time: Int64

    init(_ start: Int64 = 1_000_000) {
        time = start
    }

    var now: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return time
    }

    func advance(_ ms: Int64) {
        lock.lock()
        time += ms
        lock.unlock()
    }
}

/// One request a stand-in received.
struct StubbedRequest: Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Every value of a query parameter, in order.
    func query(_ name: String) -> [String] {
        (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).filter { $0.name == name }.compactMap(\.value)
    }

    var path: String { URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? "" }
}

/// A local stand-in for a server: it answers in the order answers were queued and keeps every
/// request. Each one has its own host, so stand-ins never see each other's requests, and nothing
/// ever reaches a real server.
final class ListeningStub: @unchecked Sendable {
    let host = "listening-\(UUID().uuidString.lowercased()).stub"
    private var taken = 0

    var base: URL { URL(string: "https://\(host)/")! }

    /// A configuration whose requests to this host reach the stand-in.
    var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ListeningStubProtocol.self]
        return configuration
    }

    func answer(code: Int = 200, body: String = #"{"status":"ok"}"#, headers: [String: String] = [:]) {
        ListeningStubProtocol.enqueue(host: host, .answer(code: code, body: body, headers: headers))
    }

    /// The next request gets no answer at all, as when nothing listens there.
    func unreachable() {
        ListeningStubProtocol.enqueue(host: host, .unreachable)
    }

    var requestCount: Int { ListeningStubProtocol.requests(host: host).count }

    /// The next request the stand-in was sent, in order.
    func takeRequest() -> StubbedRequest {
        let requests = ListeningStubProtocol.requests(host: host)
        defer { taken += 1 }
        return requests[taken]
    }
}

enum StubAnswer {
    case answer(code: Int, body: String, headers: [String: String])
    case unreachable
}

final class ListeningStubProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var answers: [String: [StubAnswer]] = [:]
    nonisolated(unsafe) private static var received: [String: [StubbedRequest]] = [:]

    static func enqueue(host: String, _ answer: StubAnswer) {
        lock.lock()
        answers[host, default: []].append(answer)
        lock.unlock()
    }

    static func requests(host: String) -> [StubbedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return received[host] ?? []
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host.hasPrefix("listening-") && host.hasSuffix(".stub")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func read(_ stream: InputStream?) -> Data {
        guard let stream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func startLoading() {
        guard let url = request.url, let host = url.host else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let body = request.httpBody ?? Self.read(request.httpBodyStream)
        let seen = StubbedRequest(url: url, method: request.httpMethod ?? "GET", headers: request.allHTTPHeaderFields ?? [:], body: body)
        Self.lock.lock()
        Self.received[host, default: []].append(seen)
        var queue = Self.answers[host] ?? []
        let answer = queue.isEmpty ? StubAnswer.answer(code: 500, body: "nothing queued", headers: [:]) : queue.removeFirst()
        Self.answers[host] = queue
        Self.lock.unlock()
        switch answer {
        case .unreachable:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
        case .answer(let code, let text, let headers):
            let fields = ["Content-Type": "application/json"].merging(headers) { $1 }
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: "HTTP/1.1", headerFields: fields)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
