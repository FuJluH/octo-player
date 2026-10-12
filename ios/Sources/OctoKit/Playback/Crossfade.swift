import Foundation

/// What the crossfade needs to know about a song.
public struct FadeSong: Sendable, Equatable {
    public var albumId: String?
    public var albumOrder: Int?
    public var durationMs: Int

    public init(albumId: String?, albumOrder: Int?, durationMs: Int) {
        self.albumId = albumId
        self.albumOrder = albumOrder
        self.durationMs = durationMs
    }
}

/// The shortest blend worth doing; anything shorter just sounds like a cut.
public let shortestFadeMs = 500

/// How long the next song should fade in over the end of this one, or 0 for no crossfade. The
/// fade shrinks to half of either song, so a short song is never mostly fade.
public func crossfadeLength(_ current: FadeSong, _ next: FadeSong?, fadeMs: Int, repeatOne: Bool, stopAtEndOfSong: Bool) -> Int {
    guard fadeMs > 0, let next, !repeatOne, !stopAtEndOfSong else { return 0 }
    if current.durationMs <= 0 || next.durationMs <= 0 { return 0 }
    // An album played in order stays gapless: songs meant to run into each other should not
    // be blended.
    if let album = current.albumId, album == next.albumId, let order = current.albumOrder, next.albumOrder == order + 1 {
        return 0
    }
    let length = min(fadeMs, min(current.durationMs, next.durationMs) / 2)
    return length < shortestFadeMs ? 0 : length
}

/// Equal-power fade: the two volumes' squares always add up to one, so the blend never dips or
/// swells in loudness. `progress` runs from 0 to 1.
public func fadeOutVolume(_ progress: Float) -> Float { cos(min(max(progress, 0), 1) * Float.pi / 2) }

public func fadeInVolume(_ progress: Float) -> Float { sin(min(max(progress, 0), 1) * Float.pi / 2) }
