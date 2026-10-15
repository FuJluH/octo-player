import OctoKit
import SwiftUI

/// Octo's bar: two pieces of floating Liquid Glass, 10 points apart. The tab tray sits on the
/// left and the round now-playing button on the right. Tapping that button grows it into the
/// small player while the tray folds into a circle at the left: the two swap sizes in one
/// spring that overshoots a little. Tapping the folded circle brings the tabs back.
struct OctoBar: View {
    let tab: AppTab
    let playerMode: Bool
    /// A tab tapped, the one in use or another.
    let select: (AppTab) -> Void
    /// The round button tapped.
    let roundButton: () -> Void
    /// The folded tray tapped.
    let showTabs: () -> Void
    let openPlayer: () -> Void
    /// The glass's film, which can carry a trace of the song's color.
    var film: Color = OctoColor.glazeFilm
    @Environment(Player.self) private var player

    static let height = ShellMeasures.barHeight
    static let gap = ShellMeasures.barGap
    /// How far above the bottom safe area the bar floats.
    static let bottomGap = ShellMeasures.barBottomGap
    /// Room pages leave under their content for the bar.
    static let clearance = ShellMeasures.clearance
    /// The bar's shape change: damping 0.75, stiffness 200. Reduce motion leaves it as it is.
    static let morph = Animation.octoSpring(0.75, 200)

    private var showsPlayer: Bool { playerMode && player.current != nil }

    var body: some View {
        GeometryReader { box in
            BarFrame(grown: showsPlayer ? 1 : 0, pill: Double(tab.index), width: box.size.width, tab: tab,
                     folded: showsPlayer, hasSong: player.current != nil, film: film,
                     select: select, roundButton: roundButton, showTabs: showTabs, openPlayer: openPlayer)
        }
        .frame(height: Self.height)
        .frame(maxWidth: ShellMeasures.maxWidth)
        .padding(.horizontal, ShellMeasures.sideMargin)
        .animation(Self.morph, value: showsPlayer)
        .animation(.octoSpring(0.8, 350), value: tab)
    }
}

/// The bar laid out from `grown` (0 open, 1 the small player shown) and the selected pill's
/// place, both moving on springs. Widths follow `grown` as it overshoots; fades hold it to 0...1.
private struct BarFrame: View, Animatable {
    var grown: Double
    var pill: Double
    let width: CGFloat
    let tab: AppTab
    let folded: Bool
    let hasSong: Bool
    let film: Color
    let select: (AppTab) -> Void
    let roundButton: () -> Void
    let showTabs: () -> Void
    let openPlayer: () -> Void

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(grown, pill) }
        set {
            grown = newValue.first
            pill = newValue.second
        }
    }

    var body: some View {
        let height = ShellMeasures.barHeight
        let full = max(height, width - height - ShellMeasures.barGap)
        let tray = full + (height - full) * grown
        GlassEffectContainer(spacing: ShellMeasures.barGap) {
            ZStack(alignment: .topLeading) {
                TabTray(fullWidth: full, folded: grown, isFolded: folded, pill: pill, tab: tab, select: select)
                    .frame(width: max(0, tray), height: height, alignment: .leading)
                    .clipShape(Capsule())
                    .octoGlass(Capsule(), film: film, interactive: true)
                    .background { BarShadow() }
                    .overlay {
                        if folded {
                            Color.clear
                                .contentShape(Capsule())
                                .onTapGesture(perform: showTabs)
                                .accessibilityElement()
                                .accessibilityLabel("Show tabs")
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { showTabs() }
                        }
                    }
                NowPlayingGlass(fullWidth: full, grown: grown, shown: folded, hasSong: hasSong,
                                roundButton: roundButton, openPlayer: openPlayer)
                    .frame(width: max(0, width - tray - ShellMeasures.barGap), height: height, alignment: .trailing)
                    .clipShape(Capsule())
                    .octoGlass(Capsule(), film: film, interactive: true)
                    .background { BarShadow() }
                    .offset(x: tray + ShellMeasures.barGap)
            }
            .frame(width: width, height: height, alignment: .topLeading)
        }
    }
}

