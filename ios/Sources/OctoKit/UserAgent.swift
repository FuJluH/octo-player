import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// How every request the app sends names it: "Octo/1.9.0 (iPhone)", as Android sends
/// "(Android)" and the desktop its system, so a server can tell the app and the platform apart.
public func octoUserAgent(_ version: String) -> String { "Octo/\(version) (iPhone)" }

public extension URLSessionConfiguration {
    /// Names the app in every request the session sends, so none goes out with the system's own
    /// name. A request that sets its own User-Agent keeps it.
    func namingOcto(_ version: String) -> URLSessionConfiguration {
        var headers = httpAdditionalHeaders ?? [:]
        headers["User-Agent"] = octoUserAgent(version)
        httpAdditionalHeaders = headers
        return self
    }
}
