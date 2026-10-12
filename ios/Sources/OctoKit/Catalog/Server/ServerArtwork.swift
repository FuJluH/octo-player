import Foundation

// Covers from the signed-in server. A cover's address is signed afresh for each download, so the
// download is cached under what the picture is, never under the address. A cover the server has
// none for answers "not found"; the picture then fails and the artwork keeps its empty tile.
//
// A server may instead answer with a stand-in picture of its own (Navidrome's blue record), which
// would be cached as the cover for good. That answer is let go, from the disk too, and the
// cover's fallback is drawn in its place: for a library song, the cover of its album's first
// song. With no fallback the picture fails, so the app's own empty tile shows.

/// Covers are asked for at one of these sizes, so one download serves every size up to it.
public let serverCoverSizes = [150, 300, 600, 1200]

/// Covers of things found online are kept under keys of their own, apart from library covers.
/// Raise this if the server ever changes how it draws them again. 3: the server sends them at
/// full size, where it had sent soft 600 pixel ones.
public let onlineCoverVersion = 3

/// The size to ask for when a picture of `wanted` pixels (its longer side) is drawn: the
/// smallest size at least that big, the largest when none is, and 600 when no size is given.
public func serverCoverSize(wanted: Int) -> Int {
    let wanted = wanted > 0 ? wanted : 600
    return serverCoverSizes.first { $0 >= wanted } ?? serverCoverSizes[serverCoverSizes.count - 1]
}

/// What a cover is remembered by, whatever address fetched it: its server and id. A cover Octo
/// paints (a station's or a mix's) changes under the same id, so it is kept under its version
/// and the UTC day, and asked for again each day.
public func serverCoverKey(sourceId: String, coverId: String, online: Bool, nowMs: Int64 = serverArtNowMs()) -> String {
    if online { return "online-art:v\(onlineCoverVersion):\(sourceId)|\(coverId)" }
    if isDrawnCoverId(coverId) { return "drawn-art:\(drawnCoverStamp(nowMs)):\(sourceId)|\(coverId)" }
    return "server-art:\(sourceId)|\(coverId)"
}

/// The key of a server cover, or nil for a picture from the phone.
public func serverCoverKey(_ art: ArtworkRef, nowMs: Int64 = serverArtNowMs()) -> String? {
    guard case .server(let sourceId, let coverId, let online, _) = art else { return nil }
    return serverCoverKey(sourceId: sourceId, coverId: coverId, online: online, nowMs: nowMs)
}

/// What one downloaded size of a cover is kept on disk under.
public func serverCoverDiskKey(_ art: ArtworkRef, px: Int, nowMs: Int64 = serverArtNowMs()) -> String? {
    serverCoverKey(art, nowMs: nowMs).map { "\($0)|\(px)" }
}

/// One cover download to try: the server's id for the picture, the size to ask for, and the key
/// its answer is kept under.
public struct ServerCoverTry: Sendable, Hashable {
    public var coverId: String
    public var px: Int
    public var diskKey: String

    public init(coverId: String, px: Int, diskKey: String) {
        self.coverId = coverId
        self.px = px
        self.diskKey = diskKey
    }
}

/// The downloads to try for a cover, in order: the cover itself, then its fallback, from the same
/// server. Nil for a picture from the phone, or a cover from a server that is not the one signed
/// in (`signedInSource`): no picture is drawn, and nothing has failed. Each try whose key the
/// server answered with its stand-in this run (`standIns`) is skipped. When every try fails or
/// is a stand-in, the cover has none (`NoServerCover`).
public func serverCoverTries(_ art: ArtworkRef, signedInSource: String?, wantedPx: Int, standIns: Set<String> = [],
                             nowMs: Int64 = serverArtNowMs()) -> [ServerCoverTry]? {
    guard case .server(let sourceId, let coverId, let online, let fallbackId) = art, sourceId == signedInSource else { return nil }
    let px = serverCoverSize(wanted: wantedPx)
    let covers = [coverId] + (fallbackId.map { [$0] } ?? [])
    return covers.map { id in
        ServerCoverTry(coverId: id, px: px, diskKey: "\(serverCoverKey(sourceId: sourceId, coverId: id, online: online, nowMs: nowMs))|\(px)")
    }.filter { !standIns.contains($0.diskKey) }
}

/// Whether a picture this many bytes long could be the server's stand-in at all. A cover read
/// from the disk says its length without being read; any other length needs no closer look.
public func serverCoverMayBeStandIn(length: Int64, standIns: StandIns = standInCovers) -> Bool {
    standIns.mayBe(length)
}

/// Whether a downloaded picture is the server's stand-in for a cover it could not give. Only a
/// picture no longer than the longest known stand-in is looked at.
public func serverCoverIsStandIn(_ bytes: some Collection<UInt8>, standIns: StandIns = standInCovers) -> Bool {
    if bytes.count > standIns.longest { return false }
    return standIns.mayBe(Int64(bytes.count)) && standIns.isStandIn(bytes)
}

/// The server had no picture to give for a cover, only its stand-in.
public struct NoServerCover: Error, Equatable, LocalizedError {
    public var coverId: String

    public init(coverId: String) { self.coverId = coverId }

    public var errorDescription: String? { "No cover for \(coverId)" }
}

/// Now, in milliseconds since 1970.
public func serverArtNowMs() -> Int64 { Int64((Date().timeIntervalSince1970 * 1000).rounded(.down)) }
