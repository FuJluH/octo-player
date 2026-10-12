import Foundation

/// The volume never moves faster than from silence to full in this long, so an armed or dropped
/// transition never clicks.
public let transitionSlewMs = 30.0

/// Filters come in and go out over this long, mixed with the sound as it was. Switching them off
/// at once would step the waveform by the filter's phase shift: a click on bass notes.
public let filterEngageMs = 10.0

/// The volume and filter cutoffs are worked out again every this many frames.
public let automationBlockFrames = 32

/// The outgoing song fades out at once (as fast as the volume may move) when it stays below its
/// silence gate this long during the blend.
public let earlyFadeMs = 300.0

/// The headroom comes in over this share of the blend at its start and goes out over the same
/// share at its end.
public let headroomRamp = 0.15

/// What one deck does through a transition, worked out from that deck's own song time. The
/// outgoing deck follows the plan from its start (startMs in its song); the incoming deck from
/// its entry (entryMs in its song), at beatMatchRate when it is set, so both reach the same place
/// in the blend at the same moment once their songs are lined up. `entryId` is the queue entry it
/// belongs to: other songs on the same deck are left alone. `stepped` lets the low-pass step on
/// the beat when the plan is locked to the bar. `gateDb`, for the outgoing deck, is the level
/// below which the song counts as silent.
public final class DeckTransition: Sendable {
    public let entryId: String?
    public let plan: TransitionPlan
    public let incoming: Bool
    public let stepped: Bool
    public let gateDb: Double?
    /// The beats inside the blend, as places through it, and how long the low-pass glides between
    /// steps, in the same units.
    let beats: [Double]
    let glide: Double
    private let headroom: Double

    public init(entryId: String?, plan: TransitionPlan, incoming: Bool, stepped: Bool? = nil, gateDb: Double? = nil) {
        self.entryId = entryId
        self.plan = plan
        self.incoming = incoming
        let stepped = stepped ?? plan.barLocked
        self.stepped = stepped
        self.gateDb = gateDb
        let beats = stepped && !incoming ? plan.beatProgress() : []
        self.beats = beats
        glide = beats.isEmpty || plan.overlapMs <= 0 ? 0 : (plan.beatMs ?? 0) * Double(beatsPerBar) / 8 / Double(plan.overlapMs)
        headroom = pow(10, -plan.headroomDb / 20)
    }

    /// How far through the blend this deck is at `songMs` of its own song: below 0 before it, 1
    /// and above after it.
    public func progressAt(_ songMs: Double) -> Double {
        let since = incoming ? (songMs - Double(plan.entryMs)) / (plan.beatMatchRate ?? 1) : songMs - Double(plan.startMs)
        let length = Double(plan.overlapMs)
        if length <= 0 { return since >= 0 ? 1 : -1 }
        return since / length
    }

    /// The volume at `t` through the blend, before an early fade.
    public func gainAt(_ t: Double) -> Double {
        if incoming {
            if t < 0 { return 0 }
            if t >= 1 { return 1 }
            return plan.inGain(t) * headroomAt(t)
        }
        if t < 0 { return 1 }
        if t >= 1 { return 0 }
        return plan.outGain(t) * headroomAt(t)
    }

    /// The headroom's share of its full cut at `t`: ramped in and out at the ends of the blend,
    /// where one song is nearly silent anyway.
    private func headroomAt(_ t: Double) -> Double {
        let w = max(0, min(1, min(t, 1 - t) / headroomRamp))
        return w >= 1 ? headroom : pow(headroom, w)
    }

    /// Whether the filters run at `t`: only inside the blend, and only with sweeps in the plan.
    public func filtersAt(_ t: Double) -> Bool { plan.filterStrength > 0 && t >= 0 && t < 1 }

    /// The low-pass cutoff, outgoing only.
    public func lowPassAt(_ t: Double) -> Double {
        beats.isEmpty ? plan.outgoingLowPassAt(t) : steppedOutgoingLowPassHz(t, plan.filterStrength, beats, glide)
    }

    /// The high-pass cutoff: the bass swap going out, the thin start coming in.
    public func highPassAt(_ t: Double) -> Double { incoming ? plan.incomingHighPassAt(t) : plan.outgoingHighPassAt(t) }

