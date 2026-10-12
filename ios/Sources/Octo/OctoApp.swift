import SwiftUI

@main
struct OctoApp: App {
    @State private var session: Session
    @State private var player: Player

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
                .tint(OctoColor.accent)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(Session.self) private var session

    var body: some View {
        if session.client == nil {
            SignInView()
        } else {
            MainTabs()
        }
    }
}
