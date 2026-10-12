import Foundation

/// The next song starts playing silently this long (in the playing song's time) before it comes
/// in, so the two can be lined up while nobody hears it.
public let preRollLeadMs = 2_500

/// The next song is loaded at least this long before the blend starts: songs from outside the
/// library are slow to start.
public let planLoadLeadMs = 15_000

/// The decks are measured this long after the next one starts playing, and this long after it
/// plays again following a correction.
public let alignFirstMs = 1_000
public let alignAgainMs = 400

/// An offset this small is left alone.
public let alignToleranceMs = 10.0

/// The filters step on the beat only when the decks are lined up this closely.
public let barLockToleranceMs = 15.0

/// Corrections tried before the blend goes ahead as it is.
public let alignMostSeeks = 3

/// A correction needs the next song to play for a while before the blend; with less than this
/// left it is not tried.
public let alignLastChanceMs = 400

/// A position that moves this far from where it should be means the plan no longer fits.
public let replanJumpMs = 2_000

/// A spare this close to where it should be parked is left there.
public let parkToleranceMs = 40

/// Where a deck is in loading a song.
public enum DeckState: Sendable, Equatable {
    case idle
    case buffering
    case ready
    case ended
}

/// Why a deck that wants to play is held silent, if it is.
public enum DeckSuppression: Sendable, Equatable {
    case none
    /// A call or another app holds the sound for a while.
    case interruption
}

/// Whether a deck that stopped playing is only waiting for its sound to arrive (a rebuffer),
/// which a blend rides out, rather than paused by the listener or held back by a call.
public func isRebuffering(playWhenReady: Bool, state: DeckState, suppression: DeckSuppression) -> Bool {
    playWhenReady && state == .buffering && suppression == .none
}

extension AutomixSettings {
    /// The settings the planner gets at a playback speed: the longest blend is in song time, so
    /// at 1.5x speed an 8 s blend covers 12 s of the songs and still lasts 8 s.
    public func atSpeed(_ speed: Float) -> AutomixSettings {
        if speed == 1 { return self }
        var paced = self
        paced.maxOverlapMs = Int((Double(maxOverlapMs) * Double(speed)).rounded())
        return paced
    }
}

/// The playing song's level and tempo as the planner is told them: with the song's end from the
/// server's profile, that end is already measured against the whole song, so no level goes with
/// it, and its tempo is the whole song's from the profile, else what was heard.
public func heardFor(_ profile: TransitionProfile?, heardLevelDb: Double?, heardTempo: Double?) -> (level: Double?, tempo: Double?) {
    guard let profile else { return (heardLevelDb, heardTempo) }
    return (nil, profile.tempoPrior ?? heardTempo)
}

/// What a scouted end of a song and start of the next go through: the shared analysis, with the
/// song's tag tempo picking its tempo's octave.
public func tailAnalyzer(_ tagBpm: Double?) -> @Sendable (SectionEnvelope) -> SectionAnalysis { { analyzeTail($0, tagBpm: tagBpm) } }

public func headAnalyzer(_ tagBpm: Double?) -> @Sendable (SectionEnvelope) -> SectionAnalysis { { analyzeHead($0, tagBpm: tagBpm) } }

/// Whether a spare parked at `positionMs` must move to `targetMs`: not when it is there already,
/// give or take a frame or two.
public func needsRepark(_ positionMs: Int, _ targetMs: Int) -> Bool { abs(positionMs - targetMs) > parkToleranceMs }

extension TransitionPlan {
    /// The incoming song's playback rate through the blend.
    public func incomingRate() -> Double { beatMatchRate ?? 1 }

    /// Where the incoming song starts its silent run-up.
    public func preRollFromMs() -> Int {
        overlapMs <= 0 ? 0 : max(0, entryMs - Int(Double(preRollLeadMs) * incomingRate()))
    }

    /// Where in the playing song the incoming song starts its run-up.
    public func preRollAtMs() -> Double { Double(startMs) - Double(entryMs - preRollFromMs()) / incomingRate() }

    /// Where the incoming song should be when the playing song is at `outgoingMs`.
    public func incomingAtMs(_ outgoingMs: Double) -> Double { Double(entryMs) + (outgoingMs - Double(startMs)) * incomingRate() }

