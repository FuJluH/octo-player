import OctoIntents
import OctoSystem
import SwiftUI
import UIKit
import WidgetKit

/// The song that is on, with play, pause and skip. It shows what the app last left on the
/// shelf; with nothing there it is "Nothing playing" and a play button that picks up the saved
/// queue. The app asks for a redraw when the song changes or the music starts or stops, so it
/// never asks for one itself.
struct NowPlayingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.nowPlaying, provider: NowPlayingProvider()) { entry in
            NowPlayingView(entry: entry)
        }
        .configurationDisplayName(WidgetWords.nowPlaying)
        .description(WidgetWords.nowPlayingDescription)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let playback: WidgetPlayback?
    let cover: UIImage?
    /// The shape the widget is drawn at.
    let size: WidgetSize
}

struct NowPlayingProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), playback: WidgetPlayback(title: "Hold On, We're Going Home", artist: "Drake", isPlaying: true),
                        cover: nil, size: size(context))
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        completion(entry(context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        completion(Timeline(entries: [entry(context)], policy: .never))
    }

    private func entry(_ context: Context) -> NowPlayingEntry {
        let shelf = WidgetShelf.shared()
        let shelved = shelf?.read()
        let cover = shelved.flatMap { shelf?.coverURL($0) }.flatMap { UIImage(contentsOfFile: $0.path) }
        return NowPlayingEntry(date: Date(), playback: shelved?.playback, cover: cover, size: size(context))
    }

    private func size(_ context: Context) -> WidgetSize {
        WidgetSize(width: Double(context.displaySize.width), height: Double(context.displaySize.height))
    }
}

struct NowPlayingView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) private var family

    private var face: NowPlayingFace { nowPlayingFace(entry.playback, entry.size) }

    var body: some View {
        content
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .containerBackground(for: .widget) { Backdrop(cover: face.empty ? nil : entry.cover) }
            // The picture and the words open the full player; with nothing loaded, the app.
            .widgetURL(face.empty ? OctoLink.open.url : OctoLink.player.url)
    }

    @ViewBuilder private var content: some View {
        switch entry.size {
        case .small: small
        case .medium: row
        case .large: family == .systemLarge ? AnyView(tall) : AnyView(wide)
        }
    }

    /// The small square: the cover and play or pause, the title under them.
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Cover(image: entry.cover, empty: face.empty, side: 64, radius: 12)
                Spacer(minLength: 8)
                Controls(face: face, family: family, playSide: 42)
            }
            Spacer(minLength: 8)
            Title(face: face, font: .system(size: 15, weight: .semibold))
        }
    }

    /// Wide and short: everything in one row.
    private var row: some View {
        HStack(spacing: 12) {
            Cover(image: entry.cover, empty: face.empty, side: 48, radius: 10)
            VStack(alignment: .leading, spacing: 1) {
                Title(face: face, font: .system(size: 15, weight: .semibold))
                Artist(face: face, font: .system(size: 13))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Controls(face: face, family: family, playSide: 40)
        }
    }

    /// The medium widget: the cover beside the words, the buttons under them.
    private var wide: some View {
        HStack(spacing: 14) {
            Cover(image: entry.cover, empty: face.empty, side: nil, radius: 14)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Title(face: face, font: .system(size: 17, weight: .semibold))
                Artist(face: face, font: .system(size: 14))
                Spacer(minLength: 6)
                Controls(face: face, family: family, playSide: 46)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The large widget: the cover above the words and the buttons.
    private var tall: some View {
        VStack(alignment: .leading, spacing: 12) {
            Cover(image: entry.cover, empty: face.empty, side: 180, radius: 18)
            VStack(alignment: .leading, spacing: 2) {
                Title(face: face, font: .system(size: 20, weight: .semibold))
                Artist(face: face, font: .system(size: 15))
            }
            Controls(face: face, family: family, playSide: 54)
                .frame(maxWidth: .infinity)
        }
    }
}

/// The song's cover, or the empty cover: a dark tile with a music note.
private struct Cover: View {
    let image: UIImage?
    let empty: Bool
    /// A fixed side, or nil to take the height it is given.
    let side: CGFloat?
    let radius: CGFloat

    var body: some View {
        picture
            .aspectRatio(1, contentMode: .fit)
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .accessibilityLabel(WidgetWords.openPlayer)
    }

    @ViewBuilder private var picture: some View {
        if let image, !empty {
            Image(uiImage: image)
                .resizable()
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFill()
        } else {
            ZStack {
                WidgetLook.coverTile
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(WidgetLook.secondary)
            }
        }
    }
}

private struct Title: View {
    let face: NowPlayingFace
    let font: Font

    var body: some View {
        Text(face.title)
            .font(font)
            .lineLimit(face.titleLines)
            .truncationMode(.tail)
            .widgetAccentable()
    }
}

private struct Artist: View {
    let face: NowPlayingFace
    let font: Font

    var body: some View {
        if let artist = face.artist {
            Text(artist)
                .font(font)
                .foregroundStyle(WidgetLook.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Previous, play or pause, and next, as the shape shows them.
private struct Controls: View {
    let face: NowPlayingFace
    let family: WidgetFamily
    let playSide: CGFloat

    var body: some View {
        HStack(spacing: playSide * 0.3) {
            if face.showSkips {
                ControlButton(command: .previous, family: family, side: playSide * 0.82, prominent: false)
            }
            ControlButton(command: face.playing ? .pause : .play, family: family, side: playSide, prominent: true)
            if face.showSkips {
                ControlButton(command: .next, family: family, side: playSide * 0.82, prominent: false)
            }
        }
    }
}

/// One button: an intent the app carries out without opening, or where the build cannot run
/// intents, a link that opens Octo to do the same. A small widget has no links of its own, so
/// there it only shows the state.
private struct ControlButton: View {
    let command: WidgetCommand
    let family: WidgetFamily
    let side: CGFloat
    let prominent: Bool

    var body: some View {
        if WidgetLook.intentsReady {
            intentButton
        } else if family != .systemSmall {
            Link(destination: OctoLink.command(command).url) { face }
        } else {
            face
        }
    }

    @ViewBuilder private var intentButton: some View {
        switch command {
        case .play: Button(intent: PlayIntent()) { face }.buttonStyle(.plain)
        case .pause: Button(intent: PauseIntent()) { face }.buttonStyle(.plain)
        case .next: Button(intent: NextIntent()) { face }.buttonStyle(.plain)
        case .previous: Button(intent: PreviousIntent()) { face }.buttonStyle(.plain)
        case .quick: face
        }
    }

    private var face: some View {
        Image(systemName: symbol)
            .font(.system(size: side * (prominent ? 0.42 : 0.5), weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background {
                if prominent { Circle().fill(.white.opacity(0.18)) }
            }
            .contentShape(Circle())
            .widgetAccentable()
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch command {
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .next: "forward.fill"
        case .previous: "backward.fill"
        case .quick: "play.fill"
        }
    }

    private var label: String {
        switch command {
        case .play: WidgetWords.play
        case .pause: WidgetWords.pause
        case .next: WidgetWords.next
        case .previous: WidgetWords.previous
        case .quick: WidgetWords.play
        }
    }
}

/// Behind the widget: Octo's dark, washed with the song's cover.
private struct Backdrop: View {
    let cover: UIImage?

    var body: some View {
        ZStack {
            WidgetLook.background
            if let cover {
                Image(uiImage: cover)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .opacity(0.55)
            }
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
    }
}
