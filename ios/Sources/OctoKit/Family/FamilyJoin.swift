import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What signing up from an invite came to: the member's username and the password they chose,
/// to sign in with like any typed one; a certificate the device does not trust yet; or why it
/// did not work, and whether the server could not be reached at all.
public enum JoinOutcome: Sendable, Equatable, CustomStringConvertible {
    case signedUp(username: String, password: String, at: URL?)
    case untrusted(host: String)
    case failed(String, unreachable: Bool)

    public var description: String {
        switch self {
        case .signedUp(let username, _, let at): "SignedUp(username=\(username), at=\(at?.absoluteString ?? "null"))"
        case .untrusted(let host): "Untrusted(host=\(host))"
        case .failed(let message, _): "Failed(\(message))"
        }
    }
}

public let minPassword = 8
public let maxPassword = 1024

/// What an invite still needs before it is accepted, or nil when it can go.
public func inviteProblem(displayName: String, password: String, again: String) -> String? {
    if displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Type your name" }
    if password.utf16.count < minPassword { return "Choose a password of at least \(minPassword) characters" }
    if password.utf16.count > maxPassword { return "That password is too long" }
    if password != again { return "The two passwords are not the same" }
    return nil
}

/// How strong a password looks, in plain words, while it is typed. Nil before anything is typed.
public func passwordStrength(_ password: String) -> String? {
    if password.isEmpty { return nil }
    let length = password.utf16.count
    if length < minPassword { return "Too short: at least \(minPassword) characters" }
    let scalars = password.unicodeScalars
    let kinds = [
        scalars.contains { $0.properties.isLowercase },
        scalars.contains { $0.properties.isUppercase },
        scalars.contains { $0.properties.numericType == .decimal },
        scalars.contains { !$0.properties.isAlphabetic && $0.properties.numericType != .decimal },
    ].filter { $0 }.count
    if length >= 16 || (length >= 12 && kinds >= 3) { return "Strong" }
    if length >= 12 || kinds >= 3 { return "Good. Longer is stronger." }
    return "Weak: make it longer, or mix in numbers and symbols"
}

/// Accepts an invite on this device: the new member's name and the password they choose go to
/// the family page, which makes the account. The caller then signs in with that username and
/// password. `home`, from the link, is tried when `address` can't be reached at all (no
/// connection, or its certificate failed), never after the server turned the invite down.
public func joinWithInvite(address: URL, token: String, displayName: String, password: String, session: URLSession,
                           headers: [String: String] = [:], home: URL? = nil) async -> JoinOutcome {
    let first = await joining(at: address, token: token, displayName: displayName, password: password, session: session, headers: headers)
    let unreached: Bool = switch first {
    case .failed(_, let unreachable): unreachable
    case .untrusted: true
    case .signedUp: false
    }
    guard let home, home != address, unreached else { return first }
    let second = await joining(at: home, token: token, displayName: displayName, password: password, session: session, headers: headers)
    if case .signedUp = second { return second }
    if case .untrusted = second, !{ if case .untrusted = first { true } else { false } }() { return second }
    return first
}

private func joining(at address: URL, token: String, displayName: String, password: String, session: URLSession,
                     headers: [String: String]) async -> JoinOutcome {
    let refused = "That invite did not work. Ask for a new one."
    do {
        let username = try await FamilyWeb(server: address, session: session, headers: headers)
            .join(token: token, password: password, displayName: displayName)
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .failed("The server did not answer with a username. Ask for a new invite.", unreachable: false)
        }
        return .signedUp(username: username, password: password, at: address)
    } catch {
        switch SubsonicError(error) {
        case .wrongCredentials(let message):
            return .failed(message.isEmpty ? refused : message, unreachable: false)
        case .unreachable(_, let certificate):
            return certificate ? .untrusted(host: address.host ?? "")
                : .failed("Octo can't reach that address. Check it and try again.", unreachable: true)
        case .notSubsonic(let message, let status):
            if status == 404 { return .failed("That server has no family sign-up. Check the address, or update Octo on the server.", unreachable: false) }
            return .failed(status != nil ? message : "That address did not answer like an Octo server.", unreachable: false)
        case let other:
            return .failed(other.message.isEmpty ? refused : other.message, unreachable: false)
        }
    }
}
