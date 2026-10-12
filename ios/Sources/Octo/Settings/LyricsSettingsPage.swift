import AVFoundation
import OctoKit
import SwiftUI

/// Where lyrics come from, the screen while they show, how synced lyrics look, and their timing
/// on the output playing now.
struct LyricsSettingsPage: View {
    var highlight: String?
    @Environment(LyricsStore.self) private var lyrics
    @State private var settings = AppSettings.shared
    @State private var output = CurrentOutput.shared

    var body: some View {
        let look = settings.lyricsLook
        let name = output.name
        let timing = settings.outputTiming(name.key)
        SettingsPageFrame(title: SettingsPage.lyrics.title, highlight: highlight) {
            SettingsGroup {
                ToggleRow(SettingsIndex.lyricsOnline, isOn: settings.player.lyricsOnline,
                          helper: "From LRCLIB when your music has none. Sends only the title, artist, album and length.") { on in
                    settings.setLyricsOnline(on)
                    lyrics.online = on
                }
                ToggleRow(SettingsIndex.lyricsScreenOn, isOn: settings.keepScreenOn, onChange: settings.setKeepScreenOn)
            }
            SettingsGroup(title: "Synced lyrics", icon: SettingsIcon.lyrics) {
                ChoiceRow(SettingsIndex.lyricsStyle, value: look.style.label, question: SettingsQuestion(
                    SettingsIndex.lyricsStyle.title, LyricsStyle.allCases, current: look.style,
                    answer: { SettingsAnswer($0.label, $0.about) }, pick: { style in
                        settings.setLyricsStyle(style)
                        lyrics.look = style == .classic ? .classic : .flowing
                    }))
            }
            SettingsGroup(title: "Timing", icon: SettingsIcon.timer,
                          footer: "Words late? Tap Earlier. Early? Tap Later. One song is set from the player's lyrics menu.") {
                InfoRow(SettingsIndex.lyricsOutputTiming, title: name.label, value: LyricsOutputTiming.signed(timing.ms),
                        helper: LyricsOutputTiming.about(name.key, automatic: timing.automatic))
                TimingButtons(ms: timing.ms, canReset: !timing.automatic) { steps in
                    settings.stepOutputTiming(name.key, steps: steps)
                    lyrics.moveOutput(steps: steps)
                } reset: {
                    settings.resetOutputTiming(name.key)
                    lyrics.resetOutput()
                }
                .padding(.top, 12)
                .padding(.horizontal, 8)
            }
            SettingsGroup(title: "Look", icon: SettingsIcon.appearance, footer: "For the Flowing style.") {
                ForEach(LookDial.allCases, id: \.self) { dial in
                    dialRow(dial, look.percent(dial))
                }
                ToggleRow(SettingsIndex.lyricsKeepCompleted, isOn: look.keepCompleted, helper: "Sung lines stay faintly above.",
                          onChange: settings.setKeepCompleted)
                ToggleRow(SettingsIndex.lyricsArc, isOn: look.arc, helper: "Lines bend round a drum.", onChange: settings.setArc)
            }
        }
    }

    /// One of the look's sliders, in percent, in steps of 5.
    private func dialRow(_ dial: LookDial, _ percent: Int) -> some View {
        let range = dial.range
        let span = Double(range.upperBound - range.lowerBound)
        return SliderRow(Self.entries[dial], value: "\(percent)%", fraction: Double(percent - range.lowerBound) / span) { fraction in
            let raw = Double(range.lowerBound) + fraction * span
            let picked = (Int((raw / 5 + 0.5).rounded(.down)) * 5).held(to: range)
            if picked != percent { settings.setLookDial(dial, picked) }
        }
    }

    /// Each slider's row in the index.
    private static let entries: [LookDial: SettingEntry] = [
        .emphasis: SettingsIndex.lyricsEmphasis,
        .glow: SettingsIndex.lyricsGlow,
        .lift: SettingsIndex.lyricsLift,
        .speed: SettingsIndex.lyricsMotionSpeed,
        .inactiveScale: SettingsIndex.lyricsInactiveScale,
        .fade: SettingsIndex.lyricsFade,
        .cascade: SettingsIndex.lyricsCascade,
    ]
}

/// Earlier and Later, a step a tap, and Use automatic under them, dimmed while there is nothing
/// to put back. Earlier always shows the words sooner.
private struct TimingButtons: View {
    let ms: Int
    let canReset: Bool
    let step: (Int) -> Void
    let reset: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { step(-1) } label: { Text("Earlier").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                    .disabled(ms <= -LyricsOutputTiming.limitMs)
                Button { step(1) } label: { Text("Later").frame(maxWidth: .infinity) }
                    .buttonStyle(.glass)
                    .disabled(ms >= LyricsOutputTiming.limitMs)
            }
            .font(.octoBodySmall.weight(.medium))
            Button(action: reset) {
                Text("Use automatic")
                    .font(.settingsLabel)
                    .foregroundStyle(OctoColor.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .opacity(canReset ? 1 : 0.4)
            .disabled(!canReset)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }
}

/// The output playing now, followed as it changes: the phone's speaker, a cable, a Bluetooth or
/// USB device, or an AirPlay receiver.
@MainActor
@Observable
final class CurrentOutput {
    static let shared = CurrentOutput()
    private(set) var name = AudioOutputName.phoneSpeaker

    private init() {
        read()
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CurrentOutput.shared.read() }
        }
    }

    private func read() {
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            name = .phoneSpeaker
            return
        }
        let kind: OutputKind = switch port.portType {
        case .builtInSpeaker, .builtInReceiver: .speaker
        case .headphones, .lineOut: .wired
        case .usbAudio: .usb
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: .bluetooth
        case .airPlay: .airPlay
        case .carAudio: .carPlay
        default: .other
        }
        let next = AudioOutputName.of(kind, name: port.portName)
        if next != name { name = next }
    }
}
