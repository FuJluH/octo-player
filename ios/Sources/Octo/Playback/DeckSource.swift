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
    private var _loudness: ReplayGainInfo?
    private var _opened = false

    /// The decode thread reached the song's end in the current jump.
    let decodedToEnd = Atomic<Bool>(false)
    let skipSilence: Atomic<Bool>
    /// Where the latest jump went, in ms, to show before sound arrives.
    let jumpMs: Atomic<Int>

    init(item: QueueItem, setUp: SongSetUp?, startMs: Int, outputRate: Double, isLocal: Bool, holdSeconds: Double = 15,
         skipSilence: Bool, open: @escaping @Sendable (OpenToken) throws -> OpenedSong) {
        self.item = item
        self.setUp = setUp
        self.outputRate = outputRate
        self.isLocal = isLocal
        self.open = open
        ring = PCMRing(seconds: holdSeconds, sampleRate: outputRate)
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
    /// The loudness tags in the song's own bytes, once it has opened.
    var loudness: ReplayGainInfo? { condition.withLock { _loudness } }

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
            // Whatever the opening started (a stream on its way) stops with it.
            token.cancel()
            fail(error)
            return
        }
        let decoder = song.decoder
        defer { decoder.close() }
        if condition.withLock({ closed }) { return }
        let tags = Self.loudness(of: song.bytes)
        condition.withLock {
            _loudness = tags
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
                token.cancel()
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

    /// The loudness tags the song's file carries in its own bytes, read as the sound opens.
    private static func loudness(of bytes: ByteSource?) -> ReplayGainInfo? {
        guard let bytes, let length = try? bytes.length(), length > 0 else { return nil }
        return LoudnessTagReader.loudness(length: length) { offset, count in
            guard offset >= 0, offset <= length, count > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: Int(min(Int64(count), length - offset)))
            if buffer.isEmpty { return [] }
            let got = buffer.withUnsafeMutableBytes { raw -> Int? in
                guard let base = raw.baseAddress else { return nil }
                return try? bytes.read(at: offset, into: base, count: raw.count)
            }
            guard let got else { return nil }
            return Array(buffer.prefix(got))
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
