import Foundation

extension SubsonicClient {
    /// The server call that stars or unstars albums or artists, each by its own parameter
    /// (albumId or artistId), never as a song id. Several go in one call.
    public func favoriteCall(_ kind: FavoriteKind, star: Bool) -> @Sendable ([String]) async throws -> Void {
        let endpoint = star ? "star" : "unstar"
        let parameter = kind == .album ? "albumId" : "artistId"
        return { [self] ids in
            try await call(endpoint, ids.map { (parameter, $0) })
        }
    }
}