    /// Whether this deck has nothing left to do in the transition from `t` on.
    public func doneAt(_ t: Double) -> Bool { t >= 1 }
}

/// The two kinds of filter the sweeps use.
public enum FilterKind: Sendable { case lowPass, highPass }

/// A second-order section's coefficients for a cutoff, normalized so a0 is 1, in the order b0,
/// b1, b2, a1, a2: the same Butterworth "cookbook" filters as Biquad, with the cutoff held
/// between 1 Hz and `highestCutoffShare` of the rate.
public func sweepCoefficients(_ kind: FilterKind, sampleRate: Int, hz: Double) -> [Double] {
    var into = [Double](repeating: 0, count: 5)
    sweepCoefficients(kind, sampleRate: sampleRate, hz: hz, into: &into)
    return into
}

public func sweepCoefficients(_ kind: FilterKind, sampleRate: Int, hz: Double, into: inout [Double]) {
    let cutoff = min(max(hz, 1), Double(sampleRate) * highestCutoffShare)
    let w0 = 2 * Double.pi * cutoff / Double(sampleRate)
    let c = cos(w0)
    let alpha = sin(w0) / (2 * 0.7071067811865476)
    let a0 = 1 + alpha
    if kind == .lowPass {
        into[0] = (1 - c) / 2 / a0
        into[1] = (1 - c) / a0
    } else {
        into[0] = (1 + c) / 2 / a0
        into[1] = -(1 + c) / a0
    }
    into[2] = into[0]
    into[3] = -2 * c / a0
    into[4] = (1 - alpha) / a0
}

/// A second-order filter whose cutoff can move while it runs, one state per channel, so a sweep
/// never restarts the filter.
public final class SweptFilter {
    private let kind: FilterKind
    private let sampleRate: Int
    private var k = [Double](repeating: 0, count: 5)
    private var x1: [Double]
    private var x2: [Double]
    private var y1: [Double]
    private var y2: [Double]
    private var hz = -1.0

    public init(_ kind: FilterKind, sampleRate: Int, channels: Int) {
        self.kind = kind
        self.sampleRate = sampleRate
        x1 = [Double](repeating: 0, count: channels)
        x2 = x1
        y1 = x1
        y2 = x1
    }

    /// Moves the cutoff; a change under a thousandth is not worth working out.
    public func setCutoff(_ next: Double) {
        if hz > 0 && abs(next - hz) <= hz * 1e-3 { return }
        hz = next
        sweepCoefficients(kind, sampleRate: sampleRate, hz: next, into: &k)
    }

    public func process(_ x: Double, channel: Int) -> Double {
        let y = k[0] * x + k[1] * x1[channel] + k[2] * x2[channel] - k[3] * y1[channel] - k[4] * y2[channel]
        x2[channel] = x1[channel]
        x1[channel] = x
        y2[channel] = y1[channel]
        y1[channel] = y
        return y
    }

    public func reset() {
        for i in x1.indices {
            x1[i] = 0
            x2[i] = 0
            y1[i] = 0
            y2[i] = 0
        }
        hz = -1
    }
}

/// Runs a deck's part of a transition on its sound: the volume curve with its headroom, the filter
/// sweeps, and for the outgoing song an early fade once it has gone silent. Every sample is keyed
/// to the song time it belongs to, so the decks follow the plan however far ahead of the speaker
/// their sound is worked out. With no transition, or once it is done and the volume is back at
/// full, the sound passes through untouched. Samples are one buffer per channel.
public final class TransitionShaper {
    public let sampleRate: Int
    public let channels: Int
    private let lowPass: SweptFilter
    private let highPass: SweptFilter
    private let slew: Double
    private let engageStep: Double

    private var current: DeckTransition?
    private var gain = 1.0
    private var wet = 0.0
    private var lowPassOn = false

    /// The early fade: how long the song has been below its gate, and whether it has faded out
    /// for good.
    private let levelFrames: Int
    private var levelSquares = 0.0
    private var levelCount = 0
    private var quietMs = 0.0
    private var faded = false

    public init(sampleRate: Int, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        lowPass = SweptFilter(.lowPass, sampleRate: sampleRate, channels: channels)
        highPass = SweptFilter(.highPass, sampleRate: sampleRate, channels: channels)
        slew = 1.0 / (Double(sampleRate) * transitionSlewMs / 1000)
        engageStep = 1.0 / max(1.0, Double(sampleRate) * filterEngageMs / 1000)
        levelFrames = max(1, sampleRate / 100)
    }

