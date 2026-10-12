import Foundation
import Synchronization

/// Decoded sound waiting to play, handed from a song's decode thread to the audio thread in
/// chunks. One thread writes, one reads; neither waits on the other. Each chunk carries the song
/// time of its first frame (so silence taken out never moves the clock) and the jump it belongs
/// to: after a jump in the song the reader drops chunks of the jump before.
public final class PCMRing: @unchecked Sendable {
    public static let chunkFrames = 2048
    public static let channels = 2

    public let capacity: Int
    private let samples: UnsafeMutablePointer<Float>
    private let counts: UnsafeMutablePointer<Int>
    private let songFrames: UnsafeMutablePointer<Int64>
    private let generations: UnsafeMutablePointer<Int>
    private let ends: UnsafeMutablePointer<Bool>

    /// Chunks handed over, and chunks taken; both only grow.
    private let written = Atomic<Int>(0)
    private let taken = Atomic<Int>(0)
    /// Frames waiting in chunks of the current jump.
    private let waiting = Atomic<Int>(0)
    /// The jump being written now.
    public let generation = Atomic<Int>(0)

    /// Reader only: how far into the chunk at `taken` it has read.
    private var readOffset = 0

    public init(seconds: Double, sampleRate: Double) {
        capacity = max(8, Int(seconds * sampleRate) / Self.chunkFrames)
        samples = .allocate(capacity: capacity * Self.channels * Self.chunkFrames)
        counts = .allocate(capacity: capacity)
        counts.initialize(repeating: 0, count: capacity)
        songFrames = .allocate(capacity: capacity)
        songFrames.initialize(repeating: 0, count: capacity)
        generations = .allocate(capacity: capacity)
        generations.initialize(repeating: 0, count: capacity)
        ends = .allocate(capacity: capacity)
        ends.initialize(repeating: false, count: capacity)
    }

    deinit {
        samples.deallocate()
        counts.deallocate()
        songFrames.deallocate()
        generations.deallocate()
        ends.deallocate()
    }

    // MARK: Writer

    /// The buffers of the next free chunk, one per channel, or nil while every chunk is full.
    public func freeChunk() -> [UnsafeMutablePointer<Float>]? {
        let w = written.load(ordering: .relaxed)
        guard w - taken.load(ordering: .acquiring) < capacity else { return nil }
        let slot = w % capacity
        return (0..<Self.channels).map { samples + (slot * Self.channels + $0) * Self.chunkFrames }
    }

    /// Hands over the chunk last given by `freeChunk`, as part of the jump `gen` (the one that
    /// was current when its sound was read), so sound read before a later jump never plays.
    public func publish(frames: Int, songFrame: Int64, end: Bool, gen: Int) {
        let w = written.load(ordering: .relaxed)
        let slot = w % capacity
        counts[slot] = frames
        songFrames[slot] = songFrame
        generations[slot] = gen
        ends[slot] = end
        if gen == generation.load(ordering: .relaxed) { waiting.add(frames, ordering: .relaxed) }
        written.store(w + 1, ordering: .releasing)
    }

    /// A jump: what is waiting no longer counts. Answers the new jump.
    @discardableResult
    public func jump() -> Int {
        let next = generation.add(1, ordering: .releasing).newValue
        waiting.store(0, ordering: .relaxed)
        return next
    }

    /// Frames waiting to play in the current jump.
    public var waitingFrames: Int { max(0, waiting.load(ordering: .relaxed)) }

    // MARK: Reader

    public struct Pull {
        public var frames = 0
        /// The song frame of the first frame copied, when any was.
        public var songFrame: Int64?
        /// The song's last chunk was reached and read through.
        public var ended = false
    }

    /// Copies up to `frames` frames into `out` (one buffer per channel) from `offset` on, from
    /// chunks of the current jump only, stopping at the song's end.
    public func pull(into out: [UnsafeMutablePointer<Float>], offset: Int, frames: Int) -> Pull {
        var result = Pull()
        let current = generation.load(ordering: .acquiring)
        var t = taken.load(ordering: .relaxed)
        let w = written.load(ordering: .acquiring)
        while result.frames < frames && t < w {
            let slot = t % capacity
            if generations[slot] != current {
                t += 1
                readOffset = 0
                continue
            }
            let count = counts[slot]
            let available = count - readOffset
            if available > 0 {
                let take = min(available, frames - result.frames)
                if result.songFrame == nil { result.songFrame = songFrames[slot] + Int64(readOffset) }
                for ch in 0..<Self.channels {
                    let from = samples + (slot * Self.channels + ch) * Self.chunkFrames + readOffset
                    (out[ch] + offset + result.frames).update(from: from, count: take)
                }
                readOffset += take
                result.frames += take
                waiting.subtract(take, ordering: .relaxed)
            }
            if readOffset >= count {
                let ended = ends[slot]
                t += 1
                readOffset = 0
                if ended {
                    result.ended = true
                    break
                }
            }
        }
        taken.store(t, ordering: .releasing)
        return result
    }

    /// Reader: lets go of chunks left from a jump before, so the writer has room again.
    public func dropStale() {
        let current = generation.load(ordering: .acquiring)
        var t = taken.load(ordering: .relaxed)
        let w = written.load(ordering: .acquiring)
        while t < w && generations[t % capacity] != current {
            t += 1
            readOffset = 0
        }
        taken.store(t, ordering: .releasing)
    }

    /// The song frame the reader is at, from the chunk it reads next, when one is there.
    public func nextSongFrame() -> Int64? {
        let t = taken.load(ordering: .relaxed)
        guard t < written.load(ordering: .acquiring) else { return nil }
        let slot = t % capacity
        return songFrames[slot] + Int64(readOffset)
    }
}
