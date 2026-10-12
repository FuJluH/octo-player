import Foundation

/// One copy of a song: a file on the phone, a stream from a server, or a download kept on the
/// phone. Several copies of the same recording make one library song.
public struct SongCopy: Sendable, Equatable, Hashable {
    public var id: String
    /// "server:<host>" for a server, "download" for a download, anything else the phone.
    public var sourceId: String
    /// The song's id where it lives (the server's id for a server copy).
    public var nativeId: String
    public var uri: String?
    public var mimeType: String?
    public var sizeBytes: Int?
    /// Bits a second; a value under 10 000 is kilobits.
    public var bitrate: Int?
    public var sampleRate: Int?
    public var bitDepth: Int?
    public var durationMs: Int
    public var bpm: Int?
    public var trackGain: Double?
    public var trackPeak: Double?
    public var albumGain: Double?
    public var albumPeak: Double?

    public init(id: String, sourceId: String, nativeId: String, uri: String? = nil, mimeType: String? = nil, sizeBytes: Int? = nil,
                bitrate: Int? = nil, sampleRate: Int? = nil, bitDepth: Int? = nil, durationMs: Int = 0, bpm: Int? = nil,
                trackGain: Double? = nil, trackPeak: Double? = nil, albumGain: Double? = nil, albumPeak: Double? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.nativeId = nativeId
        self.uri = uri
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.bitrate = bitrate
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.durationMs = durationMs
        self.bpm = bpm
        self.trackGain = trackGain
        self.trackPeak = trackPeak
        self.albumGain = albumGain
        self.albumPeak = albumPeak
    }

    /// A copy from a server streams; any other copy is a file on the phone.
    public var isServerCopy: Bool { sourceId.hasPrefix("server:") }

    /// The loudness a copy's source keeps for it, if any.
    public var storedLoudness: ReplayGainInfo? {
        ReplayGainTags.stored(trackGain: trackGain, trackPeak: trackPeak, albumGain: albumGain, albumPeak: albumPeak)
    }
}

/// The copy of a song to play. The setting decides between copies that can play right now: a
/// server's when one can be reached, the phone's while its file is still there. When none can,
/// one is still handed over, so it fails and is skipped like any song that cannot play. A tie
/// goes to the phone.
public func chooseCopy(_ copies: [SongCopy], _ preference: CopyPreference, serverReachable: Bool,
                       phoneFileMissing: (SongCopy) -> Bool = { _ in false }) -> SongCopy? {
    // A stable sort: phone copies first, each side in its own order.
    let ordered = copies.filter { !$0.isServerCopy } + copies.filter(\.isServerCopy)
    let playable = ordered.filter { $0.isServerCopy ? serverReachable : !phoneFileMissing($0) }
    let pool = playable.isEmpty ? ordered : playable
    guard var best = pool.first else { return nil }
    for next in pool.dropFirst() where compareQuality(next, best) > 0 { best = next }
    switch preference {
    case .phoneFirst: return pool.first { !$0.isServerCopy } ?? best
    case .bestQuality: return best
    }
}

/// The copy to play when the song may also be downloaded. A download plays like a file on the
/// phone, ahead of any stream, unless streaming is preferred right now (`streamInstead`) and the
/// server can be reached.
public func chooseCopy(_ copies: [SongCopy], download: SongCopy?, streamInstead: Bool, _ preference: CopyPreference,
                       serverReachable: Bool, phoneFileMissing: (SongCopy) -> Bool = { _ in false }) -> SongCopy? {
    guard let download, !(streamInstead && serverReachable) else {
        return chooseCopy(copies, preference, serverReachable: serverReachable, phoneFileMissing: phoneFileMissing)
    }
    return chooseCopy(copies.filter { !$0.isServerCopy } + [download], preference, serverReachable: false, phoneFileMissing: phoneFileMissing)
}

/// Where downloads sit among a song's copies.
public let downloadSource = "download"

/// A downloaded file of a server copy, as one more copy of the song: the server's copy, but in
/// the file, and as big as the file is. A download made smaller than the server's file keeps only
/// what is still true of it.
public func downloadedCopy(_ server: SongCopy, uri: String, format: String?, sizeBytes: Int) -> SongCopy {
    let same = format == nil || format == server.mimeType
    var copy = server
    copy.id = "\(downloadSource):\(server.id)"
    copy.sourceId = downloadSource
    copy.uri = uri
    copy.mimeType = format ?? server.mimeType
    copy.sizeBytes = sizeBytes > 0 ? sizeBytes : server.sizeBytes
    copy.bitrate = same ? server.bitrate : nil
    copy.sampleRate = same ? server.sampleRate : nil
    copy.bitDepth = same ? server.bitDepth : nil
    return copy
}

/// Above zero when `a` sounds better than `b`: lossless beats lossy, then the higher sample rate,
/// the deeper bits, and last the higher bitrate. A fact only one of them has is skipped.
public func compareQuality(_ a: SongCopy, _ b: SongCopy) -> Int {
    let lossless = (isLossless(a.mimeType) ? 1 : 0) - (isLossless(b.mimeType) ? 1 : 0)
    if lossless != 0 { return lossless }
    let rate = compareKnown(a.sampleRate, b.sampleRate)
    if rate != 0 { return rate }
    let bits = compareKnown(a.bitDepth, b.bitDepth)
    if bits != 0 { return bits }
    return compareKnown(bitrateOf(a), bitrateOf(b))
}

