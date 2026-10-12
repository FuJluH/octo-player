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
        _player = State(initialValue: Player(session: session, sound: sound.processor))
        _lyrics = State(initialValue: LyricsStore(session: session))
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
                .tint(OctoColor.accent)
                .preferredColorScheme(.dark)
                #if DEBUG
                .task { await Drive.run(session: session, player: player, router: router) }
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
