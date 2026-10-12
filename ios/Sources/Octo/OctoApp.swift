import SwiftUI

@main
struct OctoApp: App {
    @State private var session: Session
    @State private var player: Player
    @State private var router: Router
    @State private var lyrics: LyricsStore
    @State private var sound: SoundStore
    @State private var downloads: Downloads
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
        _router = State(initialValue: router)
        _downloads = State(initialValue: Downloads(session: session) { words, done in router.show(words, done: done) })
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
