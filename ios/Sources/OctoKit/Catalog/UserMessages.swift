import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What to tell someone when a request to the server fails.
public func userMessage(_ error: Error) -> String {
    if let octo = error as? OctoError {
        switch octo {
        case .wrongCredentials: return SignInWords.wrongPassword
        case .authUnsupported(41, _): return SignInWords.needsLegacy
        case .authUnsupported: return SignInWords.wayRefused
        case .notFound: return "That isn't on the server any more."
        case .server(_, let message): return "The server said: \(message)"
        case .notSubsonic: return SignInWords.notMusic
        case .http(let status):
            return [502, 503, 504, 520, 521, 522, 523, 524, 530].contains(status) ? SignInWords.restarting : SignInWords.notMusic
        }
    }
    if error is URLError { return SignInWords.unreachable }
    return SignInWords.somethingWrong
}

/// Whether an error is only the work being stopped, which says nothing to anyone.
public func isCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let url = error as? URLError, url.code == .cancelled { return true }
    return false
}
