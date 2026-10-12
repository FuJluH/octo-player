import Foundation
import OctoKit
import Synchronization

/// A song opened for playing: what decodes it, and the bytes under it, so reading can be
/// stopped.
struct OpenedSong {
    let decoder: SongDecoding
    let bytes: ByteSource?
}

/// Lets a song still opening be stopped: whatever bytes the opening makes are handed here as
/// soon as they exist, and are stopped at once when the song was let go meanwhile.
final class OpenToken: @unchecked Sendable {
    private let lock = NSLock()
    private var held: [ByteSource] = []
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func adopt(_ source: ByteSource) {
        let stop = lock.withLock { () -> Bool in
            if cancelled { return true }
            held.append(source)
            return false
        }
        if stop { source.cancel() }
    }

    func cancel() {
        let sources = lock.withLock { () -> [ByteSource] in
            cancelled = true
            defer { held = [] }
            return held
        }
        for source in sources { source.cancel() }
    }
}

/// One song loaded on a deck: it is opened and decoded on a thread of its own into a ring of
/// sound that the deck plays from. A jump to another place in the song is taken by the decode
/// thread; the song's length, format and any failure are kept for the deck to read.
final class DeckSource: @unchecked Sendable {
    private static let made = Atomic<Int>(0)

    /// Tells this song load apart from every other.
    let serial = DeckSource.made.add(1, ordering: .relaxed).newValue
    let item: QueueItem
    /// How the song's loudness is judged, decided as it was queued.
    let setUp: SongSetUp?
    let ring: PCMRing
    let outputRate: Double
    /// A file on the phone starts at once; a stream waits for the start-after setting.
    let isLocal: Bool

    private let open: @Sendable (OpenToken) throws -> OpenedSong
    private let token = OpenToken()
    private let condition = NSCondition()
    private var pendingSeekMs: Int?
    private var closed = false

    private var _failure: PlayError?
    private var _measuredMs: Int?
    private var _quality: (codecMime: String?, bitDepth: Int?, sampleRate: Int?, bitrate: Int?) = (nil, nil, nil, nil)
    private var _opened = false

    /// The decode thread reached the song's end in the current jump.
    let decodedToEnd = Atomic<Bool>(false)
    let skipSilence: Atomic<Bool>
    /// Where the latest jump went, in ms, to show before sound arrives.
    let jumpMs: Atomic<Int>

    init(item: QueueItem, setUp: SongSetUp?, startMs: Int, outputRate: Double, isLocal: Bool, skipSilence: Bool,
         open: @escaping @Sendable (OpenToken) throws -> OpenedSong) {
        self.item = item
        self.setUp = setUp
        self.outputRate = outputRate
        self.isLocal = isLocal
        self.open = open
        ring = PCMRing(seconds: 15, sampleRate: outputRate)
        self.skipSilence = Atomic(skipSilence)
        jumpMs = Atomic(max(0, startMs))
        let start = max(0, startMs)
        let thread = Thread { [self] in run(startMs: start) }
        thread.qualityOfService = .userInitiated
        thread.name = "octo-decode"
        thread.start()
    }

    var failure: PlayError? { condition.withLock { _failure } }
    var measuredMs: Int? { condition.withLock { _measuredMs } }
    var opened: Bool { condition.withLock { _opened } }
    var quality: (codecMime: String?, bitDepth: Int?, sampleRate: Int?, bitrate: Int?) { condition.withLock { _quality } }

    /// Jumps to `ms` in the song; what was waiting is let go.
    func seek(toMs ms: Int) {
        condition.lock()
        pendingSeekMs = max(0, ms)
        ring.jump()
        decodedToEnd.store(false, ordering: .relaxed)
        jumpMs.store(max(0, ms), ordering: .relaxed)
        condition.broadcast()
        condition.unlock()
    }