private func compareKnown(_ a: Int?, _ b: Int?) -> Int {
    guard let a, let b, a > 0, b > 0 else { return 0 }
    return a < b ? -1 : (a > b ? 1 : 0)
}

private let losslessTypes: Set<String> = [
    "audio/flac", "audio/x-flac", "audio/alac", "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave",
    "audio/aiff", "audio/x-aiff", "audio/ape", "audio/x-ape", "audio/wavpack", "audio/x-wavpack",
]

public func isLossless(_ mimeType: String?) -> Bool {
    guard let mimeType else { return false }
    return losslessTypes.contains(mimeType.lowercased())
}

/// Bits per second, as the source says, or worked out from the file's size and length. Servers
/// speak in kilobits, so a small number is read as that.
public func bitrateOf(_ copy: SongCopy) -> Int? {
    if let rate = copy.bitrate, rate > 0 { return rate < 10_000 ? rate * 1000 : rate }
    guard let size = copy.sizeBytes, size > 0, copy.durationMs > 0 else { return nil }
    let seconds = Double(copy.durationMs) / 1000.0
    return Int(Double(size * 8) / seconds)
}

/// What to ask the server for: its file as it is, or an MP3 capped at `maxKbps`. MP3 because
/// every server that makes smaller streams offers it, and a constant-bitrate MP3 has a length the
/// player can seek in and blend.
public struct StreamRequest: Sendable, Hashable {
    public var maxKbps: Int?

    public init(_ maxKbps: Int?) { self.maxKbps = maxKbps }

    public var params: [(String, String)] {
        guard let maxKbps else { return [("format", "raw")] }
        return [("format", "mp3"), ("maxBitRate", "\(maxKbps)"), ("estimateContentLength", "true")]
    }

    /// What the player will receive, for the quality badge.
    public func mimeType(_ original: String?) -> String? { maxKbps == nil ? original : "audio/mpeg" }
}

/// A lossy file already within the size plays as it is: making it an MP3 would only lose quality.
public func streamRequest(_ mimeType: String?, _ bitrate: Int?, _ quality: StreamQuality) -> StreamRequest {
    guard let cap = quality.kbps else { return StreamRequest(nil) }
    if !isLossless(mimeType), let bitrate, bitrate / 1000 <= cap { return StreamRequest(nil) }
    return StreamRequest(cap)
}

/// The kinds of file the phone opens as they are. Anything else (Ogg, Opus, WMA, Monkey's Audio,
/// WavPack, DSD) is asked for as an MP3, at the quality's cap or 320 kbps for Original.
public func phoneOpens(_ mimeType: String?) -> Bool {
    guard let mime = mimeType?.lowercased(), !mime.isEmpty else { return true }
    return [
        "audio/mpeg", "audio/mp3", "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/aacp", "audio/x-aac",
        "audio/flac", "audio/x-flac", "audio/alac", "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave",
        "audio/aiff", "audio/x-aiff", "audio/x-caf",
    ].contains(mime)
}

/// The request as the phone sends it: `streamRequest`, except that a file the phone cannot open
/// as it is comes as an MP3.
public func phoneRequest(_ mimeType: String?, _ bitrate: Int?, _ quality: StreamQuality) -> StreamRequest {
    let request = streamRequest(mimeType, bitrate, quality)
    if request.maxKbps == nil && !phoneOpens(mimeType) { return StreamRequest(quality.kbps ?? 320) }
    return request
}

/// The song's tempo: the playing copy's, or failing that the first other copy's that has one,
/// since each copy is the same recording.
public func songBpm(_ playing: SongCopy?, _ copies: [SongCopy]) -> Int? {
    if let bpm = playing?.bpm, bpm > 0 { return bpm }
    return copies.lazy.compactMap { $0.bpm.flatMap { $0 > 0 ? $0 : nil } }.first
}

/// The stored loudness to play a song at: the playing copy's, or failing that another copy's of
/// the same song, since each copy is the same recording.
public func storedLoudness(_ playing: SongCopy?, _ copies: [SongCopy]) -> ReplayGainInfo? {
    playing?.storedLoudness ?? copies.lazy.compactMap(\.storedLoudness).first
}

/// A stored tempo the automix analysis can use: none for a missing or nonsense value.
public func tagBpm(_ stored: Int?) -> Double? {
    guard let stored, (1...999).contains(stored) else { return nil }
    return Double(stored)
}

/// How long a song is: what the player measured of its sound (nil while it has not), else
/// `listedMs`.
public func songLengthMs(listedMs: Int, playerMs: Int?) -> Int { playingLengthMs(listedMs: listedMs, playerMs: playerMs) }

/// The quality a stream asks for: this app's, for the connection the phone is on, when it picks;
/// otherwise the file as it is, and the server applies the account's choice.
public func streamQualityFor(appPicks: Bool, onMobile: Bool, prefs: StreamPrefs) -> StreamQuality {
    if !appPicks { return .original }
    return onMobile ? prefs.mobile : prefs.wifi
}
