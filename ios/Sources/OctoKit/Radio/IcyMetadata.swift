import Foundation

/// Splits a live stream sent with ICY metadata into its sound and its titles. The station sends
/// `interval` bytes of sound, then one byte giving the metadata's length in 16-byte blocks, then
/// the metadata itself, over and over; any of it may be cut across reads.
public struct IcyReader: Sendable {
    public let interval: Int
    private var soundLeft: Int
    /// The metadata bytes still to come, nil while sound or the length byte is next.
    private var metaLeft: Int?
    private var meta = Data()

    public init(interval: Int) {
        self.interval = max(1, interval)
        soundLeft = max(1, interval)
    }

    /// The sound in `data`, and what each metadata block it finished names, in order. A block
    /// with an empty title is kept, since it says the station names nothing now; a block with no
    /// StreamTitle at all gives none.
    public mutating func feed(_ data: Data) -> (sound: Data, titles: [IcyMeta]) {
        let read = feedMarked(data)
        return (read.sound, read.titles.map(\.meta))
    }

    /// The same, with where each block sat in the sound given back: `at` sound bytes of this read
    /// came before it, so its title belongs to what plays once they have.
    public mutating func feedMarked(_ data: Data) -> (sound: Data, titles: [IcyMark]) {
        var sound = Data()
        var titles: [IcyMark] = []
        var at = data.startIndex
        while at < data.endIndex {
            if let left = metaLeft {
                let take = min(left, data.endIndex - at)
                meta.append(data[at..<(at + take)])
                at += take
                if take == left {
                    if let named = icyMeta(meta) { titles.append(IcyMark(at: sound.count, meta: named)) }
                    meta.removeAll(keepingCapacity: true)
                    metaLeft = nil
                    soundLeft = interval
                } else {
                    metaLeft = left - take
                }
            } else if soundLeft == 0 {
                let length = Int(data[at]) * 16
                at += 1
                if length == 0 {
                    soundLeft = interval
                } else {
                    metaLeft = length
                }
            } else {
                let take = min(soundLeft, data.endIndex - at)
                sound.append(data[at..<(at + take)])
                at += take
                soundLeft -= take
            }
        }
        return (sound, titles)
    }
}

/// A metadata block and where it sat: after `at` bytes of the sound given back with it.
public struct IcyMark: Sendable, Equatable {
    public var at: Int
    public var meta: IcyMeta

    public init(at: Int, meta: IcyMeta) {
        self.at = at
        self.meta = meta
    }
}

/// Titles held until the sound sent before them has been read, so a title changes when the
/// song it names starts to play instead of when its bytes arrive. Positions count every sound
/// byte the stream has given, across reconnects.
public struct IcyTitleQueue: Sendable {
    private var waiting: [(at: Int64, meta: IcyMeta)] = []

    public init() {}

    /// Holds a title that comes after `at` sound bytes of the stream.
    public mutating func hold(_ meta: IcyMeta, at: Int64) {
        waiting.append((at, meta))
    }

    /// The titles whose sound before them has all been read once `read` bytes have, in order.
    public mutating func due(read: Int64) -> [IcyMeta] {
        guard let first = waiting.first, first.at <= read else { return [] }
        let count = waiting.prefix { $0.at <= read }.count
        let ready = waiting.prefix(count).map(\.meta)
        waiting.removeFirst(count)
        return ready
    }

    public var isEmpty: Bool { waiting.isEmpty }
}

/// What one ICY metadata block names: its StreamTitle, trimmed, and the address sent with it
/// (StreamArtwork, else StreamUrl), empty when there is none.
public struct IcyMeta: Sendable, Equatable, Hashable {
    public var title: String
    public var url: String

    public init(title: String, url: String = "") {
        self.title = title
        self.url = url
    }
}

/// The StreamTitle of an ICY metadata block (`StreamTitle='Artist - Song';StreamUrl='';`) with
/// its address, read as UTF-8 or else Latin-1, or nil when the block has no StreamTitle. The
/// NULs padding the block are dropped.
public func icyMeta(_ block: Data) -> IcyMeta? {
    let fields = icyFields(icyText(block))
    guard let title = fields["StreamTitle"] else { return nil }
    return IcyMeta(title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: icyArtworkField(fields) ?? "")
}

/// A metadata block as text: UTF-8, else Latin-1, without the NULs that pad it.
func icyText(_ block: Data) -> String {
    var bytes = Array(block)
    while bytes.last == 0 { bytes.removeLast() }
    return String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
}

/// The fields of one ICY metadata block, `StreamTitle='...';StreamUrl='...';`, by name, each name
/// once (the first wins). A value ends at a `';` that the next `Key='` or the end of the block
/// follows, so a quote inside a name stays in it ("LA's #1", "I DON'T WANNA MISS A THING"); else
/// at a quote that ends the block, else at the end.
public func icyFields(_ block: String) -> [String: String] {
    var scalars = Array(block.unicodeScalars)
    while scalars.last == "\u{0}" { scalars.removeLast() }
    let text = IcyText(scalars)
    var fields: [String: String] = [:]
    var at = 0
    while at < text.count {
        guard let eq = text.find("='", from: at) else { break }
        var key = text.string(at, eq).trimmingCharacters(in: .whitespacesAndNewlines)
        while key.hasPrefix(";") { key.removeFirst() }
        key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = eq + 2
        let end = text.valueEnd(from: start)
        if !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }), fields[key] == nil {
            fields[key] = text.string(start, end)
        }
        at = min(end + 1, text.count)
        if at < text.count, text[at] == ";" { at += 1 }
    }
    return fields
}

