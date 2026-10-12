import Foundation

/// One piece of a song's metadata that can carry loudness: an ID3 user text frame, a Vorbis
/// comment (FLAC, Ogg, Opus), an MP4 free-form tag, or the gains an MP3 encoder wrote into its
/// own header.
public enum LoudnessTag: Sendable, Equatable {
    case id3UserText(description: String?, value: String?)
    case vorbisComment(key: String, value: String)
    case mp4FreeForm(domain: String, name: String, value: String)
    case mp3Header(Mp3InfoReplayGain)
}

/// The loudness fields in an MP3 encoder's own header: a peak and up to two gain fields.
public struct Mp3InfoReplayGain: Sendable, Equatable {
    public struct GainField: Sendable, Equatable {
        public static let nameRadio = 1
        public static let nameAudiophile = 2

        public let name: Int
        public let originator: Int
        public let gain: Double

        /// A field as the header packs it in 16 bits: three bits of name, three of who set it,
        /// a sign bit and nine bits of tenths of a decibel. Nothing for an unset name.
        public static func parse(_ field: Int) -> GainField? {
            let name = (field >> 13) & 7
            guard name != 0 else { return nil }
            let originator = (field >> 10) & 7
            let size = Double(field & 0x1FF) / 10
            return GainField(name: name, originator: originator, gain: field & 0x200 != 0 ? -size : size)
        }
    }

    public let peak: Double
    public let field1: GainField?
    public let field2: GainField?

    public init(peak: Double, field1: GainField?, field2: GainField?) {
        self.peak = peak
        self.field1 = field1
        self.field2 = field2
    }

    /// The header's loudness, or nothing when neither field is set.
    public static func parse(peak: Double, field1: Int, field2: Int) -> Mp3InfoReplayGain? {
        let first = GainField.parse(field1)
        let second = GainField.parse(field2)
        guard first != nil || second != nil else { return nil }
        return Mp3InfoReplayGain(peak: peak, field1: first, field2: second)
    }
}

extension ReplayGainTags {
    /// Reads a song's loudness from its metadata: ID3 user text frames, Vorbis comments and
    /// MP4 free-form tags in the "com.apple.iTunes" domain. An MP3's own encoder header is only
    /// used when none of those carry a gain.
    public static func read(_ metadata: [LoudnessTag]?) -> ReplayGainInfo? {
        guard let metadata else { return nil }
        var tags: [(String, String)] = []
        var header: Mp3InfoReplayGain?
        for entry in metadata {
            switch entry {
            case .id3UserText(let description, let value):
                if let description, let value { tags.append((description, value)) }
            case .vorbisComment(let key, let value):
                tags.append((key, value))
            case .mp4FreeForm(let domain, let name, let value):
                if domain.caseInsensitiveCompare("com.apple.iTunes") == .orderedSame { tags.append((name, value)) }
            case .mp3Header(let found):
                header = found
            }
        }
        let fromTags = fromTags(tags)
        if fromTags?.hasGain == true { return fromTags }
        return header.flatMap(fromHeader) ?? fromTags
    }

    static func fromHeader(_ header: Mp3InfoReplayGain) -> ReplayGainInfo? {
        let fields = [header.field1, header.field2].compactMap { $0 }
        let track = fields.first { $0.name == Mp3InfoReplayGain.GainField.nameRadio }?.gain
        let album = fields.first { $0.name == Mp3InfoReplayGain.GainField.nameAudiophile }?.gain
        let peak = header.peak > 0 ? header.peak : nil
        let info = ReplayGainInfo(trackGain: track, trackPeak: peak, albumGain: album, albumPeak: nil)
        return info.hasGain ? info : nil
    }
}

/// What the Smart loudness mode calls a song's album: the catalog's album id, or its album and
/// artist names when it has none. Nothing without an album title.
public func albumKey(albumId: String?, albumTitle: String?, albumArtist: String?, artist: String?) -> String? {
    if let albumId { return albumId }
    guard let title = albumTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return nil }
    return "\(title)/\(albumArtist ?? artist ?? "")"
}
