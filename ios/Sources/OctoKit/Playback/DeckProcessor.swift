import Foundation
import Synchronization

/// What the crossfade needs from a deck's audio path: whether its sound runs through Octo's
/// processor (so transitions can be shaped there), a way to arm a transition, and what the deck
/// has heard of its song, its tempo's octave picked by the song's tag tempo when it has one.
public protocol DeckSound: AnyObject, Sendable {
    var shapesTransitions: Bool { get }
    func arm(_ transition: DeckTransition?)
    func reading(_ entryId: String?, tagBpm: Double?) -> TapReading?
}

/// One deck's sound shaping that runs before the transition: level, equalizer, balance and
/// limiter. Called on the audio thread only. `songStarted` comes exactly at the first frame of
/// each song (with its loudness), `flush` after a jump to another place.
public protocol DeckSoundStage: AnyObject {
    func configure(sampleRate: Double, channels: Int)
    func songStarted(_ loudness: SongLoudness?)
    func flush()
    func process(_ buffers: [UnsafeMutablePointer<Float>], frames: Int)
}

/// A deck's audio step: what the listener hears goes to the live tap (only while crossfade
/// keeps it active), then through the sound stage, then through the armed transition. It keeps
/// the song time of every frame it hands on, from where each stream starts in its song and the
/// speed, and runs an armed transition on that time. Samples are one buffer per channel, full
/// scale at 1.
public final class DeckProcessor: DeckSound, @unchecked Sendable {
    private let keepActive: @Sendable () -> Bool
    private let tap: LiveTapFeed?
    private let stage: DeckSoundStage?

    private let armed = Mutex<DeckTransition?>(nil)
    private let speedBits = Atomic<UInt32>(Float(1).bitPattern)

    private var sampleRate = 48_000
    private var channels = 2
    private var transitions: TransitionShaper?
    private var configured = false

    /// The queue entry the stream belongs to, where in its song the stream started, and the
    /// frames handed on since.
    private var entryId: String?
    private var streamStartMs = 0.0
    private var framesOut = 0

    public init(keepActive: @escaping @Sendable () -> Bool, tap: LiveTapFeed?, stage: DeckSoundStage?) {
        self.keepActive = keepActive
        self.tap = tap
        self.stage = stage
    }

    /// Transitions can be shaped once the deck's audio runs through this step.
    public var shapesTransitions: Bool { true }

    public func arm(_ transition: DeckTransition?) {
        armed.withLock { $0 = transition }
    }

    public func reading(_ entryId: String?, tagBpm: Double?) -> TapReading? { tap?.reading(entryId, tagBpm: tagBpm) }

    /// The speed the frames handed on play at, against the song's own pace.
    public func setSpeed(_ value: Float) {
        speedBits.store(value.bitPattern, ordering: .relaxed)
    }

    /// Audio thread: the stream's format.
    public func configure(sampleRate: Int, channels: Int) {
        if configured && sampleRate == self.sampleRate && channels == self.channels { return }
        self.sampleRate = sampleRate
        self.channels = channels
        configured = true
        transitions = TransitionShaper(sampleRate: sampleRate, channels: channels)
        stage?.configure(sampleRate: Double(sampleRate), channels: channels)
    }

    /// Audio thread: a stream starts at `streamStartMs` in its song, after a jump or as the next
    /// song begins. A new song (not the same one carried on) starts a new live tap and takes its
    /// loudness from here.
    public func flush(streamStartMs: Double, entryId: String?, newSong: Bool, loudness: SongLoudness?) {
        let sameSong = !newSong && entryId == self.entryId
        self.entryId = entryId
        self.streamStartMs = streamStartMs
        framesOut = 0
        if newSong { stage?.songStarted(loudness) } else { stage?.flush() }
        if !sameSong { tap?.begin(entryId, sampleRate: sampleRate, channels: channels) }
    }

    /// Audio thread: shapes `frames` frames in place.
    public func process(_ buffers: [UnsafeMutablePointer<Float>], frames: Int) {
        guard frames > 0, buffers.count == channels else { return }
        // The tap is only for planning blends.
        if keepActive() { tap?.push(channels: buffers, frames: frames) }
        stage?.process(buffers, frames: frames)
        shapeTransition(buffers, frames)
    }

    /// Runs the armed transition, when it is for this song, on the frames about to be handed on,
    /// and moves the song time past them.
    private func shapeTransition(_ buffers: [UnsafeMutablePointer<Float>], _ frames: Int) {
        let speed = Double(Float(bitPattern: speedBits.load(ordering: .relaxed)))
        let msPerFrame = 1_000.0 * speed / Double(sampleRate)
        let songMs = streamStartMs + Double(framesOut) * msPerFrame
        framesOut += frames
        let shaping = transitions ?? TransitionShaper(sampleRate: sampleRate, channels: channels)
        transitions = shaping
        // A stream whose song is not known takes the transition too.
        let transition = armed.withLock { found -> DeckTransition? in
            guard let found, found.entryId == nil || entryId == nil || found.entryId == entryId else { return nil }
            return found
        }
        shaping.arm(transition, songMs: songMs)
        shaping.process(buffers, frames: frames, songMs: songMs, msPerFrame: msPerFrame)
    }

    /// The song time of the next frame this step hands on.
    public var songMs: Double {
        streamStartMs + Double(framesOut) * 1_000.0 * Double(Float(bitPattern: speedBits.load(ordering: .relaxed))) / Double(sampleRate)
    }

    /// Lets go of the live tap's worker.
    public func reset() {
        tap?.close()
        entryId = nil
    }
}