    /// Stops reading and decoding for good.
    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
        token.cancel()
    }

    // MARK: The decode thread

    private func run(startMs: Int) {
        let song: OpenedSong
        do {
            song = try open(token)
        } catch {
            fail(error)
            return
        }
        let decoder = song.decoder
        defer { decoder.close() }
        if condition.withLock({ closed }) { return }
        condition.withLock {
            _opened = true
            _measuredMs = decoder.durationMs
            _quality = (decoder.codecMime, decoder.bitDepth, Int(decoder.fileSampleRate), decoder.bitrate)
        }
        var songFrame: Int64 = 0
        var ended = false
        let skipper = SilenceSkipper(sampleRate: outputRate)
        let block = PCMRing.chunkFrames
        let scratch = (0..<PCMRing.channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: block) }
        defer { for buffer in scratch { buffer.deallocate() } }
        let decodeInto = Array(scratch.prefix(decoder.channels))
        var pending: Int? = startMs > 0 ? startMs : nil

        while true {
            condition.lock()
            if closed {
                condition.unlock()
                return
            }
            if let seek = pendingSeekMs {
                pendingSeekMs = nil
                pending = seek
            }
            // The jump this stretch of sound belongs to, read while no jump can come in between.
            let gen = ring.generation.load(ordering: .acquiring)
            condition.unlock()

            if let target = pending {
                pending = nil
                do {
                    try decoder.seek(toMs: target)
                } catch {
                    fail(error)
                    return
                }
                songFrame = Int64(Double(target) * outputRate / 1000)
                ended = false
                skipper.reset()
                continue
            }
            if ended {
                waitBriefly(0.5)
                continue
            }
            guard ring.freeChunk() != nil else {
                waitBriefly(0.02)
                continue
            }
            let read: Int
            do {
                read = try decoder.read(into: decodeInto, frames: block)
            } catch {
                if condition.withLock({ closed }) { return }
                fail(error)
                return
            }
            if read == 0 {
                guard waitForChunk() != nil else { return }
                ring.publish(frames: 0, songFrame: songFrame, end: true, gen: gen)
                ended = true
                decodedToEnd.store(true, ordering: .relaxed)
                continue
            }
            if decoder.channels == 1 { scratch[1].update(from: scratch[0], count: read) }
            let kept = skipSilence.load(ordering: .relaxed) ? skipper.keep(scratch, frames: read) : [0..<read]
            for range in kept where !range.isEmpty {
                // Each run of kept frames is a chunk of its own, so its song time stays true.
                guard let chunk = waitForChunk() else { return }
                for ch in 0..<PCMRing.channels { chunk[ch].update(from: scratch[ch] + range.lowerBound, count: range.count) }
                ring.publish(frames: range.count, songFrame: songFrame + Int64(range.lowerBound), end: false, gen: gen)
            }
            songFrame += Int64(read)
        }
    }

    private func waitBriefly(_ seconds: Double) {
        condition.lock()
        if !closed && pendingSeekMs == nil { condition.wait(until: Date().addingTimeInterval(seconds)) }
        condition.unlock()
    }

    private func waitForChunk() -> [UnsafeMutablePointer<Float>]? {
        while true {
            if let chunk = ring.freeChunk() { return chunk }
            condition.lock()
            if closed {
                condition.unlock()
                return nil
            }
            condition.wait(until: Date().addingTimeInterval(0.02))
            condition.unlock()
        }
    }

    private func fail(_ error: Error) {
        condition.withLock {
            if !closed { _failure = error as? PlayError ?? PlayError(.unspecified, detail: "\(error)") }
        }
    }
}

/// Shortens quiet stretches inside a song: a run below the quiet level that lasts past 100 ms
/// keeps a fifth of its length, at most two seconds; the rest is left out.
final class SilenceSkipper {
    private let threshold: Float = 1024.0 / 32768.0
    private let shortest: Int
    private let longestKept: Int
    private var run = 0
    private var kept = 0

    init(sampleRate: Double) {
        shortest = Int(sampleRate * 0.1)
        longestKept = Int(sampleRate * 2)
    }

    func reset() {
        run = 0
        kept = 0
    }

    /// The ranges of frames to keep from a block.
    func keep(_ buffers: [UnsafeMutablePointer<Float>], frames: Int) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start: Int?
        for i in 0..<frames {
            let quiet = abs(buffers[0][i]) < threshold && abs(buffers[1][i]) < threshold
            var keepThis = true
            if quiet {
                run += 1
                if run > shortest {
                    let allowed = max(shortest, min(Int(Double(run) * 0.2), longestKept))
                    keepThis = kept < allowed
                }
                if keepThis { kept += 1 }
            } else {
                run = 0
                kept = 0
            }
            if keepThis {
                if start == nil { start = i }
            } else if let from = start {
                ranges.append(from..<i)
                start = nil
            }
        }
        if let from = start { ranges.append(from..<frames) }
        return ranges
    }
}
