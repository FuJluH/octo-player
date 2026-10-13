import Foundation

// Reading a live HLS station: its playlists, which segments to fetch, and the sound inside each
// segment (an MPEG transport stream, or packed AAC or MP3), handed on as one plain stream for the
// live decoder.

/// One stream a master playlist offers.
public struct HlsVariant: Sendable, Equatable {
    public var uri: URL
    public var bandwidth: Int
    public var codecs: String

    /// Whether it carries sound only, by its codecs; one that names none is taken as it may.
    public var soundOnly: Bool {
        let named = codecs.lowercased()
        return !named.isEmpty && !named.contains("avc") && !named.contains("hvc") && !named.contains("hev")
    }
}

public struct HlsSegment: Sendable, Equatable {
    public var sequence: Int
    public var uri: URL
    public var seconds: Double
}

/// A media playlist: its segments, how long each runs at most, and whether more will come.
public struct HlsMedia: Sendable, Equatable {
    public var targetSeconds: Double
    public var segments: [HlsSegment]
    public var ended: Bool
    /// Its segments are encrypted, which this app does not read.
    public var encrypted: Bool
    /// Its segments are fragmented MP4, which this app does not read.
    public var fragmentedMp4: Bool
}

public enum HlsPlaylist: Sendable, Equatable {
    /// The streams to choose from, and the separate sound streams named for them.
    case master([HlsVariant], audio: [URL])
    case media(HlsMedia)
    /// A plain playlist (M3U) naming whole streams, not segments: its entries in order.
    case plain([URL])
}

/// The longest and shortest a segment's target time is taken to be, in seconds.
public let hlsTargetRange: ClosedRange<Double> = 1...60

/// The highest segment number read; anything above is held there, so counting on never overflows.
public let hlsSequenceCap = 1 << 48

/// Reads a playlist, its addresses taken against `base`; nil for text that is not one. One with
/// no target time, or with entries of unknown length (`#EXTINF:-1`), names whole streams.
public func parseHlsPlaylist(_ text: String, base: URL) -> HlsPlaylist? {
    let lines = text.replacingOccurrences(of: "\r", with: "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    func address(_ line: String) -> URL? { URL(string: line, relativeTo: base)?.absoluteURL }
    let entries = lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }.compactMap(address)
    guard lines.first(where: { !$0.isEmpty })?.hasPrefix("#EXTM3U") == true else {
        // Whole web addresses one to a line, with no header at all.
        let web = lines.filter { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
            .compactMap { URL(string: $0) }
        return web.isEmpty ? nil : .plain(web)
    }
    if lines.contains(where: { $0.hasPrefix("#EXT-X-STREAM-INF") }) {
        var variants: [HlsVariant] = []
        var audio: [URL] = []
        var pending: [String: String]?
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                pending = hlsAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
            } else if line.hasPrefix("#EXT-X-MEDIA:") {
                let attributes = hlsAttributes(String(line.dropFirst("#EXT-X-MEDIA:".count)))
                if attributes["TYPE"] == "AUDIO", let uri = attributes["URI"], let url = address(uri) {
                    audio.append(url)
                }
            } else if let attributes = pending, !line.isEmpty, !line.hasPrefix("#") {
                if let url = address(line) {
                    let bandwidth = Int(attributes["BANDWIDTH"] ?? "").map { min(max($0, 0), 1 << 40) } ?? 0
                    variants.append(HlsVariant(uri: url, bandwidth: bandwidth, codecs: attributes["CODECS"] ?? ""))
                }
                pending = nil
            }
        }
        return .master(variants, audio: audio)
    }
    var target: Double?
    var sequence = 0
    var segments: [HlsSegment] = []
    var seconds: Double?
    var ended = false
    var encrypted = false
    var fragmented = false
    var unknownLength = false
    for line in lines {
        if line.hasPrefix("#EXT-X-TARGETDURATION:") {
            target = Double(line.dropFirst("#EXT-X-TARGETDURATION:".count).trimmingCharacters(in: .whitespaces))
        } else if line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:") {
            let number = Int(line.dropFirst("#EXT-X-MEDIA-SEQUENCE:".count).trimmingCharacters(in: .whitespaces)) ?? 0
            sequence = min(max(number, 0), hlsSequenceCap)
        } else if line.hasPrefix("#EXTINF:") {
            let length = Double(line.dropFirst("#EXTINF:".count).split(separator: ",").first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 0
            if length < 0 { unknownLength = true }
            seconds = length.isFinite ? min(max(length, 0), 3_600) : 0
        } else if line.hasPrefix("#EXT-X-ENDLIST") {
            ended = true
        } else if line.hasPrefix("#EXT-X-KEY:") {
            let method = hlsAttributes(String(line.dropFirst("#EXT-X-KEY:".count)))["METHOD"] ?? "NONE"
            if method != "NONE" { encrypted = true }
        } else if line.hasPrefix("#EXT-X-MAP:") {
            fragmented = true
        } else if !line.isEmpty, !line.hasPrefix("#") {
            if let url = address(line), let length = seconds {
                segments.append(HlsSegment(sequence: sequence + segments.count, uri: url, seconds: length))
            }
            seconds = nil
        }
    }
    guard let target, !unknownLength else { return entries.isEmpty ? nil : .plain(entries) }
    let held = target.isFinite ? min(max(target, hlsTargetRange.lowerBound), hlsTargetRange.upperBound) : 6
    return .media(HlsMedia(targetSeconds: held, segments: segments, ended: ended, encrypted: encrypted, fragmentedMp4: fragmented))
}

