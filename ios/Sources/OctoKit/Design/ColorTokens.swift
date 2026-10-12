import Foundation

/// A color as sRGB channels and an opacity, each from 0 to 1.
public struct RGBA: Sendable, Hashable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// A color from `0xRRGGBB`.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    /// A color from 0 to 255 channels.
    public init(_ r: Int, _ g: Int, _ b: Int, alpha: Double = 1) {
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, alpha: alpha)
    }

    /// A color from `0xAARRGGBB`.
    public init(argb: UInt32) {
        self.init(hex: argb & 0xFFFFFF, alpha: Double((argb >> 24) & 0xFF) / 255)
    }

    public static let white = RGBA(red: 1, green: 1, blue: 1)
    public static let black = RGBA(red: 0, green: 0, blue: 0)
    public static let clear = RGBA(red: 0, green: 0, blue: 0, alpha: 0)

    /// The same color at another opacity.
    public func opacity(_ alpha: Double) -> RGBA { RGBA(red: red, green: green, blue: blue, alpha: alpha) }

    /// The color as `0xRRGGBB`, each channel rounded to a byte.
    public var hex: UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(red) << 16 | byte(green) << 8 | byte(blue)
    }

    /// Relative luminance, from the sRGB channels.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
}

/// Mixes two colors channel by channel, the way a stylesheet does. The result is opaque.
public func mix(_ from: RGBA, _ to: RGBA, _ amount: Double) -> RGBA {
    RGBA(red: from.red + (to.red - from.red) * amount,
         green: from.green + (to.green - from.green) * amount,
         blue: from.blue + (to.blue - from.blue) * amount)
}

/// Winters' Glass, the palette every Octo app shares. Dark only.
public enum OctoPalette {
    public static let background = RGBA(hex: 0x0C0C0D)
    /// A low-alpha wash that tints glass panels.
    public static let backgroundSecondary = RGBA.white.opacity(0.03)
    /// The solid surface under cards and glazed controls.
    public static let backgroundTertiary = RGBA(hex: 0x1A1A1B)
    public static let accent = RGBA(hex: 0x97B1B9)
    /// A raised surface for rows to read and change: the solid gray with a touch of the accent.
    public static let surfaceRaised = mix(RGBA(hex: 0x1A1A1B), RGBA(hex: 0x97B1B9), 0.06)
    public static let accentHover = RGBA(hex: 0xADC4CC)
    public static let textPrimary = RGBA.white
    public static let textSecondary = accent
    /// The quietest words: four fifths of the accent, 5.8:1 on the page.
    public static let textMuted = accent.opacity(0.8)
    public static let error = RGBA(hex: 0xEF4444)
    /// A standard button's resting fill: a tenth of the accent in a dark gray.
    public static let accentTonal = mix(RGBA(hex: 0x1E1E1E), accent, 0.10)
    /// A selected list row: the accent 40% of the way out of black.
    public static let accentSelected = mix(.black, accent, 0.40)
    /// The ring round a focused control.
    public static let focusRing = accent.opacity(0.70)
    /// A menu row under the finger: the selected row's tint, half as strong.
    public static let menuPress = accentSelected.opacity(0.55)
    /// A destructive action's words: a soft red.
    public static let destructive = RGBA(hex: 0xFF3B30).opacity(0.85)
    public static let signalRed = RGBA(hex: 0xFF3B30)
    public static let signalOrange = RGBA(hex: 0xFF9500)
    public static let signalYellow = RGBA(hex: 0xFFCC00)
    public static let signalGreen = RGBA(hex: 0x28CD41)
    public static let signalBlue = RGBA(hex: 0x007AFF)
    /// The filled button: the accent 45% of the way to black.
    public static let accentFill = mix(accent, .black, 0.45)
    /// A sheet's fill: the background with a little accent, nearly solid.
    public static let sheetFill = mix(background, accent, 0.05).opacity(0.97)
    /// The film in Octo's glass: the faintest dim.
    public static let glazeFilm = RGBA.black.opacity(0.16)
    /// The film under a pop-up: darker, since words sit on it.
    public static let popupFilm = RGBA.black.opacity(0.52)
    /// The darker pill that marks the chosen item inside glass.
    public static let glazeSelected = RGBA.black.opacity(0.72)
}

/// White at falling opacities, for what has no Octo color of its own.
public enum OctoInk {
    public static let primaryAlpha = 0.85
    public static let secondaryAlpha = 0.55
    public static let tertiaryAlpha = 0.25
    public static let quaternaryAlpha = 0.10
    public static let quinaryAlpha = 0.05

    /// Titles and body.
    public static let primary = RGBA.white.opacity(primaryAlpha)
    /// Subtitles and details.
    public static let secondary = RGBA.white.opacity(secondaryAlpha)
    /// Disabled words and placeholders.
    public static let tertiary = RGBA.white.opacity(tertiaryAlpha)
    /// Hover fills and hairlines.
    public static let quaternary = RGBA.white.opacity(quaternaryAlpha)
    /// Resting fills and alternate rows.
    public static let quinary = RGBA.white.opacity(quinaryAlpha)

    /// How faint a control that cannot be used right now is.
    public static let disabledAlpha = 0.5
}

/// Corner sizes, in points.
public enum OctoRadii {
    /// Buttons and groups in the chrome, and their small size.
    public static let chrome = 10.0
    public static let chromeSmall = 6.0
    /// List rows.
    public static let row = 12.0
    /// Artwork, from a thumbnail to a hero.
    public static let artXs = 3.0
    public static let artS = 6.0
    public static let artM = 8.0
    public static let artL = 12.0
    /// Windows and dialogs.
    public static let dialog = 12.0
    /// Anything else.
    public static let xs = 2.0
    public static let s = 4.0
    public static let m = 6.0
    public static let l = 8.0
}

/// The height of a menu row: compact for the pointer, taller for a finger.
public enum MenuRowHeight {
    public static let pointer = 30.0
    public static let touch = 40.0
}

/// How light a color looks, from 0 (black) to 1 (white): CIE L* from its luminance.
public func perceivedLightness(_ color: RGBA) -> Double {
    let y = color.luminance
    let l = y > 216.0 / 24389.0 ? 116 * cbrt(y) - 16 : y * 24389.0 / 27.0
    return min(1, max(0, l / 100))
}

/// Where words switch from white to black on a fill.
public let lightFillThreshold = 0.58

/// The color words take on a fill: black on a light one, white on a dark one.
public func contentColorFor(_ fill: RGBA) -> RGBA {
    perceivedLightness(fill) > lightFillThreshold ? .black : .white
}

/// CSS blur values, as the glass recipes are written, turned into a Gaussian's sigma in
/// points. A box shadow's blur B is a Gaussian of sigma B / 2.
public func shadowSigma(_ cssBlur: Double) -> Double { cssBlur / 2 }

/// A backdrop filter's blur B is a Gaussian of sigma B.
public func backdropSigma(_ cssBlur: Double) -> Double { cssBlur }
