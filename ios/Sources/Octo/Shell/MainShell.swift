import OctoKit
import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case home, search, library, settings

    var title: String {
        switch self {
        case .home: "Home"
        case .search: "Search"
        case .library: "Library"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .search: "magnifyingglass"
        case .library: "square.stack"
        case .settings: "gearshape"
        }
    }

}

/// Where a tap goes inside a tab.
enum Route: Hashable {
    case album(Album)
    case artist(id: String, name: String)
    case playlist(Playlist)
    case artists, albums, playlists, favorites
    /// The library pages beyond these: songs, genres, folders, history, downloads and the rest.
    case library(LibraryPage)
}

/// The app's frame: every tab's pages, kept alive while another tab is in front, the floating
/// bar over them, messages above the bar, and the full player over everything.
struct MainShell: View {
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @Environment(Downloads.self) private var downloads
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("tab") private var tab: AppTab = .home
    @AppStorage("bar.player") private var playerMode = false
    @State private var paths: [AppTab: NavigationPath] = [:]
    @State private var playerOpen = false

    var body: some View {
        @Bindable var router = router
        ZStack(alignment: .bottom) {
            OctoColor.background.ignoresSafeArea()
            ZStack {
                ForEach(AppTab.allCases, id: \.self) { item in
                    NavigationStack(path: path(item)) {
                        root(item).routes()
                    }
                    .opacity(item == tab ? 1 : 0)
                    .scaleEffect(item == tab ? 1 : 0.97)
                    .allowsHitTesting(item == tab)
                    .accessibilityHidden(item != tab)
                }
            }
            .animation(.easeOut(duration: 0.22).delay(0.04), value: tab)

            VStack(spacing: 10) {
                if let toast = router.toast {
                    ToastView(toast: toast)
                        .transition(.scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(y: 10)))
                }
                OctoBar(tab: $tab, playerMode: $playerMode, reselect: popToRoot) {
                    withAnimation(.easeOut(duration: 0.4)) { playerOpen = true }
                }
                .selectionBarOver()
            }
            .padding(.bottom, OctoBar.bottomGap)
            .opacity(playerOpen ? 0 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: router.toast)

            if playerOpen {
                NowPlayingView { withAnimation(.easeIn(duration: 0.3)) { playerOpen = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onChange(of: router.route) { _, route in
            guard let route else { return }
            var path = paths[tab] ?? NavigationPath()
            path.append(route)
            paths[tab] = path
            withAnimation(.easeIn(duration: 0.3)) { playerOpen = false }
            router.routeTaken()
        }
        .onChange(of: player.current == nil) { _, empty in
            if empty {
                playerOpen = false
                playerMode = false
            }
        }
        .onChange(of: router.drive) { _, request in
            guard let request else { return }
            router.drive = nil
            switch request {
            case .tab(let item): tab = item
            case .openPlayer, .lyrics: if player.current != nil { withAnimation(.easeOut(duration: 0.4)) { playerOpen = true } }
            case .closePlayer: withAnimation(.easeIn(duration: 0.3)) { playerOpen = false }
            }
            if request == .lyrics { router.lyricsRequested = true }
        }
        .modifier(LibraryPresenter())
        .task(id: session.activeId) { await downloads.resume() }
        .onChange(of: session.client == nil) { _, _ in Task { await downloads.resume() } }
        .onChange(of: scenePhase, initial: true) { _, phase in downloads.setForeground(phase == .active) }
        .fullScreenCover(item: $router.signIn) { form in
            SignInView(form: form, session: session) { notice in
                if let notice { router.show(notice, done: true) }
            }
        }
    }

    @ViewBuilder
    private func root(_ item: AppTab) -> some View {
        switch item {
        case .home: HomeView()
        case .search: SearchView()
        case .library: LibraryView()
        case .settings: SettingsView()
        }
    }

    private func path(_ item: AppTab) -> Binding<NavigationPath> {
        Binding(get: { paths[item] ?? NavigationPath() }, set: { paths[item] = $0 })
    }

    /// Tapping the tab in use goes back to its first page.
    private func popToRoot(_ item: AppTab) {
        paths[item] = NavigationPath()
    }
}

extension View {
    /// Every page a tab can open, each without the system's bar: titles scroll with the page and
    /// a glass back button floats over detail pages.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            Group {
                switch route {
                case .album(let album): AlbumView(album: album)
                case .artist(let id, let name): ArtistView(id: id, name: name)
                case .playlist(let playlist): PlaylistView(playlist: playlist)
                case .artists: ArtistsView()
                case .albums: AlbumsView()
                case .playlists: PlaylistsView()
                case .favorites: FavoritesView()
                case .library(let page): LibraryPageView(page: page)
                }
            }
            .detailPage()
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(OctoColor.background)
    }
}

/// A short message above the bar, with an action like Undo when it has one.
struct ToastView: View {
    let toast: Router.Toast
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 10) {
            if toast.done {
                Image(systemName: "checkmark").font(.system(size: 16, weight: .semibold))
            }
            Text(toast.text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action = toast.action {
                Button(action) {
                    toast.perform?()
                    router.dismissToast()
                }
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.white.opacity(0.12), in: Capsule())
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 48)
        .glassEffect(.regular, in: .capsule)
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .onTapGesture { if toast.action == nil { router.dismissToast() } }
        .accessibilityAddTraits(.updatesFrequently)
    }
}
