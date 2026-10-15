import AVFoundation
import AVKit
import MediaPlayer
import Observation
import OctoKit
import SwiftUI
import UIKit

// MARK: Top line

/// The device the phone's sound goes to when it is not the phone itself or something worn.
@MainActor
@Observable
final class AudioRoute {
    private(set) var elsewhere: String?
    @ObservationIgnored private var watch: NSObjectProtocol?

    init() {
        read()
        watch = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.read() }
        }
    }

    private func read() {
        let away: Set<AVAudioSession.Port> = [.airPlay, .HDMI, .carAudio]
        elsewhere = AVAudioSession.sharedInstance().currentRoute.outputs.first { away.contains($0.portType) }?.portName
    }
}

/// The system's AirPlay and Bluetooth picker.
struct RoutePicker: UIViewRepresentable {
    var tint: UIColor = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = tint
        view.prioritizesVideoDevices = false
        view.delegate = RouteChoice.shared
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = tint
    }
}

// MARK: Title

/// A single line too long for its room. It fades out softly at its right edge; with `scroll` it
/// also scrolls through three times, waiting 1.2 s before each pass, at 30 points a second, with a
/// third of the room between the end and the start again, fading softly at its left edge only
/// while it moves, so at rest its first letter sits crisp. The fades are eased masks over 28
/// points on the line's own room. Once the passes are done, or for a line that fits, nothing
/// ticks; a new line starts it over.
struct PlayerMarquee: View {
    let text: String
    let font: Font
    let color: Color
    var scroll = true
    @State private var textWidth: CGFloat = 0
    @State private var room: CGFloat = 0
    @State private var started = Date()
    @State private var resting = false

    var body: some View {
        let overflow = textWidth > room + 0.5 && room > 0
        let gap = room * Marquee.spacing
        let distance = textWidth + gap
        let moving = overflow && scroll && !resting
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) {
                TimelineView(.animation(paused: !moving)) { time in
                    let at: (offset: Double, leftFade: Double) =
                        moving ? Marquee.at(time.date.timeIntervalSince(started), distance: Double(distance)) : (0, 0)
                    HStack(spacing: gap) {
                        line
                        if moving { line }
                    }
                    .offset(x: -CGFloat(at.offset))
                    .frame(width: max(room, 1), alignment: .leading)
                    .clipped()
                    .mask { if overflow { MarqueeFades(left: at.leftFade) } else { Rectangle() } }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
            .background {
                line.fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .task(id: MarqueeRun(text: text, distance: distance, scrolls: overflow && scroll)) {
                started = Date()
                resting = false
                guard overflow && scroll else { return }
                try? await Task.sleep(for: .seconds(Marquee.duration(distance: Double(distance))))
                if !Task.isCancelled { resting = true }
            }
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    private var line: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }

    private struct MarqueeRun: Equatable {
        let text: String
        let distance: CGFloat
        let scrolls: Bool
    }
}

/// The marquee's masks: the right edge always faded out over the fade's length, eased, and the
/// left edge as much as `left` (0 to 1) of the same.
private struct MarqueeFades: View {
    let left: Double

    var body: some View {
        GeometryReader { box in
            let fade = min(CGFloat(Marquee.fade), box.size.width / 2)
            HStack(spacing: 0) {
                LinearGradient(stops: Marquee.easedOut.reversed().map { stop in
                    Gradient.Stop(color: .black.opacity(1 - left * (1 - stop.alpha)), location: 1 - stop.at)
                }, startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
                Rectangle()
                LinearGradient(stops: Marquee.easedOut.map { Gradient.Stop(color: .black.opacity($0.alpha), location: $0.at) },
                               startPoint: .leading, endPoint: .trailing)
                .frame(width: fade)
            }
        }
    }
}

/// The full player's buttons beside the song's name, measured from the name's font: their icons
/// stand about 1.15 times as tall as its capitals, at the weight of the switches under the
/// controls, and sit on the middle of those capitals.
struct TitleIcons: Equatable, Sendable {
    /// The name's font, as `Font.octo(24, .bold, .title1)` draws it: its size, how far its
    /// baseline sits below the top of its line, and its capitals' height.
    let fontSize: CGFloat
    let ascender: CGFloat
    let capHeight: CGFloat
    /// The symbols' point size.
    let pointSize: CGFloat
    /// Half of what the heart and the dots cover across.
    let heartHalf: CGFloat
    let dotsHalf: CGFloat
    /// How strongly the icons show while not lit.
    var alpha: Double = Double(PlayerTitleRow.iconAlpha)

    /// Down from the top of the name's line to the middle of its capitals.
    var capMiddleFromTop: CGFloat { CGFloat(capMiddle(baseline: Double(ascender), capHeight: Double(capHeight))) }

    /// How far the buttons reach into the row's side margin so the gaps read even.
    func reach(sideMargin: CGFloat) -> CGFloat {
        CGFloat(titleButtonsReach(sideMargin: Double(sideMargin), heartHalf: Double(heartHalf), dotsHalf: Double(dotsHalf)))
    }

    /// For the phone's text size now.
    @MainActor static func current() -> TitleIcons {
        let font = UIFontMetrics(forTextStyle: .title1).scaledFont(for: .systemFont(ofSize: 24, weight: .bold))
        if let known = cache, known.fontSize == font.pointSize { return known }
        let target = font.capHeight * CGFloat(PlayerTitleRow.heightOverCap)
        func size(_ symbol: String, _ point: CGFloat) -> CGSize {
            UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: point, weight: .regular))?.size
                ?? CGSize(width: point, height: point)
        }
        let probe = size(OctoIcon.like.symbol, 100)
        let point = probe.height > 0 ? 100 * target / probe.height : target
        let icons = TitleIcons(fontSize: font.pointSize, ascender: font.ascender, capHeight: font.capHeight, pointSize: point,
                               heartHalf: size(OctoIcon.like.symbol, point).width / 2,
                               dotsHalf: size(OctoIcon.more.symbol, point).width / 2)
        cache = icons
        return icons
    }

    @MainActor private static var cache: TitleIcons?
}

extension EnvironmentValues {
    /// Set inside the full player's title row: the icons' measures and how quiet they are.
    @Entry var titleIcons: TitleIcons? = nil
}

/// One of the title row's icons, an SF Symbol at the row's measures in a 44 point target.
struct TitleGlyph: View {
    let icon: OctoIcon
    let color: Color
    @Environment(\.titleIcons) private var icons

