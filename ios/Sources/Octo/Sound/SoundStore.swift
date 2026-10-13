import AVFoundation
import Observation
import OctoKit

/// The sound settings, for the output playing now, and the listener's own presets. With "each
/// output keeps its own sound" on, the speaker, a cable and each Bluetooth, USB, AirPlay or car
/// device remember their own; otherwise one shared set is used everywhere. The audio path
/// follows `current` on every change, with crossfeed only where there can be headphones.
@MainActor
@Observable
final class SoundStore {
    /// Where the sound goes now, followed live as devices come and go.
    private(set) var output: AudioOutput
    /// Whether each output keeps its own sound.
    private(set) var perOutput: Bool
    /// Every saved set by output key; "all" holds the shared one.
    private(set) var saved: [String: SoundSettings]
    /// The listener's own presets, in the order they were saved.
    private(set) var presets: [EqPreset]
    /// A state of the Sound page asked for from outside it.
    var pageRequest: SoundPageRequest?
    /// How many Sound pages are on screen.
    @ObservationIgnored var pagesShown = 0

    @ObservationIgnored let processor = SoundProcessor()
    @ObservationIgnored private let soundData: UserDefaults
    @ObservationIgnored private let presetData: UserDefaults
    @ObservationIgnored private var watchers: [NSObjectProtocol] = []

    /// The store in use, for steps driven from outside the app.
    static weak var live: SoundStore?

    private static let profilesKey = "profiles"
    private static let perOutputKey = "per_output"
    private static let presetsKey = "presets"

    init() {
        soundData = UserDefaults(suiteName: "sound") ?? .standard
        presetData = UserDefaults(suiteName: "sound_presets") ?? .standard
        saved = SoundProfiles.decode(soundData.string(forKey: Self.profilesKey))
        perOutput = soundData.bool(forKey: Self.perOutputKey)
        presets = UserPresetRules.decode(presetData.string(forKey: Self.presetsKey))
        output = Self.routeOutput()
        processor.update(SoundOutputs.playing(SoundOutputs.current(saved, perOutput: perOutput, output: output), on: output))
        let center = NotificationCenter.default
        for name in [AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            watchers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.readOutput() }
            })
        }
        Self.live = self
    }

    /// The settings that play now.
    var current: SoundSettings { SoundOutputs.current(saved, perOutput: perOutput, output: output) }

    /// Changes the settings of the output playing now, saved at once.
    func update(_ change: (SoundSettings) -> SoundSettings) {
        saved = SoundOutputs.saving(change, to: saved, perOutput: perOutput, output: output)
        soundData.set(SoundProfiles.encode(saved), forKey: Self.profilesKey)
        publish()
    }

    /// Whether each output keeps its own settings. Turning it on starts every output from the
    /// shared set; turning it off goes back to it, and the outputs' own sets stay saved.
    func setPerOutput(_ on: Bool) {
        perOutput = on
        soundData.set(on, forKey: Self.perOutputKey)
        publish()
    }

    /// Saves the ten bands under a name, replacing a preset of the same name.
    func savePreset(_ name: String, gains: [Double]) {
        presets = UserPresetRules.saving(name, gains: gains, to: presets)
        presetData.set(UserPresetRules.encode(presets), forKey: Self.presetsKey)
    }

    func deletePreset(_ name: String) {
        presets = UserPresetRules.deleting(name, from: presets)
        presetData.set(UserPresetRules.encode(presets), forKey: Self.presetsKey)
    }

    // MARK: Backup

    /// Every saved set by output key, and whether each output keeps its own, for a backup.
    var backup: (perOutput: Bool, profiles: [String: SoundSettings]) { (perOutput, saved) }

    /// Puts back the sets from a backup. Outputs the backup does not name keep what they have.
    func restore(perOutput: Bool, profiles: [String: SoundSettings]) {
        saved = SoundProfiles.restoring(profiles, into: saved)
        soundData.set(SoundProfiles.encode(saved), forKey: Self.profilesKey)
        setPerOutput(perOutput)
    }

    /// Adds presets from a backup, each replacing one of the same name.
    func restorePresets(_ restored: [EqPreset]) {
        presets = UserPresetRules.restoring(restored, into: presets)
        presetData.set(UserPresetRules.encode(presets), forKey: Self.presetsKey)
    }

    // MARK: The output

    private func readOutput() {
        let now = Self.routeOutput()
        guard now != output else { return }
        output = now
        publish()
    }

    /// Hands the settings to the audio path, with crossfeed left off where there are no
    /// headphones.
    private func publish() {
        processor.update(SoundOutputs.playing(current, on: output))
    }

    /// The output from the outputs the sound is routed to now.
    private static func routeOutput() -> AudioOutput {
        SoundOutputs.outputFor(AVAudioSession.sharedInstance().currentRoute.outputs.map { port in
            OutputDevice(kind: kind(of: port.portType), name: port.portName.trimmingCharacters(in: .whitespacesAndNewlines), address: port.uid)
        })
    }

    private static func kind(of port: AVAudioSession.Port) -> OutputDevice.Kind {
        switch port {
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: .bluetooth
        case .airPlay: .airPlay
        case .carAudio: .car
        case .usbAudio: .usb
        case .headphones: .wired
        default: .other
        }
    }
}

/// A state of the Sound page to open, asked for from outside it.
enum SoundPageRequest: Equatable {
    /// Scrolls to the parametric filter editor.
    case editor
    /// Opens the "Save as preset" card.
    case savePreset
    /// Asks to delete one of the listener's own presets.
    case deletePreset(String)
    /// Scrolls to a card: "loudness", "crossfeed", "balance" or "correction".
    case card(String)
}
