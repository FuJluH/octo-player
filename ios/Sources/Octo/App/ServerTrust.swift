import CryptoKit
import Foundation
import Security

/// Decides whom the app trusts. The system's own trust comes first; after that, a certificate
/// the person accepted for that host, kept by its SHA-256 fingerprint. A pinned certificate also
/// stands in for the host name, since a self-made certificate rarely names the address a phone
/// uses. And when a server asks the phone to prove itself, the chosen client certificate answers.
final class ServerTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    /// A certificate the system does not trust, waiting for the person's answer.
    struct Untrusted: Error, Equatable {
        let host: String
        let fingerprint: String
    }

    static let shared = ServerTrust()

    private let lock = NSLock()
    private var pins: [String: String]
    private var rejected: [String: Untrusted] = [:]
    private var identity: SecIdentity?
    private var chain: [SecCertificate] = []

    private static let pinsKey = "trust.pins"

    override init() {
        pins = UserDefaults.standard.dictionary(forKey: Self.pinsKey) as? [String: String] ?? [:]
    }

    /// One URLSession for everything that talks to the server, so every request is judged here.
    lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

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

    /// The certificate the phone shows a server that asks for one, from a PKCS #12 file.
    func useClientCertificate(_ data: Data?, password: String) throws {
        guard let data else {
            lock.withLock { identity = nil; chain = [] }
            return
        }
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let found = first[kSecImportItemIdentity as String]
        else { throw ClientCertificateError.unreadable }
        let certificates = first[kSecImportItemCertChain as String] as? [SecCertificate] ?? []
        lock.withLock {
            identity = (found as! SecIdentity)
            chain = certificates
        }
    }

    var hasClientCertificate: Bool { lock.withLock { identity != nil } }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        answer(challenge)
    }

    /// The one decision, shared with the audio loader.
    func answer(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
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
            guard let identity = lock.withLock({ identity }) else { return (.performDefaultHandling, nil) }
            let certificates = lock.withLock { chain }
            return (.useCredential, URLCredential(identity: identity, certificates: certificates.isEmpty ? nil : certificates,
                                                   persistence: .forSession))
        default:
            return (.performDefaultHandling, nil)
        }
    }

    /// SHA-256 of the certificate, as colon-separated pairs, the way people compare them.
    static func fingerprint(of certificate: SecCertificate) -> String {
        let der = SecCertificateCopyData(certificate) as Data
        return SHA256.hash(data: der).map { String(format: "%02X", $0) }.joined(separator: ":")
    }
}

enum ClientCertificateError: LocalizedError {
    case unreadable

    var errorDescription: String? { "That certificate could not be opened. Check its password." }
}