    var body: some View {
        Image(systemName: icon.symbol)
            .font(.system(size: icons?.pointSize ?? 19, weight: .regular))
            .foregroundStyle(color)
            .frame(width: PlayerTitleRow.buttonSize, height: PlayerTitleRow.buttonSize)
            .accessibilityHidden(true)
    }
}

extension VerticalAlignment {
    private enum PlayerTitleLine: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
    }

    /// The middle of the player's title line, for what sits level with the title rather than with
    /// the title and the line under it.
    static let playerTitleLine = VerticalAlignment(PlayerTitleLine.self)
}

/// The song's name (24 bold, scrolling when long unless motion is reduced, the explicit mark kept
/// still after it) and its artist, who opens their page, the two close together so they read as
/// one. Either line too long fades out at its end. The buttons beside it sit on the middle of the
/// name's capitals, taken from the name's font, so they hold their place whatever the name is
/// doing.
struct PlayerTitleBlock: View {
    let song: Song
    let ink: Color
    let accent: Color
    let openArtist: (() -> Void)?
    @Environment(\.octoReduceMotion) private var calm
    @Environment(\.titleIcons) private var icons

    var body: some View {
        let capMiddle = icons?.capMiddleFromTop
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                PlayerMarquee(text: song.title, font: .octo(24, .bold, .title1), color: ink, scroll: !calm)
                if song.isExplicit {
                    ExplicitMark(size: 14, color: accent).fixedSize()
                }
            }
            .alignmentGuide(.playerTitleLine) { d in capMiddle ?? d[VerticalAlignment.center] }
            // Only the name itself opens the artist.
            Group {
                if let openArtist {
                    Button(action: openArtist) { artist }
                        .buttonStyle(NoPress())
                } else {
                    artist
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, -CGFloat(PlayerTitleRow.artistRaise))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artist: some View {
        PlayerMarquee(text: song.byline, font: .octoBody, color: accent, scroll: false)
    }
}

/// The heart for a library song: filled, full and glowing while liked; an outline a step quieter
/// than the name otherwise. Liking it gives a small beat.
struct PlayerHeart: View {
    let liked: Bool
    let ink: Color
    let toggle: () -> Void
    @Environment(\.titleIcons) private var icons
    @State private var beats = 0