/// A tag's attributes, `NAME=value` or `NAME="value"`, split on commas outside quotes.
func hlsAttributes(_ text: String) -> [String: String] {
    var out: [String: String] = [:]
    var name = ""
    var value = ""
    var inValue = false
    var quoted = false
    func finish() {
        let key = name.trimmingCharacters(in: .whitespaces)
        if !key.isEmpty { out[key] = value }
        name = ""
        value = ""
        inValue = false
    }
    for char in text {
        if quoted {
            if char == "\"" { quoted = false } else { value.append(char) }
        } else if char == "\"" && inValue {
            quoted = true
        } else if char == "=" && !inValue {
            inValue = true
        } else if char == "," {
            finish()
        } else if inValue {
            value.append(char)
        } else {
            name.append(char)
        }
    }
    finish()
    return out
}

/// The stream to play from a master playlist: the richest that carries sound only, else a sound
/// stream named apart, else the leanest of the rest, whose sound is taken from it.
public func hlsPickStream(_ variants: [HlsVariant], audio: [URL]) -> URL? {
    if let best = variants.filter(\.soundOnly).max(by: { $0.bandwidth < $1.bandwidth }) { return best.uri }
    if let separate = audio.first { return separate }
    return variants.min(by: { $0.bandwidth < $1.bandwidth })?.uri
}

/// The segments to fetch next: after the last one fetched, or, starting a live playlist, its last
/// three, so play starts near the live edge. A playlist that has ended starts at its first.
public func hlsNextSegments(_ media: HlsMedia, after last: Int?) -> [HlsSegment] {
    guard let last else { return media.ended ? media.segments : Array(media.segments.suffix(3)) }
    let newer = media.segments.filter { $0.sequence > last }
    // Fallen behind past what the playlist still lists: back to its live edge.
    if let first = media.segments.first, first.sequence > last + 1, !media.ended { return Array(newer.suffix(3)) }
    return newer
}

/// The kind of sound a segment carries, as the live decoder is told it.
public enum HlsSound: String, Sendable {
    case aac = "audio/aac"
    case mpeg = "audio/mpeg"
}

/// The plain sound in one segment, and its kind: a transport stream is unpacked, an ID3 tag at
/// the front of packed sound is cut off. Nil for a segment this app does not read (fragmented
/// MP4, or no sound it knows).
public func hlsSegmentSound(_ data: Data) -> (sound: Data, kind: HlsSound)? {
    if data.count >= 188, data[data.startIndex] == 0x47, data.count < 376 || data[data.startIndex + 188] == 0x47 {
        var demuxer = TransportDemuxer()
        let sound = demuxer.feed(data)
        guard let kind = demuxer.sound, !sound.isEmpty else { return nil }
        return (sound, kind)
    }
    let packed = withoutId3(data)
    guard packed.count >= 2 else { return nil }
    let first = packed[packed.startIndex], second = packed[packed.startIndex + 1]
    guard first == 0xFF else { return nil }
    if second & 0xF6 == 0xF0 { return (packed, .aac) }
    if second & 0xE0 == 0xE0 && second & 0x06 != 0 { return (packed, .mpeg) }
    return nil
}

