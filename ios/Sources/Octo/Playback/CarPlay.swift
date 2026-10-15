import CarPlay
import OctoKit
import UIKit

/// What the car's screen reaches: the player and the library. Set as the app starts.
@MainActor
enum CarLink {
    static weak var player: Player?
}

/// Octo in the car: tabs for Recent, Playlists, Albums and Artists, each list playing from where
/// it is chosen, and the system's now playing screen with Octo's song on it. The car only shows
/// apps signed with Apple's CarPlay audio entitlement.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var interfaceController: CPInterfaceController?
    private var library: CarLibrary?

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated {
            self.interfaceController = interfaceController
            guard let player = CarLink.player else { return }
            let library = CarLibrary(player: player, interface: interfaceController)
            self.library = library
            player.onLibraryChanged = { [weak library] in library?.reload() }
            player.onHeartChange = { [weak library] heart in library?.showHeart(heart) }
            library.showHeart(player.heart)
            interfaceController.setRootTemplate(library.root(), animated: false, completion: nil)
        }
    }

    func templateApplicationScene(_ scene: CPTemplateApplicationScene, didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        MainActor.assumeIsolated {
            self.interfaceController = nil
            library = nil
            CarLink.player?.onLibraryChanged = nil
            CarLink.player?.onHeartChange = nil
        }
    }
}

/// The car's browse tree, read from the library.
@MainActor
final class CarLibrary {
    private unowned let player: Player
    private weak var interface: CPInterfaceController?
    private let recent = CPListTemplate(title: "Recent", sections: [])
    private let playlists = CPListTemplate(title: "Playlists", sections: [])
    private let albums = CPListTemplate(title: "Albums", sections: [])
    private let artists = CPListTemplate(title: "Artists", sections: [])

    init(player: Player, interface: CPInterfaceController) {
        self.player = player
        self.interface = interface
        recent.tabImage = UIImage(systemName: "clock")
        playlists.tabImage = UIImage(systemName: "music.note.list")
        albums.tabImage = UIImage(systemName: "square.stack")
        artists.tabImage = UIImage(systemName: "music.mic")
    }

    func root() -> CPTabBarTemplate {
        reload()
        return CPTabBarTemplate(templates: [recent, playlists, albums, artists])
    }

    /// Reads every tab again, as after a server switch.
    func reload() {
        Task {
            await fillRecent()
            await fillPlaylists()
            await fillAlbums()
            await fillArtists()
        }
    }

    private var data: DataServices? { player.data }
    private var most: Int { CPListTemplate.maximumItemCount }

    // MARK: Tabs

    /// The 20 albums played most recently, then the 20 most played songs.
    private func fillRecent() async {
        guard let library = data?.library else { return }
        let played = await library.recentlyPlayedAlbums(limit: 20)
        let songs = await library.mostPlayedTracks(limit: 20)
        let albumItems = played.map(albumItem)
        let ids = songs.map(\.id)
        let songItems = songs.enumerated().map { index, track in
            item(track.title, track.artist, track.artwork) { [weak self] in
                self?.play(ids, from: index)
            }
        }
        recent.updateSections([
            CPListSection(items: Array(albumItems.prefix(most / 2)), header: "Recently played", sectionIndexTitle: nil),
            CPListSection(items: Array(songItems.prefix(most / 2)), header: "Most played", sectionIndexTitle: nil),
        ].filter { !$0.items.isEmpty })
    }

    /// "Liked songs" when there are likes, then each playlist.
    private func fillPlaylists() async {
        guard let library = data?.library else { return }
        var items: [CPListItem] = []
        let liked = await library.likedCount()
        if liked > 0 {
            items.append(item("Liked songs", songCount(liked), nil) { [weak self] in
                self?.openList("Liked songs") { await $0.likedTracks() }
            })
        }
        for list in await library.playlists() {
            items.append(item(list.name, songCount(list.songCount), list.covers.first) { [weak self] in
                self?.openList(list.name) { await $0.playlistTracks(list.id).map(\.track) }
            })
        }
        playlists.updateSections([CPListSection(items: Array(items.prefix(most)))])
    }

