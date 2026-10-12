import OctoKit
import SwiftUI
import UIKit

/// Winters' Glass, the palette every Octo app shares. Dark only. On iPhone the glass itself is
/// Apple's Liquid Glass; these colours are what sits under and in it.
enum OctoColor {
    static let background = Color(OctoPalette.background)
    /// A low-alpha wash that tints glass panels.
    static let backgroundSecondary = Color(OctoPalette.backgroundSecondary)
    /// The solid surface under cards and glazed controls, and the artwork placeholder tile.
    static let backgroundTertiary = Color(OctoPalette.backgroundTertiary)
    static let accent = Color(OctoPalette.accent)
    static let accentHover = Color(OctoPalette.accentHover)
    static let surfaceRaised = Color(OctoPalette.surfaceRaised)
    static let textPrimary = Color.white
    static let textSecondary = accent
    /// Four fifths of the accent: 5.8:1 on the page, so it keeps WCAG AA.
    static let textMuted = Color(OctoPalette.textMuted)
    static let error = Color(OctoPalette.error)
    /// A standard button's resting fill.
    static let accentTonal = Color(OctoPalette.accentTonal)
    /// A selected list row.
    static let accentSelected = Color(OctoPalette.accentSelected)
    /// The filled button.
    static let accentFill = Color(OctoPalette.accentFill)
    static let focusRing = Color(OctoPalette.focusRing)
    /// A menu row under the finger.
    static let menuPress = Color(OctoPalette.menuPress)
    /// A destructive action's words; its icon stays white.
    static let destructive = Color(OctoPalette.destructive)
    static let signalRed = Color(OctoPalette.signalRed)
    static let signalOrange = Color(OctoPalette.signalOrange)
    static let signalYellow = Color(OctoPalette.signalYellow)
    static let signalGreen = Color(OctoPalette.signalGreen)
    static let signalBlue = Color(OctoPalette.signalBlue)
    /// A sheet's nearly solid fill.
    static let sheetFill = Color(OctoPalette.sheetFill)
    /// The film in Octo's glass: the faintest dim.
    static let glazeFilm = Color(OctoPalette.glazeFilm)
    /// The film under a pop-up: darker, since words sit on it.
    static let popupFilm = Color(OctoPalette.popupFilm)
    /// The darker pill that marks the chosen item inside glass.
    static let glazeSelected = Color(OctoPalette.glazeSelected)
    /// Hairlines between rows of a menu.
    static let hairline = Color.white.opacity(0.08)
    /// The app icon's lavender, used where Octo marks something as its own.
    static let lavender = Color(hex: 0x9C8AF0)
}

/// White at falling opacities, for what has no Octo colour of its own.
enum OctoInkColor {
    static let primary = Color(OctoInk.primary)
    static let secondary = Color(OctoInk.secondary)
    static let tertiary = Color(OctoInk.tertiary)
    static let quaternary = Color(OctoInk.quaternary)
    static let quinary = Color(OctoInk.quinary)
    /// How faint a control that cannot be used right now is.
    static let disabled = OctoInk.disabledAlpha
}

/// Corner sizes, the same steps every Octo app uses.
enum OctoRadius {
    static let chrome = CGFloat(OctoRadii.chrome)
    static let chromeSmall = CGFloat(OctoRadii.chromeSmall)
    static let row = CGFloat(OctoRadii.row)
    static let artXs = CGFloat(OctoRadii.artXs)
    static let artS = CGFloat(OctoRadii.artS)
    static let artM = CGFloat(OctoRadii.artM)
    static let artL = CGFloat(OctoRadii.artL)
    static let dialog = CGFloat(OctoRadii.dialog)
    static let xs = CGFloat(OctoRadii.xs)
    static let s = CGFloat(OctoRadii.s)
    static let m = CGFloat(OctoRadii.m)
    static let l = CGFloat(OctoRadii.l)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    init(_ rgba: RGBA) {
        self.init(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}

extension Font {
    /// The type scale, on SF. Sizes follow the phone's text size, as the other apps' do.
    static var octoDisplay: Font { octo(32, .black, .largeTitle) }
    static var octoTitle: Font { octo(24, .black, .title1) }
    static var octoHeadline: Font { octo(20, .bold, .title3) }
    static var octoSection: Font { octo(18, .bold, .headline) }
    static var octoBody: Font { octo(16, .medium, .body) }
    static var octoBodySmall: Font { octo(14, .regular, .subheadline) }
    static var octoCaption: Font { octo(12, .regular, .caption1) }
    static var octoLabel: Font { octo(13.5, .semibold, .footnote) }

    /// A size from the scale, grown or shrunk with the phone's text size.
    static func octo(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle = .body) -> Font {
        Font(UIFontMetrics(forTextStyle: style).scaledFont(for: .systemFont(ofSize: size, weight: weight)) as CTFont)
    }
}

/// The display title's letter spacing.
let octoDisplayTracking: CGFloat = -0.5
