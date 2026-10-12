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
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
        view.activeTintColor = tint
    }
}

// MARK: Title

/// A line too long for its room scrolls sideways three times, waiting 1.2 s before each run, at
/// 30 points a second, with a third of the room between the end and the start again.
struct PlayerMarquee: View {
    let text: String
    let font: Font
    let color: Color
    @State private var textWidth: CGFloat = 0
    @State private var room: CGFloat = 0
    @State private var started = Date()

    private static let runs = 3
    private static let pause = 1.2
    private static let speed: CGFloat = 30

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .overlay(alignment: .leading) {
                let gap = room / 3
                let distance = textWidth + gap
                let moving = textWidth > room + 0.5 && room > 0
                TimelineView(.animation(paused: !moving)) { time in
                    let x = moving ? offset(time.date, distance) : 0
                    HStack(spacing: gap) {
                        line
                        if moving { line }
                    }
                    .offset(x: x)
                    .frame(width: max(room, 1), alignment: .leading)
                }
                .clipped()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { room = $0 }
            .background {
                line.fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .onChange(of: text) { _, _ in started = Date() }
            .accessibilityElement()
            .accessibilityLabel(text)
    }

    private var line: some View {
        Text(text).font(font).foregroundStyle(color).lineLimit(1).fixedSize()
    }

    private func offset(_ now: Date, _ distance: CGFloat) -> CGFloat {
        let cycle = Self.pause + Double(distance / Self.speed)
        let t = now.timeIntervalSince(started)
        let run = Int(t / cycle)
        guard run < Self.runs else { return 0 }
        let local = t - Double(run) * cycle
        guard local > Self.pause else { return 0 }
        return -min(CGFloat(local - Self.pause) * Self.speed, distance)
    }
}

/// The song's title (24 bold, scrolling when long, the explicit mark kept still after it) and
/// its artist, who opens their page.
struct PlayerTitleBlock: View {
    let song: Song
    let ink: Color
    let accent: Color
    let openArtist: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                PlayerMarquee(text: song.title, font: .octo(24, .bold, .title1), color: ink)
                if song.isExplicit {
                    ExplicitMark(size: 14, color: accent).fixedSize()
                }
            }
            Group {
                if let openArtist {
                    Button(action: openArtist) { artist }
                        .buttonStyle(NoPress())
                } else {
                    artist
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artist: some View {
        Text(song.byline)
            .font(.octoBody)
            .foregroundStyle(accent)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The heart for a library song: filled, full and glowing while liked; an outline at 60%
/// otherwise. Liking it gives a small beat.
struct PlayerHeart: View {
    let liked: Bool
    let ink: Color
    let toggle: () -> Void
    @State private var beats = 0

    var body: some View {
        Button {
            if !liked { beats += 1 }
            toggle()
        } label: {
            IconView(liked ? .liked : .like, size: 24, color: liked ? ink : ink.opacity(0.6))
                .iconGlow(liked, color: ink)
                .iconAccent(.pulse, trigger: beats)
                .frame(width: 44, height: 44)
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
/// not 1x, the speed. The position is read every frame while the song plays.
struct PlayerProgress: View {
    let ink: Color
    let muted: Color
    let song: Song
    let openSpeed: () -> Void
    @Environment(Player.self) private var player
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(paused: !player.isPlaying)) { _ in
                let position = player.livePosition
                let length = max(player.duration, position)
                OctoSlider(value: length > 0 ? min(max(position / length, 0), 1) : 0, onChange: { fraction in
                    let target = fraction * max(player.duration, player.livePosition)
                    player.seek(to: target)
                }, color: ink, trackColor: ink.opacity(0.24))
                .accessibilityHidden(true)
            }
            ZStack {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let length = max(player.duration, player.livePosition)
                    let gone = Int(min(max(player.livePosition, 0), length))
                    let left = max(Int(length) - gone, 0)
                    HStack {
                        Text(asClock(gone))
                        Spacer()
                        Text("-" + asClock(left))
                    }
                    .font(.octoCaption.monospacedDigit())
                    .foregroundStyle(muted)
                }
                HStack(spacing: 8) {
                    QualityBadge(song: song, ink: ink)
                    let speed = settings.player.speed
                    if speed != 1 {
                        Button(action: openSpeed) {
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
            }
            .padding(.top, -8)
        }
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
private enum PlayPop {
    static var transition: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity).animation(.octoTween(fixed: 150)),
                    removal: .scale(scale: 0.6).combined(with: .opacity).animation(.octoTween(fixed: 100)))
    }
}

/// One transport control in a 72 point box: it shrinks while held and springs back; previous and
/// next nudge the way they go on every tap.
private struct TransportButton<Icon: View>: View {
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