    /// An album, a playlist or Liked songs opens its songs, with Play first to play it from the
    /// top; choosing a song plays the list from that song.
    private func openList(_ title: String, _ songs: @escaping @MainActor (Library) async -> [LibraryTrack]) {
        Task {
            guard let library = data?.library else { return }
            let tracks = await songs(library)
            let ids = tracks.map(\.id)
            var rows = [item("Play", songCount(tracks.count), nil, symbol: "play.fill") { [weak self] in self?.play(ids, from: 0) }]
            rows += tracks.prefix(max(0, most - 1)).enumerated().map { index, track in
                item(track.title, track.artist, track.artwork) { [weak self] in self?.play(ids, from: index) }
            }
            interface?.pushTemplate(CPListTemplate(title: title, sections: [CPListSection(items: rows)]), animated: true, completion: nil)
        }
    }

    private func fillAlbums() async {
        guard let library = data?.library else { return }
        let all = await library.albums()
        albums.updateSections([CPListSection(items: Array(all.prefix(most)).map(albumItem))])
    }

    private func fillArtists() async {
        guard let library = data?.library else { return }
        let all = await library.artists()
        let items = Array(all.prefix(most)).map { artist in
            item(artist.name, nil, artist.artwork) { [weak self] in self?.openArtist(artist) }
        }
        artists.updateSections([CPListSection(items: items)])
    }

    /// An artist opens their albums.
    private func openArtist(_ artist: LibraryArtist) {
        Task {
            guard let albumsOf = await data?.library.artistAlbums(artist.id) else { return }
            let page = CPListTemplate(title: artist.name, sections: [CPListSection(items: Array(albumsOf.prefix(most)).map(albumItem))])
            interface?.pushTemplate(page, animated: true, completion: nil)
        }
    }

    private func albumItem(_ album: LibraryAlbum) -> CPListItem {
        item(album.title, album.artist, album.artwork) { [weak self] in
            self?.openList(album.title) { await $0.albumTracks(album.id) }
        }
    }

    private func songCount(_ count: Int) -> String { count == 1 ? "1 song" : "\(count) songs" }

    // MARK: Rows

    private func item(_ text: String, _ detail: String?, _ artwork: String?, symbol: String = "music.note",
                      choose: @escaping @MainActor () -> Void) -> CPListItem {
        let row = CPListItem(text: text, detailText: detail, image: UIImage(systemName: symbol))
        row.handler = { _, done in
            MainActor.assumeIsolated { choose() }
            done()
        }
        if let artwork { loadCover(artwork, into: row) }
        return row
    }

    /// Car covers are drawn about 320 px wide.
    private func loadCover(_ artwork: String, into row: CPListItem) {
        let session = player.session
        Task {
            if let image = await ArtworkCache.shared.image(artwork, px: 320, client: session.client, signedInSource: session.inUse?.sourceId) {
                row.setImage(image)
            }
        }
    }

    /// The heart for a library song, or the download for a song found online, beside the
    /// song on the car's now playing screen.
    func showHeart(_ heart: NotificationHeart) {
        var buttons: [CPNowPlayingButton] = []
        switch heart {
        case .like(let liked):
            if let image = UIImage(systemName: liked ? "heart.fill" : "heart") {
                buttons.append(CPNowPlayingImageButton(image: image) { [weak self] _ in
                    MainActor.assumeIsolated { self?.player.likeFromOutside() }
                })
            }
        case .download:
            buttons.append(CPNowPlayingAddToLibraryButton { [weak self] _ in
                MainActor.assumeIsolated { self?.player.downloadFromOutside() }
            })
        case .none:
            break
        }
        CPNowPlayingTemplate.shared.updateNowPlayingButtons(buttons)
    }

    /// Plays a list from one of its songs. Lists chosen in the car carry no name.
    private func play(_ ids: [String], from index: Int) {
        guard !ids.isEmpty else { return }
        player.play(ids: ids, from: index)
        interface?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil)
    }
}
