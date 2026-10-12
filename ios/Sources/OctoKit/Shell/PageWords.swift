import Foundation

/// A song's length as a clock, like 3:07 or 1:02:45.
public func asClock(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// An album's or playlist's length in words, rounded to the nearest minute, like 48 min or
/// 1 hr 12 min.
public func asLength(_ seconds: Int) -> String {
    let minutes = (seconds + 30) / 60
    return minutes >= 60 ? "\(minutes / 60) hr \(minutes % 60) min" : "\(minutes) min"
}

public func songsCount(_ count: Int) -> String { count == 1 ? "1 song" : "\(count) songs" }

public func albumsCount(_ count: Int) -> String { count == 1 ? "1 album" : "\(count) albums" }

/// What a proxy or tunnel answers while the server behind it is restarting or down.
public let busyStatuses: Set<Int> = [502, 503, 504, 520, 521, 522, 523, 524, 530]

/// What to tell someone when a request fails. A cancelled request is not a failure and has no
/// words: it gives nil.
public func userMessage(for error: Error) -> String? {
    if error is CancellationError { return nil }
    if let error = error as? URLError {
        if error.code == .cancelled { return nil }
        return "Couldn't reach the server. Check the address, and that you're on the right network."
    }
    guard let error = error as? OctoError else { return "Something went wrong." }
    switch error {
    case .notSubsonic:
        return "That address answered, but not like a music server. Check the port."
    case .http(let status):
        return busyStatuses.contains(status)
            ? "The server isn't answering right now. It may be restarting, so try again in a moment."
            : "That address answered, but not like a music server. Check the port."
    case .wrongCredentials:
        return "Wrong username or password."
    case .authUnsupported(let code, _):
        return code == 41
            ? "This account can't sign in with a token. Turn on Legacy sign-in under Advanced."
            : "The server doesn't take this way of signing in."
    case .notFound:
        return "That isn't on the server any more."
    case .server(_, let message):
        return "The server said: \(message)"
    }
}
