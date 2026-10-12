import OctoKit
import SwiftUI

/// While lyrics show, the controls fold into one glass bar: the song, previous, play, next and
/// the lyrics switch, with the progress along its bottom edge.
struct LyricsBar: View {
    let ink: Color
    let close: () -> Void
    let menu: () -> Void
    @Environment(Player.self) private var player
    @State private var scrub: Double?

    var body: some View {
        HStack(spacing: 0) {
            Button(action: close) {
                HStack(spacing: 10) {
                    Cover(id: player.current?.coverArt, size: 40, radius: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.current?.title ?? "").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        Text(player.current?.byline ?? "").font(.system(size: 11)).opacity(0.6).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave lyrics")
            control("backward.fill", 22, "Previous", player.previous)
            control(player.isPlaying ? "pause.fill" : "play.fill", 26, player.isPlaying ? "Pause" : "Play", player.toggle)
            control("forward.fill", 22, "Next", player.next)
            PlayerChromeButton(icon: "quote.bubble.fill", label: "Lyrics", ink: ink, action: close)
                .accessibilityValue("Showing")
            Button(action: menu) {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold)).foregroundStyle(ink.opacity(0.7))
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lyrics menu")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 64)
        .overlay(alignment: .bottom) {
            // Dragging along the bottom edge scrubs through the song.
            GeometryReader { box in
                let fraction = scrub.map { $0 / max(player.duration, 1) } ?? player.progress
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.18))
                    Capsule().fill(ink.opacity(scrub == nil ? 0.7 : 0.95)).frame(width: box.size.width * fraction)
                }
                .frame(height: scrub == nil ? 2 : 3)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 4).onChanged { drag in
                    scrub = max(0, min(1, drag.location.x / box.size.width)) * player.duration
                }.onEnded { _ in
                    if let scrub { player.seek(to: scrub) }
                    scrub = nil
                })
            }
            .frame(height: 22)
            .padding(.horizontal, 32)
            .padding(.bottom, 4)
        }
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, -12)
    }

    private func control(_ icon: String, _ size: CGFloat, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size)).frame(width: 40, height: 40)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
