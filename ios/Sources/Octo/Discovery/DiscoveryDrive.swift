#if DEBUG
import Foundation
import OctoKit

/// Launch steps that reach the discovery screens:
///
/// - `query:TEXT` opens Search and types TEXT into its field
/// - `charts` opens the Charts page
/// - `whatsnew` makes the What's new card due again and opens Home
/// - `livelist:new` opens the editor for a new live list; `livelist:ID` opens that live list
/// - `downloads` opens the server downloads sheet on its list
/// - `log:first` or `log:running` opens the log of the first download the server lists, or the
///   first still running
/// - `findsongs:TEXT` opens Find songs for the first song a search for TEXT finds
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
        case "whatsnew":
            // Forgets which notes were seen, so Home shows the card when it opens next.
            UserDefaults.standard.set(0, forKey: "whats_new.last_seen_version")
            router.drive = .tab(.home)
            NotificationCenter.default.post(name: .driveWhatsNew, object: nil)
        case "livelist":
            if value.isEmpty || value == "new" { router.go(.liveListEditor(id: nil)) } else { router.go(.liveList(id: value)) }
        case "downloads":
            router.serverDownloads = .list(focus: nil)
        case "log":
            guard let client = session.client, let list = try? await client.acquisitions() else { return }
            let keyed = list.filter { $0.key != nil }
            let pickedRow = value == "running" ? keyed.first { $0.stage != .done && $0.stage != .failed } ?? keyed.first : keyed.first
            if let key = pickedRow?.key { router.serverDownloads = .log(key: key) }
        case "findsongs":
            guard let client = session.client, let found = try? await client.search(value, artists: 0, albums: 0, songs: 20),
                  let song = found.song.first
            else { return }
            router.serverDownloads = .find(id: song.id, title: song.title, from: nil)
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
