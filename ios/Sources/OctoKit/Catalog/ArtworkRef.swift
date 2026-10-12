import Foundation

/// Where a picture comes from, stored as one string in the library.
public enum ArtworkRef: Sendable, Hashable {
    /// Artwork inside a file on the phone. The key groups one album's songs so they share one
    /// cached picture.
    case device(key: String, uri: String)
    /// A cover on a server, by the server's own id for it. The address to fetch it is signed only
    /// when it is drawn, so none is ever stored. `online` is for something the server found online
    /// rather than one in the library, so its cover is cached apart. `fallbackId` is a second cover
    /// for the same thing, drawn when the server answers the first with its stand-in picture.
    case server(sourceId: String, coverId: String, online: Bool = false, fallbackId: String? = nil)

    /// Whether Octo paints this cover itself, a station's or a mix's. Its id tells.
    public var drawn: Bool {
        guard case .server(_, let coverId, let online, _) = self else { return false }
        return !online && isDrawnCoverId(coverId)
    }

    public func encode() -> String {
        switch self {
        case .device(let key, let uri):
            return "device:\(key)|\(uri)"
        case .server(let sourceId, let coverId, let online, let fallbackId):
            let fallback = fallbackId.flatMap { !$0.isEmpty && $0 != coverId ? "|\($0)" : nil } ?? ""
            return "\(online ? "online" : "server"):\(sourceId)|\(coverId)\(fallback)"
        }
    }

    public static func decode(_ text: String?) -> ArtworkRef? {
        guard let text else { return nil }
        let kind = text.before(":")
        let rest = text.after(":")
        switch kind {
        case "device":
            return .device(key: rest.before("|"), uri: rest.after("|"))
        case "server", "online":
            // Source, cover, then the fallback cover when there is one. Cover ids never hold a "|".
            let covers = rest.after("|")
            let fallback = covers.after("|", missing: "")
            return .server(sourceId: rest.before("|"), coverId: covers.before("|"), online: kind == "online",
                           fallbackId: fallback.isEmpty ? nil : fallback)
        default:
            return nil
        }
    }
}

/// The cover of something the server found online, as stored.
public func onlineArtwork(_ sourceId: String, _ coverId: String?) -> String? {
    guard let coverId, !coverId.isEmpty else { return nil }
    return ArtworkRef.server(sourceId: sourceId, coverId: coverId, online: true).encode()
}

extension String {
    /// The text before the first `separator`, or all of it when there is none.
    func before(_ separator: String) -> String {
        guard let range = range(of: separator) else { return self }
        return String(self[..<range.lowerBound])
    }

    /// The text after the first `separator`, or `missing` (all of it, by default) when there is none.
    func after(_ separator: String, missing: String? = nil) -> String {
        guard let range = range(of: separator) else { return missing ?? self }
        return String(self[range.upperBound...])
    }

    /// The text after the last `separator`, or all of it when there is none.
    func afterLast(_ separator: String) -> String {
        guard let range = range(of: separator, options: .backwards) else { return self }
        return String(self[range.upperBound...])
    }
}

// Covers Octo paints itself: a station's or a mix's. The server paints each afresh as the list's
// songs change, under the list's own id, so they are kept apart from library covers and only for
// a day.

/// Raise this when the server changes how it draws them, so every copy kept is dropped at once.
public let drawnCoverVersion = 1

/// How long a drawn cover is kept: a UTC day.
public let drawnCoverMs: Int64 = 24 * 60 * 60 * 1000

/// Whether a cover id is one of Octo's own lists: "or" for a station, "og" for a mix, then 20
/// letters and digits.
public func isDrawnCoverId(_ coverId: String) -> Bool {
    coverId.count == 22 && (coverId.hasPrefix("or") || coverId.hasPrefix("og"))
        && coverId.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("A"..."Z").contains($0) || ("a"..."z").contains($0) }
}

/// Which day a drawn cover asked for at `nowMs` belongs to.
public func drawnCoverDay(_ nowMs: Int64) -> Int64 {
    let (quotient, remainder) = nowMs.quotientAndRemainder(dividingBy: drawnCoverMs)
    return remainder < 0 ? quotient - 1 : quotient
}

/// What a drawn cover is kept under on the day `nowMs` falls in.
public func drawnCoverStamp(_ nowMs: Int64) -> String { "v\(drawnCoverVersion):\(drawnCoverDay(nowMs))" }

/// Whether a server marks something explicit. OpenSubsonic's `explicitStatus` is "explicit",
/// "clean" or empty; only "explicit" gets the small "E".
public func isExplicit(_ explicitStatus: String?) -> Bool {
    explicitStatus.map { trimmed($0).lowercased() == "explicit" } ?? false
}

extension Song {
    public var isExplicit: Bool { OctoKit.isExplicit(explicitStatus) }
}
