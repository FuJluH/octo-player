import AVFoundation
import Foundation
import OctoKit

/// Sleep timer, queue and quality rules the player's parts read. The same rules
/// every Octo app follows, kept here beside the parts that show them.
enum PlayerRule {
    // MARK: Sleep timer

    /// Where the sleep timer is: off, counting down, or waiting for songs to end.
    enum Sleep: Equatable {
        case off
        case counting(remainingMs: Int)
        case endOfSong
        /// Waiting for this many songs to end, the one playing included. Always 2 or more.
        case songs(Int)
        /// Waiting for one song further down the queue to end.
        case afterSong(title: String)
    }

    /// The lengths offered, in minutes; what a running countdown can be lengthened by; how many
    /// songs the music can stop after; the longest custom timer.
    static let sleepMinutes = [5, 15, 30, 45, 60]
    static let sleepExtensions = [5, 10]
    static let sleepSongCounts = [1, 2, 3, 5]
    static let maxSleepMinutes = 720

    /// A timer in words, for the timer's card and its button.
    static func sleepSummary(_ state: Sleep) -> String {
        switch state {
        case .off: "Off"
        case .counting(let remaining): "\((remaining + 59_999) / 60_000) min left"
        case .endOfSong: "At the end of this song"
        case .songs(let left): "After \(left == 1 ? "1 song" : "\(left) songs")"
        case .afterSong(let title): "After \(title)"
        }
    }

    // MARK: Queue sources

    /// Where a song in the queue came from: the listener's own pick, a list that was played, or
    /// Autoplay.
    enum Source: Hashable {
        case you
        case played(String?)
        case autoplay
    }

    /// The heading over a run of songs to come from one source.
    static func queueSourceTitle(_ source: Source) -> String {
        switch source {
        case .you: "Next from you"
        case .autoplay: "Next from Autoplay"
        case .played(let name): name.map { "Next from \($0)" } ?? "Up next"
        }
    }

    /// The songs to come cut into runs of one source each, in the order they play. Songs from one
    /// source that are apart stay in runs of their own.
    static func sourceRuns<T>(_ items: [T], sourceOf: (T) -> Source) -> [(source: Source, items: [T])] {
        var runs: [(source: Source, items: [T])] = []
        for item in items {
            let source = sourceOf(item)
            if let last = runs.last, last.source == source {
                runs[runs.count - 1].items.append(item)
            } else {
                runs.append((source, [item]))
            }
        }
        return runs
    }

    // MARK: Quality

    /// How a song is encoded, for the badge under the progress line.
    struct Quality: Equatable {
        var codec: String
        var lossless: Bool
        /// Lossless above 48 kHz.
        var hiRes: Bool
        /// Like "24-bit · 48 kHz" for lossless, or "128 kbps" for everything else.
        var specs: String?
        /// The song's sample rate, and the rate the phone's output runs at, when known.
        var songRate: Int?
        var outputRate: Int?

        /// What the badge says at a glance.
        var label: String { hiRes ? "Hi-Res" : (lossless ? "Lossless" : codec) }

        /// Everything, shown when the badge is tapped, with the output's rate when the phone plays
        /// the song at another.
        var full: String {
            var parts = [codec]
            if let specs { parts.append(specs) }
            if let outputRate, let songRate, outputRate != songRate { parts.append("plays at \(kilohertz(outputRate)) kHz") }
            return parts.joined(separator: " · ")
        }
    }

    private static let losslessCodecs: Set<String> = ["FLAC", "ALAC", "WAV"]

    /// A song's quality from what it is: its codec, bit depth, rate and bitrate.
    static func audioQuality(codec: String?, bitDepth: Int?, sampleRate: Int?, bitrate: Int?) -> Quality? {
        guard let codec else { return nil }
        let rate = sampleRate.flatMap { $0 > 0 ? "\(kilohertz($0)) kHz" : nil }
        if losslessCodecs.contains(codec) {
            let specs = [bitDepth.map { "\($0)-bit" }, rate].compactMap { $0 }.joined(separator: " · ")
            return Quality(codec: codec, lossless: true, hiRes: (sampleRate ?? 0) > 48_000, specs: specs.isEmpty ? nil : specs,
                                songRate: sampleRate.flatMap { $0 > 0 ? $0 : nil })
        }
        let specs = bitrate.flatMap { $0 > 0 ? "\($0 / 1000) kbps" : nil } ?? rate
        return Quality(codec: codec, lossless: false, hiRes: false, specs: specs, songRate: sampleRate.flatMap { $0 > 0 ? $0 : nil })
    }

    /// A codec's name from a file type or a mime type.
    static func codecName(_ type: String?) -> String? {
        switch type?.lowercased() {
        case "flac", "audio/flac", "audio/x-flac": "FLAC"
        case "alac", "audio/alac": "ALAC"
        case "mp3", "mpeg", "audio/mpeg", "audio/mp3": "MP3"
        case "aac", "m4a", "mp4", "audio/aac", "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac-adts": "AAC"
        case "opus", "audio/opus": "Opus"
        case "vorbis", "audio/vorbis": "Vorbis"
        case "ogg", "oga", "audio/ogg", "application/ogg": "Ogg"
        case "wav", "wave", "audio/wav", "audio/x-wav", "audio/wave": "WAV"
        default: nil
        }
    }

    /// 44100 reads as "44.1", 48000 as "48".
    static func kilohertz(_ hz: Int) -> String { hz % 1000 == 0 ? "\(hz / 1000)" : String(format: "%.1f", Double(hz) / 1000) }

    /// What the decoder says about the song once it is open, else what its file type says.
    @MainActor
    static func readQuality(_ asset: AVAsset?, song: Song) async -> Quality? {
        var codec: String?
        var depth: Int?
        var rate: Int?
        var bitrate: Int?
        if let asset, let track = try? await asset.loadTracks(withMediaType: .audio).first,
           let formats = try? await track.load(.formatDescriptions), let format = formats.first,
           let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
            switch stream.mFormatID {
            case kAudioFormatFLAC: codec = "FLAC"
            case kAudioFormatAppleLossless: codec = "ALAC"
            case kAudioFormatMPEGLayer3: codec = "MP3"
            case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: codec = "AAC"
            case kAudioFormatOpus: codec = "Opus"
            case kAudioFormatLinearPCM: codec = "WAV"
            default: codec = nil
            }
            if stream.mSampleRate > 0 { rate = Int(stream.mSampleRate) }
            if stream.mBitsPerChannel > 0 {
                depth = Int(stream.mBitsPerChannel)
            } else if stream.mFormatID == kAudioFormatFLAC || stream.mFormatID == kAudioFormatAppleLossless {
                switch stream.mFormatFlags {
                case 1: depth = 16
                case 2: depth = 20
                case 3: depth = 24
                case 4: depth = 32
                default: depth = nil
                }
            }
            if let estimated = try? await track.load(.estimatedDataRate), estimated > 0 { bitrate = Int(estimated) }
        }
        let fallback = codecName(song.suffix) ?? codecName(song.contentType)
        if codec == nil {
            codec = fallback
            rate = rate ?? song.samplingRate
            depth = depth ?? song.bitDepth
            bitrate = bitrate ?? song.bitRate.map { $0 * 1000 }
        }
        if codec != nil, losslessCodecs.contains(codec ?? ""), depth == nil { depth = song.bitDepth }
        guard var quality = audioQuality(codec: codec, bitDepth: depth, sampleRate: rate, bitrate: bitrate) else { return nil }
        let output = AVAudioSession.sharedInstance().sampleRate
        if output > 0 { quality.outputRate = Int(output) }
        return quality
    }
}
