import OctoIntents
import OctoSystem
import SwiftUI
import WidgetKit

/// Four squares that each start music: Liked songs, Recently added, Album mix and Resume.
/// Nothing on it changes, so it is drawn once.
struct QuickPlayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.quickPlay, provider: QuickPlayProvider()) { _ in
            QuickPlayView()
        }
        .configurationDisplayName(WidgetWords.quickPlay)
        .description(WidgetWords.quickPlayDescription)
        // Without intents the squares are links, which a small widget cannot hold.
        .supportedFamilies(WidgetLook.intentsReady ? [.systemSmall, .systemMedium] : [.systemMedium])
    }
}

struct QuickPlayEntry: TimelineEntry {
    let date: Date
}

struct QuickPlayProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickPlayEntry { QuickPlayEntry(date: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (QuickPlayEntry) -> Void) {
        completion(QuickPlayEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickPlayEntry>) -> Void) {
        completion(Timeline(entries: [QuickPlayEntry(date: Date())], policy: .never))
    }
}

struct QuickPlayView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .systemSmall {
                // Two by two.
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        QuickTile(pick: .liked)
                        QuickTile(pick: .recentlyAdded)
                    }
                    GridRow {
                        QuickTile(pick: .albumMix)
                        QuickTile(pick: .resume)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(QuickPick.allCases, id: \.self) { QuickTile(pick: $0) }
                }
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { WidgetLook.background }
    }
}

/// One square: its symbol over its name. A tap starts its music in the app.
private struct QuickTile: View {
    let pick: QuickPick

    var body: some View {
        if WidgetLook.intentsReady {
            intentButton
        } else {
            Link(destination: OctoLink.command(.quick(pick)).url) { face }
        }
    }

    @ViewBuilder private var intentButton: some View {
        switch pick {
        case .liked: Button(intent: PlayLikedIntent()) { face }.buttonStyle(.plain)
        case .recentlyAdded: Button(intent: PlayRecentlyAddedIntent()) { face }.buttonStyle(.plain)
        case .albumMix: Button(intent: PlayAlbumMixIntent()) { face }.buttonStyle(.plain)
        case .resume: Button(intent: ResumeIntent()) { face }.buttonStyle(.plain)
        }
    }

    private var face: some View {
        VStack(spacing: 4) {
            Image(systemName: pick.symbol)
                .font(.system(size: 20, weight: .semibold))
                .widgetAccentable()
            Text(pick.label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(WidgetLook.tile))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
