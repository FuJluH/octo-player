import Foundation

/// Where the copy of a song that plays comes from.
public enum SongInfoSource: Equatable, Sendable {
    /// A file on the phone, by its path when known.
    case phone(path: String?)
    /// A server, by the name people know it by, and the file it was downloaded to on the phone.
    case server(name: String?, downloadedTo: String?)
    /// A song found online, not in the library yet.
    case found
}

/// Everything the info page says about a song. When it was added is in seconds; when last
/// played in milliseconds. Gains are in decibels; peaks where 1 is full scale.
public struct SongInfoFacts: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String?
    public var year: Int?
    public var genre: String = ""
    public var trackNo: Int?
    public var discNo: Int?
    public var durationMs: Int64 = 0
    public var mimeType: String?
    /// Bits per second, samples per second, bits per sample.
    public var bitrate: Int?
    public var sampleRate: Int?
    public var bitDepth: Int?
    public var sizeBytes: Int64?
    public var source: SongInfoSource = .found
    public var addedAtSeconds: Int64 = 0
    public var plays: Int = 0
    public var lastPlayedAt: Int64 = 0
    public var rating: Int = 0
    public var trackGain: Double?
    public var albumGain: Double?
    public var trackPeak: Double?
    public var albumPeak: Double?
    public var originalYear: Int?
    public var genres: [String] = []
    public var composer: String?
    public var bpm: Int?
    public var comment: String?
    public var explicit: Bool?
    public var discTitle: String?
    public var mbRecordingId: String?
    public var mbAlbumId: String?
    public var mbReleaseGroupId: String?
    public var mbArtistIds: [String] = []
    /// Which of Octo's radio sources suggested it.
    public var suggestedBy: String?

    public init(title: String, artist: String, album: String) {
        self.title = title
        self.artist = artist
        self.album = album
    }
}

/// One line of the info page. A copyable one gets a Copy button.
public struct InfoLine: Equatable, Sendable {
    public var label: String
    public var value: String
    public var copyable: Bool

    public init(_ label: String, _ value: String, copyable: Bool = false) {
        self.label = label
        self.value = value
        self.copyable = copyable
    }
}

private func blank(_ text: String?) -> Bool { text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }

/// The page's lines, in reading order, leaving out whatever is not known.
public func infoLines(_ facts: SongInfoFacts, zone: TimeZone = .current, locale: Locale = .current) -> [InfoLine] {
    var out: [InfoLine] = []
    out.append(InfoLine("Title", facts.title))
    if !blank(facts.artist) { out.append(InfoLine("Artist", facts.artist)) }
    if !blank(facts.album) { out.append(InfoLine("Album", facts.album)) }
    if let value = facts.albumArtist, !blank(value) { out.append(InfoLine("Album artist", value)) }
    if let value = facts.composer, !blank(value) { out.append(InfoLine("Composer", value)) }
    let year = facts.year.flatMap { $0 > 0 ? $0 : nil }
    if let year { out.append(InfoLine("Year", String(year))) }
    if let original = facts.originalYear, original > 0, original != year { out.append(InfoLine("Original year", String(original))) }
    var seen = Set<String>()
    let genres = ([facts.genre] + facts.genres).filter { !blank($0) }.filter { seen.insert($0.lowercased()).inserted }
    if !genres.isEmpty { out.append(InfoLine(genres.count == 1 ? "Genre" : "Genres", genres.joined(separator: ", "))) }
    if let track = facts.trackNo, track > 0 { out.append(InfoLine("Track", String(track))) }
    if let disc = facts.discNo, disc > 0 {
        let title = facts.discTitle.flatMap { blank($0) ? nil : $0 }
        out.append(InfoLine("Disc", title.map { "\(disc) · \($0)" } ?? String(disc)))
    }
    if let bpm = facts.bpm, bpm > 0 { out.append(InfoLine("BPM", String(bpm))) }
    if let explicit = facts.explicit { out.append(InfoLine("Lyrics", explicit ? "Explicit" : "Clean")) }
    if let comment = facts.comment, !blank(comment) { out.append(InfoLine("Comment", comment)) }

    if facts.durationMs > 0 { out.append(InfoLine("Length", asClock(Int(facts.durationMs / 1_000)))) }
    if let format = formatName(facts.mimeType) { out.append(InfoLine("Format", format)) }
    if let mime = facts.mimeType, !blank(mime) { out.append(InfoLine("File type", mime)) }
    if let bitrate = facts.bitrate, bitrate > 0 { out.append(InfoLine("Bitrate", bitrateText(bitrate))) }
    if let rate = facts.sampleRate, rate > 0 { out.append(InfoLine("Sample rate", sampleRateText(rate))) }
    if let depth = facts.bitDepth, depth > 0 { out.append(InfoLine("Bit depth", "\(depth)-bit")) }
    if let size = facts.sizeBytes, size > 0 { out.append(InfoLine("File size", sizeText(size))) }

    switch facts.source {
    case .phone(let path):
        out.append(InfoLine("Source", "This phone"))
        if let path { out.append(InfoLine("Path", path, copyable: true)) }
    case .server(let name, let downloadedTo):
        out.append(InfoLine("Source", name ?? "Your server"))
        if let downloadedTo { out.append(InfoLine("Downloaded to", downloadedTo, copyable: true)) }
    case .found:
        out.append(InfoLine("Source", "Found online"))
    }
    if let by = facts.suggestedBy, !blank(by) { out.append(InfoLine("Suggested by", by)) }
    if facts.addedAtSeconds > 0 { out.append(InfoLine("Added", dateText(facts.addedAtSeconds * 1_000, zone: zone, locale: locale))) }
    out.append(InfoLine("Plays", grouped(facts.plays)))
    if facts.lastPlayedAt > 0 { out.append(InfoLine("Last played", dateText(facts.lastPlayedAt, zone: zone, locale: locale))) }
    if facts.rating > 0 { out.append(InfoLine("Rating", facts.rating == 1 ? "1 star" : "\(facts.rating) stars")) }

    if let gain = facts.trackGain { out.append(InfoLine("Track gain", gainText(gain))) }
    if let peak = facts.trackPeak { out.append(InfoLine("Track peak", peakText(peak))) }
    if let gain = facts.albumGain { out.append(InfoLine("Album gain", gainText(gain))) }
    if let peak = facts.albumPeak { out.append(InfoLine("Album peak", peakText(peak))) }

    if let id = facts.mbRecordingId { out.append(InfoLine("Recording MBID", id, copyable: true)) }
    if let id = facts.mbAlbumId { out.append(InfoLine("Release MBID", id, copyable: true)) }
    if let id = facts.mbReleaseGroupId { out.append(InfoLine("Release group MBID", id, copyable: true)) }
    if !facts.mbArtistIds.isEmpty {
        out.append(InfoLine(facts.mbArtistIds.count == 1 ? "Artist MBID" : "Artist MBIDs", facts.mbArtistIds.joined(separator: "\n"),
                            copyable: true))
    }
    return out
}

private let losslessCodecs: Set<String> = ["FLAC", "ALAC", "WAV"]

/// The codec, from the file's type, and whether it is lossless.
public func formatName(_ mimeType: String?) -> String? {
    guard let codec = codecName(mimeType) else { return nil }
    return losslessCodecs.contains(codec) ? "\(codec), lossless" : codec
}

public func bitrateText(_ bitsPerSecond: Int) -> String { "\((bitsPerSecond + 500) / 1000) kbps" }

/// 44100 reads as "44.1 kHz", 48000 as "48 kHz".
public func sampleRateText(_ hz: Int) -> String {
    hz % 1000 == 0 ? "\(hz / 1000) kHz" : String(format: "%.1f kHz", Double(hz) / 1000)
}

/// Kilobytes under a megabyte, megabytes under a gigabyte, gigabytes above.
public func sizeText(_ bytes: Int64) -> String {
    if bytes < 1_000_000 { return String(format: "%.0f KB", Double(bytes) / 1_000) }
    if bytes < 1_000_000_000 { return String(format: "%.1f MB", Double(bytes) / 1_000_000) }
    return String(format: "%.2f GB", Double(bytes) / 1_000_000_000)
}

/// With its sign, like "+1.50 dB" or "-6.20 dB".
public func gainText(_ db: Double) -> String { String(format: "%+.2f dB", db) }

public func peakText(_ peak: Double) -> String { String(format: "%.3f", peak) }

/// "14 Nov 2023".
public func dateText(_ epochMs: Int64, zone: TimeZone = .current, locale: Locale = .current) -> String {
    let format = DateFormatter()
    format.locale = locale
    format.timeZone = zone
    format.dateFormat = "d MMM yyyy"
    return format.string(from: Date(timeIntervalSince1970: Double(epochMs) / 1_000))
}

/// Whether a type of audio is lossless.
public func isLosslessMime(_ mimeType: String?) -> Bool { downloadIsLossless(mimeType) }
