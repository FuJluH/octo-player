import Foundation

/// How a song is encoded, for the badge under the progress line.
public struct AudioQuality: Sendable, Equatable {
    public var codec: String
    public var lossless: Bool
    /// Lossless above 48 kHz.
    public var hiRes: Bool
    /// Like "24-bit · 48 kHz" for lossless, or "128 kbps" for everything else.
    public var specs: String?
    /// The song's sample rate, and the rate the phone's output runs at, when known; they differ
    /// when the phone resamples.
    public var songRate: Int?
    public var outputRate: Int?

    public init(codec: String, lossless: Bool, hiRes: Bool, specs: String?, songRate: Int? = nil, outputRate: Int? = nil) {
        self.codec = codec
        self.lossless = lossless
        self.hiRes = hiRes
        self.specs = specs
        self.songRate = songRate
        self.outputRate = outputRate
    }

    /// What the badge says at a glance.
    public var label: String { hiRes ? "Hi-Res" : (lossless ? "Lossless" : codec) }

    /// Everything, shown when the badge is tapped, with the output's rate when the phone plays the
    /// song at another.
    public var full: String {
        [codec, specs, resampledTo.map { "plays at \(kilohertz($0)) kHz" }].compactMap { $0 }.joined(separator: " · ")
    }

    private var resampledTo: Int? {
        guard let outputRate, songRate != nil, outputRate != songRate else { return nil }
        return outputRate
    }

    public func playingAt(_ rate: Int?) -> AudioQuality {
        var copy = self
        copy.outputRate = rate
        return copy
    }
}

/// The badge from what the decoder reports once the song is open (`codecMime`, `bitDepth` of
/// the decoded sound, `sampleRate`, `bitrate`, each nil or 0 and below when not known), and the
/// file type before then.
public func audioQuality(codecMime: String?, fileMime: String?, bitDepth: Int?, sampleRate: Int?, bitrate: Int?) -> AudioQuality? {
    guard let codec = codecName(codecMime) ?? codecName(fileMime) else { return nil }
    let rate = sampleRate.flatMap { $0 > 0 ? $0 : nil }
    let rateText = rate.map { "\(kilohertz($0)) kHz" }
    if ["FLAC", "ALAC", "WAV"].contains(codec) {
        let specs = [bitDepth.flatMap { $0 > 0 ? "\($0)-bit" : nil }, rateText].compactMap { $0 }.joined(separator: " · ")
        return AudioQuality(codec: codec, lossless: true, hiRes: (rate ?? 0) > 48_000, specs: specs.isEmpty ? nil : specs, songRate: rate)
    }
    let specs = bitrate.flatMap { $0 > 0 ? "\($0 / 1000) kbps" : nil } ?? rateText
    return AudioQuality(codec: codec, lossless: false, hiRes: false, specs: specs, songRate: rate)
}

/// A codec's name from a MIME type, as the quality badge names it.
public func codecName(_ mime: String?) -> String? {
    switch mime?.lowercased() {
    case nil: nil
    case "audio/flac", "audio/x-flac": "FLAC"
    case "audio/alac": "ALAC"
    case "audio/mpeg", "audio/mpeg-l2", "audio/mpeg-l1": "MP3"
    case "audio/mp4a-latm", "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac-adts", "audio/aac": "AAC"
    case "audio/opus": "Opus"
    case "audio/vorbis": "Vorbis"
    case "audio/ogg", "application/ogg": "Ogg"
    case "audio/wav", "audio/raw", "audio/x-wav", "audio/wave": "WAV"
    default: nil
    }
}

/// 44100 reads as "44.1", 48000 as "48".
func kilohertz(_ hz: Int) -> String {
    hz % 1000 == 0 ? "\(hz / 1000)" : String(format: "%.1f", Double(hz) / 1000.0)
}
