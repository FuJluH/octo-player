import AVKit
import CoreImage
import MediaPlayer
import OctoKit
import SwiftUI
import UIKit

/// The player's background: the cover, blurred and oversized, slowly drifting, dimmed just
/// enough for the words on it to read.
struct CoverWash: View {
    let coverArt: String?
    let tone: CoverTone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Sized by the screen, never by the oversized covers inside it.
        Color.clear.overlay {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { time in
                waves(time.date.timeIntervalSinceReferenceDate)
            }
        }
        .clipped()
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.5), value: coverArt)
    }

    private func waves(_ t: TimeInterval) -> some View {
            ZStack {
                OctoColor.background
                Cover(id: coverArt, size: 700, radius: 0)
                    .scaleEffect(1.5 + 0.08 * sin(t / 9))
                    .rotationEffect(.degrees(reduceMotion ? 0 : 8 * sin(t / 13)))
                    .offset(x: reduceMotion ? 0 : 40 * cos(t / 11), y: reduceMotion ? 0 : 30 * sin(t / 7))
                    .blur(radius: 70)
                Cover(id: coverArt, size: 700, radius: 0)
                    .scaleEffect(1.3 + 0.06 * cos(t / 8))
                    .rotationEffect(.degrees(reduceMotion ? 180 : 180 + 10 * cos(t / 10)))
                    .offset(x: reduceMotion ? 0 : -50 * sin(t / 12), y: reduceMotion ? 0 : 40 * cos(t / 9))
                    .blur(radius: 90)
                    .opacity(0.6)
                Color.black.opacity(tone.dim)
            }
            .saturation(1.6)
    }
}

/// How light a cover is, and so what colour the words over it take.
struct CoverTone: Equatable {
    /// 0 for black, 1 for white.
    var luminance: Double = 0.2

    /// Light covers get dark words; dark ones white words over a light dim.
    var isLight: Bool { luminance > 0.62 }
    var ink: Color { isLight ? Color(hex: 0x141416) : .white }
    var muted: Color { isLight ? Color(hex: 0x141416).opacity(0.6) : OctoColor.accent.opacity(0.8) }
    var artist: Color { isLight ? Color(hex: 0x141416).opacity(0.75) : OctoColor.accent }
    var dim: Double { isLight ? 0.05 : max(0.15, (luminance - 0.2) * 0.9 + 0.15) }

    /// The average lightness of a cover.
    static func of(_ image: UIImage) -> CoverTone {
        guard let input = CIImage(image: image),
              let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input, kCIInputExtentKey: CIVector(cgRect: input.extent)]),
              let output = filter.outputImage
        else { return CoverTone() }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(output, toBitmap: &pixel, rowBytes: 4,
                                                                   bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                                                   format: .RGBA8, colorSpace: nil)
        let r = Double(pixel[0]) / 255, g = Double(pixel[1]) / 255, b = Double(pixel[2]) / 255
        return CoverTone(luminance: 0.2126 * r + 0.7152 * g + 0.0722 * b)
    }
}

/// The glowing line the song's progress runs along. It thickens and shows a thumb while held,
/// and only seeks when the finger lifts.
struct LineSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let ink: Color
    let onCommit: (Double) -> Void
    @Binding var dragging: Double?

    var body: some View {
        GeometryReader { box in
            let width = box.size.width
            let shown = dragging ?? value
            let fraction = range.upperBound > range.lowerBound ? (shown - range.lowerBound) / (range.upperBound - range.lowerBound) : 0
            let held = dragging != nil
            ZStack(alignment: .leading) {
                Capsule().fill(ink.opacity(0.24)).frame(height: held ? 8 : 3.5)
                Capsule()
                    .fill(ink)
                    .frame(width: max(0, min(width, width * fraction)), height: held ? 8 : 3.5)
                    .shadow(color: ink.opacity(0.6), radius: 4)
                    .shadow(color: ink.opacity(0.3), radius: 10)
                if held {
                    Circle().fill(ink).frame(width: 9 * 1.6, height: 9 * 1.6)
                        .offset(x: max(0, min(width, width * fraction)) - 7)
                }
            }
            .frame(height: 48)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let f = max(0, min(1, drag.location.x / width))
                        dragging = range.lowerBound + f * (range.upperBound - range.lowerBound)
                    }
                    .onEnded { _ in
                        if let target = dragging { onCommit(target) }
                        dragging = nil
                    }
            )
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: held)
        }
        .frame(height: 48)
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue(Duration.seconds(value).formatted(.time(pattern: .minuteSecond)))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            onCommit(min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step))))
        }
    }
}

