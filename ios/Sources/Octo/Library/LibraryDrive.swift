#if DEBUG
import Foundation
import OctoKit
import SwiftUI

/// The library's OCTO_DRIVE steps:
///
/// - `page:NAME` opens a library page: library, playlists, favorites, liked, favorite-albums,
///   artists, albums, songs, genres, folders, history, mostplayed, downloads, health, removed
/// - `album:NAME`, `artist:NAME`, `playlist:NAME`, `genre:NAME` open that page, by name
/// - `menu:song`, `menu:album`, `menu:artist`, `menu:playlist` (or `menu:song=TITLE`) show the
///   menu's items for the first such item (or the one named) in a sheet, with the same groups,
///   words and states as the long-press menu
/// - `info:TITLE` opens the song info sheet
/// - `sort:LIST:OPTION:asc|desc` sets a list's order, like `sort:songs:Year:desc`
/// - `select:COUNT` picks the first COUNT songs of the page in front that can pick songs
/// - `songs-search:TEXT` opens Songs with the search open and the words typed
@MainActor
enum LibraryDrive {
    /// Asks the page in front to pick songs.
    static var pendingSelect = 0
    /// Words for the Songs page's search when it opens.
    static var pendingSearch: String?

    static func step(_ name: String, _ value: String, router: Router) async {
        guard let actions = LibraryActions.current else { return }
        let library = actions.state.library
        router.drive = .tab(.library)
        try? await Task.sleep(for: .milliseconds(300))
        switch name {
        case "page":
            if let route = route(value) { router.go(route) }
        case "album":
            let found = await library.search(value, artists: 0, albums: 5, songs: 0).albums.first
            if let album = found { router.go(.album(album.asAlbum)) }
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
            actions.drivenMenu = await menu(value, library: library, state: actions.state)
        case "info":
            if let track = await library.search(value, artists: 0, albums: 0, songs: 5).tracks.first {
                actions.songInfo = LibraryActions.InfoTarget(track: track, song: track.asSong)
            }
        case "sort":
            let parts = value.split(separator: ":").map(String.init)
            if parts.count == 3, let list = SortList.allCases.first(where: { $0.key == parts[0] || $0.rawValue == parts[0] }) {
                actions.state.setOrder(list, list.decode("\(parts[1]):\(parts[2])"))
            }
        case "select":
            pendingSelect = Int(value) ?? 1
        case "songs-search":
            pendingSearch = value
            router.go(.library(.songs))
        default:
            break
        }
    }

    private static func route(_ name: String) -> Route? {
        switch name.lowercased() {
        case "playlists": .playlists
        case "favorites": .favorites
        case "liked": .library(.favorites(.songs))
        case "favorite-albums": .library(.favorites(.albums))
        case "favorite-artists": .library(.favorites(.artists))
        case "artists": .artists
        case "albums": .albums
        case "songs": .library(.songs)
        case "genres": .library(.genres)
        case "folders": .library(.folders)
        case "history": .library(.history(mostPlayed: false))
        case "mostplayed": .library(.history(mostPlayed: true))
        case "downloads": .library(.downloads)
        case "health": .library(.health)
        case "removed": .library(.recentlyRemoved)
        default: nil
        }
    }

    private static func menu(_ value: String, library: Library, state: LibraryState) async -> DrivenMenu? {
        let parts = value.split(separator: "=", maxSplits: 1).map(String.init)
        let kind = parts.first ?? "song"
        let named = parts.count > 1 ? parts[1] : nil
        switch kind {
        case "song":
            let track = if let named { await library.search(named, artists: 0, albums: 0, songs: 5).tracks.first } else {
                await library.tracks().first
            }
            return track.map { .song($0) }
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

/// A menu shown as a sheet for checking from outside: the same items as its long-press menu.
enum DrivenMenu: Identifiable {
    case song(LibraryTrack)
    case album(LibraryAlbum)
    case artist(LibraryArtist)
    case playlist(PlaylistSummary)

    var id: String {
        switch self {
        case .song(let t): "song.\(t.id)"
        case .album(let a): "album.\(a.id)"
        case .artist(let a): "artist.\(a.id)"
        case .playlist(let p): "playlist.\(p.id)"
        }
    }
}

/// The items of a menu as a list, with its header on top.
struct DrivenMenuSheet: View {
    let menu: DrivenMenu

    var body: some View {
        List {
            switch menu {
            case .song(let track):
                MenuHeader(artwork: track.artwork, title: track.title, line: track.artist).listRowInsets(EdgeInsets())
                SongActions(track: track)
            case .album(let album):
                MenuHeader(artwork: album.artwork, title: album.title, line: album.artist).listRowInsets(EdgeInsets())
                CollectionActions(target: .album(album.id), album: album)
            case .artist(let artist):
                MenuHeader(artwork: artist.artwork, title: artist.name, line: albumsCount(artist.albumCount), round: true)
                    .listRowInsets(EdgeInsets())
                CollectionActions(target: .artist(artist.id), artist: artist)
            case .playlist(let playlist):
                MenuHeader(artwork: playlist.covers.first, title: playlist.name, line: songsCount(playlist.songCount))
                    .listRowInsets(EdgeInsets())
                CollectionActions(target: .playlist(playlist.id), playlist: playlist)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