    var body: some View {
        Button {
            if !liked { beats += 1 }
            toggle()
        } label: {
            TitleGlyph(icon: liked ? .liked : .like, color: liked ? ink : ink.opacity(icons?.alpha ?? 0.7))
                .iconGlow(liked, color: ink)
                .iconAccent(.pulse, trigger: beats)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoPress())
        .accessibilityLabel("Like")
        .accessibilityValue(liked ? "In Liked songs" : "Not in Liked songs")
    }
}

// MARK: Progress

/// The song's place: a glowing line that seeks where it is tapped or where a drag ends, the time
/// gone and the time left under it, and between them the quality badge and, when the speed is
/// not 1x, the speed, which opens the speed card in a popover. While the song plays the line is
/// read each time it moves on by half a pixel (every frame for a short song) and the times once
/// a second; paused, nothing ticks, and a seek redraws them at once.
struct PlayerProgress: View {
    let ink: Color
    let muted: Color
    let song: Song
    @Binding var speedOpen: Bool
    @Environment(Player.self) private var player
    @Environment(\.displayScale) private var scale
    @State private var settings = AppSettings.shared
    @State private var lineWidth: CGFloat = 0
    @State private var motion = PlayerMotion.shared
    /// The whole second the times step from.
    @State private var wholeSeconds = wholeSecondAtOrBefore(.now)

    var body: some View {
        let _ = player.timeEvents
        let step = progressStepSeconds(player.duration / Double(max(player.speed, 0.1)), lengthPixels: Double(lineWidth * scale))
        // Every frame while the player opens, is pulled or closes; each half pixel at rest.
        let interval = pacedInterval(step > 0 ? step : nil, moving: motion.moving)
        VStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: interval, paused: !player.isPlaying)) { _ in
                let length = player.duration
                OctoSlider(value: length > 0 ? min(max(player.livePosition / length, 0), 1) : 0, onChange: { fraction in
                    player.seek(to: fraction * player.duration)
                }, color: ink, trackColor: ink.opacity(0.24))
                .accessibilityHidden(true)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { lineWidth = $0 }
            ZStack {
                // An unknown length shows 0:00 both sides.
                Group {
                    if player.isPlaying {
                        TimelineView(.periodic(from: wholeSeconds, by: 1)) { _ in times }
                    } else {
                        times
                    }
                }
                HStack(spacing: 8) {
                    QualityBadge(song: song, ink: ink)
                    let speed = settings.player.speed
                    if speed != 1 {
                        Button { speedOpen = true } label: {
                            Text(Pace.speedLabel(speed))
                                .font(.octo(10.5, .semibold, .caption2).monospacedDigit())
                                .foregroundStyle(ink)
                                .lineLimit(1)
                                .padding(4)
                        }
                        .buttonStyle(NoPress())
                        .accessibilityLabel("Playback speed \(Pace.speedLabel(speed))")
                    }
                }
                .glassPopover(isPresented: $speedOpen) {
                    TimeCard(start: .speed) { speedOpen = false }
                }
            }
            .padding(.top, -8)
        }
    }

    /// The time gone and the time left.
    private var times: some View {
        let length = max(player.duration, 0)
        let gone = Int(min(max(player.livePosition, 0), length))
        let left = max(Int(length) - gone, 0)
        return HStack {
            Text(asClock(gone))
            Spacer()
            Text("-" + asClock(left))
        }
        .font(.octoCaption.monospacedDigit())
        .foregroundStyle(muted)
    }
}

/// How the song is encoded, on clear glass once it is known. A tap spells it out for 4 s, or
/// until tapped again; a new song starts it closed.
struct QualityBadge: View {
    let song: Song
    let ink: Color
    @Environment(Player.self) private var player
    @State private var open = false
    @State private var closing: Task<Void, Never>?

    var body: some View {
        Group {
            if let quality = player.quality {
                Button(action: toggle) {
                    HStack(spacing: 5) {
                        if quality.lossless { IconView(.lossless, size: 13, color: ink) }
                        Text(open ? quality.full : quality.label.uppercased())
                            .font(open ? .octo(11, .regular, .caption2) : .octo(10.5, .semibold, .caption2))
                            .tracking(open ? 0 : 1)
                            .foregroundStyle(ink)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .contentShape(Capsule())
                }
                .buttonStyle(NoPress())
                .octoGlass(Capsule(), film: .clear)
                .animation(.octoSpring(0.8, 400), value: open)
                .accessibilityLabel("\(quality.label), \(quality.full)")
            }
        }
        .task(id: song.id) {
            open = false
            closing?.cancel()
        }
    }

    private func toggle() {
        closing?.cancel()
        open.toggle()
        guard open else { return }
        closing = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { open = false }
        }
    }
}

// MARK: Transport

