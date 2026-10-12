import Foundation
import OctoKit

/// The server a change is for: its client, its account (the kept server's id), its source, and
/// what it can do. Captured when the change is made, so it is sent there even after a switch.
struct ServerInUse: @unchecked Sendable {
    let client: SubsonicClient
    let account: String
    let sourceId: String
    let extensions: [String]
    let isOcto: Bool

    var username: String { client.credentials.username }

    /// Whether the server takes a call's params in a form body.
    var formPost: Bool { extensions.contains { $0.hasPrefix(formPostExtension + ":") } }

    func lists(_ name: String, version: Int = 1) -> Bool { extensions.contains("\(name):\(version)") }
}

extension Session {
    /// The server in use, while one is signed in.
    var inUse: ServerInUse? {
        guard let client, let server = active, !server.signedOut else { return nil }
        return ServerInUse(client: client, account: server.id, sourceId: server.sourceId,
                           extensions: profile?.extensions ?? server.extensions, isOcto: isOcto)
    }
}

/// Runs a server call, handing back what went wrong, if anything.
@MainActor
func failureOf(_ call: @MainActor () async throws -> Void) async -> Error? {
    do {
        try await call()
        return nil
    } catch {
        return error
    }
}
