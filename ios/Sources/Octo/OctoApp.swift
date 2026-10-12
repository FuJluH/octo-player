import SwiftUI

@main
struct OctoApp: App {
    @State private var session: Session
    @State private var player: Player
    @State private var router = Router()

    init() {
        let session = Session()
        _session = State(initialValue: session)
        _player = State(initialValue: Player(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(player)
                .environment(router)
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
