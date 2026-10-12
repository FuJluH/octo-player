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
/// limiter. Called on the audio thread only. The song that plays next is handed to the stage by
/// the engine; `flush` comes at the start of every song and after every jump.
public protocol DeckSoundStage: AnyObject {
    /// Sets up for the stream's format; answers whether the stage shapes the sound.
    @discardableResult
    func configure(sampleRate: Double, channels: Int) -> Bool
    func flush()
    /// Shapes `frames` frames of `input` into `output` (which may be the same buffers); answers
    /// the frames written, fewer than went in only while the stage's delay fills.
    func process(_ input: [UnsafeMutablePointer<Float>], frames: Int, output: [UnsafeMutablePointer<Float>]) -> Int
    /// Hands out the frames still held back at the end of a song; answers how many.
    func endOfStream(into output: [UnsafeMutablePointer<Float>]) -> Int
    /// How many frames late the shaped sound comes out.
    var latency: Int { get }
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

    public private(set) var sampleRate = 48_000
    public private(set) var channels = 2
    private var transitions: TransitionShaper?
    private var configured = false

    /// The queue entry the stream belongs to, where in its song the stream started, and the
    /// frames handed on since.
    public private(set) var entryId: String?
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
        if !configured || sampleRate != self.sampleRate || channels != self.channels {
            transitions = TransitionShaper(sampleRate: sampleRate, channels: channels)
        }
        self.sampleRate = sampleRate
        self.channels = channels
        configured = true
        stage?.configure(sampleRate: Double(sampleRate), channels: channels)
    }

    /// Audio thread: a stream starts at `streamStartMs` in its song, after a jump or as the next
    /// song begins. A new song (not the same one carried on) starts a new live tap.
    public func flush(streamStartMs: Double, entryId: String?) {
        let sameSong = configured && entryId == self.entryId && tapStarted
        self.entryId = entryId
        self.streamStartMs = streamStartMs
        framesOut = 0
        stage?.flush()
        if !sameSong {
            tap?.begin(entryId, sampleRate: sampleRate, channels: channels)
            tapStarted = true
        }
    }

    private var tapStarted = false

    /// Audio thread: the frames handed on next are at `ms` in the song, after a stretch left
    /// out (a skipped silence). The stage carries on as it was.
    public func moveSongTime(toMs ms: Double) {
        streamStartMs = ms
        framesOut = 0
    }

    /// Audio thread: shapes `frames` frames of `input` into `output` (which may be the same
    /// buffers). Answers the frames written: fewer than went in only while the stage's delay
    /// fills at the start of a stream.
    public func process(_ input: [UnsafeMutablePointer<Float>], frames: Int, output: [UnsafeMutablePointer<Float>]) -> Int {
        guard frames > 0, input.count == channels, output.count == channels else { return 0 }
        // The tap is only for planning blends.
        if keepActive() { tap?.push(channels: input, frames: frames) }
        let written: Int
        if let stage {
            written = stage.process(input, frames: frames, output: output)
        } else {
            for (from, to) in zip(input, output) where from != to { to.update(from: from, count: frames) }
            written = frames
        }
        shapeTransition(output, written)
        return written
    }

    /// Audio thread: shapes `frames` frames in place.
    public func process(_ buffers: [UnsafeMutablePointer<Float>], frames: Int) {
        _ = process(buffers, frames: frames, output: buffers)
    }

    /// Audio thread: the frames the stage still holds at the end of a song, shaped like the rest
    /// of it. Answers how many were written.
    public func endOfStream(into output: [UnsafeMutablePointer<Float>]) -> Int {
        guard let stage, output.count == channels else { return 0 }
        let written = stage.endOfStream(into: output)
        shapeTransition(output, written)
        return written
    }

    /// How many frames late the sound comes out of the stage.
    public var latency: Int { stage?.latency ?? 0 }

    /// Runs the armed transition, when it is for this song, on the frames about to be handed on,
    /// and moves the song time past them.
    private func shapeTransition(_ buffers: [UnsafeMutablePointer<Float>], _ frames: Int) {
        guard frames > 0 else { return }
        let speed = Double(Float(bitPattern: speedBits.load(ordering: .relaxed)))
        let msPerFrame = 1_000.0 * speed / Double(sampleRate)
        let songMs = streamStartMs + Double(framesOut) * msPerFrame
        framesOut += frames
        let shaping = transitions ?? TransitionShaper(sampleRate: sampleRate, channels: channels)
        transitions = shaping
        // A stream whose song is not known takes the transition too.
        let current = entryId
        let transition = armed.withLock { found -> DeckTransition? in
            guard let armedNow = found else { return nil }
            return armedNow.entryId == nil || current == nil || armedNow.entryId == current ? armedNow : nil
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
        tapStarted = false
    }
}
