import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The OpenSubsonic extension an Octo server lists while its owner has animated art on: Apple
/// Music's animated album covers, through getAnimatedArt and an `animatedArt` field on getAlbum.
public let octoAnimatedArt = "octoAnimatedArt"

/// One looping clip of an album's animated art: its HLS playlist, a still of its first frame,
/// the color it sits on ("rrggbb"), and its size. The addresses are either whole (Apple's own)
/// or relative to the server, such as "animated/<token>/square.m3u8" when the server passes the
/// clips on itself; `resolved(on:)` makes them whole.
public struct AnimatedClip: Codable, Sendable, Hashable {
    public var video: String
    public var poster: String?
    public var color: String?
    public var width: Int
    public var height: Int

    public init(video: String = "", poster: String? = nil, color: String? = nil, width: Int = 0, height: Int = 0) {
        self.video = video
        self.poster = poster
        self.color = color
        self.width = width
        self.height = height
    }

    enum CodingKeys: String, CodingKey { case video, poster, color, width, height }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        video = c.string(.video) ?? ""
        poster = c.string(.poster)
        color = c.string(.color)
        width = c.int(.width) ?? 0
        height = c.int(.height) ?? 0
    }

    /// The color as 0xRRGGBB, or nil when the server named none or it is not six hex digits.
    public var colorRgb: UInt32? {
        guard var text = color?.trimmingCharacters(in: .whitespaces) else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(text, radix: 16)
    }

    /// Whether there is a video to play.
    public var playable: Bool { !video.trimmingCharacters(in: .whitespaces).isEmpty }

    /// The clip with whole addresses, relative ones put under `base` (the server's address, with
    /// any path it has). Nil when the video address is not one a player can open.
    public func resolved(on base: URL) -> AnimatedClip? {
        guard let videoUrl = resolveArtAddress(video, base: base) else { return nil }
        var clip = self
        clip.video = videoUrl.absoluteString
        clip.poster = poster.flatMap { resolveArtAddress($0, base: base)?.absoluteString }
        return clip
    }
}

/// An album's animated art: the square loop that plays in place of the cover, and the tall one
/// that fills the player. Either can be missing.
public struct AnimatedArt: Codable, Sendable, Hashable {
    public var square: AnimatedClip?
    public var tall: AnimatedClip?

    public init(square: AnimatedClip? = nil, tall: AnimatedClip? = nil) {
        self.square = square
        self.tall = tall
    }

    enum CodingKeys: String, CodingKey { case square, tall }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        square = (try? c.decodeIfPresent(AnimatedClip.self, forKey: .square)) ?? nil
        tall = (try? c.decodeIfPresent(AnimatedClip.self, forKey: .tall)) ?? nil
    }

    public var isEmpty: Bool { !(square?.playable ?? false) && !(tall?.playable ?? false) }

    /// Both clips with whole addresses; a clip whose address cannot be made whole is dropped.
    public func resolved(on base: URL) -> AnimatedArt {
        AnimatedArt(square: square?.resolved(on: base), tall: tall?.resolved(on: base))
    }
}

/// What the server said about an album's animated art.
public enum AnimatedArtAnswer: Sendable, Equatable {
    /// The album has animated art.
    case found(AnimatedArt)
    /// The album has none, or the server's owner hid it.
    case none
    /// The server has animated art off.
    case off
    /// The server could not say just now (Apple Music did not answer, or the server was out of
    /// reach). Worth asking again later, never worth keeping.
    case notNow
}

/// What the server's error says: off, or Apple Music out of reach (both are code 0), or the
/// album unknown.
func animatedArtAnswer(for error: Error) -> AnimatedArtAnswer {
    switch error as? OctoError {
    case .server(let code, let message):
        if code == 0 && message.range(of: "is off", options: .caseInsensitive) != nil { return .off }
        return code == 0 ? .notNow : .none
    case .notFound:
        return .none
    default:
        return .notNow
    }
}

/// A whole address for one the server gave: as it is when it is already whole, else under the
/// server's address. Only http and https.
public func resolveArtAddress(_ address: String, base: URL) -> URL? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return nil }
    if trimmed.contains("://") {
        guard let whole = URL(string: trimmed), let scheme = whole.scheme?.lowercased(),
              scheme == "http" || scheme == "https", whole.host?.isEmpty == false
        else { return nil }
        return whole
    }
    var relative = Substring(trimmed)
    while relative.hasPrefix("/") { relative.removeFirst() }
    let pieces = relative.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    let path = String(pieces[0])
    let query = pieces.count > 1 ? String(pieces[1]) : nil
    guard var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
    // Added after the base's own path, ending in a slash or not.
    var basePath = parts.percentEncodedPath
    while basePath.hasSuffix("/") { basePath.removeLast() }
    let allowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%"))
    parts.percentEncodedPath = basePath + "/" + (path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path)
    parts.percentEncodedQuery = query
    parts.fragment = nil
    return parts.url
}

/// The part of getAnimatedArt's answer the app reads: the art, or nothing.
struct AnimatedArtBody: Decodable {
    var animatedArt: AnimatedArt?

    enum CodingKeys: String, CodingKey { case animatedArt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        animatedArt = (try? c.decodeIfPresent(AnimatedArt.self, forKey: .animatedArt)) ?? nil
    }
}

extension SubsonicClient {
    /// An album's animated art, on a server that lists octoAnimatedArt, with whole addresses. A
    /// server that never asked Apple about the album asks now, for up to 10 seconds, so this
    /// call may take that long.
    public func animatedArt(_ albumId: String) async -> AnimatedArtAnswer {
        do {
            let body: AnimatedArtBody = try await get("getAnimatedArt", [("id", albumId)], key: nil, timeout: 30)
            guard let art = body.animatedArt?.resolved(on: baseURL), !art.isEmpty else { return .none }
            return .found(art)
        } catch {
            return animatedArtAnswer(for: error)
        }
    }

    /// A whole address for one of an animated art clip's, which a server passing the clips on
    /// itself gives relative to its own address.
    public func animatedArtUrl(_ address: String) -> URL? { resolveArtAddress(address, base: baseURL) }
}
