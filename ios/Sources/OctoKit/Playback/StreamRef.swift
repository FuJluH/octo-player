import Foundation

/// How a server song sits in the queue: its id on the server and what its file is, never a
/// signed address. The address is signed as the song loads.
public let streamScheme = "octo-stream"

private let rawRequest = "raw"

/// A server song as the queue holds it: which server, its id there, its type and bits a second,
/// and, once chosen, what exactly to ask the server for. A request is chosen ("pinned") just
/// before the song loads, so the saved copy and the signed address always agree.
public struct StreamRef: Sendable, Hashable {
    public var sourceId: String?
    public var serverId: String
    public var mimeType: String?
    public var bitrate: Int?
    public var pinned: StreamRequest?

    public init(sourceId: String?, serverId: String, mimeType: String?, bitrate: Int?, pinned: StreamRequest? = nil) {
        self.sourceId = sourceId
        self.serverId = serverId
        self.mimeType = mimeType
        self.bitrate = bitrate
        self.pinned = pinned
    }

    public func pin(_ request: StreamRequest) -> StreamRef {
        var copy = self
        copy.pinned = request
        return copy
    }

    /// What to ask for: the pinned request, or the one for this stream size.
    public func request(_ quality: StreamQuality) -> StreamRequest { pinned ?? phoneRequest(mimeType, bitrate, quality) }
}

public func streamUri(_ ref: StreamRef) -> String {
    var out = "\(streamScheme)://song/\(formEncode(ref.serverId))"
    var params: [(String, String)] = []
    if let source = ref.sourceId { params.append(("source", source)) }
    if let mime = ref.mimeType { params.append(("mime", mime)) }
    if let bitrate = ref.bitrate { params.append(("bitrate", "\(bitrate)")) }
    if let pinned = ref.pinned { params.append(("max", pinned.maxKbps.map(String.init) ?? rawRequest)) }
    if !params.isEmpty { out += "?" + params.map { "\($0.0)=\(formEncode($0.1))" }.joined(separator: "&") }
    return out
}

/// Reads back what `streamUri` wrote. Anything else, such as a phone file, is not a server song.
public func parseStreamUri(_ uri: String) -> StreamRef? {
    guard let parts = URLComponents(string: uri), parts.scheme == streamScheme,
          parts.percentEncodedUser == nil, parts.port == nil, parts.percentEncodedHost == "song" else { return nil }
    let path = parts.percentEncodedPath
    guard path.hasPrefix("/") else { return nil }
    let id = String(path.dropFirst())
    guard !id.isEmpty, !id.contains("/"), let serverId = formDecode(id) else { return nil }
    var query: [String: String] = [:]
    for pair in (parts.percentEncodedQuery ?? "").split(separator: "&") where !pair.isEmpty {
        if let at = pair.firstIndex(of: "=") {
            guard let key = formDecode(String(pair[..<at])), let value = formDecode(String(pair[pair.index(after: at)...])) else { return nil }
            query[key] = value
        } else {
            guard let key = formDecode(String(pair)) else { return nil }
            query[key] = ""
        }
    }
    let pinned: StreamRequest? = query["max"].flatMap { max in
        max == rawRequest ? StreamRequest(nil) : Int(max).map { StreamRequest($0) }
    }
    return StreamRef(sourceId: query["source"].flatMap { $0.isEmpty ? nil : $0 }, serverId: serverId,
                     mimeType: query["mime"].flatMap { $0.isEmpty ? nil : $0 }, bitrate: query["bitrate"].flatMap { Int($0) },
                     pinned: pinned)
}

/// The name a server song is saved under on the phone: the server, the song, its file type and
/// what was asked for. Never the signed address, which has a new random part every time, so the
/// same song finds its saved copy.
public func streamCacheKey(_ sourceId: String, _ ref: StreamRef, _ request: StreamRequest) -> String {
    "\(sourceId)|\(ref.serverId)|\(ref.mimeType ?? "unknown")|\(request.maxKbps.map(String.init) ?? rawRequest)"
}

/// Every request any stream size could make for this song: the file as it is first, then
/// smaller MP3s, largest first.
public func requestVariants(_ ref: StreamRef) -> [StreamRequest] {
    distinctInOrder(StreamQuality.choices.map { phoneRequest(ref.mimeType, ref.bitrate, $0) })
        .enumerated()
        .sorted { a, b in
            let x = a.element.maxKbps ?? Int.max, y = b.element.maxKbps ?? Int.max
            return x != y ? x > y : a.offset < b.offset
        }
        .map(\.element)
}

/// The request to load a song with. What this connection's stream size asks for, unless it is
/// not saved on the phone and another size is: then that one plays, since it costs no data and
/// works with no connection. Failing that, a size already partly saved, such as the one a song
/// started playing in: a seek after moving from Wi-Fi to mobile data must read the same file, or
/// it would land in the middle of a different one.
public func chooseRequest(_ sourceId: String, _ ref: StreamRef, _ quality: StreamQuality, fullySaved: (String) -> Bool,
                          partlySaved: (String) -> Bool = { _ in false }) -> StreamRequest {
    if let pinned = ref.pinned { return pinned }
    let wanted = phoneRequest(ref.mimeType, ref.bitrate, quality)
    func key(_ request: StreamRequest) -> String { streamCacheKey(sourceId, ref, request) }
    if fullySaved(key(wanted)) { return wanted }
    let others = requestVariants(ref).filter { $0 != wanted }
    if let saved = others.first(where: { fullySaved(key($0)) }) { return saved }
    if partlySaved(key(wanted)) { return wanted }
    return others.first { partlySaved(key($0)) } ?? wanted
}

/// UTF-8 form encoding: letters, digits and `.-*_` as they are, everything else as %XX, a space
/// as %20.
func formEncode(_ value: String) -> String {
    var out = ""
    for byte in value.utf8 {
        switch byte {
        case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
             UInt8(ascii: "."), UInt8(ascii: "-"), UInt8(ascii: "*"), UInt8(ascii: "_"):
            out.unicodeScalars.append(Unicode.Scalar(byte))
        default:
            out += String(format: "%%%02X", byte)
        }
    }
    return out
}

/// Reads form encoding back: %XX as bytes, `+` as a space. Nil when it is not valid UTF-8.
func formDecode(_ value: String) -> String? {
    var bytes: [UInt8] = []
    var iterator = Array(value.utf8).makeIterator()
    while let byte = iterator.next() {
        if byte == UInt8(ascii: "+") {
            bytes.append(UInt8(ascii: " "))
        } else if byte == UInt8(ascii: "%") {
            guard let high = iterator.next(), let low = iterator.next(),
                  let number = UInt8(String(decoding: [high, low], as: UTF8.self), radix: 16) else { return nil }
            bytes.append(number)
        } else {
            bytes.append(byte)
        }
    }
    return String(validating: bytes, as: UTF8.self)
}
