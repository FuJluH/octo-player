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
    /// The library pages beyond these: songs, genres, folders, history, downloads and the rest.
    case library(LibraryPage)
    /// An album or artist the server found online, and the Charts page.
    case onlineAlbum(id: String, name: String)
    case onlineArtist(id: String, name: String)
    case charts
    /// A live list, and its editor (a new one when `id` is nil).
    case liveList(id: String)
    case liveListEditor(id: String?)
    /// A new live list's editor, started from a page's filters (a saved query).
    case liveListFrom(query: String)
    /// The Sound page: equalizer, loudness, balance and headphone correction.
    case sound
    /// The order of Home's shelves, and which ones show.
    case homeSections
    /// Live radio stations near a place, from the Radio Browser catalog.
    case liveRadioNear
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
        case .library(let page): page.ambientPage
        case .sound: .sound
        case .homeSections: .settingsPage
        case .liveRadioNear: .liveRadio
        case .onlineAlbum: .onlineAlbum
        case .onlineArtist: .onlineArtist
        case .charts: .charts
        case .liveList: .liveList
        case .liveListEditor, .liveListFrom: .liveListEdit
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
/// glow behind them, the floating bar over them, the full player over that, and the selection
/// bar. Sheets, popovers, menus and questions are the system's own, and the message line floats
/// over all of them in its own window.
struct MainShell: View {
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(Session.self) private var session
    @Environment(Downloads.self) private var downloads
    @Environment(ServerDownloads.self) private var serverDownloads
    @Environment(LiveListStore.self) private var liveLists
    @Environment(AmbientSettings.self) private var ambience
    @Environment(ArtworkColorStore.self) private var colorStore
    @Environment(Overlays.self) private var overlays
    @Environment(Accounts.self) private var accounts
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.motionScale) private var motion
    @SceneStorage("tab") private var tab: AppTab = .home
    /// The bar's small player, kept through a relaunch of the scene.
    @SceneStorage("bar.player") private var barPlayer = false
    @SceneStorage("player.open") private var playerOpen = false
    /// Every tab's stack. A stack can hold any page value, so the other parts of the app can
    /// open pages of their own kinds.
    @State private var paths: [AppTab: NavigationPath] = [:]
    /// Every tab's stack, kept with the scene.
    @SceneStorage("paths") private var savedPaths: Data?
    /// The tab that was in front before the last change, still drawn full size while it fades.
    @State private var leaving: AppTab?
    @State private var reselects: [AppTab: Int] = [:]
    @State private var drift = AmbientDrift()
    /// The player stays in place, faded out, until its cover has flown home, and only then is
    /// taken down; the pages under it wake at the same moment. Both are heavy, so neither lands
    /// in the middle of the closing animation.
    @State private var playerMounted = false
    @State private var pagesCovered = false
    /// A new player for each opening, so one opened again while the last still lingers starts
    /// fresh.
    @State private var playerOpening = 0
    @State private var takeDown: Task<Void, Never>?
    /// The player opening a frame after its cover took off.
    @State private var openingSoon: Task<Void, Never>?
    @Namespace private var art

    private var hasTrack: Bool { player.current != nil }

    /// The glow drifts only while music plays, the app is in view, the player does not cover
    /// the pages, the glow shows and nothing asks for less motion.
    private var drifting: Bool {
        player.isPlaying && scenePhase == .active && !(playerOpen && hasTrack) && !motion.still
            && ambience.prefs.strength != .off
    }

    var body: some View {
        ZStack {
            OctoColor.background.ignoresSafeArea()
            tabs
                .onChange(of: playerOpen && hasTrack, initial: true) { _, open in playerShown(open) }

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
                DownloadsPill()
            }
            .opacity(playerOpen && hasTrack ? 0 : 1)
            .animation(.octoTween(fixed: 300), value: playerOpen && hasTrack)

            if playerMounted && hasTrack {
                PlayerHost(dismiss: closePlayer)
                    .equatable()
                    .id(playerOpening)
                    .opacity(playerOpen ? 1 : 0)
                    .animation(.octoTween(fixed: 300), value: playerOpen)
                    .allowsHitTesting(playerOpen)
                    .transition(.asymmetric(insertion: .opacity.animation(.octoTween(fixed: 400)), removal: .identity))
                    .zIndex(1)
            }
            // The cover flying between the bar and the player, above both.
            CoverFlightLayer()
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .zIndex(1.2)

            // Over the bar and even the player.
            SelectionBarHost().zIndex(1.5)
        }
        .background(ToastWindowProbe(router: router))
        .environment(\.nowPlayingArt, art)
        .environment(drift)
        .task(id: drifting) { if drifting { await drift.run() } }
        .environment(\.nowMark, NowMark(songId: player.current?.id, isPlaying: player.isPlaying))
        .onChange(of: router.route) { _, route in
            guard let route else { return }
            leavePlayer()
            paths[tab, default: NavigationPath()].append(route)
            router.routeTaken()
        }
        .onChange(of: router.accountRoute) { _, route in
            guard let route else { return }
            leavePlayer()
            let switching = tab != .settings
            if switching { select(.settings) }
            // A list shared in while Import is already on top stays on that page.
            if !(route == .imports && accounts.imports.showing) {
                // A page that comes with a change of tab arrives with the tab's motion, not a slide.
                var quiet = Transaction()
                quiet.disablesAnimations = switching
                withTransaction(quiet) { paths[.settings, default: NavigationPath()].append(route) }
            }
            router.accountRouteTaken()
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
            case .closePlayer: leavePlayer()
            case .barPlayer: if hasTrack { barPlayer = true }
            case .showTabs: barPlayer = false
            case .reselect: select(tab)
            case .back: back()
            }
            if request == .lyrics { router.lyricsRequested = true }
        }
        .modifier(LibraryPresenter())
        .onAppear(perform: restorePaths)
        .onChange(of: paths) { _, now in
            // A stack holding a page that cannot be kept starts afresh next time.
            let byName = Dictionary(uniqueKeysWithValues: now.compactMap { entry in
                entry.value.codable.map { (entry.key.rawValue, $0) }
            })
            savedPaths = try? JSONEncoder().encode(byName)
        }
        .task(id: session.activeId) { await downloads.resume() }
        // The server's own updates are followed from the start, for the Settings tab's dot.
        .task { ServerUpdates.shared.start(session) }
        .onChange(of: session.client == nil) { _, _ in Task { await downloads.resume() } }
        .onChange(of: scenePhase, initial: true) { _, phase in
            downloads.setForeground(phase == .active)
            serverDownloads.setForeground(phase == .active)
        }
        .onChange(of: serverDownloadsKey, initial: true) {
            serverDownloads.sessionChanged()
            liveLists.accountChanged()
        }
        .onChange(of: router.serverDownloads) { _, page in
            guard let page else { return }
            router.serverDownloads = nil
            serverDownloads.show(page)
        }
        .sheet(isPresented: Binding(get: { serverDownloads.view != nil }, set: { if !$0 { serverDownloads.close() } })) {
            ServerDownloadsSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .modifier(CodeSheetHost())
        .fullScreenCover(item: Bindable(router).signIn) { form in
            SignInView(form: form, session: session) { notice in
                if let notice { router.done(notice) }
            }
            .environment(drift)
        }
    }

    /// The server in use as the downloads sheet follows it: which, signed in or not, and what it
    /// lists.
    private var serverDownloadsKey: String {
        "\(session.activeId ?? "")|\(session.client != nil)|\(session.profile?.extensions.joined(separator: ",") ?? "-")"
    }

    /// Every tab's stack, each keeping its pages while another tab is in front. Changing tab,
    /// the new one fades in a touch after the old one fades out, growing from 0.97 into place;
    /// nothing slides.
    private var tabs: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { item in
                let front = item == tab
                NavigationStack(path: path(item)) {
                    TabRoot(item: item).equatable()
                        .background { PageBackdrop(page: item.rootPage, route: nil) }
                        .pageMotion(rootBack: item == .home ? nil : { select(.home) })
                        .routes()
                        .environment(\.tabReselects, reselects[item, default: 0])
                        .background(ScrollTopProbe(signal: reselects[item, default: 0]))
                }
                .environment(\.shellAwake, front && !pagesCovered)
                .opacity(front ? 1 : 0)
                .animation(front ? .octoTween(220, OctoEasing.standard, scale: motion, delay: 40)
                                 : .octoTween(100, OctoEasing.standard, scale: motion), value: tab)
                .scaleEffect(front || item == leaving ? 1 : motion.scale(0.97))
                .animation(front ? .octoTween(260, OctoEasing.spring, scale: motion) : nil, value: tab)
                .allowsHitTesting(front)
                .accessibilityHidden(!front)
            }
        }
    }

    /// Brings every tab's stack back as it was when the scene was last kept.
    private func restorePaths() {
        guard paths.isEmpty, let savedPaths,
              let byName = try? JSONDecoder().decode([String: NavigationPath.CodableRepresentation].self, from: savedPaths)
        else { return }
        var restored: [AppTab: NavigationPath] = [:]
        for (name, stack) in byName {
            if let item = AppTab(rawValue: name) { restored[item] = NavigationPath(stack) }
        }
        paths = restored
    }


    private func path(_ item: AppTab) -> Binding<NavigationPath> {
        Binding(get: { paths[item] ?? NavigationPath() }, set: { paths[item] = $0 })
    }

    /// A tab tapped. The tab in use goes back to its first page, or, already there, scrolls it
    /// to the top; another tab comes to the front as it was left. Either folds the bar's small
    /// player back into the round button.
    private func select(_ item: AppTab) {
        barPlayer = false
        if item == tab {
            if paths[item]?.isEmpty == false {
                paths[item] = NavigationPath()
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
    private func openPlayer() {
        guard !playerOpen else { return }
        // From the small player the cover takes off first, and the player is built a frame
        // later under it, so its building never holds the cover still.
        guard hasTrack, CoverFlight.shared.launch(flightKey(player.current)) else {
            playerOpen = true
            return
        }
        openingSoon?.cancel()
        openingSoon = Task {
            try? await Task.sleep(for: .milliseconds(playerBuildDelayMs))
            guard !Task.isCancelled else { return }
            playerOpen = true
        }
    }

    /// The player opened or closed: mounted at once on opening (a fresh one when the last still
    /// lingers), and on closing taken down and the pages woken 0.7 s later, once the cover is home.
    private func playerShown(_ open: Bool) {
        takeDown?.cancel()
        PlayerMotion.shared.moved(for: open ? PlayerMotionClock.openSeconds : PlayerMotionClock.closeSeconds)
        if open {
            if playerMounted { playerOpening += 1 }
            playerMounted = true
            pagesCovered = true
            return
        }
        guard playerMounted else {
            pagesCovered = false
            return
        }
        takeDown = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            playerMounted = false
            pagesCovered = false
        }
    }

    private func closePlayer() { playerOpen = false }

    /// Closes the player the way it closes itself, the cover flying home and the background
    /// drawing back, whatever asks.
    private func leavePlayer() {
        if playerOpen && hasTrack {
            PlayerDrive.shared.ask("close")
        } else {
            closePlayer()
        }
    }

    /// Back: a sheet opened from code first, then the player, then the page on top; at the first
    /// page of another tab, Home.
    private func back() {
        if overlays.back() { return }
        if playerOpen && hasTrack {
            leavePlayer()
        } else if paths[tab]?.isEmpty == false {
            paths[tab]?.removeLast()
        } else if tab != .home {
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
                case .library(let page): LibraryPageView(page: page)
                case .onlineAlbum(let id, let name): OnlineAlbumView(id: id, name: name)
                case .onlineArtist(let id, let name): OnlineArtistView(id: id, name: name)
                case .charts: ChartsView()
                case .liveList(let id): LiveListView(id: id)
                case .liveListEditor(let id): LiveListEditView(id: id)
                case .liveListFrom(let query): LiveListEditView(id: nil, start: LibraryQuery.fromJSON(query))
                case .sound: SoundPage()
                case .homeSections: HomeSectionsPage()
                case .liveRadioNear: LiveRadioPage()
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

/// The full player as the shell holds it. The shell is drawn again whenever anything it watches
/// changes; the player is not drawn again with it, only when something the player itself watches
/// changes, since laying the whole player out takes several frames.
private struct PlayerHost: View, Equatable {
    let dismiss: () -> Void

    nonisolated static func == (lhs: PlayerHost, rhs: PlayerHost) -> Bool { true }

    var body: some View { NowPlayingView(dismiss: dismiss) }
}

/// Calls `action` when the page wakes (the player stops covering it, or its tab comes back), and
/// with `alsoOnActive` when the app comes back while the page is awake. Only this small view
/// watches, so waking never lays the whole page out again.
struct WakeWatch: View {
    var alsoOnActive = false
    let action: () -> Void
    @Environment(\.shellAwake) private var awake
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Color.clear
            .onChange(of: awake) { _, now in if now { action() } }
            .onChange(of: scenePhase) { _, phase in if alsoOnActive && phase == .active && awake { action() } }
    }
}

/// A tab's first page. It takes nothing from the shell but which tab it is, so the shell being
/// drawn again (the player opening or closing, a song changing) never lays the page out again;
/// the page still redraws for everything it watches itself.
private struct TabRoot: View, Equatable {
    let item: AppTab

    var body: some View {
        switch item {
        case .home: HomeView()
        case .search: SearchView()
        case .library: LibraryView()
        case .settings: SettingsView()
        }
    }
}
