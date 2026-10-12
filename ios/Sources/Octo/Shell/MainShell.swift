import OctoKit
import SwiftUI
import UIKit

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

    /// The page at the bottom of the tab's stack, as the glow sees it.
    var rootPage: AmbientPage {
        switch self {
        case .home: .home
        case .search: .search
        case .library: .library
        case .settings: .settings
        }
    }
}

/// Where a tap goes inside a tab. Routes are plain values, so every tab's stack can be kept
/// when the system ends the app in the background and brought back as it was.
enum Route: Hashable, Codable {
    case album(Album)
    case artist(id: String, name: String)
    case playlist(Playlist)
    case artists, albums, playlists, favorites
}

extension Route {
    /// What kind of page this is, as the glow sees it. A page not listed gets no glow.
    var ambientPage: AmbientPage? {
        switch self {
        case .album: .album
        case .artist: .artist
        case .playlist: .playlist
        case .artists: .artists
        case .albums: .albums
        case .playlists: .playlists
        case .favorites: .favorites
        }
    }
}

/// The measures the shell's floating pieces share.
enum ShellMeasures {
    static let barHeight: CGFloat = 56
    static let barGap: CGFloat = 10
    /// How far above the bottom safe area the bar floats.
    static let barBottomGap: CGFloat = 14
    /// The bar's side margins, and the widest it gets inside them.
    static let sideMargin: CGFloat = 20
    static let maxWidth: CGFloat = 520
    /// Messages and the downloads pill sit this far above the bottom safe area: just above the bar.
    static let aboveBar: CGFloat = barBottomGap + barHeight + 10
    /// Room pages leave under their content for the bar.
    static let clearance: CGFloat = 120
}

extension EnvironmentValues {
    /// Shared by the bar's small player and the full player's artwork card, so the cover flies
    /// between them. The id is the same whatever song is on.
    @Entry var nowPlayingArt: Namespace.ID? = nil
    /// Tells a tab's first page that its tab was tapped again while it was showing.
    @Entry var tabReselects = 0
    /// Whether the pages here are in front and uncovered, so their glow may drift.
    @Entry var shellAwake = true
}

/// The id the bar's cover and the player's card share in `nowPlayingArt`.
let nowPlayingArtID = "now-playing-art"