    /// Takes up a transition, or drops it with nil. An incoming song armed fresh takes its first
    /// volume at once, so it starts silent instead of fading down. An outgoing song is audible
    /// already, so a transition armed after its start glides to the curve instead of jumping.
    public func arm(_ transition: DeckTransition?, songMs: Double) {
        if transition === current { return }
        let fresh = current == nil && gain == 1
        current = transition
        faded = false
        quietMs = 0
        levelSquares = 0
        levelCount = 0
        if let transition, fresh, transition.incoming { gain = transition.gainAt(transition.progressAt(songMs)) }
    }

    /// Changes `frames` frames in place. The first frame is at `songMs` in its song and each frame
    /// moves the song on `msPerFrame`.
    public func process(_ buffers: [UnsafeMutablePointer<Float>], frames: Int, songMs: Double, msPerFrame: Double) {
        let transition = current
        if gain == 1 && wet == 0 {
            guard let transition else { return }
            // An outgoing song before its blend is left exactly as it is.
            if !transition.incoming && transition.progressAt(songMs + Double(frames) * msPerFrame) < 0 { return }
        }
        let channels = min(self.channels, buffers.count)
        var frame = 0
        while frame < frames {
            let count = min(automationBlockFrames, frames - frame)
            let at = songMs + Double(frame) * msPerFrame
            let t = transition?.progressAt(at)
            var target = 1.0
            if let transition, let t { target = transition.gainAt(t) }
            var filtersOn = false
            if let transition, let t, transition.filtersAt(t) {
                filtersOn = true
                let outgoing = !transition.incoming
                lowPassOn = outgoing
                if outgoing { lowPass.setCutoff(transition.lowPassAt(t)) }
                highPass.setCutoff(transition.highPassAt(t))
            }
            if let transition, let t, !transition.incoming, let gate = transition.gateDb {
                watchSilence(buffers, channels, frame, count, t, gate)
            }
            if faded { target = 0 }
            let wetTarget = filtersOn ? 1.0 : 0.0
            for i in 0..<count {
                gain += min(max(target - gain, -slew), slew)
                if wet != wetTarget { wet = wetTarget > wet ? min(wetTarget, wet + engageStep) : max(wetTarget, wet - engageStep) }
                let g = gain
                let index = frame + i
                for ch in 0..<channels {
                    let x = Double(buffers[ch][index])
                    var y = x
                    if wet > 0 {
                        var f = highPass.process(x, channel: ch)
                        if lowPassOn { f = lowPass.process(f, channel: ch) }
                        y = x + (f - x) * wet
                    }
                    buffers[ch][index] = Float(y * g)
                }
            }
            if wet == 0 && !filtersOn {
                lowPass.reset()
                highPass.reset()
                lowPassOn = false
            }
            frame += count
        }
        if let transition, gain == 1, wet == 0, transition.incoming,
           transition.doneAt(transition.progressAt(songMs + Double(frames) * msPerFrame)) {
            // An incoming song past its blend is simply playing now.
            current = nil
        }
    }

    /// Measures the outgoing song in 10 ms steps through the blend, before any volume change, and
    /// fades it out once it has stayed below its gate for `earlyFadeMs`.
    private func watchSilence(_ buffers: [UnsafeMutablePointer<Float>], _ channels: Int, _ from: Int, _ count: Int, _ t: Double, _ gateDb: Double) {
        if faded || t < 0 || t >= 1 { return }
        for i in 0..<count {
            var sum = 0.0
            for ch in 0..<channels { sum += Double(buffers[ch][from + i]) }
            let mono = sum / Double(channels)
            levelSquares += mono * mono
            levelCount += 1
            if levelCount == levelFrames {
                let db = levelSquares <= 1e-10 * Double(levelCount) ? -100.0 : 10 * log10(levelSquares / Double(levelCount))
                quietMs = db < gateDb ? quietMs + Double(levelCount) * 1000.0 / Double(sampleRate) : 0
                levelSquares = 0
                levelCount = 0
                if quietMs >= earlyFadeMs {
                    faded = true
                    return
                }
            }
        }
    }
}
