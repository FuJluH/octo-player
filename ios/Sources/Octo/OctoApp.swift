import SwiftUI

@main
struct OctoApp: App {
    @State private var session: Session
    @State private var player: Player
    @State private var router: Router
    @State private var lyrics: LyricsStore
    @State private var sound: SoundStore
    @State private var downloads: Downloads
    @State private var data: DataServices
    @State private var overlays: Overlays
    @State private var prompts: Prompts
    @State private var presses: PressSpots
    @State private var motion = MotionSettings()
    @State private var ambience = AmbientSettings()
    @State private var pageArtworks = PageArtworks()
    @State private var selectionBar: SelectionBarState
    @State private var selectionActions: SelectionActions
    @State private var libraryActions: LibraryActions
    @State private var artworkColors: ArtworkColorStore

    init() {
        let session = Session()
        let sound = SoundStore()
        let router = Router()
        let data = DataServices(session: session) { words, done in router.show(words, done: done) }
        _data = State(initialValue: data)
        _router = State(initialValue: router)
        _downloads = State(initialValue: data.downloads)
        _session = State(initialValue: session)
        _sound = State(initialValue: sound)
        let player = Player(session: session, sound: sound.processor)
        _player = State(initialValue: player)
        let prompts = Prompts()
        let overlays = Overlays()
        let presses = PressSpots()
        let selectionBar = SelectionBarState()
        let selectionActions = SelectionActions()
        _prompts = State(initialValue: prompts)
        _overlays = State(initialValue: overlays)
        _presses = State(initialValue: presses)
        _selectionBar = State(initialValue: selectionBar)
        _selectionActions = State(initialValue: selectionActions)
        _libraryActions = State(initialValue: LibraryActions(
            state: LibraryState(data: data, session: session), player: player, router: router, session: session,
            prompts: prompts, overlays: overlays, spots: presses, selection: selectionActions, selectionBar: selectionBar))
        _lyrics = State(initialValue: LyricsStore(session: session))
        _artworkColors = State(initialValue: ArtworkColorStore(session: session))
        data.start()
        #if DEBUG
        DataDrive.install(data) { router.show($0) }
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
                .environment(overlays)
                .environment(prompts)
                .environment(presses)
                .environment(motion)
                .environment(ambience)
                .environment(pageArtworks)
                .environment(artworkColors)
                .environment(selectionBar)
                .environment(selectionActions)
                .environment(libraryActions)
                .environment(libraryActions.state)
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