/// The app's frame: every tab's pages, kept alive while another tab is in front, the artwork's
/// glow behind them, the floating bar over them, the full player over that, then sheets, the
/// message line and pop-ups, in that order.
struct MainShell: View {
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @Environment(Downloads.self) private var downloads
    @Environment(AmbientSettings.self) private var ambience
    @Environment(ArtworkColorStore.self) private var colorStore
    @Environment(Overlays.self) private var overlays
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motionScale) private var motion
    @SceneStorage("tab") private var tab: AppTab = .home
    /// The bar's small player, kept through a relaunch of the scene.
    @SceneStorage("bar.player") private var barPlayer = false
    @SceneStorage("player.open") private var playerOpen = false
    @State private var paths: [AppTab: [Route]] = [:]
    /// Every tab's stack, kept with the scene.
    @SceneStorage("paths") private var savedPaths: Data?
    /// The tab that was in front before the last change, still drawn full size while it fades.
    @State private var leaving: AppTab?
    @State private var reselects: [AppTab: Int] = [:]
    @Namespace private var art

    private var hasTrack: Bool { player.current != nil }

    var body: some View {
        ZStack {
            OctoColor.background.ignoresSafeArea()
            tabs

            OctoBar(tab: tab, playerMode: barPlayer, select: select, roundButton: roundButton,
                    showTabs: { barPlayer = false }, openPlayer: openPlayer,
                    film: BarFilm.color(settings: ambience, store: colorStore, player: player))
                .animation(.octoTween(fixed: AmbientTiming.crossMs), value: BarFilm.color(settings: ambience, store: colorStore, player: player))
                .padding(.bottom, ShellMeasures.barBottomGap)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .opacity(playerOpen && hasTrack ? 0 : 1)
                .allowsHitTesting(!(playerOpen && hasTrack))
                .animation(.octoTween(fixed: 300), value: playerOpen && hasTrack)
                .ignoresSafeArea(.keyboard)

            AboveBarTrailing {
                // The downloads pill goes here: songs on their way, tapping opens the server
                // downloads sheet.
                EmptyView()
            }
            .opacity(playerOpen && hasTrack ? 0 : 1)
            .animation(.octoTween(fixed: 300), value: playerOpen && hasTrack)

            if playerOpen && hasTrack {
                NowPlayingView(dismiss: closePlayer)
                    .transition(.asymmetric(insertion: .opacity.animation(.octoTween(fixed: 400)),
                                            removal: .opacity.animation(.octoTween(fixed: 300))))
                    .zIndex(1)
            }

            SheetsLayer().zIndex(2)
            ToastHost().zIndex(3)
            PopupsLayer().zIndex(4)
            PromptsHost().zIndex(5)
        }
        .environment(\.nowPlayingArt, art)
        .environment(\.nowMark, NowMark(songId: player.current?.id, isPlaying: player.isPlaying))
        .onChange(of: router.route) { _, route in
            guard let route else { return }
            closePlayer()
            paths[tab, default: []].append(route)
            router.routeTaken()
        }
        .onChange(of: hasTrack) { _, has in
            if !has {
                barPlayer = false
                playerOpen = false
            }
        }
        .onChange(of: router.drive) { _, request in
            guard let request else { return }
            router.drive = nil
            switch request {
            case .tab(let item): select(item)
            case .openPlayer, .lyrics: openPlayer()
            case .closePlayer: closePlayer()
            case .barPlayer: if hasTrack { barPlayer = true }
            case .showTabs: barPlayer = false
            case .reselect: select(tab)
            case .back: back()
            }
            if request == .lyrics { router.lyricsRequested = true }
        }
        .onAppear(perform: restorePaths)
        .onChange(of: paths) { _, now in
            let byName = Dictionary(uniqueKeysWithValues: now.map { ($0.key.rawValue, $0.value) })
            savedPaths = try? JSONEncoder().encode(byName)
        }
        .task(id: session.activeId) { await downloads.resume() }
        .onChange(of: session.client == nil) { _, _ in Task { await downloads.resume() } }
        .onChange(of: scenePhase, initial: true) { _, phase in downloads.setForeground(phase == .active) }
        .fullScreenCover(item: Bindable(router).signIn) { form in
            SignInView(form: form, session: session) { notice in
                if let notice { router.done(notice) }
            }
        }
    }

    /// Every tab's stack, each keeping its pages while another tab is in front. Changing tab,
    /// the new one fades in a touch after the old one fades out, growing from 0.97 into place;
    /// nothing slides.
    private var tabs: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { item in
                let front = item == tab
                NavigationStack(path: path(item)) {
                    root(item)
                        .background { PageBackdrop(page: item.rootPage, route: nil) }
                        .pageMotion()
                        .routes()
                        .environment(\.tabReselects, reselects[item, default: 0])
                        .background(ScrollTopProbe(signal: reselects[item, default: 0]))
                }
                .environment(\.shellAwake, front && !(playerOpen && hasTrack))
                .opacity(front ? 1 : 0)
                .animation(front ? .octoTween(220, OctoEasing.standard, scale: motion, delay: 40)
                                 : .octoTween(100, OctoEasing.standard, scale: motion), value: tab)
                .scaleEffect(front || item == leaving ? 1 : motion.scale(0.97))
                .animation(front ? .octoTween(260, OctoEasing.spring, scale: motion) : nil, value: tab)
                .allowsHitTesting(front)
                .accessibilityHidden(!front)
                .simultaneousGesture(homeEdge, including: front ? .all : .subviews)
            }
        }
    }

    /// Brings every tab's stack back as it was when the scene was last kept.
    private func restorePaths() {
        guard paths.isEmpty, let savedPaths,
              let byName = try? JSONDecoder().decode([String: [Route]].self, from: savedPaths) else { return }
        var restored: [AppTab: [Route]] = [:]
        for (name, stack) in byName {
            if let item = AppTab(rawValue: name) { restored[item] = stack }
        }
        paths = restored
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

    private func path(_ item: AppTab) -> Binding<[Route]> {
        Binding(get: { paths[item] ?? [] }, set: { paths[item] = $0 })
    }

    /// A tab tapped. The tab in use goes back to its first page, or, already there, scrolls it
    /// to the top; another tab comes to the front as it was left. Either folds the bar's small
    /// player back into the round button.
    private func select(_ item: AppTab) {
        barPlayer = false
        if item == tab {
            if paths[item]?.isEmpty == false {
                paths[item] = []
            } else {
                reselects[item, default: 0] += 1
            }
        } else {
            leaving = tab
            tab = item
        }
    }

    /// With a song loaded the round button grows into the small player; with nothing loaded it
    /// shuffles the whole library.
    private func roundButton() {
        if hasTrack {
            barPlayer = true
        } else {
            Task { await player.shuffleLibrary() }
        }
    }

    /// Asked for, the player opens; with nothing loaded it waits and opens when a song loads.
    private func openPlayer() { playerOpen = true }

    private func closePlayer() { playerOpen = false }

    /// Back: a pop-up or sheet first, then the player, then the page on top; at the first page
    /// of another tab, Home.
    private func back() {
        if overlays.back() { return }
        if playerOpen && hasTrack {
            closePlayer()
        } else if paths[tab]?.isEmpty == false {
            paths[tab]?.removeLast()
        } else if tab != .home {
            select(.home)
        }
    }

    /// At the first page of Search, Library or Settings, a swipe in from the left edge goes Home.
    private var homeEdge: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { drag in
                guard drag.startLocation.x < 24, drag.translation.width > 60,
                      abs(drag.translation.height) < drag.translation.width,
                      tab != .home, paths[tab]?.isEmpty != false else { return }
                select(.home)
            }
    }
}

