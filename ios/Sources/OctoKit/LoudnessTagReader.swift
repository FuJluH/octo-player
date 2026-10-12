import Foundation

/// Finds the loudness tags a song file carries in its own bytes, the way a player reads them as
/// it opens the file: ID3 user text frames (in front of an MP3, or of any other file), the MP3
/// encoder header's gains, Vorbis comments in FLAC and in Ogg (Vorbis, Opus, FLAC), and MP4
/// free-form tags. Pictures and other large parts are stepped over, never read.
public enum LoudnessTagReader {
    /// Reads up to `count` bytes at `offset`: fewer only at the end, nothing when it fails.
    public typealias Read = (_ offset: Int64, _ count: Int) -> [UInt8]?

    /// The most read for one comment block, tag frame or Ogg header; a bigger one is read as far
    /// as this.
    static let largestPart = 1 << 20

    /// The loudness the file's own tags give, or nothing when they give none.
    public static func loudness(length: Int64, read: Read) -> ReplayGainInfo? {
        ReplayGainTags.read(tags(length: length, read: read))
    }

    /// Every loudness-bearing piece of the file, in the order found.
    public static func tags(length: Int64, read: Read) -> [LoudnessTag] {
        var found: [LoudnessTag] = []
        var offset: Int64 = 0
        // One or more ID3 tags can sit in front of the sound.
        while let head = read(offset, 10), head.count == 10, head.starts(with: Array("ID3".utf8)) {
            guard let size = id3Size(head) else { break }
            found += id3UserText(at: offset, head: head, read: read)
            offset += 10 + size + (head[3] >= 4 && head[5] & 0x10 != 0 ? 10 : 0)
        }
        guard let start = read(offset, 12), start.count >= 4 else { return found }
        if start.starts(with: Array("fLaC".utf8)) {
            found += flacComments(at: offset + 4, read: read)
        } else if start.starts(with: Array("OggS".utf8)) {
            found += oggComments(at: offset, read: read)
        } else if start.count >= 8, Array(start[4..<8]) == Array("ftyp".utf8) {
            found += mp4FreeForm(from: offset, length: length, read: read)
        } else if let header = mp3Header(from: offset, read: read) {
            found.append(.mp3Header(header))
        }
        return found
    }

    // MARK: ID3

    /// The size of an ID3 tag's body from its header, or nothing when the header is broken.
    static func id3Size(_ head: [UInt8]) -> Int64? {
        guard (2...4).contains(head[3]), head[6..<10].allSatisfy({ $0 & 0x80 == 0 }) else { return nil }
        return Int64(syncSafe(head[6], head[7], head[8], head[9]))
    }

