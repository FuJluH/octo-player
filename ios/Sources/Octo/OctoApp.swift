import SwiftUI

@main
struct OctoApp: App {
    @UIApplicationDelegateAdaptor(OctoAppDelegate.self) private var appDelegate
    @State private var session: Session
    @State private var player: Player
    @State private var router: Router
    @State private var lyrics: LyricsStore
    @State private var sound: SoundStore
    @State private var downloads: Downloads
    @State private var data: DataServices
    @State private var discovery: Discovery
    @State private var serverDownloads: ServerDownloads
    @State private var liveLists: LiveListStore
    @State private var liveLibrary: LiveLibrary
    @State private var artistExtras: ArtistExtrasSource
    @State private var overlays: Overlays
    @State private var motion = MotionSettings()
    @State private var ambience = AmbientSettings()
    @State private var pageArtworks = PageArtworks()
    @State private var selectionBar: SelectionBarState
    @State private var selectionActions: SelectionActions
    @State private var libraryActions: LibraryActions
    @State private var artworkColors: ArtworkColorStore
    @State private var accounts: Accounts
    /// The ways in from outside the app; kept here so they live as long as it does.
    @State private var entries: SystemEntries

    init() {
        let session = Session()
        let sound = SoundStore()
        let router = Router()
        let data = DataServices(session: session) { words, done in router.show(words, done: done) }
        _data = State(initialValue: data)
        _router = State(initialValue: router)
        let downloads = data.downloads
        _downloads = State(initialValue: downloads)
        let discovery = Discovery(session: session, online: data.discovery, library: data.library)
        _discovery = State(initialValue: discovery)
        let serverDownloads = ServerDownloads(session: session, router: router)
        downloads.onAsk = { serverDownloads.wake() }
        _serverDownloads = State(initialValue: serverDownloads)
        _liveLists = State(initialValue: LiveListStore(session: session))
        _liveLibrary = State(initialValue: LiveLibrary(library: data.library))
        _artistExtras = State(initialValue: ArtistExtrasSource(session: session, library: data.library, discovery: discovery))
        _session = State(initialValue: session)
        _sound = State(initialValue: sound)
        let player = Player(session: session, sound: sound.processor, data: data)
        player.announce = { router.show($0) }
        _player = State(initialValue: player)
        let overlays = Overlays()
        let selectionBar = SelectionBarState()
        let selectionActions = SelectionActions()
        _overlays = State(initialValue: overlays)
        _selectionBar = State(initialValue: selectionBar)
        _selectionActions = State(initialValue: selectionActions)
        _libraryActions = State(initialValue: LibraryActions(
            state: LibraryState(data: data, session: session), player: player, router: router, session: session,
            selection: selectionActions, selectionBar: selectionBar))
        _lyrics = State(initialValue: LyricsStore(session: session, library: data.library, player: player))
        _artworkColors = State(initialValue: ArtworkColorStore(session: session))
        data.start()
        let accounts = Accounts(session: session, router: router)
        _accounts = State(initialValue: accounts)
        let entries = SystemEntries(session: session, player: player, router: router, accounts: accounts)
        _entries = State(initialValue: entries)
        SystemEntries.shared = entries
        SystemHooks.start(player: player, router: router)
        FamilyNotices.session = session
        AccountHooks.install(data, session: session, family: accounts.family)
        AnimatedArtStore.shared.attach(session: session, player: player, library: data.library)
        #if DEBUG
        DataDrive.install(data) { router.show($0) }
        AnimatedDrive.install(player: player, session: session)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(player)
                .environment(router)
                .environment(lyrics)
                .environment(sound)
                .environment(downloads)
                .dataEnvironment(data)
                .environment(discovery)
                .environment(serverDownloads)
                .environment(liveLists)
                .environment(liveLibrary)
                .environment(artistExtras)
                .environment(overlays)
                .environment(motion)
                .environment(ambience)
                .environment(pageArtworks)
                .environment(artworkColors)
                .environment(selectionBar)
                .environment(selectionActions)
                .environment(libraryActions)
                .environment(libraryActions.state)
                .environment(accounts)
                .task { accounts.start() }
                .motionScaled(motion)
                .preferredColorScheme(.dark)
                #if DEBUG
                .task { PlaybackDrive.install(player: player, router: router, overlays: overlays)
                        SystemDrive.install(router: router)
                        await Drive.run(session: session, player: player, router: router, motion: motion,
                                         overlays: overlays, ambience: ambience, selectionBar: selectionBar) }
                #endif
        }
        .backgroundTask(.appRefresh(FamilyNotices.taskId)) {
            await FamilyNotices.check()
            await FamilyNotices.scheduleNext()
        }
    }
}

/// Octo opens on its library whether or not a server is signed in; a server is an add-on.
struct RootView: View {
    var body: some View {
        MainShell()
            .systemEntries()
            .keepsAccent()
    }
}
