import Foundation

/// The progress ring round a small round artwork (the bar's now-playing button, the mini player,
/// the lyrics bar): how far through the song it is as an arc from the top, the whole circle for a
/// station. Playing, it holds steady and advances; paused, a faint track shows the full circle and
/// the arc breathes in brightness and width for a minute, then settles into a still dimmed look.
/// With motion reduced it holds that still look at once.
public enum RingLook {
    /// The paused ring's faint full track.
    public static let pausedTrackAlpha = 0.18
    /// The arc's dimmest point in a breath.
    public static let pausedLowAlpha = 0.35
    /// The arc's brightness while it holds still, paused.
    public static let pausedStillAlpha = 0.45
    /// The arc's width, in points: playing, and at the fullest of a breath.
    public static let thinWidth = 2.0
    public static let wideWidth = 3.0

    /// One breath in and out, in seconds.
    public static let breathSeconds = 2.6
    /// The time between a breath's redraws: about 12 a second, smooth enough for something this
    /// slow.
    public static let breathFrameSeconds = 0.083
    /// How long the ring breathes after a pause before it settles.
    public static let breathLimitSeconds = 60.0
    /// How often a ring round a small artwork steps while the song plays: it moves a point or two a
    /// second, so once a second, on the clock's whole seconds.
    public static let stepSeconds = 1.0

    private static let settleBelow = 0.2
}

/// How far into a breath it is at `seconds`, 1 at its fullest and 0 at its faintest, easing at
/// both ends.
public func pauseBreath(_ seconds: Double) -> Double { 0.5 + 0.5 * cos(2 * .pi * seconds / RingLook.breathSeconds) }

/// Whether a breath `seconds` in settles now: past the limit, near its faintest, where the still
/// look is close, so settling shows no jump.
public func breathSettles(_ seconds: Double) -> Bool {
    seconds >= RingLook.breathLimitSeconds && pauseBreath(seconds) <= 0.2
}

/// When a breath begun at 0 settles: the first moment past the limit that is near its faintest.
/// Known up front, so whatever draws the breath can stop at that moment instead of looking on
/// every frame.
public func breathSettleSeconds() -> Double {
    let period = RingLook.breathSeconds
    let start = RingLook.breathLimitSeconds
    // pauseBreath(t) <= 0.2 while cos(2 pi t / period) <= -0.6: a window around each faintest point.
    let opens = acos(-0.6) / (2 * .pi)
    let closes = 1 - opens
    let phase = start.truncatingRemainder(dividingBy: period) / period
    if phase >= opens && phase <= closes { return start }
    if phase < opens { return start + (opens - phase) * period }
    return start + (1 - phase + opens) * period
}

/// How the arc is drawn: its opacity and width in points. `breath` is the breath's value (0 to 1),
/// nil once it has settled or with motion reduced.
public struct RingArc: Equatable, Sendable {
    public var alpha: Double
    public var width: Double

    public static func of(paused: Bool, breath: Double?) -> RingArc {
        guard paused else { return RingArc(alpha: 1, width: RingLook.thinWidth) }
        guard let breath else { return RingArc(alpha: RingLook.pausedStillAlpha, width: RingLook.thinWidth) }
        let b = min(max(breath, 0), 1)
        return RingArc(alpha: RingLook.pausedLowAlpha + (1 - RingLook.pausedLowAlpha) * b,
                       width: RingLook.thinWidth + (RingLook.wideWidth - RingLook.thinWidth) * b)
    }
}

/// How much of the ring the arc covers: the song's share played, or all of it for a station.
public func ringSweep(position: Double, length: Double, live: Bool) -> Double {
    if live { return 1 }
    return length > 0 ? min(max(position / length, 0), 1) : 0
}

/// How much of the song has played, as a screen reader says it: "1:05 of 3:20 played". Nothing for
/// a station or a song of no known length.
public func playedWords(playedSeconds: Int, lengthSeconds: Int, live: Bool) -> String {
    if live || lengthSeconds <= 0 { return "" }
    return "\(asClock(min(max(playedSeconds, 0), lengthSeconds))) of \(asClock(lengthSeconds)) played"
}

/// What the round now-playing button says: the song, or what a tap does with nothing loaded.
public func nowPlayingWords(title: String?, artist: String?, loaded: Bool) -> String {
    guard loaded else { return "Shuffle your library" }
    let song = [title, artist].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    return song.isEmpty ? "Now playing" : "Now playing: \(song)"
}

/// Whether the round button reads as playing, paused, or a station stopped.
public func nowPlayingState(loaded: Bool, paused: Bool, live: Bool) -> String {
    guard loaded else { return "" }
    if !paused { return "Playing" }
    return live ? "Stopped" : "Paused"
}

/// The time a `seconds` long song takes to move a `lengthPixels` line on by half a pixel, at most
/// a second, or 0 when that is about a frame or less (or the line or the song has no length),
/// meaning every frame.
public func progressStepSeconds(_ seconds: Double, lengthPixels: Double) -> Double {
    guard seconds > 0, lengthPixels > 0 else { return 0 }
    let step = seconds / (lengthPixels * 2)
    return step < 0.016 ? 0 : min(step, 1)
}
