import OctoKit
import SwiftUI

/// While lyrics show, the controls fold into one glass bar: the round artwork with the song's
/// progress as a ring round it (as the bar's round button has it: full for a station, breathing
/// while paused), the song (a tap on it leaves the lyrics), previous, play and next, the lit
/// lyrics switch and the lyrics menu, a system menu whose timing opens in a popover beside it. A
/// sideways drag starting along the bottom edge scrubs, the ring following the finger; an upright
/// one is the player's pull.
struct LyricsBar: View {
    let ink: Color
    let close: () -> Void
    @Binding var timing: Bool
    let chooseOther: () -> Void
    @Environment(Player.self) private var player
    @Environment(Downloads.self) private var downloads
    @Environment(\.passedDrag) private var passedDrag
    @State private var scrub: Double?
    /// The drag went up or down first: it is handed on to the player.
    @State private var passing = false
    @GestureState private var touching = false
    @State private var width: CGFloat = 0

    private static let height: CGFloat = 64
    /// A scrub keeps to the capsule's straight part.
    private static let inset: CGFloat = 32
    /// The room between the artwork and its ring.
    private static let ringRoom: CGFloat = 3
    private static let scrubZone: CGFloat = 22

    var body: some View {
        HStack(spacing: 0) {
            // The artwork sits 12 points in; its ring takes the room around it.
            ZStack {
                BadgedCover(id: player.current?.coverArt, size: 40, radius: 20,
                            external: isOutsideLibrary(player.current, adopted: downloads.adopted))
                if player.current != nil {
                    ProgressRing(scrub: scrub, speaks: songWords)
                }
            }
            .frame(width: 40 + Self.ringRoom * 2, height: 40 + Self.ringRoom * 2)
            .padding(.trailing, -Self.ringRoom)
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
            .accessibilityElement(children: .combine)
            .accessibilityHint("Leave lyrics")
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
        .padding(.leading, 12 - Self.ringRoom)
        .padding(.trailing, 6)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .floatingGlass(Capsule())
        .simultaneousGesture(scrubbing)
        .onChange(of: touching) { _, now in
            // A drag taken away by something else seeks nothing.
            guard !now else { return }
            scrub = nil
            if passing {
                passing = false
                passedDrag?.cancelled()
            }
        }
    }

    /// The song and its artist, as a screen reader hears the artwork.
    private var songWords: String {
        [player.current?.title, player.current?.byline].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// A sideways drag that starts in the bottom 22 points scrubs, once the song's length is known;
    /// the song plays from there when the finger lifts. A drag that goes up or down first is the
    /// player's.
    private var scrubbing: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($touching) { _, state, _ in state = true }
            .onChanged { value in
                if passing {
                    passedDrag?.moved(value.translation)
                    return
                }
                if scrub == nil {
                    let sideways = abs(value.translation.width) > abs(value.translation.height)
                    guard sideways, player.duration > 0, value.startLocation.y >= Self.height - Self.scrubZone else {
                        if !sideways {
                            passing = true
                            passedDrag?.moved(value.translation)
                        }
                        return
                    }
                }
                scrub = fraction(value.location.x)
            }
            .onEnded { value in
                if passing {
                    passing = false
                    passedDrag?.ended(value.translation, value.velocity)
                    return
                }
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
