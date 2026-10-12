import OctoKit
import SwiftUI

// The row, line and colors the Server and sync page, Family and the server's extras share,
// beside the settings rows.

/// A row that opens another account page on the tab's stack, drawn like a settings link row.
/// `also` runs as it opens, for a page that should open something of its own.
struct AccountLinkRow: View {
    let entry: SettingEntry
    let route: AccountRoute
    var also: (() -> Void)?

    var body: some View {
        NavigationLink(value: route) {
            RowFrame(entry: entry) {
                Text(entry.title).font(.octoBody).foregroundStyle(OctoColor.textPrimary).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: SettingsIcon.chevron)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(OctoColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(SettingsRowPress())
        .simultaneousGesture(TapGesture().onEnded { also?() })
    }
}

/// A muted line of a list page, 20 points in.
struct PanelLine: View {
    let text: String
    var color: Color = OctoColor.textMuted

    var body: some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
    }
}

/// The few colors the account pages use beyond the shared palette.
enum AccountColor {
    static let signalOrange = Color(hex: 0xFF9500)
    static let signalGreen = Color(hex: 0x28CD41)
    /// Black with 40% of the accent: a chosen pill.
    static let accentSelected = Color.black.mix(with: OctoColor.accent, by: 0.4)
    /// A dark grey with 10% of the accent: a soft badge.
    static let accentTonal = Color(hex: 0x1E1E1E).mix(with: OctoColor.accent, by: 0.1)
    /// Words on the accent fill.
    static let onAccent = Color(hex: 0x0C0C0D)
    static let fill = Color.white.opacity(0.04)
    static let edge = Color.white.opacity(0.08)
}
