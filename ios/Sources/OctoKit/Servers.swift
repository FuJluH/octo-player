import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A server kept on the phone. Secrets (the password or key, header values, the client
/// certificate) are kept apart in the keychain; this record holds only what is safe to store.
public struct StoredServer: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var label: String?
    public var address: URL
    public var homeAddress: URL?
    public var username: String
    public var mode: AuthMode
    /// The names of the custom headers; their values are secrets.
    public var headerNames: [String]
    public var hasClientCertificate: Bool
    public var serverType: String?
    public var serverVersion: String?
    public var isOcto: Bool
    public var extensions: [String]
    /// Kept in the list without a password, to sign in again later.
    public var signedOut: Bool

    public init(id: String = UUID().uuidString, label: String? = nil, address: URL, homeAddress: URL? = nil,
                username: String, mode: AuthMode = .token, headerNames: [String] = [], hasClientCertificate: Bool = false,
                serverType: String? = nil, serverVersion: String? = nil, isOcto: Bool = false, extensions: [String] = [],
                signedOut: Bool = false) {
        self.id = id
        self.label = label
        self.address = address
        self.homeAddress = homeAddress
        self.username = username
        self.mode = mode
        self.headerNames = headerNames
        self.hasClientCertificate = hasClientCertificate
        self.serverType = serverType
        self.serverVersion = serverVersion
        self.isOcto = isOcto
        self.extensions = extensions
        self.signedOut = signedOut
    }

    /// The name people see: the label, else the host.
    public var name: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return address.host ?? ServerAddress.shown(address)
    }

    /// "user at host".
    public var account: String { "\(username) at \(address.host ?? ServerAddress.shown(address))" }

    /// What kind of server it is, for a status line: "Octo 2026.10.11", "Navidrome 0.58".
    public var kind: String {
        if isOcto { return ["Octo", serverVersion].compactMap { $0 }.joined(separator: " ") }
        return [serverType?.capitalized, serverVersion].compactMap { $0 }.joined(separator: " ")
    }
}

/// Custom header rules, the same as the other apps: names are an HTTP token, values printable
/// ASCII or tab.
public enum HeaderRules {
    static let nameCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")

    public static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { nameCharacters.contains($0) }
    }

    public static func isValidValue(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { $0 == "\t" || (0x20...0x7E).contains($0.value) }
    }
}

/// What a person reads when signing in goes wrong, the same words as the other apps.
public enum SignInWords {
    public static let unreachable = "Couldn't reach the server. Check the address, and that you're on the right network."
    public static let restarting = "The server isn't answering right now. It may be restarting, so try again in a moment."
    public static let notMusic = "That address answered, but not like a music server. Check the port."
    public static let wrongPassword = "Wrong username or password."
    public static let needsLegacy = "This account can't sign in with a token. Turn on Legacy sign-in under Advanced."
    public static let legacyOverHttp = "This server needs the password sent as it is, which isn't safe over http. Use https, or turn on Legacy sign-in under Advanced."
    public static let wayRefused = "The server doesn't take this way of signing in."
    public static let somethingWrong = "Something went wrong."
    public static let badAddress = "That doesn't look like a server address."
    public static let badHomeAddress = "The home network address doesn't look like a server address."
    public static let missingSecret = "Enter the password or key to sign in this way."
    public static let badHeaders = "Each header needs a name with no spaces and a plain text value."
    public static let notTrusted = "Not connected. The server's certificate wasn't trusted."

    public static func alreadyKept(_ name: String) -> String {
        "\(name) is already in your list with that address and username."
    }

    /// The words for any error a sign-in can end with.
    public static func describe(_ error: Error) -> String {
        if let octo = error as? OctoError {
            switch octo {
            case .wrongCredentials: return wrongPassword
            case .authUnsupported(41, _): return needsLegacy
            case .authUnsupported: return wayRefused
            case .notFound(let message), .server(_, let message):
                return message.isEmpty ? somethingWrong : "The server said: \(message)"
            case .notSubsonic: return notMusic
            case .http(let status):
                return [502, 503, 504, 520, 521, 522, 523, 524, 530].contains(status) ? restarting : notMusic
            }
        }
        if error is URLError { return unreachable }
        return somethingWrong
    }
}
