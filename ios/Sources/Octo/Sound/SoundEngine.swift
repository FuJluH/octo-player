import AVFoundation
import MediaToolbox
import Observation
import OctoKit
import os

/// The sound settings for each output (the phone's speaker, wired headphones, each Bluetooth
/// device and AirPlay receiver keep their own), and the presets the listener saved.
@MainActor
@Observable
final class SoundStore {
    private(set) var outputKey = "speaker"
    private(set) var outputName = "This iPhone"
    private var byOutput: [String: SoundSettings]
    private(set) var userPresets: [String: [Double]]
    /// While held, the equalizer is bypassed so the listener hears the sound flat.
    var heldFlat = false { didSet { publish() } }

    @ObservationIgnored let processor = SoundProcessor()
    @ObservationIgnored private var routeWatch: NSObjectProtocol?

    private static let settingsKey = "sound.byOutput"
    private static let presetsKey = "sound.userPresets"

    init() {
        let defaults = UserDefaults.standard
        byOutput = (defaults.data(forKey: Self.settingsKey)).flatMap { try? JSONDecoder().decode([String: SoundSettings].self, from: $0) } ?? [:]
        userPresets = defaults.dictionary(forKey: Self.presetsKey) as? [String: [Double]] ?? [:]
        readOutput()
        routeWatch = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.readOutput() }
        }
        publish()
    }

    /// The settings of the output in use. Changing them applies at once.
    var settings: SoundSettings {
        get { byOutput[outputKey] ?? SoundSettings() }
        set {
            byOutput[outputKey] = newValue
            save()
            publish()
        }
    }

    func savePreset(_ name: String) {
        userPresets[name] = settings.graphicGains
        UserDefaults.standard.set(userPresets, forKey: Self.presetsKey)
    }

    func deletePreset(_ name: String) {
        userPresets[name] = nil
        UserDefaults.standard.set(userPresets, forKey: Self.presetsKey)
    }

    private func readOutput() {
        let port = AVAudioSession.sharedInstance().currentRoute.outputs.first
        let key = port.map { "\($0.portType.rawValue):\($0.uid)" } ?? "speaker"
        guard key != outputKey || outputName != (port?.portName ?? "This iPhone") else { return }
        outputKey = key
        outputName = port?.portName ?? "This iPhone"
        publish()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(byOutput), forKey: Self.settingsKey)
    }

    private func publish() {
        var shown = settings
        if heldFlat { shown.eqEnabled = false }
        processor.update(shown)
    }
}

/// What the audio thread runs: built on the main thread, swapped in whole.
final class SoundChain: @unchecked Sendable {
    let settings: SoundSettings
    let filters: [EqFilter]
    let preamp: Float

    init(settings: SoundSettings) {
        self.settings = settings
        filters = settings.activeFilters()
        preamp = Float(pow(10, settings.effectivePreampDb() / 20))
    }
}

/// The audio processor every song plays through, the same chain as the other apps: level
/// (equalizer preamp and ReplayGain), the equalizer's filters, balance and mono, then the
/// limiter. Gain changes are ramped over one buffer so nothing clicks.
final class SoundProcessor: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State())
    private let albums = AlbumRun()

    struct State {
        var chain = SoundChain(settings: SoundSettings())
        var replayGain: Float = 1
        var loudness: SongLoudness?
    }

    func update(_ settings: SoundSettings) {
        let chain = SoundChain(settings: settings)
        state.withLock {
            $0.chain = chain
            $0.replayGain = Float(replayGainFactor(settings, $0.loudness))
        }
    }

    /// A new song begins: its loudness, and whether it follows a song from the same album.
    func songStarted(id: String, albumId: String?, replayGain: ReplayGain?) {
        let follows = albums.follows(id, albumId)
        let info = replayGain.flatMap {
            ReplayGainTags.stored(trackGain: $0.trackGain, trackPeak: $0.trackPeak, albumGain: $0.albumGain, albumPeak: $0.albumPeak)
        }
        state.withLock {
            $0.loudness = SongLoudness(info, followsSameAlbum: follows)
            $0.replayGain = Float(replayGainFactor($0.chain.settings, $0.loudness))
        }
    }

    /// The tap to put on a song's audio track.
    func makeTap() -> MTAudioProcessingTap? {
        let context = TapContext(processor: self)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue().prepare(format.pointee)
            },
            unprepare: { _ in },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .process(buffers, frames: Int(framesOut.pointee))
            })
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        return status == noErr ? tap : nil
    }

    fileprivate func snapshot() -> (SoundChain, Float) {
        state.withLock { ($0.chain, $0.replayGain) }
    }
}

/// One song's processing state on the audio thread: its filters' memory, its limiter, and the
/// level it last played at.
private final class TapContext: @unchecked Sendable {
    let processor: SoundProcessor
    private var sampleRate = 48_000.0
    private var channels = 2
    private var supported = false
    private var bank: FilterBank?
    private var bankChain: SoundChain?
    private var limiter: Limiter?
    private var level: Float = 1

    init(processor: SoundProcessor) {
        self.processor = processor
    }

    func prepare(_ format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate
        channels = Int(format.mChannelsPerFrame)
        supported = format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            && format.mBitsPerChannel == 32
        limiter = Limiter(channels: channels, sampleRate: sampleRate)
    }

    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard supported, frames > 0 else { return }
        let (chain, replayGain) = processor.snapshot()
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let channelData: [UnsafeMutablePointer<Float>] = buffers.compactMap { $0.mData?.assumingMemoryBound(to: Float.self) }
        guard channelData.count == channels else { return }

        // The level, ramped from the last buffer's to this one's so a change never clicks.
        let target = chain.preamp * replayGain
        if target != 1 || level != 1 {
            let step = (target - level) / Float(frames)
            for ch in channelData {
                var g = level
                for i in 0..<frames {
                    g += step
                    ch[i] *= g
                }
            }
            level = target
        }

        // The equalizer. A new curve carries on from the old filters' memory when they line up.
        if bankChain !== chain {
            let fresh = FilterBank(filters: chain.filters, sampleRate: sampleRate, channels: channels)
            if let bank { fresh.continueFrom(bank) }
            bank = fresh
            bankChain = chain
        }
        if let bank, !bank.isEmpty {
            for (index, ch) in channelData.enumerated() { bank.process(ch, frames: frames, channel: index) }
        }

        // Balance and mono, for two channels.
        if channels == 2 {
            let left = channelData[0], right = channelData[1]
            if chain.settings.mono {
                for i in 0..<frames {
                    let mid = (left[i] + right[i]) * 0.5
                    left[i] = mid
                    right[i] = mid
                }
            }
            let balance = Float(chain.settings.balance)
            if balance != 0 {
                let leftGain = balance > 0 ? 1 - balance : 1
                let rightGain = balance < 0 ? 1 + balance : 1
                for i in 0..<frames {
                    left[i] *= leftGain
                    right[i] *= rightGain
                }
            }
        }

        // The limiter catches any peak that would still clip.
        if let limiter {
            limiter.enabled = chain.settings.limiter
            limiter.process(channelData, frames: frames)
        }
    }
}