/// The shadow pooled under a piece of the bar, cast by the shape 12 points smaller all round.
private struct BarShadow: View {
    var body: some View {
        Capsule()
            .inset(by: 12)
            .fill(Color.black.opacity(0.45))
            .blur(radius: shadowRadius(24))
            .offset(y: 8)
            .mask {
                Rectangle().padding(-48).overlay { Capsule().fill(Color.black).blendMode(.destinationOut) }.compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

/// The tabs in their glass, the selected one in a darker pill that glides between them.
/// Folding, the tabs slide under the shrinking edge and fade, while the pill slides left and
/// swells into the whole circle carrying the selected tab's icon, which turns from the accent to
/// white.
private struct TabTray: View {
    let fullWidth: CGFloat
    let folded: Double
    let isFolded: Bool
    let pill: Double
    let tab: AppTab
    let select: (AppTab) -> Void

    @State private var updates = ServerUpdates.shared

    private static let iconSize: CGFloat = 23
    private static let pillWidth: CGFloat = 62

    var body: some View {
        let height = ShellMeasures.barHeight
        let fold = min(1, max(0, folded))
        let column = (fullWidth - 12) / CGFloat(AppTab.allCases.count)
        let capsuleX = 6 + column * CGFloat(pill) + (column - Self.pillWidth) / 2
        let pillX = capsuleX + (0 - capsuleX) * CGFloat(folded)
        let pillW = Self.pillWidth + (height - Self.pillWidth) * CGFloat(folded)
        let pillH = 44 + (height - 44) * CGFloat(folded)
        ZStack(alignment: .leading) {
            if folded < 1 {
                GlazeSelected(shape: Capsule())
                    .frame(width: pillW, height: pillH)
                    .opacity(1 - fold)
                    .offset(x: pillX)
                HStack(spacing: 0) {
                    ForEach(AppTab.allCases, id: \.self) { item in
                        TabButton(item: item, selected: item == tab, showIcon: folded <= 0 || item != tab,
                                  marked: item == .settings && item != tab && updates.showsDot) {
                            select(item)
                        }
                        .frame(width: column, height: height)
                        .disabled(isFolded)
                    }
                }
                .padding(.horizontal, 6)
                .frame(width: fullWidth, height: height, alignment: .leading)
                .opacity(1 - fold)
            }
            if folded > 0 {
                IconView(tab.selectedIcon, size: Self.iconSize,
                         color: OctoColor.accent.mix(with: .white, by: fold))
                    .offset(x: pillX + (pillW - Self.iconSize) / 2)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: fullWidth, height: height, alignment: .leading)
    }
}

/// One tab: its icon only, white, or filled in the accent while selected. The whole column
/// answers the finger, with no highlight.
private struct TabButton: View {
    let item: AppTab
    let selected: Bool
    let showIcon: Bool
    /// Something waits on the tab: a small dot on the icon's corner.
    var marked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(selected ? item.selectedIcon : item.icon, size: 23, color: selected ? OctoColor.accent : .white)
                // The outline and filled symbols swap at once; only the color moves. The system's
                // own symbol replace would shrink the icon out of sight and back.
                .contentTransition(.identity)
                .overlay(alignment: .topTrailing) {
                    if marked {
                        Circle().fill(OctoColor.accent).frame(width: 7, height: 7).offset(x: 3, y: -2)
                    }
                }
                .opacity(showIcon ? 1 : 0)
                .animation(.octo(OctoSprings.state), value: selected)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoHighlight())
        .accessibilityLabel(marked ? "\(item.title), \(ServerUpdateWords.mark)" : item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A press that shows nothing.
struct NoHighlight: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

/// The right-hand glass: the round now-playing button, or the small player grown from it. Its
/// contents lean with a swipe; sideways skips, up opens the player. With no song, no swipes.
private struct NowPlayingGlass: View {
    let fullWidth: CGFloat
    let grown: Double
    let shown: Bool
    let hasSong: Bool
    let roundButton: () -> Void
    let openPlayer: () -> Void

    var body: some View {
        let fade = min(1, max(0, grown))
        ZStack(alignment: .leading) {
            if grown < 1 {
                NowPlayingFace(tap: roundButton)
                    .frame(width: ShellMeasures.barHeight, height: ShellMeasures.barHeight)
                    .opacity(1 - fade)
                    .allowsHitTesting(!shown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if grown > 0 {
                MiniPlayerPill(open: openPlayer)
                    .frame(width: fullWidth, height: ShellMeasures.barHeight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(Capsule())
                    .opacity(fade)
                    .allowsHitTesting(shown)
            }
        }
        .barSwipes(enabled: hasSong, openPlayer: openPlayer)
    }
}

extension AppTab {
    var index: Int { AppTab.allCases.firstIndex(of: self) ?? 0 }

    var icon: OctoIcon {
        switch self {
        case .home: .home
        case .search: .search
        case .library: .library
        case .settings: .settings
        }
    }

    var selectedIcon: OctoIcon {
        switch self {
        case .home: .homeSelected
        case .search: .searchSelected
        case .library: .librarySelected
        case .settings: .settingsSelected
        }
    }
}

extension View {
    /// The bar's swipes: sideways skips (left to the next song, right to the one before), and up
    /// opens the player. The axis is taken once, at the first clear movement; then the drag is
    /// the swipe's, and the tap under it does not fire. The contents lean with the finger and
    /// spring back; one tick as the finger passes the point where letting go acts.
    func barSwipes(enabled: Bool, openPlayer: @escaping () -> Void) -> some View {
        modifier(BarSwipes(enabled: enabled, openPlayer: openPlayer))
    }
}

private struct BarSwipes: ViewModifier {
    let enabled: Bool
    let openPlayer: () -> Void
    @Environment(Player.self) private var player
    @State private var axis: DragAxis = .undecided
    @State private var lean: CGSize = .zero
    @State private var armed = false
    @State private var ticks = 0
    @GestureState private var dragging = false

    func body(content: Content) -> some View {
        content
            .offset(x: lean.width * BarSwipe.lean, y: lean.height * BarSwipe.lean)
            .contentShape(Capsule())
            .highPriorityGesture(swipe, including: enabled ? .all : .subviews)
            .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: ticks)
            .onChange(of: dragging) { _, now in
                // A drag taken over by something else ends as if it went nowhere.
                guard !now, axis != .undecided else { return }
                axis = .undecided
                armed = false
                withAnimation(.octoSpring(0.8, 400)) { lean = .zero }
            }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: BarSwipe.slop)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { drag in
                if axis == .undecided {
                    axis = dragAxis(drag.translation.width, drag.translation.height, slop: BarSwipe.slop)
                }
                switch axis {
                case .horizontal:
                    lean = CGSize(width: drag.translation.width, height: 0)
                    mark(abs(drag.translation.width) >= BarSwipe.skipAt)
                case .vertical:
                    lean = CGSize(width: 0, height: min(0, drag.translation.height))
                    mark(drag.translation.height <= -BarSwipe.openAt)
                case .undecided:
                    break
                }
            }
            .onEnded { drag in
                let taken = axis
                axis = .undecided
                armed = false
                switch taken {
                case .horizontal:
                    switch swipeSkip(offset: drag.translation.width, velocity: drag.velocity.width,
                                     distance: BarSwipe.skipAt, fling: BarSwipe.fling) {
                    case .next: player.next()
                    case .previous: player.previous()
                    case .stay: break
                    }
                    withAnimation(.octoSpring(0.8, 400)) { lean = .zero }
                case .vertical:
                    if swipeUp(offset: drag.translation.height, velocity: drag.velocity.height,
                               distance: BarSwipe.openAt, fling: BarSwipe.fling) {
                        lean = .zero
                        openPlayer()
                    } else {
                        withAnimation(.octoSpring(0.8, 400)) { lean = .zero }
                    }
                case .undecided:
                    withAnimation(.octoSpring(0.8, 400)) { lean = .zero }
                }
            }
    }

    /// A tick when the finger first passes the point where letting go acts.
    private func mark(_ past: Bool) {
        guard past != armed else { return }
        armed = past
        if past { ticks += 1 }
    }
}

/// The round now-playing button: the song's artwork in a circle with a thin ring round it showing
/// how far through the song it is (the whole ring for a station), which breathes while paused.
/// A tap opens the small player, which has play and pause. With nothing loaded it shows the play
/// sign, since the button then shuffles the library.
struct NowPlayingFace: View {
    let tap: () -> Void
    @Environment(Player.self) private var player
    /// Where the sound goes when it is not the phone itself: AirPlay, for one.
    @State private var route = AudioRoute()

    var body: some View {
        let song = player.current
        Button(action: tap) {
            ZStack {
                if let live = player.live {
                    LiveCover(live, coverArt: song?.coverArt, size: OctoBar.height - 12, radius: (OctoBar.height - 12) / 2)
                } else if let song {
                    Cover(id: song.coverArt, size: OctoBar.height - 12, radius: (OctoBar.height - 12) / 2, online: song.isExternal)
                }
                if song == nil {
                    IconView(.play, size: 22, color: .white)
                } else {
                    ProgressRing().padding(3)
                }
            }
            .frame(width: OctoBar.height, height: OctoBar.height)
            .overlay(alignment: .bottomTrailing) {
                // Playing on another device: its mark in the corner.
                if route.elsewhere != nil {
                    IconView(.castConnected, size: 11, color: .white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.black.opacity(0.72)))
                        .padding(2)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(NoHighlight())
        .accessibilityLabel(nowPlayingWords(title: song?.title, artist: song?.byline, loaded: song != nil))
        .accessibilityValue(nowPlayingState(loaded: song != nil, paused: !player.liveOn, live: player.live != nil))
    }
}

/// The mini player in the bar: the cover with its progress ring, the song, and previous, play
/// and next. A tap anywhere else opens the player, and the cover flies up into it.
struct MiniPlayerPill: View {
    let open: () -> Void
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(\.displayScale) private var scale
    @State private var flight = CoverFlight.shared

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                Group {
                    if let live = player.live {
                        LiveCover(live, coverArt: player.current?.coverArt, size: 36, radius: 18)
                    } else {
                        BadgedCover(id: player.current?.coverArt, size: 36, radius: 18, external: player.current?.isExternal ?? false)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { flight.barFrame = $0 }
                .opacity(flight.hidesBar ? 0 : 1)
                .onDisappear { flight.barFrame = nil }
                if player.current != nil {
                    ProgressRing().padding(1)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 0) {
                SongTitleLine(player.current?.title ?? "", explicit: player.current?.isExplicit ?? false, font: .octoLabel,
                              color: .white)
                Text(player.current?.byline ?? "")
                    .font(.octo(11, .regular, .caption1))
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let lineup = player.lineup {
                // A live station: Back and Next change station, and Play and Stop rejoin and
                // leave what is on air.
                if lineup.shows {
                    transport(.previous, "Previous station", action: player.previous).disabled(!lineup.hasPrevious)
                }
                transport(player.liveOn ? .stop : .play, player.liveOn ? "Stop" : "Play", action: player.toggle)
                if lineup.shows {
                    transport(.next, "Next station", action: player.next).disabled(!lineup.hasNext)
                }
            } else {
                transport(.previous, "Previous", action: player.previous)
                transport(player.isPlaying ? .pause : .play, player.isPlaying ? "Pause" : "Play", action: player.toggle)
                transport(.next, "Next", action: player.next)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .contentShape(Capsule())
        .onTapGesture(perform: open)
        .task(id: flightKey(player.current)) {
            // The player's card is at most the phone's width less its margins, under 430 points;
            // the flight draws the cover at that size.
            if let live = player.live {
                await flight.prepare(live: live, coverArt: player.current?.coverArt, size: Int(430 * scale), client: session.client)
            } else {
                await flight.prepare(player.current?.coverArt, size: Int(430 * scale), client: session.client)
            }
        }
        .accessibilityAction(named: "Open player", open)
    }

    private func transport(_ icon: OctoIcon, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TransportIcon(icon: icon)
        }
        .buttonStyle(NoHighlight())
        .accessibilityLabel(label)
    }
}

/// The song's progress as an accent ring that starts at twelve o'clock, the whole circle for a
/// station. Playing, it holds steady and steps once a second, on the clock's whole seconds, so
/// every small ring on screen moves in the same frame; a seek or a new song moves it at once.
/// Paused, a faint track shows the full circle and the arc breathes for a minute, about twelve
/// times a second, then settles into a still dimmed look; with motion reduced it holds that look
/// at once. Nothing ticks while the app is out of sight. `scrub` shows a place being dragged to
/// instead. With `speaks`, a screen reader hears the song (`speaks`) and how much has played.
struct ProgressRing: View {
    var scrub: Double?
    var speaks: String?
    @Environment(Player.self) private var player
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.scenePhase) private var phase
    @State private var pausedAt = Date()
    @State private var settled = false
    @State private var motion = PlayerMotion.shared
    /// The whole second the playing ring steps from.
    @State private var wholeSeconds = wholeSecondAtOrBefore(.now)

    var body: some View {
        let live = player.live != nil
        let paused = player.current != nil && !player.liveOn
        let away = phase != .active
        // A seek, a new song, play or pause: drawn again at once.
        let _ = player.timeEvents
        ZStack {
            if let scrub {
                ring(sweep: scrub, arc: .of(paused: false, breath: nil), track: false)
            } else if paused {
                let still = calm || settled || away
                TimelineView(.animation(minimumInterval: pacedInterval(RingLook.breathFrameSeconds, moving: motion.moving), paused: still)) { time in
                    let breath = still ? nil : pauseBreath(max(0, time.date.timeIntervalSince(pausedAt)))
                    ring(sweep: sweep(live: live), arc: .of(paused: true, breath: breath), track: true)
                }
            } else if live || away {
                ring(sweep: sweep(live: live), arc: .of(paused: false, breath: nil), track: false)
            } else {
                TimelineView(.periodic(from: wholeSeconds, by: RingLook.stepSeconds)) { _ in
                    ring(sweep: sweep(live: false), arc: .of(paused: false, breath: nil), track: false)
                }
            }
        }
        .task(id: BreathKey(paused: paused, active: !away)) {
            // Each pause breathes from its start, for a minute; coming back to the app starts it
            // over.
            settled = false
            guard paused, !away else { return }
            pausedAt = Date()
            try? await Task.sleep(for: .seconds(breathSettleSeconds()))
            if !Task.isCancelled { settled = true }
        }
    }

    private func sweep(live: Bool) -> Double {
        ringSweep(position: player.livePosition, length: max(player.duration, player.livePosition), live: live)
    }

    @ViewBuilder
    private func ring(sweep: Double, arc: RingArc, track: Bool) -> some View {
        let accent = OctoColor.accent
        let drawn = ZStack {
            if track {
                Circle().stroke(accent.opacity(RingLook.pausedTrackAlpha), lineWidth: RingLook.thinWidth)
            }
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(accent.opacity(arc.alpha), style: StrokeStyle(lineWidth: arc.width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        if let speaks {
            drawn
                .accessibilityElement()
                .accessibilityLabel(speaks)
                .accessibilityValue(playedWords(playedSeconds: Int(player.livePosition), lengthSeconds: Int(player.duration),
                                                live: player.live != nil))
        } else {
            drawn.accessibilityHidden(true)
        }
    }

    private struct BreathKey: Equatable {
        let paused: Bool
        let active: Bool
    }
}

extension View {
    /// Kept for callers inside the bar; the bar's glass takes the swipes (see `barSwipes`).
    func swipeToSkip(open: @escaping () -> Void) -> some View { self }
}

/// The small E after the title of a song marked explicit: a muted tile with the letter cut out
/// of it, so whatever is behind shows through. As tall as a line of small text, so it grows with
/// the text size. Screen readers hear "Explicit".
struct ExplicitMark: View {
    var size: CGFloat = 14
    var color: Color = OctoColor.textMuted
    @ScaledMetric(relativeTo: .caption) private var grow: CGFloat = 1

    var body: some View {
        let side = size * grow
        RoundedRectangle(cornerRadius: side * 3 / 14, style: .continuous)
            .fill(color)
            .frame(width: side, height: side)
            .overlay {
                Text("E")
                    .font(.system(size: side * 9.5 / 14, weight: .bold))
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .accessibilityElement()
            .accessibilityLabel("Explicit")
    }
}

/// A mini player button's icon, dimmed while the button cannot be used.
private struct TransportIcon: View {
    let icon: OctoIcon
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        IconView(icon, size: 28, color: .white.opacity(enabled ? 1 : 0.35))
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }
}
