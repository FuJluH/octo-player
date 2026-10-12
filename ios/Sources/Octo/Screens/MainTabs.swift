import OctoKit
import SwiftUI

enum AppTab: Hashable {
    case home, library, settings, search
}

/// Where a tap goes inside a tab.
enum Route: Hashable {
    case album(Album)
    case artist(id: String, name: String)
    case playlist(Playlist)
    case artists, albums, playlists, favorites
}

/// The app's frame: Apple's own Liquid Glass tab bar, with the mini player as its accessory, and
/// the full player opening out of the mini player.
struct MainTabs: View {
    @Environment(Player.self) private var player
    @State private var tab: AppTab = .home
    @State private var showsPlayer = false
    @Namespace private var playerSpace

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house.fill", value: AppTab.home) {
                NavigationStack { HomeView().routes() }
            }
            Tab("Library", systemImage: "square.stack.fill", value: AppTab.library) {
                NavigationStack { LibraryView().routes() }
            }
            Tab("Settings", systemImage: "gearshape.fill", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack { SearchView().routes() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .miniPlayer(shown: player.current != nil) {
            MiniPlayer { showsPlayer = true }
                .matchedTransitionSource(id: "player", in: playerSpace)
        }
        .fullScreenCover(isPresented: $showsPlayer) {
            NowPlayingView()
                .navigationTransition(.zoom(sourceID: "player", in: playerSpace))
        }
    }
}

extension View {
    /// The mini player in the tab bar's accessory, only while something is playing. iOS 26.0 has
    /// no switch for the accessory, so there it is added and taken away instead.
    @ViewBuilder
    func miniPlayer<Accessory: View>(shown: Bool, @ViewBuilder accessory: () -> Accessory) -> some View {
        if #available(iOS 26.1, *) {
            tabViewBottomAccessory(isEnabled: shown, content: accessory)
        } else if shown {
            tabViewBottomAccessory(content: accessory)
        } else {
            self
        }
    }

    /// Every page a tab can open.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .album(let album): AlbumView(album: album)
            case .artist(let id, let name): ArtistView(id: id, name: name)
            case .playlist(let playlist): PlaylistView(playlist: playlist)
            case .artists: ArtistsView()
            case .albums: AlbumsView()
            case .playlists: PlaylistsView()
            case .favorites: FavoritesView()
            }
        }
        .background(OctoColor.background)
    }
}