/// A title too long for its room scrolls slowly from start to end and back.
struct Marquee: View {
    let text: String
    let font: Font
    let color: Color
    @State private var textWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { box in
            let overflow = max(0, textWidth - box.size.width)
            TimelineView(.animation(paused: overflow == 0 || reduceMotion)) { time in
                let cycle = 4 + Double(overflow) / 30
                let phase = time.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle * 2) / cycle
                let travel = phase < 1 ? min(1, max(0, (phase - 0.2) / 0.6)) : min(1, max(0, (1.8 - phase) / 0.6))
                Text(text)
                    .font(font)
                    .foregroundStyle(color)
                    .fixedSize()
                    .background(GeometryReader { Color.clear.preference(key: WidthKey.self, value: $0.size.width) })
                    .offset(x: -overflow * travel)
            }
            .frame(width: box.size.width, alignment: .leading)
            .clipped()
            .mask(LinearGradient(stops: overflow > 0 ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                                        .init(color: .black, location: 0.97), .init(color: .clear, location: 1)]
                                                     : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .onPreferenceChange(WidthKey.self) { textWidth = $0 }
        .accessibilityLabel(text)
    }

    private struct WidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}

/// The song's quality on clear glass; tapping it spells it out for four seconds.
struct QualityBadge: View {
    let song: Song
    let ink: Color
    @State private var expanded = false

    var body: some View {
        if let label = song.qualityLabel {
            Button {
                withAnimation(.snappy) { expanded = true }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.snappy) { expanded = false }
                }
            } label: {
                HStack(spacing: 4) {
                    if song.isLossless { Image(systemName: "waveform").font(.system(size: 11, weight: .semibold)) }
                    Text(expanded ? (song.qualityDetail ?? label) : label)
                        .font(.system(size: expanded ? 11 : 10.5, weight: .semibold))
                        .tracking(expanded ? 0 : 1)
                }
                .foregroundStyle(ink)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .glassEffect(.clear, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(song.qualityDetail ?? label)")
        }
    }
}

/// The system volume, as Octo's line between two speakers. The line drives a hidden system
/// volume view, which is the only way an app may set the volume; the hardware buttons move
/// the line too.
struct VolumeRow: View {
    let ink: Color
    @State private var volume = SystemVolume()
    @State private var dragging: Double?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill").font(.system(size: 15)).foregroundStyle(ink.opacity(0.85))
                .frame(width: 20)
            GeometryReader { box in
                let fraction = dragging ?? Double(volume.level)
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.24)).frame(height: dragging == nil ? 4 : 7)
                    Capsule().fill(ink.opacity(0.85)).frame(width: box.size.width * fraction, height: dragging == nil ? 4 : 7)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    let value = max(0, min(1, drag.location.x / box.size.width))
                    dragging = value
                    volume.set(Float(value))
                }.onEnded { _ in dragging = nil })
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: dragging == nil)
            }
            .frame(height: 30)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 15)).foregroundStyle(ink.opacity(0.85))
                .frame(width: 24)
        }
        .background(HiddenVolumeView(volume: volume).frame(width: 1, height: 1).opacity(0.01))
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(volume.level * 100)) percent")
        .accessibilityAdjustableAction { direction in
            volume.set(max(0, min(1, volume.level + (direction == .increment ? 0.0625 : -0.0625))))
        }
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

/// The system's AirPlay and Bluetooth picker.
struct RoutePicker: UIViewRepresentable {
    var tint: UIColor = .white

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = tint
        view.activeTintColor = UIColor(OctoColor.accentHover)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {
        view.tintColor = tint
    }
}

/// A round glass button for the player's chrome.
struct PlayerChromeButton: View {
    let icon: String
    let label: String
    let ink: Color
    var lit = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(ink.opacity(lit ? 1 : 0.45))
                .shadow(color: lit ? ink.opacity(0.5) : .clear, radius: lit ? 6 : 0)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A transport control: the icon squeezes while pressed and nudges the way it goes.
struct TransportButtonStyle: ButtonStyle {
    var nudge: CGFloat = 0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .offset(x: configuration.isPressed ? nudge : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.45), value: configuration.isPressed)
    }
}
