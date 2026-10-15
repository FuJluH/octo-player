#if DEBUG
import Foundation
import OctoKit

/// Steps for the OCTO_DRIVE launch variable that reach the library's data, each answering with a
/// short line on screen so a run can be read from a screenshot:
///
/// - `catalog` shows how many songs, albums, artists, playlists and likes the library holds
/// - `sync` copies the server's library now and shows how it went
/// - `like:TEXT` likes (or unlikes) the first library song a search for TEXT finds
/// - `rate:N:TEXT` rates that song N stars (0 takes the rating off)
/// - `playlist:NAME` makes a phone playlist NAME with the first five songs of the library
/// - `pin` pins the newest album to Home
/// - `history` shows how many plays the history holds and the first day heading
/// - `phone` shows the phone's music as the settings see it: access, songs, folders, protected songs
/// - `download:TEXT` downloads the first library song a search for TEXT finds
/// - `offline` shows how many downloads kept on the phone there are in each state
/// - `refresh` runs a pull to refresh and shows how it went
@MainActor
enum DataDrive {
    static func install(_ data: DataServices, show: @escaping @MainActor (String) -> Void) {
        Drive.steps.append { name, value in
            await run(data, name, value, show)
        }
    }

    private static func run(_ data: DataServices, _ name: String, _ value: String, _ show: @MainActor (String) -> Void) async -> Bool {
        let library = data.library
        switch name {
        case "covertime":
            await CoverTiming.run(session: data.session, library: library, count: Int(value) ?? 10)
        case "catalog":
            let line = "\(await library.trackCount()) songs, \(await library.albumCount()) albums, \(await library.artistCount()) artists, "
                + "\(await library.playlists().count) playlists, \(await library.likedCount()) liked"
            show(line)
        case "sync":
            let problem = await data.serverSync.syncNowAndWait()
            show(problem ?? "Copied: \(data.serverSync.last?.songs ?? 0) songs")
        case "like":
            guard let song = await library.search(value).tracks.first else { show("No song for \(value)"); return true }
            data.likes.toggle(song.id)
            show("Like changed: \(song.title)")
        case "rate":
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let stars = Int(parts[0]), let song = await library.search(parts[1]).tracks.first else { return true }
            data.ratings.rate(song.id, stars)
            show("Rated \(song.title): \(stars)")
        case "playlist":
            let songs = Array(await library.tracks().prefix(5)).map(\.id)
            data.playlists.create(value, trackIds: songs)
            show("Made \(value) with \(songs.count) songs")
        case "pin":
            guard let album = await library.recentAlbums(limit: 1).first else { return true }
            let pinned = await data.pins.pin(.album, album.id)
            show(pinned ? "Pinned \(album.title)" : "Home is full")
        case "history":
            let days = await library.historyDays()
            show("\(days.reduce(0) { $0 + $1.plays.count }) plays, \(days.first?.label ?? "none")")
        case "phone":
            let phone = PhoneMusic.shared
            show("\(phone.access), \(phone.songCount) songs, \(phone.folders.count) folders, \(data.device.protectedSongs) protected")
        case "download":
            guard let song = await library.search(value).tracks.first else { show("No song for \(value)"); return true }
            data.offline.download([song.id])
            show("Download asked: \(song.title)")
        case "offline":
            let rows = data.offline.rows
            let states = Dictionary(grouping: rows, by: { "\($0.state)" }).map { "\($0.value.count) \($0.key)" }.sorted()
            show(rows.isEmpty ? "No downloads" : states.joined(separator: ", "))
        case "refresh":
            let problem = await data.refresh.refresh()
            show(problem ?? "Refreshed")
        default:
            return false
        }
        return true
    }
}
#endif
