import Foundation

/// How long a change of level, balance or curve takes, so it never clicks.
public let glideMs = 30.0

extension SoundSettings {
    /// Whether these settings ask for any shaping at all.
    public var shapesSound: Bool {
        eqEnabled || replayGain != .off || limiter || balance != 0 || mono
    }
}

/// A value that glides to a new setting over a number of frames.
struct Glide {
    private(set) var value: Float
    private var target: Float
    private var step: Float = 0
    private var left = 0

    init(_ initial: Float) {
        value = initial
        target = initial
    }

    var moving: Bool { left > 0 }

    mutating func to(_ next: Float, frames: Int) {
        target = next
        if frames <= 0 || next == value {
            value = next
            left = 0
        } else {
            step = (next - value) / Float(frames)
            left = frames
        }
    }

    mutating func next() -> Float {
        if left > 0 {
            left -= 1
            value = left == 0 ? target : value + step
        }
        return value
    }
}

/// The sound shaping for one stream. In order: the level (ReplayGain and the equalizer's
/// preamp), the equalizer's filters, mono and balance, then the limiter. Samples are floats,
/// one buffer per channel, full scale at 1.
public final class SoundShaper: @unchecked Sendable {
    public let sampleRate: Double
    public let channels: Int
    private let glideFrames: Int
    private var gain = Glide(1)
    private var left = Glide(1)
    private var right = Glide(1)
    private var mono = Glide(0)

    private var bank: FilterBank
    private var bankCoefficients: [Coefficients] = []
    /// While the curve changes, the old filters keep running and fade out.
    private var fadingFrom: FilterBank?
    private var fadeLeft = 0
    private var fadeScratch: [[Float]] = []

    private let limiter: Limiter
    private var started = false

    /// How many frames late the sound comes out.
    public var latency: Int { limiter.latency }

    public init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        glideFrames = max(1, Int((sampleRate * glideMs / 1_000).rounded()))
        bank = FilterBank(channels: channels, coefficients: [])
        limiter = Limiter(channels: channels, sampleRate: sampleRate)
    }

    /// Takes up new settings or a new song. Changes glide in, unless `instant`, as at the very
    /// start of a song.
    public func apply(_ settings: SoundSettings, song: SongLoudness?, instant: Bool) {
        let now = instant || !started
        started = true
        let frames = now ? 0 : glideFrames

        let bands = settings.activeFilters().filter { $0.frequency < sampleRate * highestBandShare }
            .map { coefficients($0, sampleRate: sampleRate) }
        if bands != bankCoefficients {
            let next = FilterBank(channels: channels, coefficients: bands)
            next.continueFrom(bank)
            fadingFrom = now ? nil : bank
            fadeLeft = now ? 0 : glideFrames
            bank = next
            bankCoefficients = bands
        }

        let preamp = Float(pow(10, settings.effectivePreampDb(sampleRate: sampleRate) / 20))
        let level = Float(replayGainFactor(settings, song)) * preamp
        gain.to(level, frames: frames)

        let stereo = channels >= 2
        let balance = stereo ? Float(min(1, max(-1, settings.balance))) : 0
        left.to(balance > 0 ? 1 - balance : 1, frames: frames)
        right.to(balance < 0 ? 1 + balance : 1, frames: frames)
        let toMono = stereo && settings.mono
        mono.to(toMono ? 1 : 0, frames: frames)

        // Sound that is left as it is passes through untouched; the limiter only catches peaks
        // the shaping could push over.
        let untouched = bands.isEmpty && level == 1 && balance == 0 && !toMono
        limiter.enabled = settings.limiter && !untouched
    }

    /// Shapes `frames` frames in place, one buffer per channel. The sound comes out the
    /// limiter's latency late.
    public func process(_ buffers: [UnsafeMutablePointer<Float>], frames: Int) {
        guard buffers.count == channels, frames > 0 else { return }
        applyGain(buffers, frames)
        applyFilters(buffers, frames)
        applyMix(buffers, frames)
        limiter.process(buffers, frames: frames)
    }

    /// Forgets the sound held back, after a jump to another place.
    public func clearHeld() { limiter.clear() }

    private func applyGain(_ buffers: [UnsafeMutablePointer<Float>], _ frames: Int) {
        if !gain.moving && gain.value == 1 { return }
        for i in 0..<frames {
            let g = gain.next()
            for ch in 0..<channels { buffers[ch][i] *= g }
        }
    }

    private func applyFilters(_ buffers: [UnsafeMutablePointer<Float>], _ frames: Int) {
        guard let old = fadingFrom else {
            for ch in 0..<channels { bank.process(buffers[ch], frames: frames, channel: ch) }
            return
        }
        if fadeScratch.count != channels || (fadeScratch.first?.count ?? 0) < frames {
            fadeScratch = Array(repeating: Array(repeating: 0, count: frames), count: channels)
        }
        for ch in 0..<channels {
            fadeScratch[ch].withUnsafeMutableBufferPointer { scratch in
                scratch.baseAddress!.update(from: buffers[ch], count: frames)
                old.process(scratch.baseAddress!, frames: frames, channel: ch)
            }
            bank.process(buffers[ch], frames: frames, channel: ch)
        }
        for i in 0..<frames {
            let w: Float = fadeLeft > 0 ? 1 - Float(fadeLeft) / Float(glideFrames) : 1
            if fadeLeft > 0 { fadeLeft -= 1 }
            for ch in 0..<channels {
                let faded = fadeScratch[ch][i]
                buffers[ch][i] = faded + (buffers[ch][i] - faded) * w
            }
        }
        if fadeLeft == 0 { fadingFrom = nil }
    }

    private func applyMix(_ buffers: [UnsafeMutablePointer<Float>], _ frames: Int) {
        guard channels >= 2 else { return }
        let still = !mono.moving && !left.moving && !right.moving
        if still && mono.value == 0 && left.value == 1 && right.value == 1 { return }
        for i in 0..<frames {
            let m = mono.next()
            if m != 0 {
                var sum: Float = 0
                for ch in 0..<channels { sum += buffers[ch][i] }
                let average = sum / Float(channels)
                for ch in 0..<channels { buffers[ch][i] += (average - buffers[ch][i]) * m }
            }
            buffers[0][i] *= left.next()
            buffers[1][i] *= right.next()
        }
    }
}