/// The bytes after any ID3v2 tags at the front.
public func withoutId3(_ data: Data) -> Data {
    var rest = Data(data)
    while rest.count >= 10, rest[0] == 0x49, rest[1] == 0x44, rest[2] == 0x33 {
        let size = (Int(rest[6] & 0x7F) << 21) | (Int(rest[7] & 0x7F) << 14) | (Int(rest[8] & 0x7F) << 7) | Int(rest[9] & 0x7F)
        let footer = rest[5] & 0x10 != 0 ? 10 : 0
        let total = 10 + size + footer
        guard total <= rest.count else { return Data() }
        rest = Data(rest.dropFirst(total))
    }
    return rest
}

/// Takes the sound out of an MPEG transport stream: the program's first AAC (ADTS) or MPEG
/// audio stream, its packets' payloads joined, their PES headers cut off. Bytes may come in any
/// pieces.
public struct TransportDemuxer: Sendable {
    /// The kind of sound found, once the program table named it.
    public private(set) var sound: HlsSound?
    private var programTable: Int?
    private var soundPid: Int?
    private var carry = Data()

    public init() {}

    public mutating func feed(_ data: Data) -> Data {
        carry.append(data)
        var out = Data()
        var at = 0
        let bytes = [UInt8](carry)
        while bytes.count - at >= 188 {
            guard bytes[at] == 0x47 else {
                // Lost step: find the next packet start.
                at += 1
                continue
            }
            packet(bytes[at..<(at + 188)], into: &out)
            at += 188
        }
        carry = Data(bytes[at...])
        return out
    }

    private mutating func packet(_ p: ArraySlice<UInt8>, into out: inout Data) {
        let s = p.startIndex
        let unitStart = p[s + 1] & 0x40 != 0
        let pid = (Int(p[s + 1] & 0x1F) << 8) | Int(p[s + 2])
        let control = (p[s + 3] >> 4) & 0x03
        var start = s + 4
        if control == 2 || control == 0 { return }
        if control == 3 { start += 1 + Int(p[s + 4]) }
        guard start < p.endIndex else { return }
        let payload = p[start..<p.endIndex]
        if pid == 0 {
            if unitStart { readPat(payload) }
        } else if pid == programTable {
            if unitStart { readPmt(payload) }
        } else if pid == soundPid {
            if unitStart {
                let b = payload.startIndex
                guard payload.count >= 9, payload[b] == 0, payload[b + 1] == 0, payload[b + 2] == 1 else { return }
                let headerEnd = b + 9 + Int(payload[b + 8])
                guard headerEnd <= payload.endIndex else { return }
                out.append(contentsOf: payload[headerEnd..<payload.endIndex])
            } else {
                out.append(contentsOf: payload)
            }
        }
    }

    /// The section after its pointer field, and its length.
    private func section(_ payload: ArraySlice<UInt8>) -> ArraySlice<UInt8>? {
        guard let pointer = payload.first else { return nil }
        let begin = payload.startIndex + 1 + Int(pointer)
        guard begin + 3 <= payload.endIndex else { return nil }
        let length = (Int(payload[begin + 1] & 0x0F) << 8) | Int(payload[begin + 2])
        let end = min(payload.endIndex, begin + 3 + length)
        return payload[begin..<end]
    }

    private mutating func readPat(_ payload: ArraySlice<UInt8>) {
        guard let table = section(payload), table.count >= 12, table[table.startIndex] == 0x00 else { return }
        var at = table.startIndex + 8
        while at + 4 <= table.endIndex - 4 {
            let program = (Int(table[at]) << 8) | Int(table[at + 1])
            let pid = (Int(table[at + 2] & 0x1F) << 8) | Int(table[at + 3])
            if program != 0 {
                programTable = pid
                return
            }
            at += 4
        }
    }

