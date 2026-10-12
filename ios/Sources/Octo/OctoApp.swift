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

    init() {
        let session = Session()
        let sound = SoundStore()
        let router = Router()
        _router = State(initialValue: router)
        let downloads = Downloads(session: session) { words, done in router.show(words, done: done) }
        _downloads = State(initialValue: downloads)
        _discovery = State(initialValue: Discovery(session: session, downloads: downloads))
        let serverDownloads = ServerDownloads(session: session, router: router)
        downloads.onAsk = { serverDownloads.wake() }
        _serverDownloads = State(initialValue: serverDownloads)
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
                .environment(downloads)
                .environment(discovery)
                .environment(serverDownloads)
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