/// A place at the bottom right just above the bar, 20 points in, for a small pill.
struct AboveBarTrailing<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(.trailing, ShellMeasures.sideMargin)
            .padding(.bottom, ShellMeasures.aboveBar)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .ignoresSafeArea(.keyboard)
    }
}

/// Scrolls the first page's list back to its top when its tab is tapped again there.
private struct ScrollTopProbe: UIViewRepresentable {
    let signal: Int

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard signal != context.coordinator.seen else { return }
        context.coordinator.seen = signal
        DispatchQueue.main.async { Self.scrollToTop(from: view) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(seen: signal) }

    final class Coordinator {
        var seen: Int
        init(seen: Int) { self.seen = seen }
    }

    /// Finds the nearest vertical scroll view around `view` and takes it to its top.
    private static func scrollToTop(from view: UIView) {
        var ancestor = view.superview
        while let current = ancestor {
            if let scroll = firstScroll(in: current, skipping: view) {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: true)
                return
            }
            ancestor = current.superview
        }
    }

    private static func firstScroll(in root: UIView, skipping: UIView) -> UIScrollView? {
        var queue: [UIView] = [root]
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if next === skipping { continue }
            if let scroll = next as? UIScrollView, scroll.contentSize.height > scroll.bounds.height, scroll.isScrollEnabled {
                return scroll
            }
            queue.append(contentsOf: next.subviews)
        }
        return nil
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
                }
            }
            .background { PageBackdrop(page: route.ambientPage, route: route) }
            .detailPage()
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// What every page sits on: the plain background, and over it the artwork's glow for the page.
struct PageBackdrop: View {
    let page: AmbientPage?
    let route: Route?
    @Environment(\.shellAwake) private var awake

    var body: some View {
        ZStack {
            OctoColor.background
            AmbientBackdrop(page: page, route: route, awake: awake)
        }
        .ignoresSafeArea()
    }
}
