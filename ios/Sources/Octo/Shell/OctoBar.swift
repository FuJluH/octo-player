import OctoKit
import SwiftUI

/// Octo's bar: one floating row on Apple's Liquid Glass. A capsule of four tabs and, beside it,
/// the round now-playing button. Tapping that button grows it into the mini player in the same
/// row while the tabs fold into a small circle at the left; tapping the circle brings them back.
struct OctoBar: View {
    @Binding var tab: AppTab
    @Binding var playerMode: Bool
    let reselect: (AppTab) -> Void
    let openPlayer: () -> Void
    @Environment(Player.self) private var player
    @Namespace private var pill

    static let height: CGFloat = 56
    static let gap: CGFloat = 10
    /// How far above the bottom safe area the bar floats.
    static let bottomGap: CGFloat = 14
    /// Room pages leave under their content for the bar.
    static let clearance: CGFloat = 120
    /// The bar's shape change: a soft spring, like the other apps' (damping 0.75, stiffness 200).
    static let morph = Animation.spring(response: 0.44, dampingFraction: 0.75)

    private var showsPlayer: Bool { playerMode && player.current != nil }

    /// Two glass shapes that keep who they are while their widths change, so the growth is one
    /// continuous motion: the tabs fold to a circle at the left as the player widens beside it.
    var body: some View {
        GeometryReader { box in
            let wide = max(box.size.width - Self.height - Self.gap, Self.height)
            GlassEffectContainer(spacing: Self.gap) {
                HStack(spacing: Self.gap) {
                    ZStack(alignment: .leading) {
                        tabs
                            .frame(width: wide)
                            .opacity(showsPlayer ? 0 : 1)
                            .allowsHitTesting(!showsPlayer)
                        foldedTabs
                            .opacity(showsPlayer ? 1 : 0)
                            .allowsHitTesting(showsPlayer)
                    }
                    .frame(width: showsPlayer ? Self.height : wide, height: Self.height, alignment: .leading)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)

                    ZStack(alignment: .trailing) {
                        MiniPlayerPill(open: openPlayer)
                            .frame(width: wide)
                            .opacity(showsPlayer ? 1 : 0)
                            .allowsHitTesting(showsPlayer)
                        NowPlayingFace(tap: faceTapped)
                            .opacity(showsPlayer ? 0 : 1)
                            .allowsHitTesting(!showsPlayer)
                    }
                    .frame(width: showsPlayer ? wide : Self.height, height: Self.height, alignment: .trailing)
                    .clipShape(Capsule())
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .animation(Self.morph, value: showsPlayer)
        }
        .frame(height: Self.height)
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
    }

    /// With a song loaded the button grows into the player; with nothing loaded it shuffles
    /// the library.
    private func faceTapped() {
        if player.current != nil {
            playerMode = true
        } else {
            Task { await player.shuffleLibrary() }
        }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    if item == tab {
                        reselect(item)
                    } else {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) { tab = item }
                    }
                } label: {
                    ZStack {
                        if item == tab {
                            Capsule()
                                .fill(.black.opacity(0.72))
                                .frame(width: 62, height: 44)
                                .matchedGeometryEffect(id: "selected", in: pill)
                        }
                        Image(systemName: item.icon)
                            .symbolVariant(item == tab ? .fill : .none)
                            .font(.system(size: 21, weight: item == tab ? .semibold : .regular))
                            .foregroundStyle(item == tab ? OctoColor.accent : .white)
                            .contentTransition(.symbolEffect(.replace.offUp))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(item == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
    }

    /// The tabs, folded into one circle that shows the tab in use.
    private var foldedTabs: some View {
        Button {
            playerMode = false
        } label: {
            Image(systemName: tab.icon)
                .symbolVariant(.fill)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: Self.height, height: Self.height)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show tabs")
    }
}

/// The round now-playing button: the cover in a circle under a light shade, play or pause on
/// top, and the song's progress as a ring.
struct NowPlayingFace: View {
    let tap: () -> Void
    @Environment(Player.self) private var player

    var body: some View {
        Button(action: tap) {
            ZStack {
                Cover(id: player.current?.coverArt, size: 44, radius: 22)
                    .overlay(Circle().fill(.black.opacity(0.35)))
                    .opacity(player.current == nil ? 0 : 1)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
                ProgressRing(progress: player.progress, lineWidth: 2)
                    .padding(3)
            }
            .frame(width: OctoBar.height, height: OctoBar.height)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .swipeToSkip(open: tap)
        .accessibilityLabel("Now playing")
    }
}

/// The mini player in the bar: the cover with its progress ring, the song, and previous, play
/// and next. Tap opens the player; swipe left or right skips; swipe up opens the player.
struct MiniPlayerPill: View {
    let open: () -> Void
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Cover(id: player.current?.coverArt, size: 36, radius: 18)
                ProgressRing(progress: player.progress, lineWidth: 2)
                    .padding(1)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(player.current?.title ?? "")
                        .font(.system(size: 13.5, weight: .semibold))
                        .lineLimit(1)
                    if player.current?.explicitStatus == "explicit" { ExplicitMark(size: 12) }
                }
                Text(player.current?.byline ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            transport("backward.fill", "Previous", action: player.previous)
            transport(player.isPlaying ? "pause.fill" : "play.fill", player.isPlaying ? "Pause" : "Play", action: player.toggle)
            transport("forward.fill", "Next", action: player.next)
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .contentShape(Capsule())
        .onTapGesture(perform: open)
        .swipeToSkip(open: open)
        .accessibilityAction(named: "Open player", open)
    }

    private func transport(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .frame(width: 36, height: 36)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The song's progress as an accent ring that starts at twelve o'clock.
struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat

    var body: some View {
        Circle()
            .trim(from: 0, to: max(0, min(progress, 1)))
            .stroke(OctoColor.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.linear(duration: 0.5), value: progress)
    }
}

extension View {
    /// Sideways swipes skip (left for next, right for previous); an upward swipe opens the
    /// player. The content leans with the finger and springs back.
    func swipeToSkip(open: @escaping () -> Void) -> some View {
        modifier(SwipeToSkip(open: open))
    }
}

private struct SwipeToSkip: ViewModifier {
    let open: () -> Void
    @Environment(Player.self) private var player
    @State private var lean: CGSize = .zero
    @State private var crossed = false

    func body(content: Content) -> some View {
        content
            .offset(x: lean.width * 0.3, y: min(0, lean.height) * 0.3)
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { drag in
                        let sideways = abs(drag.translation.width) > abs(drag.translation.height)
                        lean = sideways ? CGSize(width: drag.translation.width, height: 0) : CGSize(width: 0, height: drag.translation.height)
                        let past = sideways ? abs(drag.translation.width) > 56 : drag.translation.height < -28
                        if past != crossed { crossed = past }
                    }
                    .onEnded { drag in
                        let sideways = abs(drag.translation.width) > abs(drag.translation.height)
                        let flingX = drag.predictedEndTranslation.width - drag.translation.width
                        let flingY = drag.predictedEndTranslation.height - drag.translation.height
                        if sideways, drag.translation.width < -56 || flingX < -120 {
                            player.next()
                        } else if sideways, drag.translation.width > 56 || flingX > 120 {
                            player.previous()
                        } else if !sideways, drag.translation.height < -28 || flingY < -120 {
                            open()
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { lean = .zero }
                        crossed = false
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: crossed) { _, now in now }
    }
}

/// The explicit mark: a small rounded square with an E cut out of it.
struct ExplicitMark: View {
    var size: CGFloat = 14

    var body: some View {
        RoundedRectangle(cornerRadius: size * 3 / 14, style: .continuous)
            .fill(OctoColor.textMuted)
            .frame(width: size, height: size)
            .overlay {
                Text("E")
                    .font(.system(size: size * 0.68, weight: .bold))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .accessibilityLabel("Explicit")
    }
}
