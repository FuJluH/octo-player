import Foundation

/// The highest bit rate picked among same-size versions of a loop. Above it the file grows (a
/// 24 s loop at 6 Mbit/s is about 18 MB) with no gain a cover can show.
public let loopMaxBandwidth: Int64 = 6_000_000

/// The video formats a loop comes in.
public enum LoopCodec: Sendable, Hashable {
    case avc
    case hevc
}

/// One version of a loop that an HLS playlist offers.
public struct LoopVariant: Sendable, Equatable {
    public var url: URL
    public var bandwidth: Int64
    public var width: Int
    public var height: Int
    public var codecs: String

    public init(url: URL, bandwidth: Int64, width: Int, height: Int, codecs: String) {
        self.url = url
        self.bandwidth = bandwidth
        self.width = width
        self.height = height
        self.codecs = codecs
    }

    public var codec: LoopCodec? {
        if codecs.hasPrefix("avc1") || codecs.hasPrefix("avc3") { return .avc }
        if codecs.hasPrefix("hvc1") || codecs.hasPrefix("hev1") { return .hevc }
        return nil
    }
}

/// The versions an HLS playlist offers (its EXT-X-STREAM-INF lines; the still-frame lists are
/// skipped), with whole addresses.
public func parseLoopLadder(_ playlist: String, playlistUrl: URL) -> [LoopVariant] {
    let lines = playlist.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    var found: [LoopVariant] = []
    for (index, line) in lines.enumerated() where line.hasPrefix("#EXT-X-STREAM-INF:") {
        guard let uri = lines[(index + 1)...].first(where: { !$0.isEmpty && !$0.hasPrefix("#") }),
              let url = URL(string: uri, relativeTo: playlistUrl)?.absoluteURL
        else { continue }
        let attributes = hlsAttributes(String(line.dropFirst("#EXT-X-STREAM-INF:".count)))
        let size = (attributes["RESOLUTION"] ?? "").split(separator: "x").compactMap { Int($0) }
        found.append(LoopVariant(url: url, bandwidth: attributes["BANDWIDTH"].flatMap { Int64($0) } ?? 0,
                                 width: size.count == 2 ? size[0] : 0, height: size.count == 2 ? size[1] : 0,
                                 codecs: attributes["CODECS"] ?? ""))
    }
    return found
}

/// The version to show in a space `width` by `height` pixels, scaled to cover it: the smallest
/// one in a format the device plays that needs no enlarging (else the largest), and of those the
/// same-size one with the highest bit rate up to `loopMaxBandwidth` (else the lowest).
public func pickLoopVariant(_ variants: [LoopVariant], width: Int, height: Int,
                            codecs: Set<LoopCodec> = [.avc]) -> LoopVariant? {
    let playable = variants.filter { $0.codec.map(codecs.contains) == true && $0.width > 0 && $0.height > 0 }
    guard !playable.isEmpty else { return nil }
    let wantW = Double(max(width, 1))
    let wantH = Double(max(height, 1))
    func enlarges(_ v: LoopVariant) -> Bool { max(wantW / Double(v.width), wantH / Double(v.height)) > 1 }
    func area(_ v: LoopVariant) -> Int64 { Int64(v.width) * Int64(v.height) }
    // The first of the smallest, as a stable minimum picks it.
    let fitting = playable.filter { !enlarges($0) }
    let size: LoopVariant
    if let smallest = fitting.min(by: { area($0) < area($1) }) {
        size = smallest
    } else {
        size = playable.reduce(playable[0]) { area($1) > area($0) ? $1 : $0 }
    }
    let sameSize = playable.filter { $0.width == size.width && $0.height == size.height }
    let capped = sameSize.filter { $0.bandwidth <= loopMaxBandwidth }
    if let best = capped.reduce(nil, { (best: LoopVariant?, v) in best.map { v.bandwidth > $0.bandwidth ? v : $0 } ?? v }) {
        return best
    }
    return sameSize.min { $0.bandwidth < $1.bandwidth }
}

/// A loop version kept in one file, as Apple's are: the playlist's map and every part name the
/// same file, so the whole file is the whole loop.
public struct LoopFile: Sendable, Equatable {
    public var url: URL
    public var seconds: Double

    public init(url: URL, seconds: Double) {
        self.url = url
        self.seconds = seconds
    }
}

/// The one file a version's playlist reads its parts from, or nil when the parts come from more
/// than one file.
public func parseLoopFile(_ playlist: String, playlistUrl: URL) -> LoopFile? {
    var files = Set<String>()
    var seconds = 0.0
    for raw in playlist.split(whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        if line.hasPrefix("#EXT-X-MAP:") {
            if let uri = hlsAttributes(String(line.dropFirst("#EXT-X-MAP:".count)))["URI"] { files.insert(uri) }
        } else if line.hasPrefix("#EXTINF:") {
            let value = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            seconds += Double(value.trimmingCharacters(in: .whitespaces)) ?? 0
        } else if !line.hasPrefix("#") {
            files.insert(line)
        }
    }
    guard files.count == 1, let only = files.first, let url = URL(string: only, relativeTo: playlistUrl)?.absoluteURL else { return nil }
    return LoopFile(url: url, seconds: seconds)
}
