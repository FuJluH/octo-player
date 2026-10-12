import OctoKit
import SwiftUI

/// A song's title on one line, cut short before the explicit mark so the mark always shows,
/// 6 points after the title. `lead` goes before the title.
struct SongTitleLine<Lead: View>: View {
    let title: String
    var explicit = false
    var font: Font = .octoBodySmall
    var color: Color = .white
    var markColor: Color = OctoColor.textMuted
    @ViewBuilder var lead: Lead

    var body: some View {
        HStack(spacing: 6) {
            lead
            Text(title)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
            if explicit {
                ExplicitMark(color: markColor).fixedSize()
            }
        }
    }
}

extension SongTitleLine where Lead == EmptyView {
    init(_ title: String, explicit: Bool = false, font: Font = .octoBodySmall, color: Color = .white,
         markColor: Color = OctoColor.textMuted) {
        self.init(title: title, explicit: explicit, font: font, color: color, markColor: markColor, lead: { EmptyView() })
    }
}

extension Song {
    /// Whether the song is marked explicit; a clean edit is not.
    var isExplicit: Bool { explicitStatus == "explicit" }
}

extension Font {
    /// Playlist cover words, in a display face.
    static func coverTitle(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    /// Codes people read out or type, like a sign-in code: one width per character.
    static func code(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// What lists read to mark the row of the song on now, without each watching the player.
struct NowMark: Equatable {
    var songId: String?
    var isPlaying = false
}

extension EnvironmentValues {
    @Entry var nowMark = NowMark()
}
