import OctoKit
import SwiftUI
import UIKit

/// Remembers which version's news was last put away, in its own store ("whats_new").
@MainActor
@Observable
final class WhatsNewStore {
    static let shared = WhatsNewStore()

    private let store = UserDefaults(suiteName: "whats_new") ?? .standard
    private let key = "last_seen_version"

    /// The build number running, which each update raises.
    static var currentVersion: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    private(set) var lastSeen: Int?

    private init() {
        lastSeen = store.object(forKey: key) as? Int
    }

    var due: Bool { WhatsNew.due(lastSeen: lastSeen, current: Self.currentVersion, freshInstall: Self.freshInstall) }

    /// A fresh install starts having seen this version, so later updates know where they stand.
    func settle() {
        if lastSeen == nil, Self.freshInstall { markSeen() }
    }

    func markSeen() {
        store.set(Self.currentVersion, forKey: key)
        lastSeen = Self.currentVersion
    }

    /// Installed and never used before: nothing an earlier Octo keeps is here yet.
    private static var freshInstall: Bool {
        let defaults = UserDefaults.standard
        return ["servers", "stream.quality", "bar.player", "sound.byOutput", "lyrics.look"].allSatisfy { defaults.object(forKey: $0) == nil }
    }
}

extension View {
    /// The What's new panel in a system sheet, at half height with room to pull it up; pulling
    /// it away closes it.
    func whatsNewPanel(isPresented: Binding<Bool>, onClose: @escaping () -> Void = {}) -> some View {
        sheet(isPresented: isPresented, onDismiss: onClose) {
            WhatsNewPanel()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}

/// What this update brings: the version and the notes, scrolling when they are long.
struct WhatsNewPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What's new").font(.settingsLabel).foregroundStyle(OctoColor.textSecondary)
                Text("Octo \(Session.appVersion)")
                    .font(.octoTitle)
                    .foregroundStyle(OctoColor.textPrimary)
                    .padding(.top, 2)
                    .padding(.bottom, 18)
                    .accessibilityAddTraits(.isHeader)
                MarkdownView(blocks: Markdown.parse(WhatsNew.notes))
            }
            .padding(.leading, 24)
            .padding(.trailing, 24)
            .padding(.top, 30)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityLabel("What's new")
    }
}

/// Markdown blocks drawn the way Octo draws its notes: quiet paragraphs, bold words lit, small
/// dots for bullets.
struct MarkdownView: View {
    let blocks: [Markdown.Block]
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                blockView(block, first: index == 0)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Markdown.Block, first: Bool) -> some View {
        switch block {
        case .heading(let level, let spans):
            let style = headingStyle(level)
            Text(Self.attributed(spans, base: style.color, font: style.font))
                .font(style.font)
                .lineSpacing(style.spacing)
                .padding(.top, first ? 0 : style.above)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let spans):
            Text(Self.attributed(spans, base: OctoColor.textSecondary))
                .font(.octoBodySmall)
                .lineSpacing(4)
                .padding(.top, first ? 0 : 10)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 6) {
                        bulletLine(item.text, dot: 5, color: OctoColor.textMuted)
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            bulletLine(child.text, dot: 4, color: OctoColor.textMuted.opacity(0.35)).padding(.leading, 18)
                        }
                    }
                }
            }
            .padding(.top, first ? 0 : 6)
        case .rule:
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1).padding(.vertical, 18)
        }
    }

    private func bulletLine(_ spans: [Markdown.Span], dot: CGFloat, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: dot, height: dot).padding(.top, 8)
            Text(Self.attributed(spans, base: OctoColor.textSecondary))
                .font(.octoBodySmall)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingStyle(_ level: Int) -> (font: Font, color: Color, spacing: CGFloat, above: CGFloat) {
        switch level {
        case 1: (.octoHeadline, OctoColor.textPrimary, 2, 28)
        case 2: (.octoBody.weight(.bold), OctoColor.textPrimary, 3, 26)
        default: (.settingsLabel, OctoColor.textSecondary, 2, 18)
        }
    }

    /// Bold words in the primary color at semibold, italic slanted, code in monospace on a faint
    /// patch, links in the primary color and underlined.
    static func attributed(_ spans: [Markdown.Span], base: Color, font: Font = .octoBodySmall) -> AttributedString {
        var out = AttributedString()
        for span in spans {
            var run = AttributedString(span.text)
            run.foregroundColor = span.bold || span.link != nil ? OctoColor.textPrimary : base
            if span.code {
                run.font = .system(size: 13, design: .monospaced)
                run.backgroundColor = Color.white.opacity(0.08)
            } else if span.bold || span.italic {
                var look = font
                if span.bold { look = look.weight(.semibold) }
                if span.italic { look = look.italic() }
                run.font = look
            }
            if let link = span.link, let url = URL(string: link) {
                run.link = url
                run.underlineStyle = .single
            }
            out += run
        }
        return out
    }
}
