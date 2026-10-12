import Foundation

/// A length the player measured is believed from one second to a day. Anything outside that is
/// a placeholder or a stream's nonsense.
private let shortestMeasuredMs = 1_000
private let longestMeasuredMs = 24 * 60 * 60_000

/// How far a measured length may be from the listed one and still agree with it: listings
/// carry whole seconds.
public let lengthSlackMs = 1_000

/// The player's own measure of a song's length, when it is one to believe: a length a song can
/// have, which the song has not already played past (a stream that only measured its first
/// part).
public func measuredLengthMs(_ playerMs: Int?, positionMs: Int = 0) -> Int? {
    guard let ms = playerMs else { return nil }
    if ms < shortestMeasuredMs || ms > longestMeasuredMs { return nil }
    if positionMs > ms + lengthSlackMs { return nil }
    return ms
}

/// How long the song playing is: the player's measure of the sound once it has a believable
/// one, else the listed length (0 when that is unknown), stretched to where the song has played
/// to when it has played past it. Everything timed by the song (the scrub bar, the time left,
/// the end of the song, the scrobble) uses this.
public func playingLengthMs(listedMs: Int, playerMs: Int?, positionMs: Int = 0) -> Int {
    if let measured = measuredLengthMs(playerMs, positionMs: positionMs) { return measured }
    let listed = max(0, listedMs)
    return listed > 0 && positionMs > listed ? positionMs : listed
}

/// What a song's listed length should be corrected to, or nil when the listing is right: a
/// believable measure more than a second away from the listed length, or any believable measure
/// when none was listed.
public func correctedLengthMs(listedMs: Int, playerMs: Int?) -> Int? {
    guard let measured = measuredLengthMs(playerMs) else { return nil }
    if listedMs > 0 && abs(measured - listedMs) <= lengthSlackMs { return nil }
    return measured
}

extension Song {
    /// The song listed with this length, in the whole seconds a listing has.
    public func withLength(ms: Int) -> Song {
        var copy = self
        copy.duration = (ms + 500) / 1_000
        return copy
    }
}

/// The real lengths of songs whose listing was wrong, learned by playing them, by song id.
/// Rows, the queue and the next play of a song read their length through here, so a song shows
/// the length of its sound everywhere once it has played. Kept for as long as the app runs.
public final class RealLengths: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    /// Told of each change, on the thread that made it.
    public var onChange: (@Sendable ([String: Int]) -> Void)?

    public init() {}

    public var corrected: [String: Int] { lock.withLock { values } }

    /// Takes the player's measure of a song listed at `listedMs`. Answers the length its listing
    /// should have when it is wrong, else nil.
    @discardableResult
    public func learn(_ id: String, listedMs: Int, playerMs: Int?) -> Int? {
        guard let ms = correctedLengthMs(listedMs: listedMs, playerMs: playerMs) else { return nil }
        let changed: [String: Int]? = lock.withLock {
            guard values[id] != ms else { return nil }
            values[id] = ms
            return values
        }
        if let changed { onChange?(changed) }
        return ms
    }

    /// A song's length as it should show: the real one when its listing was found wrong, else
    /// the listed one.
    public func lengthMs(_ id: String, listedMs: Int) -> Int {
        lock.withLock { values[id] } ?? listedMs
    }

    /// The song with its real length, when its listing was found wrong.
    public func applyTo(_ song: Song) -> Song {
        guard let ms = lock.withLock({ values[song.id] }) else { return song }
        let fixed = song.withLength(ms: ms)
        return fixed.duration == song.duration ? song : fixed
    }
}