/// Previous, play or pause, and next, spread across the row.
struct PlayerTransport: View {
    let ink: Color
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            TransportButton(nudge: -8, label: "Previous", action: player.previous) {
                IconView(.previous, size: 44, color: ink)
            }
            Spacer(minLength: 0)
            TransportButton(nudge: 0, label: player.isPlaying ? "Pause" : "Play", action: player.toggle) {
                ZStack {
                    if player.isPlaying {
                        IconView(.pause, size: 56, color: ink).transition(PlayPop.transition)
                    } else {
                        IconView(.play, size: 56, color: ink).transition(PlayPop.transition)
                    }
                }
                .animation(.octoTween(fixed: 150), value: player.isPlaying)
            }
            Spacer(minLength: 0)
            TransportButton(nudge: 8, label: "Next", action: player.next) {
                IconView(.next, size: 44, color: ink)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The play and pause swap: the new one grows in from 0.6 over 150 ms, the old one shrinks away
/// over 100 ms.
enum PlayPop {
    static var transition: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity).animation(.octoTween(fixed: 150)),
                    removal: .scale(scale: 0.6).combined(with: .opacity).animation(.octoTween(fixed: 100)))
    }
}

/// One transport control in a 72 point box: it shrinks while held and springs back; previous and
/// next nudge the way they go on every tap.
struct TransportButton<Icon: View>: View {
    let nudge: CGFloat
    let label: String
    let action: () -> Void
    @ViewBuilder var icon: Icon
    @State private var shift: CGFloat = 0
    @Environment(\.motionScale) private var motion

    var body: some View {
        Button {
            action()
            guard nudge != 0 else { return }
            withAnimation(.octoTween(fixed: 90)) { shift = CGFloat(motion.travel(Double(nudge))) }
            Task {
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.octoSpring(0.5, 400)) { shift = 0 }
            }
        } label: {
            icon
                .offset(x: shift)
                .frame(width: 72, height: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(TransportPress())
        .accessibilityLabel(label)
    }
}

private struct TransportPress: ButtonStyle {
    @Environment(\.motionScale) private var motion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? motion.scale(0.82) : 1)
            .animation(.octoSpring(0.45, 600), value: configuration.isPressed)
    }
}

// MARK: Volume

/// The phone's volume as a line between two speakers. Every step of a drag sets it at once; the
/// hardware buttons and other apps move it too. A hidden system volume view sets it, so no
/// system volume panel shows.
struct PlayerVolume: View {
    let ink: Color
    let muted: Color
    @State private var volume = SystemVolume()

    var body: some View {
        HStack(spacing: 0) {
            IconView(.volumeDown, size: 20, color: muted)
            OctoSlider(value: Double(volume.level), onChange: { volume.set(Float($0)) }, live: true,
                       color: ink.opacity(0.85), trackColor: ink.opacity(0.24))
                .padding(.horizontal, 10)
                .accessibilityLabel("Volume")
            IconView(.volumeUp, size: 20, color: muted)
        }
        .background(HiddenVolumeView(volume: volume).frame(width: 1, height: 1).opacity(0.01))
    }
}

@MainActor
@Observable
final class SystemVolume {
    private(set) var level: Float = AVAudioSession.sharedInstance().outputVolume
    @ObservationIgnored weak var slider: UISlider?
    @ObservationIgnored private var watch: NSKeyValueObservation?

    init() {
        watch = Self.watch { [weak self] level in Task { @MainActor in self?.level = level } }
    }

    nonisolated private static func watch(_ changed: @escaping @Sendable (Float) -> Void) -> NSKeyValueObservation {
        AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
            if let value = change.newValue { changed(value) }
        }
    }

    func set(_ value: Float) {
        level = value
        slider?.setValue(value, animated: false)
        slider?.sendActions(for: .valueChanged)
    }
}

private struct HiddenVolumeView: UIViewRepresentable {
    let volume: SystemVolume

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        volume.slider = view.subviews.compactMap { $0 as? UISlider }.first
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        if volume.slider == nil { volume.slider = view.subviews.compactMap { $0 as? UISlider }.first }
    }
}

// MARK: Switches

/// One of the row of switches: full and glowing while on, at 45% while off.
struct PlayerSwitch: View {
    let icon: OctoIcon
    let label: String
    let lit: Bool
    let ink: Color
    var state: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 22, color: lit ? ink : ink.opacity(0.45))
                .iconGlow(lit, color: ink)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(NoPress())
        .accessibilityLabel(label)
        .accessibilityValue(state ?? (lit ? "On" : "Off"))
    }
}

/// The minutes left on a countdown, in a small accent pill on the sleep button's corner.
struct SleepBadge: View {
    let minutes: Int

    var body: some View {
        Text("\(minutes)")
            .font(.octo(10, .semibold, .caption2).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(OctoColor.accentFill))
            .octoGlass(Capsule(), film: .clear)
            .accessibilityHidden(true)
    }
}
