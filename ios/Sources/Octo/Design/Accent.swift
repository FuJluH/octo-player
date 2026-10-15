import Observation
import OctoKit
import SwiftUI

/// The accent in use and whether Octo's glass takes it, read wherever the app draws a selection,
/// a slider, a switch or a filled button. Views read it while drawing, so a new choice redraws
/// only what shows it. It is set on the main thread only, by `KeepAccent`.
@Observable
final class AccentState: @unchecked Sendable {
    static let shared = AccentState()

    private(set) var rgba: RGBA = OctoPalette.accent
    private(set) var color = Color(OctoPalette.accent)
    private(set) var glassTinted = false
    /// The film laid into Octo's glass: the plain dim, or the dim carrying the accent.
    private(set) var film = Color(OctoPalette.glazeFilm)

    /// Makes `argb` the accent and `tinted` the glass's. Only a change redraws anything.
    func use(_ argb: UInt32, glass tinted: Bool) {
        let next = RGBA(argb: argb | 0xFF00_0000)
        guard next != rgba || tinted != glassTinted else { return }
        if next != rgba {
            rgba = next
            color = Color(next)
        }
        glassTinted = tinted
        film = Color(glassFilm(accent: next, tinted: tinted))
    }
}

/// Keeps the app drawn in the accent Appearance chose: a fixed one, or for From the album art the
/// playing cover's brightest color, Octo's own while nothing with a cover plays. Placed once, at
/// the root, where it also tints the system's own controls.
struct KeepAccent: ViewModifier {
    @Environment(Player.self) private var player
    @Environment(ArtworkColorStore.self) private var colorStore
    @State private var settings = AppSettings.shared
    @State private var accent = AccentState.shared

    func body(content: Content) -> some View {
        let prefs = settings.player
        let choice = prefs.accent
        // The cover's colors are only asked for while the accent follows them.
        let art: UInt32? = choice == .fromArt ? coverSeed(player.current?.coverArt) : nil
        content
            .tint(accent.color)
            .onChange(of: AccentAsk(choice: choice, art: art, glass: prefs.glassTint && choice != .octo), initial: true) { _, ask in
                accent.use(accentArgb(ask.choice, art: ask.art), glass: ask.glass)
            }
    }

    /// The cover's most vivid color, or none for music without artwork or before it is read.
    private func coverSeed(_ coverId: String?) -> UInt32? {
        guard let coverId, let colors = colorStore.colors(for: coverId), colors != .quiet, colors.mesh.count > 1 else { return nil }
        return 0xFF00_0000 | colors.mesh[1]
    }

    private struct AccentAsk: Equatable {
        let choice: AccentChoice
        let art: UInt32?
        let glass: Bool
    }
}

extension View {
    /// Draws the app in the chosen accent. Placed once, at the root.
    func keepsAccent() -> some View { modifier(KeepAccent()) }
}
