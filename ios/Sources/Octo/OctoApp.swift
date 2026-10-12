import SwiftUI

@main
struct OctoApp: App {
    @State private var session: Session
    @State private var player: Player
    @State private var router: Router
    @State private var lyrics: LyricsStore
    @State private var sound: SoundStore
    @State private var downloads: Downloads
    @State private var discovery: Discovery
    @State private var serverDownloads: ServerDownloads
    @State private var liveLists: LiveListStore
    @State private var liveLibrary: LiveLibrary
    @State private var artistExtras: ArtistExtrasSource
    @State private var library: Library
    @State private var serverSync: ServerSync
    @State private var overlays = Overlays()
    @State private var prompts = Prompts()
    @State private var presses = PressSpots()
    @State private var motion = MotionSettings()
    @State private var ambience = AmbientSettings()
    @State private var pageArtworks = PageArtworks()
    @State private var selectionBar = SelectionBarState()
    @State private var selectionActions = SelectionActions()
    @State private var artworkColors: ArtworkColorStore

    init() {
        let session = Session()
        let sound = SoundStore()
        let router = Router()
        let library = Library.open()
        let serverSync = ServerSync(session: session, library: library)
        _library = State(initialValue: library)
        _serverSync = State(initialValue: serverSync)
        _router = State(initialValue: router)
        let downloads = Downloads(session: session, library: library, sync: serverSync) { words, done in
            router.show(words, done: done)
        }
        _downloads = State(initialValue: downloads)
        serverSync.start()
        let discovery = Discovery(session: session, downloads: downloads, library: library)
        _discovery = State(initialValue: discovery)
        let serverDownloads = ServerDownloads(session: session, router: router)
        downloads.onAsk = { serverDownloads.wake() }
        _serverDownloads = State(initialValue: serverDownloads)
        _liveLists = State(initialValue: LiveListStore(session: session))
        _liveLibrary = State(initialValue: LiveLibrary(library: library))
        _artistExtras = State(initialValue: ArtistExtrasSource(session: session, library: library, discovery: discovery))
        _session = State(initialValue: session)
        _sound = State(initialValue: sound)
        _player = State(initialValue: Player(session: session, sound: sound.processor))
        _lyrics = State(initialValue: LyricsStore(session: session))
        _artworkColors = State(initialValue: ArtworkColorStore(session: session))
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
                .environment(discovery)
                .environment(serverDownloads)
                .environment(liveLists)
                .environment(liveLibrary)
                .environment(artistExtras)
                .environment(library)
                .environment(serverSync)
                .environment(overlays)
                .environment(prompts)
                .environment(presses)
                .environment(motion)
                .environment(ambience)
                .environment(pageArtworks)
                .environment(artworkColors)
                .environment(selectionBar)
                .environment(selectionActions)
                .motionScaled(motion)
                .recordsPresses(presses)
                .onAppear { prompts.spots = presses }
                .tint(OctoColor.accent)
                .preferredColorScheme(.dark)
                #if DEBUG
                .task { await Drive.run(session: session, player: player, router: router, prompts: prompts, motion: motion,
                                         overlays: overlays, ambience: ambience, selectionBar: selectionBar) }
                #endif
        }
    }
}

/// Octo opens on its library whether or not a server is signed in; a server is an add-on.
struct RootView: View {
    var body: some View {
        MainShell()
    }
}
