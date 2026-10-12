#if DEBUG
import Foundation
import OctoKit
import SwiftUI

/// The library's OCTO_DRIVE steps:
///
/// - `page:NAME` opens a library page: playlists, favorites, liked, favorite-albums,
///   favorite-artists, artists, albums, songs, genres, folders, history, mostplayed, downloads,
///   health, removed, or a health check by name (`page:health-Duplicates`)
/// - `album:NAME`, `artist:NAME`, `playlist:NAME`, `genre:NAME` open that page, by name
/// - `menu:song`, `menu:album`, `menu:artist`, `menu:playlist` (or `menu:song=TITLE`) open that
///   menu for the first such item (or the one named), beside nothing, in the middle;
///   `menu:song:PAGE` opens it on a page: rate, share, info, playlist, delete
/// - `info:TITLE` opens the song info pop-up
/// - `sort:LIST:OPTION:asc|desc` sets a list's order, like `sort:songs:Year:desc`
/// - `pick:COUNT` picks the first COUNT songs of the open page that can pick songs
/// - `songs-search:TEXT` opens Songs with the search open and the words typed
@MainActor
enum LibraryDrive {
    /// Words for the Songs page's search when it opens.
    static var pendingSearch: String?

    /// Adds the library's steps to the drive.
    static func install(router: Router) {
        Drive.steps.append { name, value in
            guard ["page", "album", "artist", "playlist", "genre", "menu", "info", "sort", "pick", "songs-search"].contains(name) else {
                return false
            }
            await step(name, value, router: router)
            return true
        }
    }

    static func step(_ name: String, _ value: String, router: Router) async {
        guard let actions = LibraryActions.current else { return }
        let library = actions.state.library
        if name != "menu" && name != "info" && name != "pick" && name != "sort" {
            router.drive = .tab(.library)
            try? await Task.sleep(for: .milliseconds(300))
        }
        switch name {
        case "page":
            if let route = route(value) { router.go(route) }
        case "album":
            if let album = await library.search(value, artists: 0, albums: 5, songs: 0).albums.first { router.go(.album(album.asAlbum)) }
        case "artist":
            if let artist = await library.search(value, artists: 5, albums: 0, songs: 0).artists.first {
                router.go(.artist(id: artist.id, name: artist.name))
            }
        case "playlist":
            if let playlist = await library.playlists().first(where: { $0.name.caseInsensitiveCompare(value) == .orderedSame }) {
                router.go(.library(.playlist(id: playlist.id)))
            }
        case "genre":
            router.go(.library(.genre(value)))
        case "menu":
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            guard let subject = await menu(parts.first ?? "song", library: library, state: actions.state) else { return }
            actions.openMenu(subject, page: parts.count > 1 ? page(parts[1]) : nil)
        case "info":
            if let track = await library.search(value, artists: 0, albums: 0, songs: 5).tracks.first {
                actions.openMenu(.songInfo(SongSubject(track: track, song: track.asSong)))
            }
        case "sort":
            let parts = value.split(separator: ":").map(String.init)
            guard parts.count == 3, let list = SortList.allCases.first(where: { $0.key == parts[0] || $0.rawValue == parts[0] }) else { return }
            actions.state.setOrder(list, list.decode("\(parts[1]):\(parts[2])"))
        case "pick":
            guard let target = actions.selectionBar?.targets.last else { return }
            for pick in target.list.prefix(max(1, Int(value) ?? 1)) {
                if target.selection.active { target.selection.toggle(pick.key) } else { target.selection.start(pick.key) }
            }
        case "songs-search":
            pendingSearch = value
            router.go(.library(.songs))
        default:
            break
        }
    }

    private static func route(_ name: String) -> Route? {
        let lower = name.lowercased()
        if lower.hasPrefix("health-") { return .library(.healthCheck(String(name.dropFirst("health-".count)))) }
        switch lower {
        case "playlists": return .playlists
        case "favorites": return .favorites
        case "liked": return .library(.favorites(.songs))
        case "favorite-albums": return .library(.favorites(.albums))
        case "favorite-artists": return .library(.favorites(.artists))
        case "artists": return .artists
        case "albums": return .albums
        case "songs": return .library(.songs)
        case "genres": return .library(.genres)
        case "folders": return .library(.folders)
        case "history": return .library(.history(mostPlayed: false))
        case "mostplayed": return .library(.history(mostPlayed: true))
        case "downloads": return .library(.downloads)
        case "health": return .library(.health)
        case "removed": return .library(.recentlyRemoved)
        default: return nil
        }
    }

    private static func page(_ name: String) -> MenuPage? {
        switch name {
        case "rate": .rate
        case "share": .share
        case "info": .info
        case "playlist": .addToPlaylist(startAt: nil)
        case "delete": .deleteFromDisk
        case "rename": .rename
        default: nil
        }
    }

    private static func menu(_ value: String, library: Library, state: LibraryState) async -> MenuSubject? {
        let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "song"
        let named = parts.count > 1 ? parts[1] : nil
        switch kind {
        case "song":
            let track = if let named { await library.search(named, artists: 0, albums: 0, songs: 5).tracks.first } else {
                await library.tracks().first
            }
            return track.map { .song(SongSubject(track: $0, song: $0.asSong)) }
        case "album":
            let album = if let named { await library.search(named, artists: 0, albums: 5, songs: 0).albums.first } else {
                await library.albums().first
            }
            return album.map { .album($0) }
        case "artist":
            let artist = if let named { await library.search(named, artists: 5, albums: 0, songs: 0).artists.first } else {
                await library.artists().first
            }
            return artist.map { .artist($0) }
        case "playlist":
            let lists = await library.playlists()
            let playlist = named.flatMap { name in lists.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } } ?? lists.first
            return playlist.map { .playlist($0) }
        default:
            return nil
        }
    }
}
#endif
