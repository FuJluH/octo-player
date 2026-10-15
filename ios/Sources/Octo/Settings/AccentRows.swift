import OctoKit
import SwiftUI

/// Appearance's accent picker: a circle for each accent and one for the playing cover's, the one
/// in use carrying a dark check and a white ring, and a line naming it and saying what it colors.
struct AccentPickerRow: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        let chosen = settings.player.accent
        RowFrame(entry: SettingsIndex.accentColor) {
            VStack(alignment: .leading, spacing: 0) {
                Text(SettingsIndex.accentColor.title).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                FlowRow(spacing: 2) {
                    ForEach(AccentChoice.allCases, id: \.self) { choice in
                        AccentSwatch(choice: choice, selected: choice == chosen) { settings.setAccent(choice) }
                    }
                }
                .padding(.top, 8)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(SettingsIndex.accentColor.title)
                Text("\(chosen.label): \(chosen.help)")
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sensoryFeedback(.selection, trigger: chosen)
    }
}

/// One accent to pick, a 44 point target round a colored circle. From the album art is drawn as
/// every other accent round its circle.
private struct AccentSwatch: View {
    let choice: AccentChoice
    let selected: Bool
    let pick: () -> Void

    private static let spectrum: [Color] = AccentChoice.fixed.dropFirst().map { Color(RGBA(argb: $0.argb!)) }

    var body: some View {
        Button(action: pick) {
            ZStack {
                if selected {
                    Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 40, height: 40)
                }
                fill.frame(width: 30, height: 30)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color(hex: 0x0C0C0D))
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(NoHighlight())
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var fill: some View {
        if let argb = choice.argb {
            Circle().fill(Color(RGBA(argb: argb)))
        } else {
            Circle().fill(AngularGradient(colors: Self.spectrum + [Self.spectrum[0]], center: .center))
        }
    }
}

/// Whether Octo's glass takes the accent too, under the picker. Off, the glass stays Apple's own;
/// with Octo's own accent there is nothing to tint it with, and the row says so.
struct GlassTintRow: View {
    @State private var settings = AppSettings.shared

    var body: some View {
        let prefs = settings.player
        ToggleRow(SettingsIndex.glassTint, isOn: prefs.glassTint && prefs.accent != .octo, helper: GlassTintWords.helper(prefs.accent),
                  enabled: prefs.accent != .octo, onChange: settings.setGlassTint)
    }
}