/// The artwork address in a block's StreamArtwork or StreamUrl: the first one not empty.
public func icyArtworkField(_ fields: [String: String]) -> String? {
    [fields["StreamArtwork"], fields["StreamUrl"]]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty }
}

/// A block's text as scalars, read by position.
private struct IcyText {
    let scalars: [Unicode.Scalar]

    init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

    var count: Int { scalars.count }

    subscript(_ index: Int) -> Unicode.Scalar { scalars[index] }

    func string(_ from: Int, _ to: Int) -> String {
        guard from < to else { return "" }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[from..<to])
        return String(view)
    }

    func find(_ pattern: String, from: Int) -> Int? {
        let wanted = Array(pattern.unicodeScalars)
        guard let first = wanted.first else { return nil }
        var at = max(0, from)
        while at + wanted.count <= count {
            if scalars[at] == first, scalars[at..<(at + wanted.count)].elementsEqual(wanted) { return at }
            at += 1
        }
        return nil
    }

    /// Whether only white space follows `from`.
    func isBlank(from: Int) -> Bool {
        scalars[min(from, count)...].allSatisfy(\.properties.isWhitespace)
    }

    /// Whether `Key='` starts at `start`, after any white space.
    func keyStarts(at start: Int) -> Bool {
        var at = start
        while at < count, scalars[at].properties.isWhitespace { at += 1 }
        guard at < count, Self.isAsciiLetter(scalars[at]) else { return false }
        at += 1
        while at < count, Self.isAsciiLetter(scalars[at]) || ("0"..."9").contains(scalars[at]) || scalars[at] == "_" || scalars[at] == "-" {
            at += 1
        }
        return at + 1 < count && scalars[at] == "=" && scalars[at + 1] == "'"
    }

    /// Where a value that starts at `start` ends: at a `';` that the next key or the end of the
    /// block follows, else at a quote that ends the block, else at the end.
    func valueEnd(from start: Int) -> Int {
        var search = start
        while let close = find("';", from: search) {
            let after = close + 2
            if after >= count || keyStarts(at: after) || isBlank(from: after) { return close }
            search = close + 1
        }
        var end = count
        while end > 0, scalars[end - 1].properties.isWhitespace { end -= 1 }
        return end - 1 >= start && scalars[end - 1] == "'" ? end - 1 : count
    }

    private static func isAsciiLetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }
}

/// The waits, in seconds, before each try to reach a live station again once it stopped sending.
/// After the last, it has failed.
public let liveReconnectDelays: [Double] = [1, 2, 4, 8]

/// Whether a live station's HTTP answer is worth asking again: a server that is busy or down
/// for a moment, never one that refused or does not have the stream.
public func liveStatusRetries(_ status: Int) -> Bool {
    status == 408 || status == 429 || status >= 500
}

/// Why a live station stopped, in the words the player shows.
public func stationFailureWords(_ error: PlayError) -> String {
    switch error.code {
    case .networkConnectionFailed, .networkConnectionTimeout, .timeout:
        "The station stopped sending and did not come back."
    case .badHttpStatus:
        "The station's server would not send it."
    case .decodingFormatUnsupported, .decodingFormatExceedsCapabilities, .parsingContainerUnsupported, .parsingManifestUnsupported:
        "Octo can't play this station's format."
    case .parsingContainerMalformed, .parsingManifestMalformed, .decodingFailed:
        "The station sent sound Octo could not read."
    default:
        playFailureOf(error).words
    }
}

/// When to reach a live station again once its connection stopped: after 1, 2, 4 and 8 s, then
/// it has failed. An answer that refused the stream fails at once. A connection that played a
/// good stretch starts the waits over.
public struct LiveReconnect: Sendable, Equatable {
    public enum Decision: Sendable, Equatable {
        case again(after: Double)
        case fail
    }

    /// Tries made since the stream last played a good stretch.
    public private(set) var tries = 0
    /// Sound bytes the connection in use has given.
    private var heard = 0

    /// A connection that gave this much sound played a good stretch.
    public static let goodStretch = 128 << 10

    public init() {}

    /// The connection stopped; `status` is the HTTP status it answered with, when it refused.
    public mutating func lost(status: Int? = nil) -> Decision {
        if let status, !liveStatusRetries(status) { return .fail }
        guard tries < liveReconnectDelays.count else { return .fail }
        let wait = liveReconnectDelays[tries]
        tries += 1
        return .again(after: wait)
    }

    /// A new connection opened.
    public mutating func connected() { heard = 0 }

    /// The connection gave `bytes` of sound.
    public mutating func heard(_ bytes: Int) {
        heard = min(heard + max(0, bytes), Self.goodStretch)
        if heard >= Self.goodStretch { tries = 0 }
    }

    /// Sound came again (a segment arrived): the waits start over.
    public mutating func recovered() { tries = 0 }
}