    static func syncSafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        Int(a) << 21 | Int(b) << 14 | Int(c) << 7 | Int(d)
    }

    static func bigEndian(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reduce(0) { $0 << 8 | Int($1) }
    }

    static func littleEndian(_ bytes: ArraySlice<UInt8>) -> Int {
        bytes.reversed().reduce(0) { $0 << 8 | Int($1) }
    }

    /// The TXXX frames of one ID3 tag, as description and first value.
    static func id3UserText(at offset: Int64, head: [UInt8], read: Read) -> [LoudnessTag] {
        guard let size = id3Size(head) else { return [] }
        let major = head[3]
        let flags = head[5]
        let headerSize = major == 2 ? 6 : 10
        // A tag unsynchronised as a whole is read in one piece and put back first.
        let whole = major < 4 && flags & 0x80 != 0
        var body: [UInt8] = []
        if whole {
            guard let all = read(offset + 10, min(Int(size), largestPart)) else { return [] }
            body = resync(all)
        }
        func bytes(_ at: Int, _ count: Int) -> [UInt8]? {
            if whole {
                guard at >= 0, at < body.count else { return nil }
                return Array(body[at..<min(body.count, at + count)])
            }
            return read(offset + 10 + Int64(at), count)
        }
        var at = 0
        if flags & 0x40 != 0, major >= 3, let ext = bytes(0, 4), ext.count == 4 {
            at = major == 4 ? syncSafe(ext[0], ext[1], ext[2], ext[3]) : bigEndian(ext[0..<4]) + 4
        }
        var found: [LoudnessTag] = []
        while at + headerSize <= Int(size) {
            guard let frame = bytes(at, headerSize), frame.count == headerSize, frame[0] != 0 else { break }
            let idLength = major == 2 ? 3 : 4
            let id = String(decoding: frame[0..<idLength], as: UTF8.self)
            let frameSize = switch major {
            case 2: bigEndian(frame[3..<6])
            case 3: bigEndian(frame[4..<8])
            default: syncSafe(frame[4], frame[5], frame[6], frame[7])
            }
            guard frameSize > 0, at + headerSize + frameSize <= Int(size) else { break }
            if id == "TXXX" || id == "TXX", let data = bytes(at + headerSize, min(frameSize, largestPart)),
               let text = frameData(data, major: major, flags: major == 2 ? 0 : Int(frame[9]) | Int(frame[8]) << 8) {
                found.append(userText(text))
            }
            at += headerSize + frameSize
        }
        return found
    }

    /// A frame's own data, with its format flags undone; nothing for a compressed or encrypted
    /// frame.
    static func frameData(_ data: [UInt8], major: UInt8, flags: Int) -> [UInt8]? {
        var bytes = data
        if major == 3 {
            if flags & 0x80 != 0 || flags & 0x40 != 0 { return nil }
            if flags & 0x20 != 0 { bytes = Array(bytes.dropFirst()) }
        } else if major == 4 {
            if flags & 0x08 != 0 || flags & 0x04 != 0 { return nil }
            if flags & 0x40 != 0 { bytes = Array(bytes.dropFirst()) }
            if flags & 0x01 != 0 { bytes = Array(bytes.dropFirst(4)) }
            if flags & 0x02 != 0 { bytes = resync(bytes) }
        }
        return bytes
    }

    /// Undoes ID3 unsynchronisation: every 0xFF 0x00 pair becomes 0xFF.
    static func resync(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var last: UInt8 = 0
        for byte in bytes {
            if !(last == 0xFF && byte == 0x00) { out.append(byte) }
            last = byte
        }
        return out
    }

    /// A TXXX frame's description and first value.
    static func userText(_ data: [UInt8]) -> LoudnessTag {
        guard let encoding = data.first else { return .id3UserText(description: nil, value: nil) }
        let wide = encoding == 1 || encoding == 2
        let parts = split(Array(data.dropFirst()), wide: wide)
        let description = parts.first.map { decode($0, encoding: encoding) }
        let value = parts.count > 1 ? decode(parts[1], encoding: encoding) : nil
        return .id3UserText(description: description, value: value)
    }

    /// Text split on its terminators: one zero byte, or two on a two-byte boundary for UTF-16.
    static func split(_ bytes: [UInt8], wide: Bool) -> [[UInt8]] {
        var parts: [[UInt8]] = []
        var current: [UInt8] = []
        var i = 0
        while i < bytes.count {
            if wide {
                if i + 1 < bytes.count, bytes[i] == 0, bytes[i + 1] == 0 {
                    parts.append(current)
                    current = []
                } else {
                    current.append(bytes[i])
                    if i + 1 < bytes.count { current.append(bytes[i + 1]) }
                }
                i += 2
            } else {
                if bytes[i] == 0 {
                    parts.append(current)
                    current = []
                } else {
                    current.append(bytes[i])
                }
                i += 1
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    static func decode(_ bytes: [UInt8], encoding: UInt8) -> String {
        switch encoding {
        case 0: return String(bytes.map { Character(Unicode.Scalar($0)) })
        case 1:
            if bytes.starts(with: [0xFF, 0xFE]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16LittleEndian) ?? "" }
            if bytes.starts(with: [0xFE, 0xFF]) { return String(data: Data(bytes.dropFirst(2)), encoding: .utf16BigEndian) ?? "" }
            return String(data: Data(bytes), encoding: .utf16LittleEndian) ?? ""
        case 2: return String(data: Data(bytes), encoding: .utf16BigEndian) ?? ""
        default: return String(decoding: bytes, as: UTF8.self)
        }
    }

    // MARK: MP3 encoder header

    /// The loudness in the encoder's own header of the first MPEG audio frame (Xing or Info,
    /// with the LAME extension), searched for a little way past `offset`.
    static func mp3Header(from offset: Int64, read: Read) -> Mp3InfoReplayGain? {
        guard let window = read(offset, 4_096 + 4) else { return nil }
        var at = 0
        while at + 4 <= window.count {
            if window[at] == 0xFF, window[at + 1] & 0xE0 == 0xE0 {
                let version = (window[at + 1] >> 3) & 3
                let layer = (window[at + 1] >> 1) & 3
                let bitrate = window[at + 2] >> 4
                let rate = (window[at + 2] >> 2) & 3
                if version != 1, layer == 1, bitrate != 0, bitrate != 15, rate != 3 {
                    let mono = window[at + 3] >> 6 == 3
                    let side = version == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17)
                    return xing(at: offset + Int64(at + 4 + side), read: read)
                }
            }
            at += 1
        }
        return nil
    }

    /// The LAME extension's peak and gains, after a Xing or Info header.
    static func xing(at offset: Int64, read: Read) -> Mp3InfoReplayGain? {
        guard let bytes = read(offset, 160), bytes.count >= 8 else { return nil }
        let marker = String(decoding: bytes[0..<4], as: UTF8.self)
        guard marker == "Xing" || marker == "Info" else { return nil }
        let flags = bigEndian(bytes[4..<8])
        var at = 8
        if flags & 1 != 0 { at += 4 }
        if flags & 2 != 0 { at += 4 }
        if flags & 4 != 0 { at += 100 }
        if flags & 8 != 0 { at += 4 }
        // Encoder name (9), revision and lowpass (2), peak (4), two gain fields (4), encoder
        // flags (2) and the gapless lengths (3).
        guard bytes.count - at >= 24 else { return nil }
        at += 11
        let peak = Float(bitPattern: UInt32(bigEndian(bytes[at..<(at + 4)])))
        let field1 = bigEndian(bytes[(at + 4)..<(at + 6)])
        let field2 = bigEndian(bytes[(at + 6)..<(at + 8)])
        return Mp3InfoReplayGain.parse(peak: Double(peak), field1: field1, field2: field2)
    }

    // MARK: Vorbis comments

    /// The comments of a Vorbis comment block: a vendor string, then each "NAME=value", every
    /// length in four little-endian bytes. A block cut short gives the comments it holds whole.
    static func vorbisComments(_ bytes: ArraySlice<UInt8>) -> [LoudnessTag] {
        var at = bytes.startIndex
        func length() -> Int? {
            guard at + 4 <= bytes.endIndex else { return nil }
            defer { at += 4 }
            return littleEndian(bytes[at..<(at + 4)])
        }
        guard let vendor = length(), at + vendor <= bytes.endIndex else { return [] }
        at += vendor
        guard let count = length() else { return [] }
        var found: [LoudnessTag] = []
        for _ in 0..<count {
            guard let size = length(), at + size <= bytes.endIndex else { break }
            let comment = String(decoding: bytes[at..<(at + size)], as: UTF8.self)
            at += size
            if let equals = comment.firstIndex(of: "=") {
                found.append(.vorbisComment(key: String(comment[..<equals]), value: String(comment[comment.index(after: equals)...])))
            }
        }
        return found
    }

    /// The Vorbis comment block of a FLAC file, from its first metadata block on.
    static func flacComments(at offset: Int64, read: Read) -> [LoudnessTag] {
        var at = offset
        for _ in 0..<64 {
            guard let head = read(at, 4), head.count == 4 else { return [] }
            let size = bigEndian(head[1..<4])
            if head[0] & 0x7F == 4 {
                guard let block = read(at + 4, min(size, largestPart)) else { return [] }
                return vorbisComments(block[...])
            }
            if head[0] & 0x80 != 0 { return [] }
            at += 4 + Int64(size)
        }
        return []
    }

    /// The comments in an Ogg file's second packet: Vorbis ("\u{3}vorbis"), Opus ("OpusTags")
    /// or FLAC in Ogg (a Vorbis comment metadata block).
    static func oggComments(at offset: Int64, read: Read) -> [LoudnessTag] {
        var packets: [[UInt8]] = []
        var current: [UInt8] = []
        var at = offset
        var serial: ArraySlice<UInt8>?
        var total = 0
        while packets.count < 2, total < largestPart {
            guard let head = read(at, 27), head.count == 27, head.starts(with: Array("OggS".utf8)) else { break }
            let segments = Int(head[26])
            guard let table = read(at + 27, segments), table.count == segments else { break }
            let size = table.reduce(0) { $0 + Int($1) }
            let pageSerial = head[14..<18]
            let ours = serial.map { $0 == pageSerial } ?? true
            if serial == nil { serial = pageSerial }
            if ours {
                guard let body = read(at + 27 + Int64(segments), size), body.count == size else { break }
                var place = 0
                for lace in table {
                    current += body[place..<(place + Int(lace))]
                    place += Int(lace)
                    if lace < 255 {
                        packets.append(current)
                        current = []
                        if packets.count == 2 { break }
                    }
                }
                total += size
            }
            at += 27 + Int64(segments) + Int64(size)
        }
        if packets.count < 2, !current.isEmpty { packets.append(current) }
        guard packets.count >= 2 else { return [] }
        let first = packets[0]
        let comment = packets[1]
        if comment.starts(with: [3] + Array("vorbis".utf8)) { return vorbisComments(comment[7...]) }
        if comment.starts(with: Array("OpusTags".utf8)) { return vorbisComments(comment[8...]) }
        if first.starts(with: [0x7F] + Array("FLAC".utf8)), comment.count >= 4, comment[0] & 0x7F == 4 {
            return vorbisComments(comment[4...])
        }
        return []
    }

    // MARK: MP4

    /// The free-form ("----") items of an MP4 file's iTunes-style tag list: moov, udta, meta,
    /// ilst.
    static func mp4FreeForm(from offset: Int64, length: Int64, read: Read) -> [LoudnessTag] {
        guard let moov = box("moov", in: offset..<length, read: read),
              let udta = box("udta", in: moov, read: read),
              let meta = box("meta", in: udta, read: read)
        else { return [] }
        // The tag list's "meta" is usually a full box (four bytes of version and flags first);
        // a QuickTime file's starts with its handler at once.
        let peek = read(meta.lowerBound, 8) ?? []
        let listed = peek.count == 8 && Array(peek[4..<8]) == Array("hdlr".utf8) ? meta : (meta.lowerBound + 4)..<meta.upperBound
        guard let ilst = box("ilst", in: listed, read: read) else { return [] }
        var found: [LoudnessTag] = []
        for item in boxes(in: ilst, read: read) where item.type == "----" {
            var domain: String?
            var name: String?
            var value: String?
            for part in boxes(in: item.body, read: read) {
                let size = Int(part.body.upperBound - part.body.lowerBound)
                guard size >= 4, size <= largestPart, let bytes = read(part.body.lowerBound, size), bytes.count == size else { continue }
                switch part.type {
                case "mean": domain = String(decoding: bytes.dropFirst(4), as: UTF8.self)
                case "name": name = String(decoding: bytes.dropFirst(4), as: UTF8.self)
                case "data" where size >= 8 && value == nil: value = String(decoding: bytes.dropFirst(8), as: UTF8.self)
                default: break
                }
            }
            if let domain, let name, let value { found.append(.mp4FreeForm(domain: domain, name: name, value: value)) }
        }
        return found
    }

    /// One box inside a range: its type and the range of its body.
    struct Box {
        let type: String
        let body: Range<Int64>
    }

    static func boxes(in range: Range<Int64>, read: Read) -> [Box] {
        var found: [Box] = []
        var at = range.lowerBound
        while at + 8 <= range.upperBound, found.count < 4_096 {
            guard let head = read(at, 16), head.count >= 8 else { break }
            var size = Int64(bigEndian(head[0..<4]))
            var start = at + 8
            if size == 1 {
                guard head.count == 16 else { break }
                size = Int64(bigEndian(head[8..<16]))
                start = at + 16
            } else if size == 0 {
                size = range.upperBound - at
            }
            guard size >= start - at, at + size <= range.upperBound else { break }
            found.append(Box(type: String(decoding: head[4..<8], as: UTF8.self), body: start..<(at + size)))
            at += size
        }
        return found
    }

    static func box(_ type: String, in range: Range<Int64>, read: Read) -> Range<Int64>? {
        boxes(in: range, read: read).first { $0.type == type }?.body
    }
}
