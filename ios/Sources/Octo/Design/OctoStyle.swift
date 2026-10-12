import SwiftUI

/// Winters' Glass, the palette the other Octo apps share (`design/.../OctoColors.kt`). Dark only.
/// On iPhone the glass itself is Apple's Liquid Glass; these colours are what sits under and in it.
enum OctoColor {
    static let background = Color(hex: 0x0C0C0D)
    static let backgroundTertiary = Color(hex: 0x1A1A1B)
    static let accent = Color(hex: 0x97B1B9)
    static let accentHover = Color(hex: 0xADC4CC)
    static let surfaceRaised = Color(hex: 0x1A1A1B).mix(with: accent, by: 0.06)
    static let textPrimary = Color.white
    static let textSecondary = accent
    /// Four fifths of the accent: 5.8:1 on the page, so it keeps WCAG AA.
    static let textMuted = accent.opacity(0.8)
    static let error = Color(hex: 0xEF4444)
    static let destructive = Color(hex: 0xFF3B30).opacity(0.85)
    /// The app icon's lavender, used where Octo marks something as its own.
    static let lavender = Color(hex: 0x9C8AF0)
}

/// Corner sizes, the same steps as `OctoRadius` on the other apps.
enum OctoRadius {
    static let row: CGFloat = 12
    static let artS: CGFloat = 6
    static let artM: CGFloat = 8
    static let artL: CGFloat = 12
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
}

extension Font {
    /// The type scale from `OctoType.kt`, on SF.
    static let octoDisplay = Font.system(size: 32, weight: .black)
    static let octoTitle = Font.system(size: 24, weight: .black)
    static let octoHeadline = Font.system(size: 20, weight: .bold)
    static let octoSection = Font.system(size: 18, weight: .bold)
    static let octoBody = Font.system(size: 16, weight: .medium)
    static let octoBodySmall = Font.system(size: 14)
    static let octoCaption = Font.system(size: 12)
}
