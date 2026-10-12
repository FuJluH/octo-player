import Foundation

/// When the projection and the player disagree by more than this, the player wins.
public let CLOCK_DRIFT_S = 0.15

/// A jump bigger than this from one frame to the next is a seek.
public let CLOCK_SEEK_S = 0.6

/// This many frames in a row with the player's position standing still means it is paused or
/// waiting, whatever it says.
public let CLOCK_STILL_FRAMES = 6

/// After a tap to seek, the target shows until the player is this close to it, or this long has
/// passed.
public let SEEK_HOLD_NEAR_S = 0.5
public let SEEK_HOLD_MAX_S = 2.5

/// The step the springs are given each frame is kept within this.
public let MAX_FRAME_STEP_S = 0.05

/// Where in the song the lyrics are, smooth from frame to frame. The player's reported position
/// moves in coarse steps, so the clock takes it as an anchor and runs on from there with the
/// phone's own steady clock, at the playback speed. It snaps back to the player when the two
/// drift apart, and tells a seek from ordinary time passing.
///
/// `latency` is how long sound takes to be heard after the player reports it, taken off the time:
/// the output's lyrics timing, where minus shows the words sooner. All times are in seconds,
/// clock times in nanoseconds.
public final class LyricClock {
    public private(set) var latency: Double

    private var anchorAt = 0.0
    private var anchorNanos = 0
    private var anchorRate = 1.0
    private var anchored = false
    private var anchorWanted = false

    private var lastReported: Double?
    private var stillFrames = 0
    private var lastTime: Double?
    private var lastNanos: Int?

    private var holdTarget: Double?
    private var holdSince = 0

    /// The time shown this frame.
    public private(set) var time = 0.0

    /// Whether this frame jumped, as a seek does.
    public private(set) var seeked = false

    /// The time since the last frame, kept small enough for the springs.
    public private(set) var step = 0.0

    public init(latency: Double = 0.0) {
        self.latency = latency
    }

    /// Starts over, as when the view comes back: the next frame anchors fresh and is not taken
    /// for a seek.
    public func reset() {
        anchored = false
        lastReported = nil
        stillFrames = 0
        lastTime = nil
        lastNanos = nil
    }

    /// Takes a new anchor from the player next frame: it played, paused, seeked, changed song or
    /// said the time changed.
    public func requestAnchor() {
        anchorWanted = true
    }

    /// A new output, or its timing moved: the time shifts by the difference from the next frame,
    /// on a fresh anchor, and the shift is not taken for a seek, so the lines glide to it instead
    /// of jumping.
    public func setLatency(_ seconds: Double) {
        if seconds == latency { return }
        lastTime = lastTime.map { $0 - (seconds - latency) }
        latency = seconds
        anchorWanted = true
    }

    /// After a tap to seek: shows `target` until the player gets there. `target` is the player's
    /// time, so the latency comes off it as off any.
    public func holdSeek(_ target: Double, nowNanos: Int) {
        holdTarget = target
        holdSince = nowNanos
    }

    /// Works out this frame's time from the player's reported position, playback speed and
    /// whether it says it is playing.
    @discardableResult
    public func frame(_ nowNanos: Int, _ reported: Double, rate: Double, playing: Bool) -> Double {
        step = lastNanos.map { (Double(nowNanos - $0) / 1e9).clamped(0.0, MAX_FRAME_STEP_S) } ?? 0.0
        lastNanos = nowNanos

        stillFrames = lastReported == reported ? stillFrames + 1 : 0
        lastReported = reported
        let moving = playing && stillFrames < CLOCK_STILL_FRAMES

        var shown: Double
        if !moving {
            // Paused: the player's own position, not projected.
            shown = reported - latency
            anchored = false
        } else {
            if !anchored || anchorWanted {
                anchor(reported, nowNanos, rate)
            } else if rate != anchorRate {
                // A new speed carries on from where the old one had got to.
                anchor(projected(nowNanos), nowNanos, rate)
            }
            var at = projected(nowNanos)
            if abs(at - reported) > CLOCK_DRIFT_S {
                anchor(reported, nowNanos, rate)
                at = reported
            }
            shown = at - latency
        }
        anchorWanted = false
        shown = max(0.0, shown)

        if let target = holdTarget {
            if abs(reported - target) <= SEEK_HOLD_NEAR_S || Double(nowNanos - holdSince) / 1e9 > SEEK_HOLD_MAX_S {
                holdTarget = nil
            } else {
                shown = max(0.0, target - latency)
            }
        }

        seeked = lastTime.map { abs(shown - $0) > CLOCK_SEEK_S } ?? false
        lastTime = shown
        time = shown
        return shown
    }

    private func anchor(_ at: Double, _ nowNanos: Int, _ rate: Double) {
        anchorAt = at
        anchorNanos = nowNanos
        anchorRate = rate
        anchored = true
    }

    private func projected(_ nowNanos: Int) -> Double { anchorAt + Double(nowNanos - anchorNanos) / 1e9 * anchorRate }
}
