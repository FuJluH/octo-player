import CryptoKit
import Foundation
import OctoKit
import Security

/// Decides whom the app trusts. The system's own trust comes first; after that, a certificate
/// the person accepted for that host, kept by its SHA-256 fingerprint. A pinned certificate also
/// stands in for the host name, since a self-made certificate rarely names the address a phone
/// uses. When the server in use asks the phone to prove itself, its client certificate answers,
/// and only at the server's own hosts. Its headers never follow a redirect to another address,
/// and a call to it that could not connect is reported, so the address in use can be looked at
/// again.
final class ServerTrust: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// A certificate the system does not trust, waiting for the person's answer.
    struct Untrusted: Error, Equatable {
        let host: String
        let fingerprint: String
    }

    /// A client certificate as the system uses it: the identity and the chain sent with it.
    struct ClientIdentity: @unchecked Sendable {
        let identity: SecIdentity
        let chain: [SecCertificate]
    }

    static let shared = ServerTrust()

    private let lock = NSLock()
    private var pins: [String: String]
    private var rejected: [String: Untrusted] = [:]
    /// The server in use: its addresses, and the certificate shown to it.
    private var scope = ServerScope()
    private var client: ClientIdentity?
    private var connectionFailed: (@Sendable () -> Void)?

    private static let pinsKey = "trust.pins"

    override init() {
        pins = UserDefaults.standard.dictionary(forKey: Self.pinsKey) as? [String: String] ?? [:]
    }

    /// One URLSession for everything that talks to the server in use, so every request is judged here.
    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    /// A session of its own for a kept server that is not the one in use, so the one in use keeps
    /// its own: this server's addresses and client certificate, the same trusted certificates, and
    /// at most `seconds` for each call as a whole. Throws when the certificate cannot be opened.
    /// The caller ends it with `finishTasksAndInvalidate()` once done.
    func ownSession(for addresses: [URL], certificate: (data: Data, password: String)?,
                    seconds: TimeInterval? = nil) throws -> URLSession {
        let identity = try certificate.map { try Self.identity($0.data, password: $0.password) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = seconds ?? 30
        if let seconds { configuration.timeoutIntervalForResource = seconds }
        let delegate = OwnServerTrust(trust: self, scope: ServerScope(addresses), client: identity)
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func trust(_ question: Untrusted) {
        lock.withLock {
            pins[question.host.lowercased()] = question.fingerprint
            rejected[question.host.lowercased()] = nil
            UserDefaults.standard.set(pins, forKey: Self.pinsKey)
        }
    }

    func forget(host: String) {
        lock.withLock {
            pins[host.lowercased()] = nil
            UserDefaults.standard.set(pins, forKey: Self.pinsKey)
        }
    }

    func isPinned(_ host: String?) -> Bool {
        guard let host else { return false }
        return lock.withLock { pins[host.lowercased()] != nil }
    }

    /// The certificate this host showed and the system turned down, if it did.
    func rejection(for host: String?) -> Untrusted? {
        guard let host else { return nil }
        return lock.withLock { rejected[host.lowercased()] }
    }

    /// The addresses of the server in use from now on, none when no server is in use. Its
    /// headers and client certificate go only to these.
    func useServer(_ addresses: [URL]) {
        lock.withLock { scope = ServerScope(addresses) }
    }

    /// The certificate the phone shows the server in use when it asks for one, from a PKCS #12
    /// file; nil for none.
    func useClientCertificate(_ data: Data?, password: String) throws {
        let read = try data.map { try Self.identity($0, password: password) }
        lock.withLock { client = read }
    }

    /// Whether a PKCS #12 file opens with this password, without using it.
    static func check(_ data: Data, password: String) throws {
        _ = try identity(data, password: password)
    }

    var hasClientCertificate: Bool { lock.withLock { client != nil } }

    /// Runs `report` after a call to the server in use could not connect at all.
    func onConnectionFailure(_ report: @escaping @Sendable () -> Void) {
        lock.withLock { connectionFailed = report }
    }

    /// Notes how a call ended: one to the server in use that could not connect (refused or no
    /// route, unknown host, or a timeout) is reported. For sessions of their own that send calls
    /// to the server too.
    func noteEnd(of request: URLRequest?, _ error: Error?) {
        guard let error = error as? URLError, SubsonicError.isConnectionError(error) else { return }
        let report: (@Sendable () -> Void)? = lock.withLock { self.scope.covers(request?.url) ? self.connectionFailed : nil }
        report?()
    }

    // MARK: Session delegate

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        answer(challenge)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        redirected(request, first: task.originalRequest)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        noteEnd(of: task.originalRequest, error)
    }

    /// The one decision, shared with the audio loader.
    func answer(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let (now, identity) = lock.withLock { (self.scope, self.client) }
        return answer(challenge, scope: now, client: identity)
    }

    /// A redirect of a call through the shared trust: the server's own headers stay only while it
    /// goes to the server in use, or to where it was first sent. For sessions of their own too.
    func redirected(_ request: URLRequest, first: URLRequest?) -> URLRequest {
        let now = lock.withLock { self.scope }
        return Self.redirected(request, first: first, scope: now)
    }

    fileprivate static func redirected(_ request: URLRequest, first: URLRequest?, scope: ServerScope) -> URLRequest {
        let drop = scope.headersToDrop(request.allHTTPHeaderFields ?? [:], to: request.url, first: first?.url)
        guard !drop.isEmpty else { return request }
        var out = request
        for name in drop { out.setValue(nil, forHTTPHeaderField: name) }
        return out
    }

    /// Answers a challenge for a server with these addresses and this client certificate.
    fileprivate func answer(_ challenge: URLAuthenticationChallenge, scope: ServerScope,
                            client: ClientIdentity?) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = space.serverTrust else { return (.performDefaultHandling, nil) }
            if SecTrustEvaluateWithError(trust, nil) {
                return (.useCredential, URLCredential(trust: trust))
            }
            guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
                return (.cancelAuthenticationChallenge, nil)
            }
            let fingerprint = Self.fingerprint(of: leaf)
            let host = space.host.lowercased()
            let pinned = lock.withLock { pins[host] }
            if pinned == fingerprint {
                return (.useCredential, URLCredential(trust: trust))
            }
            lock.withLock { rejected[host] = Untrusted(host: host, fingerprint: fingerprint) }
            return (.cancelAuthenticationChallenge, nil)
        case NSURLAuthenticationMethodClientCertificate:
            // Shown only to the server's own hosts, never to any other.
            guard let client, scope.isOwnHost(space.host) else { return (.performDefaultHandling, nil) }
            return (.useCredential, URLCredential(identity: client.identity, certificates: client.chain.isEmpty ? nil : client.chain,
                                                   persistence: .forSession))
        default:
            return (.performDefaultHandling, nil)
        }
    }

    /// The identity and chain in a PKCS #12 file.
    private static func identity(_ data: Data, password: String) throws -> ClientIdentity {
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let found = first[kSecImportItemIdentity as String]
        else { throw ClientCertificateError.unreadable }
        let certificates = first[kSecImportItemCertChain as String] as? [SecCertificate] ?? []
        return ClientIdentity(identity: found as! SecIdentity, chain: certificates)
    }

    /// SHA-256 of the certificate, as colon-separated pairs, the way people compare them.
    static func fingerprint(of certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

/// The trust of a session of its own for one kept server: the shared trusted certificates, and
/// this server's addresses and client certificate.
private final class OwnServerTrust: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let trust: ServerTrust
    let scope: ServerScope
    let client: ServerTrust.ClientIdentity?

    init(trust: ServerTrust, scope: ServerScope, client: ServerTrust.ClientIdentity?) {
        self.trust = trust
        self.scope = scope
        self.client = client
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        trust.answer(challenge, scope: scope, client: client)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        ServerTrust.redirected(request, first: task.originalRequest, scope: scope)
    }
}

enum ClientCertificateError: LocalizedError {
    case unreadable

    var errorDescription: String? { "That certificate could not be opened. Check its password." }
}
