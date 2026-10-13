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

    /// The sound in `data`, and each title a metadata block in it finished, in order. A block
    /// with no title or an empty one gives none.
    public mutating func feed(_ data: Data) -> (sound: Data, titles: [String]) {
        var sound = Data()
        var titles: [String] = []
        var at = data.startIndex
        while at < data.endIndex {
            if let left = metaLeft {
                let take = min(left, data.endIndex - at)
                meta.append(data[at..<(at + take)])
                at += take
                if take == left {
                    if let title = icyStreamTitle(meta) { titles.append(title) }
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

/// The StreamTitle in an ICY metadata block (`StreamTitle='Artist - Song';StreamUrl='';`), read
/// as UTF-8 or else Latin-1; nil when it has none or it is blank.
public func icyStreamTitle(_ block: Data) -> String? {
    let bytes = Array(block.prefix { $0 != 0 })
    let text = String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    guard let start = text.range(of: "StreamTitle='") else { return nil }
    let rest = text[start.upperBound...]
    let end = rest.range(of: "';")?.lowerBound ?? rest.lastIndex(of: "'") ?? rest.endIndex
    let title = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty || title == "-" ? nil : title
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