    /// How far the incoming song runs ahead of where it should be, in the playing song's time:
    /// negative when it is behind.
    public func alignmentErrorMs(_ outgoingMs: Double, _ incomingMs: Double) -> Double {
        (incomingMs - Double(entryMs)) / incomingRate() - (outgoingMs - Double(startMs))
    }
}

/// Lines the incoming song up with the playing one during its silent run-up. It is told the two
/// positions as they come and answers what to do: wait, move the incoming song to a position (it
/// is still silent), or go ahead with the offset it ended on. A deck that is moved stops and
/// starts again, which itself costs a little time; the lag seen after each move is added to the
/// next.
public final class Aligner {
    public enum Step: Equatable, Sendable {
        case wait
        case seek(toMs: Int)
        /// `errorMs` is the offset at the last measure, nil if none was made; `locked` says
        /// whether it is close enough to step on the beat.
        case settled(errorMs: Double?, locked: Bool)
    }

    private let plan: TransitionPlan
    private var playingSince: Int?
    private var seeks = 0
    private var lag = 0.0
    private var lastError: Double?
    private var settled: Step?

    public init(_ plan: TransitionPlan) { self.plan = plan }

    /// `nowMs` is a clock in real milliseconds; `outgoingMs` and `incomingMs` are the two songs'
    /// positions read at that moment.
    public func observe(nowMs: Int, outgoingMs: Double, incomingMs: Double, incomingPlaying: Bool) -> Step {
        if let settled { return settled }
        // Time left before the blend, in the playing song's time.
        let left = Double(plan.startMs) - outgoingMs
        if !incomingPlaying {
            playingSince = nil
            return left <= 0 ? settle() : .wait
        }
        let since = playingSince ?? nowMs
        playingSince = since
        let wait = seeks == 0 ? alignFirstMs : alignAgainMs
        if nowMs - since < wait { return left <= 0 ? settle() : .wait }
        let error = plan.alignmentErrorMs(outgoingMs, incomingMs)
        if seeks > 0 { lag -= error }
        lastError = error
        if abs(error) <= alignToleranceMs || seeks >= alignMostSeeks || left < Double(alignLastChanceMs) { return settle() }
        seeks += 1
        playingSince = nil
        // Where it should be now, plus the time a move is seen to cost.
        let target = plan.incomingAtMs(outgoingMs + lag)
        return .seek(toMs: max(0, Int(target)))
    }

    /// Goes ahead with whatever was measured last; the blend is starting.
    public func finish() -> Step { settled ?? settle() }

    private func settle() -> Step {
        let error = lastError
        let step = Step.settled(errorMs: error, locked: error.map { abs($0) < barLockToleranceMs } ?? false)
        settled = step
        return step
    }
}

/// Start loading the next song this long before the blend, so it is ready.
public let spareLoadAheadMs = 5_000

/// A next song with no known length is loaded this long before the blend instead: songs from
/// outside the library are slow to start, and their length is only known once they have opened.
public let slowSpareLoadAheadMs = 15_000

/// The next song's length as far as the crossfade knows it: what the spare deck measured once it
/// opened the song, when that is believable, else its listed length. 0 while nothing knows it.
public func nextSongLengthMs(listedMs: Int, spareMs: Int?) -> Int { playingLengthMs(listedMs: listedMs, playerMs: spareMs) }

/// Whether a blend into the next song waits only on its length: with any length it would blend,
/// but its length is not known yet.
public func waitsOnLength(_ current: FadeSong, _ next: FadeSong?, fadeMs: Int, repeatOne: Bool, stopAtEndOfSong: Bool) -> Bool {
    guard let next, next.durationMs <= 0 else { return false }
    var long = next
    long.durationMs = Int.max / 4
    return crossfadeLength(current, long, fadeMs: fadeMs, repeatOne: repeatOne, stopAtEndOfSong: stopAtEndOfSong) > 0
}

/// How long before the end of the song (in real time) the spare deck loads the next song: early
/// for a song whose length is not known yet, so it has opened and said its length before the
/// blend would start.
public func loadLeadMs(blendMs: Int, fadeMs: Int, lengthKnown: Bool) -> Int {
    lengthKnown ? blendMs + spareLoadAheadMs : fadeMs + slowSpareLoadAheadMs
}

/// Whether an address with this scheme is a file on the phone.
public func isLocalScheme(_ scheme: String?) -> Bool {
    guard let scheme else { return false }
    return ["file", "ipod-library", "data"].contains(scheme.lowercased())
}
