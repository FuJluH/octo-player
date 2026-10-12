import Foundation
import Testing
@testable import OctoKit

/// The ring of decoded sound between a song's decode thread and the audio thread.
@Suite struct PCMRingTest {
    private func write(_ ring: PCMRing, frames: Int, songFrame: Int64, value: Float, end: Bool = false, gen: Int? = nil) {
        guard let chunk = ring.freeChunk() else { Issue.record("no room"); return }
        for ch in 0..<PCMRing.channels { chunk[ch].update(repeating: value, count: frames) }
        ring.publish(frames: frames, songFrame: songFrame, end: end, gen: gen ?? ring.generation.load(ordering: .relaxed))
    }

    private func buffers(_ frames: Int) -> [UnsafeMutablePointer<Float>] {
        (0..<PCMRing.channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: frames) }
    }

    @Test func soundComesOutInOrderWithItsSongTime() {
        let ring = PCMRing(seconds: 1, sampleRate: 48_000)
        write(ring, frames: 100, songFrame: 0, value: 0.25)
        write(ring, frames: 50, songFrame: 100, value: 0.5)
        #expect(ring.waitingFrames == 150)
        let out = buffers(120)
        defer { out.forEach { $0.deallocate() } }
        let first = ring.pull(into: out, offset: 0, frames: 120)
        #expect(first.frames == 120)
        #expect(first.songFrame == 0)
        #expect(out[0][99] == 0.25)
        #expect(out[1][100] == 0.5)
        #expect(ring.nextSongFrame() == 120)
        let rest = ring.pull(into: out, offset: 0, frames: 120)
        #expect(rest.frames == 30)
        #expect(rest.songFrame == 120)
        #expect(!rest.ended)
        #expect(ring.waitingFrames == 0)
    }

    @Test func theEndIsSaidOnceItsSoundIsOut() {
        let ring = PCMRing(seconds: 1, sampleRate: 48_000)
        write(ring, frames: 10, songFrame: 0, value: 1)
        write(ring, frames: 0, songFrame: 10, value: 0, end: true)
        let out = buffers(64)
        defer { out.forEach { $0.deallocate() } }
        let pulled = ring.pull(into: out, offset: 0, frames: 64)
        #expect(pulled.frames == 10)
        #expect(pulled.ended)
    }

    @Test func aJumpLetsGoOfWhatWasWaiting() {
        let ring = PCMRing(seconds: 1, sampleRate: 48_000)
        let before = ring.generation.load(ordering: .relaxed)
        write(ring, frames: 100, songFrame: 0, value: 0.1)
        let after = ring.jump()
        #expect(after == before + 1)
        #expect(ring.waitingFrames == 0)
        // Sound read before the jump but handed over after it never plays.
        write(ring, frames: 100, songFrame: 100, value: 0.2, gen: before)
        #expect(ring.waitingFrames == 0)
        write(ring, frames: 40, songFrame: 48_000, value: 0.9)
        #expect(ring.waitingFrames == 40)
        let out = buffers(200)
        defer { out.forEach { $0.deallocate() } }
        let pulled = ring.pull(into: out, offset: 0, frames: 200)
        #expect(pulled.frames == 40)
        #expect(pulled.songFrame == 48_000)
        #expect(out[0][0] == 0.9)
    }

    @Test func droppingStaleSoundMakesRoomAgain() {
        let ring = PCMRing(seconds: 0.1, sampleRate: 48_000)
        var filled = 0
        while ring.freeChunk() != nil {
            write(ring, frames: PCMRing.chunkFrames, songFrame: Int64(filled * PCMRing.chunkFrames), value: 0)
            filled += 1
        }
        #expect(filled == ring.capacity)
        ring.jump()
        #expect(ring.freeChunk() == nil)
        ring.dropStale()
        #expect(ring.freeChunk() != nil)
        #expect(ring.nextSongFrame() == nil)
    }
}

/// Quiet stretches inside a song are shortened.
@Suite struct SilenceSkipperTest {
    private func run(_ samples: [Float], rate: Double = 1_000) -> Int {
        let skipper = SilenceSkipper(sampleRate: rate)
        let left = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
        defer {
            left.deallocate()
            right.deallocate()
        }
        left.initialize(from: samples, count: samples.count)
        right.initialize(from: samples, count: samples.count)
        return skipper.keep([left, right], frames: samples.count).reduce(0) { $0 + $1.count }
    }

    @Test func soundIsKeptWhole() {
        #expect(run([Float](repeating: 0.5, count: 500)) == 500)
    }

    @Test func aShortPauseIsKept() {
        // 100 ms at 1 kHz is the shortest pause that is shortened.
        let samples = [Float](repeating: 0.5, count: 100) + [Float](repeating: 0, count: 100) + [Float](repeating: 0.5, count: 100)
        #expect(run(samples) == 300)
    }

    @Test func aLongPauseShrinksToAFifth() {
        let samples = [Float](repeating: 0.5, count: 100) + [Float](repeating: 0, count: 1_000) + [Float](repeating: 0.5, count: 100)
        let kept = run(samples)
        #expect(kept == 200 + 200)
    }
}

@Suite struct ByteRangesTest {
    @Test func rangesMergeWhereTheyTouch() {
        var ranges = ByteRanges()
        ranges.insert(0..<10)
        ranges.insert(20..<30)
        ranges.insert(10..<20)
        #expect(ranges.ranges == [0..<30])
        #expect(ranges.total == 30)
    }

    @Test func coveringNeedsOneRangeWithoutAGap() {
        var ranges = ByteRanges()
        ranges.insert(0..<10)
        ranges.insert(15..<20)
        #expect(ranges.covers(2..<8))
        #expect(!ranges.covers(8..<16))
        #expect(ranges.contiguous(from: 4) == 6)
        #expect(ranges.contiguous(from: 12) == 0)
        #expect(ranges.covers(5..<5))
    }
}
