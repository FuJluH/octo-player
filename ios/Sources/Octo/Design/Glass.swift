import OctoKit
import SwiftUI

// Octo's glass on iPhone is Apple's Liquid Glass. Each surface keeps Octo's shape, size, film
// and shadow: the film tints the glass, and floating glass casts a soft shadow pooled under it.

extension Glass {
    /// Apple's regular glass, carrying the accent while Color the glass is on; untinted otherwise.
    static var octo: Glass {
        let accent = AccentState.shared
        return accent.glassTinted ? .regular.tint(accent.film) : .regular
    }
}

extension View {
    /// Octo's glass in `shape`, with `film` laid into it. `interactive` lets it answer the
    /// finger the way Liquid Glass controls do.
    func octoGlass<S: Shape>(_ shape: S, film: Color = OctoColor.glazeFilm, interactive: Bool = false) -> some View {
        glassEffect(interactive ? Glass.regular.tint(film).interactive() : Glass.regular.tint(film), in: shape)
    }

    /// Glass floating over the page, like the bar, a toast or the back button: the glass, with
    /// a shadow cast by the shape 12 points smaller on every side, so it pools under the glass
    /// instead of haloing around it. `halo` adds the menu plate's even dark halo, for words
    /// over busy content.
    func floatingGlass<S: InsettableShape>(_ shape: S, film: Color = OctoColor.glazeFilm, interactive: Bool = false,
                                          halo: Bool = false) -> some View {
        background { PooledShadow(shape: shape, halo: halo) }
            .octoGlass(shape, film: film, interactive: interactive)
    }

    /// The dark glass for chrome over artwork or video.
    func darkGlass<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        floatingGlass(shape, film: Color(hex: 0x282828, opacity: 0.5), interactive: interactive)
    }
}

/// The shadow under floating glass, drawn only outside the glass so it never darkens it.
private struct PooledShadow<S: InsettableShape>: View {
    let shape: S
    let halo: Bool

    var body: some View {
        ZStack {
            if halo {
                shape.fill(Color.black.opacity(0.5)).blur(radius: shadowRadius(20))
            }
            shape.inset(by: 12)
                .fill(Color.black.opacity(0.45))
                .blur(radius: shadowRadius(24))
                .offset(y: 8)
        }
        .mask {
            Rectangle()
                .padding(-48)
                .overlay { shape.fill(Color.black).blendMode(.destinationOut) }
                .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A CSS shadow blur as a SwiftUI blur radius.
func shadowRadius(_ cssBlur: Double) -> CGFloat { CGFloat(shadowSigma(cssBlur)) }

/// The darker pill that marks the chosen item inside glass: a plain shade, unlit.
struct GlazeSelected<S: Shape>: View {
    var shape: S

    var body: some View {
        shape.fill(OctoColor.glazeSelected)
    }
}

extension GlazeSelected where S == Capsule {
    init() { self.init(shape: Capsule()) }
}

/// A chosen row in a list: the darker pill lightly tinted with the accent, a light line along
/// its top and a shade along its bottom, so white words read on it.
struct SelectedRowBackground: View {
    var radius: CGFloat = OctoRadius.row

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape.fill(OctoColor.accentSelected)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    Color.white.opacity(0.28).frame(height: 1)
                    Color.white.opacity(0.12).frame(height: 1)
                }
            }
            .overlay(alignment: .bottom) { Color.black.opacity(0.14).frame(height: 1) }
            .clipShape(shape)
    }
}

extension View {
    /// A card on the page, no blur: a dark contour, a small shadow, the faint wash, and light
    /// along its top edge.
    func glassPanel(radius: CGFloat = OctoRadius.row) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape.fill(OctoColor.backgroundSecondary)
                .overlay(alignment: .top) { Color.white.opacity(0.08).frame(height: 1).clipShape(shape) }
                .overlay { shape.stroke(Color.black.opacity(0.4), lineWidth: 0.5) }
                .elevation1(shape)
        }
    }

    /// Elevation 1: a close shadow and a soft one.
    func elevation1<S: Shape>(_ shape: S) -> some View {
        shadow(color: .black.opacity(0.20), radius: shadowRadius(2), y: 1)
            .shadow(color: .black.opacity(0.12), radius: shadowRadius(6), y: 2)
    }

    /// Elevation 3: three layers, for something well off the page.
    func elevation3() -> some View {
        shadow(color: .black.opacity(0.25), radius: shadowRadius(4), y: 2)
            .shadow(color: .black.opacity(0.20), radius: shadowRadius(16), y: 8)
            .shadow(color: .black.opacity(0.15), radius: shadowRadius(32), y: 16)
    }

    /// A picture raised well off the page, like a hero cover.
    func raisedShadow() -> some View {
        shadow(color: .black.opacity(0.55), radius: shadowRadius(40), y: 8)
    }

    /// A small lift, like artwork in a grid.
    func liftShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: shadowRadius(14), y: 4)
    }

    /// The shadow a chrome button or group casts.
    func chromeShadow() -> some View {
        shadow(color: .black.opacity(0.10), radius: shadowRadius(12), y: 4)
            .shadow(color: .black.opacity(0.02), radius: shadowRadius(2), y: 1)
    }

    /// The focus ring: a 2 point line just outside the edge in the accent, at `strength`.
    func focusRing<S: InsettableShape>(_ shape: S, strength: Double, width: CGFloat = 2) -> some View {
        overlay {
            shape.inset(by: -width / 2).stroke(OctoColor.focusRing, lineWidth: width).opacity(strength)
                .allowsHitTesting(false)
        }
    }
}
