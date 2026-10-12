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

/// The faint fill the account cards use beyond the shared palette.
enum AccountColor {
    static let fill = Color.white.opacity(0.04)
}
