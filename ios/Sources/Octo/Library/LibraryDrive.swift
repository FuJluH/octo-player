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
/// - `menu:song`, `menu:album`, `menu:artist`, `menu:playlist`, `menu:options` (a playlist page's
///   options), or `menu:song=TITLE` for the one named: the menu laid out as a list on a sheet,
///   since a menu opens only under a finger. `menu:KIND:WHAT` opens what a row of it opens
///   instead: `info` (song info), `playlist` (the playlist sheet), `new` (a new playlist's name),
///   `rename`, `delete` (the question before deleting)
/// - `info:TITLE` opens the song info sheet
/// - `sort:LIST:OPTION:asc|desc` sets a list's order, like `sort:songs:Year:desc`
/// - `pick:COUNT` picks the first COUNT songs of the open page that can pick songs
/// - `songs-search:TEXT` opens Songs with the search open and the words typed
/// - `songs-filter:CHIPS` opens Songs with chips on, comma separated: favorites, week, month,
///   year, never, lately, lossless, rating4 (any stars), decade1990 (any decade)
/// - `shufflelibrary` plays the whole library shuffled, as a list's Shuffle button does
/// - `menu:live` (or `menu:live=NAME`) lays a live list's options out on a sheet;
///   `menu:live:rename` and `menu:live:delete` ask its name and its delete question
@MainActor
enum LibraryDrive {
    /// Words for the Songs page's search when it opens.
    static var pendingSearch: String?
    /// Chips to switch on as the Songs page opens.
    static var pendingFilters: [QueryRule]?

    /// Adds the library's steps to the drive.
    static func install(router: Router) {
        Drive.steps.append { name, value in
            guard ["page", "album", "artist", "playlist", "genre", "menu", "info", "sort", "pick", "songs-search", "songs-filter", "shufflelibrary"]
                .contains(name) else {
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
        case "shufflelibrary":
            actions.play(await library.tracks(), shuffled: true)
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
            guard let content = await menu(parts.first ?? "song", library: library) else { return }
            open(content, parts.count > 1 ? parts[1] : nil, actions: actions)
        case "info":
            if let track = await library.search(value, artists: 0, albums: 0, songs: 5).tracks.first {
                actions.showInfo(SongSubject(track: track, song: track.asSong))
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
        case "songs-filter":
            pendingFilters = value.split(separator: ",").compactMap { chip(String($0)) }
            router.go(.library(.songs))
        default:
            break
        }
    }

    /// A Songs chip by a short name.
    private static func chip(_ name: String) -> QueryRule? {
        let lower = name.lowercased()
        if lower.hasPrefix("rating"), let stars = Int(lower.dropFirst("rating".count)) { return FilterPresets.ratingAtLeast(stars) }
        if lower.hasPrefix("decade"), let start = Int(lower.dropFirst("decade".count)) { return FilterPresets.decade(start) }
        switch lower {
        case "favorites": return FilterPresets.favorites
        case "week": return FilterPresets.addedThisWeek
        case "month": return FilterPresets.addedThisMonth
        case "year": return FilterPresets.addedThisYear
        case "never": return FilterPresets.neverPlayed
        case "lately": return FilterPresets.notPlayedLately
        case "lossless": return FilterPresets.lossless
        default: return lower.hasPrefix("genre=") ? FilterPresets.genre(String(name.dropFirst("genre=".count))) : nil
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

    /// Opens a menu laid out on a sheet, or what one of its rows opens.
    private static func open(_ content: MenuPreview.Content, _ what: String?, actions: LibraryActions) {
        switch (content, what) {
        case (.song(let subject), "info"):
            actions.showInfo(subject)
        case (.song(let subject), "playlist"):
            actions.playlistPick = PlaylistPick(source: .tracks([subject.track]))
        case (.song(let subject), "new"):
            actions.askNewPlaylist(.tracks([subject.track]))
        case (.song(let subject), "delete"):
            actions.askDeleteFromDisk([subject.track])
        case (.collection(let subject), "playlist"):
            actions.playlistPick = PlaylistPick(source: .collection(subject.target))
        case (.collection(.playlist(let playlist)), "rename"), (.playlistOptions(let playlist), "rename"):
            actions.askRename(playlist)
        case (.collection(.playlist(let playlist)), "delete"), (.playlistOptions(let playlist), "delete"):
            actions.askDeletePlaylist(playlist)
        case (.liveListOptions(let list), "rename"):
            if let store = LiveListStore.current { actions.askRename(list, in: store) }
        case (.liveListOptions(let list), "delete"):
            if let store = LiveListStore.current { actions.askDelete(list, in: store) }
        default:
            actions.previewMenu(content)
        }
    }

    private static func menu(_ value: String, library: Library) async -> MenuPreview.Content? {
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
            return album.map { .collection(.album($0)) }
        case "artist":
            let artist = if let named { await library.search(named, artists: 5, albums: 0, songs: 0).artists.first } else {
                await library.artists().first
            }
            return artist.map { .collection(.artist($0)) }
        case "playlist", "options":
            let lists = await library.playlists()
            let playlist = named.flatMap { name in lists.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } } ?? lists.first
            return playlist.map { kind == "options" ? .playlistOptions($0) : .collection(.playlist($0)) }
        case "live":
            let lists = LiveListStore.current?.lists ?? []
            let list = named.flatMap { name in lists.first { $0.name.caseInsensitiveCompare(name) == .orderedSame } } ?? lists.first
            return list.map { .liveListOptions($0) }
        default:
            return nil
        }
    }
}
#endif
