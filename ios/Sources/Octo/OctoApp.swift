import SwiftUI

@main
struct OctoApp: App {
    @State private var session: Session
    @State private var player: Player
    @State private var router = Router()
    @State private var lyrics: LyricsStore
    @State private var sound: SoundStore

    init() {
        let session = Session()
        let sound = SoundStore()
        _session = State(initialValue: session)
        _sound = State(initialValue: sound)
        _player = State(initialValue: Player(session: session, sound: sound.processor))
        _lyrics = State(initialValue: LyricsStore(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(player)
                .environment(router)
                .environment(lyrics)
                .environment(sound)
                .tint(OctoColor.accent)
                .preferredColorScheme(.dark)
        }
    }
}

/// Octo opens on its library whether or not a server is signed in; a server is an add-on.
struct RootView: View {
    var body: some View {
        MainShell()
    }
}
