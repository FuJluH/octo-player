import Foundation

/// How long the still crossfades into the loop once its first frame is drawn, and back when the
/// loop goes.
public let loopFadeMs = 450

/// What a loop on screen does right now.
public enum LoopPlay: Sendable, Equatable {
    /// Plays, muted and looping.
    case play
    /// Stops where it is: the frame it stopped on stays (the still, when it never started).
    case hold
    /// Shows only the still: the loop is not even loaded.
    case stillOnly
}

/// What a loop does: only the still with Reduce motion on; held while its view is not seen
/// (screen off, app in the background, player closed, page covered) or while the device saves
/// power; else it plays.
public func loopPlay(seen: Bool, powerSave: Bool, reduceMotion: Bool) -> LoopPlay {
    if reduceMotion { return .stillOnly }
    if !seen || powerSave { return .hold }
    return .play
}

/// The albums whose art to ask about when a song starts: its own, then the next songs' (each
/// once, blanks left out).
public func albumsToAsk(playing: String?, next: [String?], ahead: Int = 1) -> [String] {
    var seen = Set<String>()
    return ([playing] + next.prefix(max(ahead, 0))).compactMap { $0 }.filter { id in
        !id.trimmingCharacters(in: .whitespaces).isEmpty && seen.insert(id).inserted
    }
}

/// The words over a full-screen loop shaded into `shade` (`0xFFRRGGBB`): dark where they read on
/// it and white would not, else white. Weighed as if over black, since nothing behind the shade
/// can be dimmed for the words.
public func loopShadeInk(_ shade: UInt32) -> WashInk {
    inkOver(WashRange.of(shade), 0xFF00_0000)
}

/// Which album of the server to ask about for a song's album id, as the queue holds it.
public enum AnimatedAlbum: Sendable, Equatable {
    /// This album id on the server in use.
    case server(String)
    /// The library's own id for the album: its songs' copies on the server name the album.
    case lookUp
    /// Not an album on the server in use (music on the phone, another server): never asked.
    case none
}

/// The server's own album for `albumId`: a library id made from the server in use
/// ("<source>:<native id>") is that native id; a plain id, as the server hands it, is itself; a
/// library id of another source, or one the library made, is found through the songs' copies, or
/// is no server album at all.
public func animatedAlbum(_ albumId: String?, serverInUse: String?) -> AnimatedAlbum {
    guard let albumId, !albumId.trimmingCharacters(in: .whitespaces).isEmpty, let serverInUse else { return .none }
    if albumId.hasPrefix(serverInUse + ":") {
        return serverAlbumIdOf(serverInUse, albumId).map(AnimatedAlbum.server) ?? .lookUp
    }
    if isServerSource(albumId) { return .none }
    return albumId.contains(":") ? .lookUp : .server(albumId)
}
