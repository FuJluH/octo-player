import Foundation

/// What the Change password form holds: the password now, the new one, and the new one again.
public struct PasswordDraft: Sendable, Equatable {
    public var current: String
    public var new: String
    public var confirm: String

    public init(current: String = "", new: String = "", confirm: String = "") {
        self.current = current
        self.new = new
        self.confirm = confirm
    }
}

/// What keeps the form from being sent, in plain words, or nil when it can go. Nothing is asked
/// of the server for these.
public func passwordDraftProblem(_ draft: PasswordDraft) -> String? {
    if draft.current.isEmpty { return "Enter your current password." }
    if draft.new.isEmpty { return "Enter a new password." }
    if draft.confirm != draft.new { return "The new passwords don't match." }
    if draft.new == draft.current { return "That's the password you have now. Choose a new one." }
    return nil
}

/// How a change of password went.
public enum PasswordChange: Sendable, Equatable {
    case changed
    /// The password typed as the current one is not it.
    case wrongCurrent
    /// The server does not let this account change its password.
    case notAllowed
    /// The server takes no new passwords from apps, or would only take one in the address.
    case notOffered
    /// Signed in with an API key: there is no password here to change.
    case usesKey
    case failed(String)
}

/// Changes the signed-in user's own password. The current one is checked first by signing in
/// with it, so a mistyped one is caught before anything changes. Keeping the new one is the
/// caller's part. A family member's password goes through the family's own call, which also
/// signs out every other app and device.
public func changeOwnPassword(_ client: SubsonicClient, current: String, new: String, family: Bool = false) async -> PasswordChange {
    if client.credentials.mode == .apiKey { return .usesKey }
    do {
        _ = try await client.withSecret(current).ping()
    } catch {
        if case .wrongCredentials = SubsonicError(error) { return .wrongCurrent }
        return passwordFailure(error)
    }
    do {
        if family {
            try await client.changeFamilyPassword(current: current, next: new)
        } else {
            try await client.changePassword(username: client.credentials.username, password: new)
        }
        return .changed
    } catch {
        return passwordFailure(error)
    }
}

private func passwordFailure(_ error: Error) -> PasswordChange {
    let failure = SubsonicError(error)
    switch failure {
    case .server(50, _): return .notAllowed
    // A server that ignored the form body misses the new password.
    case .server(10, _): return .notOffered
    case .notSubsonic(_, let status?) where [404, 405, 501].contains(status): return .notOffered
    case .unreachable: return .failed("Couldn't reach the server, so nothing changed. Try again in a moment.")
    case .notSubsonic where failure.serverBusy:
        return .failed("The server isn't answering right now, so nothing changed. Try again in a moment.")
    default:
        let message = failure.message.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed("The server couldn't change the password" + (message.isEmpty ? "" : ": \(failure.message)") + ".")
    }
}

/// What to tell the listener about a change of password. A family member's change signs every
/// other app and device out.
public func passwordChangeWords(_ result: PasswordChange, family: Bool = false) -> String {
    switch result {
    case .changed:
        family ? "Your password is changed. Octo uses the new one; every other app and device now needs it."
            : "Your password is changed. Octo uses the new one from now on."
    case .wrongCurrent: "That isn't your current password."
    case .notAllowed: "Your server doesn't let this account change its password. Ask whoever runs the server."
    case .notOffered: "Your server doesn't take new passwords from apps. Change it on the server's own web page."
    case .usesKey: "You signed in with an API key, so there's no password here to change."
    case .failed(let message): message
    }
}

/// What to do when the usual sign-in with a token fails.
public enum LegacyRetry: Sendable, Equatable {
    /// Not a token the server refused: nothing to change.
    case none
    /// The server takes only the password itself, and the address keeps it safe enough.
    case retry
    /// The server takes only the password itself, but it would cross the internet unencrypted.
    case unsafe
}

/// Whether a failed sign-in should be tried again with the password itself. Only for error 41,
/// a server that cannot check tokens.
public func legacyRetry(_ error: Error?, mode: AuthMode, url: URL) -> LegacyRetry {
    guard mode == .token, let error, case .authNotSupported(41, _) = SubsonicError(error) else { return .none }
    return url.scheme?.lowercased() == "https" || ServerAddress.isPrivate(url) ? .retry : .unsafe
}

/// Said when a server needs the password itself over plain http outside the home network.
public let legacyUnsafeMessage =
    "This server needs the password sent as it is, which isn't safe over http. Use https, or turn on Legacy sign-in under Advanced."