/// Where the sound is going: the phone's speaker, a cable, or one Bluetooth, USB, AirPlay or
/// car device, each able to keep its own sound settings. `formerKeys` are keys the same output
/// was saved under before, read when nothing is saved under `key` yet.
public struct AudioOutput: Sendable, Equatable {
    public var key: String
    public var label: String
    public var formerKeys: [String] = []

    public init(key: String, label: String, formerKeys: [String] = []) {
        self.key = key
        self.label = label
        self.formerKeys = formerKeys
    }

    /// Every key this output's settings may be saved under, the current one first.
    public var keys: [String] { [key] + formerKeys }

    public static let phoneSpeaker = AudioOutput(key: "speaker", label: "iPhone speaker")
    public static let bluetoothPrefix = "bluetooth:"
    /// The key of the one set every output shares while outputs do not keep their own.
    public static let shared = "all"
}

/// One output device as the system lists it.
public struct OutputDevice: Sendable, Equatable {
    public enum Kind: Int, Sendable { case bluetooth = 0, airPlay = 1, car = 2, usb = 3, wired = 4, other = 9 }

    public var kind: Kind
    public var name: String
    public var address: String

    public init(kind: Kind, name: String, address: String) {
        self.kind = kind
        self.name = name
        self.address = address
    }
}

public enum SoundOutputs {
    /// The output music goes to: a Bluetooth, AirPlay, car or USB device or a cable when one is
    /// in use, otherwise the speaker. A pair of earbuds can be listed more than once, so a
    /// Bluetooth output is known by its name; its addresses are where its settings were saved
    /// before.
    public static func outputFor(_ devices: [OutputDevice]) -> AudioOutput {
        guard let rank = devices.map(\.kind.rawValue).min(), let kind = OutputDevice.Kind(rawValue: rank), kind != .other else {
            return .phoneSpeaker
        }
        let listed = devices.filter { $0.kind == kind }.sorted {
            if $0.name.isEmpty != $1.name.isEmpty { return !$0.name.isEmpty }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.address < $1.address
        }
        let name = listed[0].name
        switch kind {
        case .bluetooth:
            let same = listed.filter { $0.name == name }
            var addresses: [String] = []
            for address in same.map(\.address) where !address.isEmpty && !addresses.contains(address) { addresses.append(address) }
            let key = AudioOutput.bluetoothPrefix + (name.isEmpty ? (addresses.first ?? "") : name)
            let former = name.isEmpty ? Array(addresses.dropFirst()) : addresses
            return AudioOutput(key: key, label: name.isEmpty ? "Bluetooth" : name, formerKeys: former.map { AudioOutput.bluetoothPrefix + $0 })
        case .airPlay:
            return AudioOutput(key: "airplay:\(name)", label: name.isEmpty ? "AirPlay" : name)
        case .car:
            return AudioOutput(key: "car:\(name)", label: name.isEmpty ? "CarPlay" : name)
        case .usb:
            return AudioOutput(key: "usb:\(name)", label: name.isEmpty ? "USB audio" : name)
        case .wired, .other:
            return AudioOutput(key: "wired", label: "Headphones")
        }
    }

    /// The settings saved for an output: under its key, or else under a key it had before.
    public static func savedFor<T>(_ saved: [String: T], _ output: AudioOutput) -> T? {
        for key in output.keys { if let found = saved[key] { return found } }
        return nil
    }

    /// The settings that play now: the output's own while outputs keep their own, else the
    /// shared set, else the defaults.
    public static func current(_ saved: [String: SoundSettings], perOutput: Bool, output: AudioOutput) -> SoundSettings {
        (perOutput ? savedFor(saved, output) : nil) ?? saved[AudioOutput.shared] ?? SoundSettings()
    }

    /// The saved sets after a change to the output playing now. With each output keeping its
    /// own, the change is saved under the output's current key and nowhere else.
    public static func saving(_ change: (SoundSettings) -> SoundSettings, to saved: [String: SoundSettings],
                              perOutput: Bool, output: AudioOutput) -> [String: SoundSettings] {
        let before = current(saved, perOutput: perOutput, output: output)
        var kept = saved
        if perOutput { for key in output.formerKeys { kept[key] = nil } }
        kept[perOutput ? output.key : AudioOutput.shared] = change(before)
        return kept
    }
}
