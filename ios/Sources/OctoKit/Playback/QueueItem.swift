import Foundation

/// One song in the queue, with everything the player and the screens need to play and show it.
/// `entryId` is given as it goes into the queue (`q:<n>`), so the same song queued twice is two
/// entries, and a list can point at one entry even while songs around it come and go.
public struct QueueItem: Sendable, Hashable, Codable, Identifiable {
    public var entryId: String?
    /// The library's id for the song, `find:<id>` for a song found online, a `radio:` or `file:`
    /// id for a station or an opened file.
    public var trackId: String
    /// Where the audio is: an `octo-stream://song/...` address, a file, or a station's address.
    public var uri: String
    /// What the player will receive, for the quality badge.
    public var mimeType: String?
    /// The file's own type, before any transcoding.
    public var fileMime: String?
    public var title: String
    public var artist: String
    public var album: String
    public var trackNo: Int?
    public var discNo: Int?
    public var year: Int?
    /// The listed length; 0 when unknown.
    public var durationMs: Int
    /// The cover art reference (the server's cover id).
    public var artwork: String?
    public var albumId: String?
    public var artistId: String?
    /// The song's place in its album, for keeping an album gapless.
    public var albumOrder: Int?
    public var explicit: Bool
    /// The song's tempo from its tags or server, 1 to 999 only.
    public var bpm: Int?
    public var genre: String?
    public var trackGain: Double?
    public var trackPeak: Double?
    public var albumGain: Double?
    public var albumPeak: Double?
    /// Where the song came from, for the queue's headings.
    public var source: QueueSource
    /// A song found online, not yet in the library.
    public var isFind: Bool
    /// The song as the server describes it, for the screens.
    public var song: Song?

    public var id: String { entryId ?? trackId }

    public init(trackId: String, uri: String, title: String, artist: String = "", album: String = "", durationMs: Int = 0,
                mimeType: String? = nil, fileMime: String? = nil, trackNo: Int? = nil, discNo: Int? = nil, year: Int? = nil,
                artwork: String? = nil, albumId: String? = nil, artistId: String? = nil, albumOrder: Int? = nil, explicit: Bool = false,
                bpm: Int? = nil, genre: String? = nil, loudness: ReplayGainInfo? = nil, source: QueueSource = .none,
                isFind: Bool = false, song: Song? = nil, entryId: String? = nil) {
        self.entryId = entryId
        self.trackId = trackId
        self.uri = uri
        self.mimeType = mimeType
        self.fileMime = fileMime
        self.title = title
        self.artist = artist
        self.album = album
        self.trackNo = trackNo
        self.discNo = discNo
        self.year = year
        self.durationMs = durationMs
        self.artwork = artwork
        self.albumId = albumId
        self.artistId = artistId
        self.albumOrder = albumOrder
        self.explicit = explicit
        self.bpm = bpm.flatMap { (1...999).contains($0) ? $0 : nil }
        self.genre = genre
        trackGain = loudness?.trackGain
        trackPeak = loudness?.trackPeak
        albumGain = loudness?.albumGain
        albumPeak = loudness?.albumPeak
        self.source = source
        self.isFind = isFind
        self.song = song
    }

    /// The loudness the song's source keeps for it, if any.
    public var loudness: ReplayGainInfo? {
        ReplayGainTags.stored(trackGain: trackGain, trackPeak: trackPeak, albumGain: albumGain, albumPeak: albumPeak)
    }

    public var isRadioStation: Bool { isRadio(trackId) }

    /// What the crossfade needs to know of the song, at a length.
    public func fadeSong(durationMs: Int) -> FadeSong { FadeSong(albumId: albumId, albumOrder: albumOrder, durationMs: durationMs) }

    /// The song's tempo as the analysis takes it.
    public var tagTempo: Double? { tagBpm(bpm) }

    public func withEntry(_ id: String) -> QueueItem {
        var copy = self
        copy.entryId = id
        return copy
    }

    public func withSource(_ source: QueueSource) -> QueueItem {
        var copy = self
        copy.source = source
        return copy
    }
}

extension QueueSource: Codable {
    public init(from decoder: Decoder) throws {
        self = queueSourceOf(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encoded)
    }
}

/// How the queue repeats.
public enum RepeatMode: Int, Sendable, Codable, CaseIterable {
    case off = 0
    case one = 1
    case all = 2

    /// Repeat cycles off, all, one.
    public var cycled: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}
