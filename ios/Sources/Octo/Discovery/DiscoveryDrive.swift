#if DEBUG
import Foundation
import OctoKit

/// Launch steps that reach the discovery screens:
///
/// - `query:TEXT` opens Search and types TEXT into its field
/// - `charts` opens the Charts page
/// - `onlinealbum:TEXT` opens the first album not in the library that a search for TEXT finds
/// - `onlineartist:TEXT` opens the first artist not in the library that a search for TEXT finds
@MainActor
enum DiscoveryDrive {
    static func step(_ name: String, _ value: String, session: Session, router: Router) async {
        switch name {
        case "query":
            router.drive = .tab(.search)
            try? await Task.sleep(for: .milliseconds(500))
            NotificationCenter.default.post(name: .driveSearch, object: value)
        case "charts":
            router.go(.charts)
        case "onlinealbum":
            guard let client = session.client, let found = try? await client.search(value, artists: 10, albums: 20, songs: 40),
                  let album = found.album.first(where: \.isExternal)
            else { return }
            router.go(.onlineAlbum(id: album.id, name: album.name))
        case "onlineartist":
            guard let client = session.client, let found = try? await client.search(value, artists: 10, albums: 20, songs: 40),
                  let artist = found.artist.first(where: { isOnlineId($0.id) })
            else { return }
            router.go(.onlineArtist(id: artist.id, name: artist.name))
        default:
            break
        }
    }
}
#endif
