import OctoKit
import SwiftUI

/// While lyrics show, the controls fold into one glass bar: the song (a tap on it leaves the
/// lyrics), previous, play and next, the lit lyrics switch and the lyrics menu, a system menu
/// whose timing opens in a popover beside it, with the song's progress along the bottom edge.
/// A sideways drag starting along that edge scrubs.
struct LyricsBar: View {
    let ink: Color
    let close: () -> Void
    @Binding var timing: Bool
    let chooseOther: () -> Void
    @Environment(Player.self) private var player
    @State private var scrub: Double?
    @State private var width: CGFloat = 0

    private static let height: CGFloat = 64
    /// The progress line keeps to the capsule's straight part.
    private static let inset: CGFloat = 32
    private static let scrubZone: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            BadgedCover(id: player.current?.coverArt, size: 40, radius: 10, external: player.current?.isExternal ?? false)
            Button(action: close) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(player.current?.title ?? "")
                        .font(.octoLabel)
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(player.current?.byline ?? "")
                        .font(.octo(11, .regular, .caption1))
                        .foregroundStyle(ink.opacity(0.6))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(NoPress())
            .accessibilityLabel("Leave lyrics")
            control(.previous, 24, "Previous", player.previous)
            control(player.isPlaying ? .pause : .play, 28, player.isPlaying ? "Pause" : "Play", player.toggle)
            control(.next, 24, "Next", player.next)
            Button(action: close) {
                IconView(.lyrics, size: 22, color: ink)
                    .iconGlow(true, color: ink)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(NoPress())
            .accessibilityLabel("Lyrics")
            .accessibilityValue("Showing")
            Menu {
                LyricsMenuItems(trackId: player.current?.id, openTiming: { timing = true }, chooseOther: chooseOther)
            } label: {
                IconView(.more, size: 22, color: ink.opacity(0.7))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .accessibilityLabel("Lyrics menu")
            .glassPopover(isPresented: $timing) {
                if let trackId = player.current?.id { TimingCard(trackId: trackId) }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { progress }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .floatingGlass(Capsule())
        .simultaneousGesture(scrubbing)
    }

    private var progress: some View {
        TimelineView(.animation(paused: !player.isPlaying || scrub != nil)) { _ in
            let length = max(player.duration, player.livePosition)
            let fraction = scrub ?? (length > 0 ? min(max(player.livePosition / length, 0), 1) : 0)
            Canvas { context, size in
                let stroke: CGFloat = scrub == nil ? 2 : 3
                let y = size.height - stroke / 2
                var track = Path()
                track.move(to: CGPoint(x: 0, y: y))
                track.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(track, with: .color(ink.opacity(0.18)), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                guard fraction > 0 else { return }
                var played = Path()
                played.move(to: CGPoint(x: 0, y: y))
                played.addLine(to: CGPoint(x: size.width * fraction, y: y))
                context.stroke(played, with: .color(ink.opacity(scrub == nil ? 0.7 : 0.95)),
                               style: StrokeStyle(lineWidth: stroke, lineCap: .round))
            }
        }
        .frame(height: 3)
        .padding(.horizontal, Self.inset)
        .padding(.bottom, 4)
        .allowsHitTesting(false)
    }

    /// A sideways drag that starts in the bottom 22 points scrubs, once the song's length is known;
    /// the song plays from there when the finger lifts.
    private var scrubbing: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                if scrub == nil {
                    guard player.duration > 0, value.startLocation.y >= Self.height - Self.scrubZone,
                          abs(value.translation.width) > abs(value.translation.height)
                    else { return }
                }
                scrub = fraction(value.location.x)
            }
            .onEnded { value in
                guard scrub != nil else { return }
                let target = fraction(value.location.x)
                scrub = nil
                player.seek(to: target * player.duration)
            }
    }

    private func fraction(_ x: CGFloat) -> Double {
        let room = max(1, width - Self.inset * 2)
        return Double(min(max((x - Self.inset) / room, 0), 1))
    }

    private func control(_ icon: OctoIcon, _ size: CGFloat, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon, size: size, color: ink)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoPress())
        .accessibilityLabel(label)
    }
}