    private mutating func readPmt(_ payload: ArraySlice<UInt8>) {
        guard let table = section(payload), table.count >= 16, table[table.startIndex] == 0x02 else { return }
        let b = table.startIndex
        let infoLength = (Int(table[b + 10] & 0x0F) << 8) | Int(table[b + 11])
        var at = b + 12 + infoLength
        while at + 5 <= table.endIndex - 4 {
            let type = table[at]
            let pid = (Int(table[at + 1] & 0x1F) << 8) | Int(table[at + 2])
            let esInfo = (Int(table[at + 3] & 0x0F) << 8) | Int(table[at + 4])
            switch type {
            case 0x0F:
                soundPid = pid
                sound = .aac
                return
            case 0x03, 0x04:
                soundPid = pid
                sound = .mpeg
                return
            default:
                at += 5 + esInfo
            }
        }
    }
}

// MARK: Following a live playlist

/// What to do with a live playlist just read.
public enum HlsStep: Sendable, Equatable {
    /// Fetch these segments (none when it has not grown), then read it again after `reloadSeconds`.
    case fetch([HlsSegment], reloadSeconds: Double)
    /// It has not grown for three of its target times: the stream is treated as lost.
    case stalled
    /// It has ended and every segment was fetched.
    case finished
}

/// Follows a live playlist from one reading to the next: which segments are new, a restart of
/// its numbering, and a stream that stopped growing.
public struct HlsFollower: Sendable, Equatable {
    /// The last segment fetched.
    public private(set) var last: Int?
    /// When the playlist last brought a new segment, in ms.
    private var grewAt: Int64?

    /// How many target times without a new segment count as a stall.
    public static let stallTargets = 3.0

    public init() {}

    public mutating func step(_ media: HlsMedia, now: Int64) -> HlsStep {
        // Numbered anew below what was fetched (the station restarted it): back to its live edge.
        if let last, let newest = media.segments.last?.sequence, newest < last { self.last = nil }
        let next = hlsNextSegments(media, after: last)
        if !next.isEmpty {
            grewAt = now
            return .fetch(next, reloadSeconds: media.targetSeconds)
        }
        if media.ended { return .finished }
        let since = grewAt ?? now
        if grewAt == nil { grewAt = now }
        if Double(now - since) >= Self.stallTargets * media.targetSeconds * 1000 { return .stalled }
        return .fetch([], reloadSeconds: media.targetSeconds / 2)
    }

    /// A segment was fetched (or passed over), so the next reading starts after it.
    public mutating func fetched(_ segment: HlsSegment) { last = segment.sequence }
}

/// What a stretch of sound's first frame says of its format (kind, sample rate, channels), to
/// tell when a stream changes format part way; nil when no frame start is found near its front.
public func hlsSoundFormat(_ sound: Data, kind: HlsSound) -> UInt32? {
    let bytes = [UInt8](sound.prefix(4_096))
    guard bytes.count >= 4 else { return nil }
    for at in 0..<(bytes.count - 3) where bytes[at] == 0xFF {
        let b1 = bytes[at + 1], b2 = bytes[at + 2], b3 = bytes[at + 3]
        switch kind {
        case .aac where b1 & 0xF6 == 0xF0:
            // Profile, sample rate and channel layout.
            return 0x0100_0000 | UInt32(b2 & 0xFD) << 8 | UInt32(b3 & 0xC0)
        case .mpeg where b1 & 0xE0 == 0xE0 && b1 & 0x06 != 0 && b2 & 0x0C != 0x0C:
            // Version and layer, sample rate, and channel mode.
            return 0x0200_0000 | UInt32(b1 & 0x1E) << 16 | UInt32(b2 & 0x0C) << 8 | UInt32(b3 & 0xC0)
        default:
            continue
        }
    }
    return nil
}

/// Whether the first bytes of an answer are a playlist's (`#EXTM3U`, after any byte order mark
/// or blank space).
public func startsLikePlaylist(_ data: Data) -> Bool {
    var bytes = [UInt8](data.prefix(64))
    if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
    let text = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.hasPrefix("#EXTM3U")
}

/// The types an HLS playlist is sent as; the first is the one a station flagged as HLS is
/// queued with.
public let hlsPlaylistTypes: [String] = ["application/vnd.apple.mpegurl", "application/x-mpegurl", "audio/mpegurl", "audio/x-mpegurl"]

/// Whether a type names an HLS playlist.
public func isHlsPlaylistType(_ type: String?) -> Bool {
    hlsPlaylistTypes.contains(type?.lowercased().trimmingCharacters(in: .whitespaces) ?? "")
}
