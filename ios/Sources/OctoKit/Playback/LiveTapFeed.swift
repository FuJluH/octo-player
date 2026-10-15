import Dispatch
import Foundation
import Synchronization

/// Room for about 2.7 s of 48 kHz stereo between the audio thread and the worker; anything that
/// does not fit is dropped.
public let tapRingSamples = 1 << 18

/// How often the worker takes what the audio thread left for it.
public let tapDrainMs = 100

/// What a deck's LiveTap knows about the song it is playing: how much of it has been heard, its
/// body level, and its tempo when that is trusted.
public struct TapReading: Sendable, Equatable {
    public var heardMs: Int
    public var bodyLevelDb: Double?
    public var tempoPrior: Double?

    public init(heardMs: Int, bodyLevelDb: Double?, tempoPrior: Double?) {
        self.heardMs = heardMs
        self.bodyLevelDb = bodyLevelDb
        self.tempoPrior = tempoPrior
    }
}

/// Feeds a deck's sound to a LiveTap without slowing the audio thread down: the audio thread
/// only copies samples into a ring, and a worker takes them from there into the tap of the song
/// they belong to. A new song (or a new format) starts a new tap exactly where its first sample
/// is in the ring. Samples in the ring are interleaved.
public final class LiveTapFeed: @unchecked Sendable {
    /// One low-priority queue every feed's worker runs on.
    public static let sharedWorker = DispatchQueue(label: "octo-live-tap", qos: .background)

    private let worker: DispatchQueue
    private let ring: UnsafeMutablePointer<Float>

    /// Absolute sample counts: written by the audio thread, read by the worker.
    private let written = Atomic<Int>(0)
    private let read = Atomic<Int>(0)

    private struct Start {
        let at: Int
        let entryId: String?
        let sampleRate: Int
        let channels: Int
    }

    private let starts = Mutex<[Start]>([])
    private let lock = NSLock()
    private var tap: LiveTap?
    private var tapEntry: String?
    private let timerLock = NSLock()
    private var timer: DispatchSourceTimer?

    public init(worker: DispatchQueue = LiveTapFeed.sharedWorker) {
        self.worker = worker
        ring = .allocate(capacity: tapRingSamples)
        ring.initialize(repeating: 0, count: tapRingSamples)
    }

    deinit {
        close()
        ring.deallocate()
    }

    /// Audio thread: the samples from here on are the start of this song.
    public func begin(_ entryId: String?, sampleRate: Int, channels: Int) {
        let at = written.load(ordering: .acquiring)
        starts.withLock { $0.append(Start(at: at, entryId: entryId, sampleRate: sampleRate, channels: channels)) }
        timerLock.lock()
        defer { timerLock.unlock() }
        if timer == nil {
            let source = DispatchSource.makeTimerSource(queue: worker)
            source.schedule(deadline: .now() + .milliseconds(tapDrainMs), repeating: .milliseconds(tapDrainMs))
            source.setEventHandler { [weak self] in self?.drain() }
            timer = source
            source.resume()
        }
    }

    /// Audio thread: interleaved samples heard by the listener.
    public func push(_ samples: UnsafePointer<Float>, count: Int) {
        let w = written.load(ordering: .relaxed)
        if count > tapRingSamples - (w - read.load(ordering: .acquiring)) { return }
        var at = w & (tapRingSamples - 1)
        var left = count
        var from = 0
        while left > 0 {
            let n = min(left, tapRingSamples - at)
            (ring + at).update(from: samples + from, count: n)
            from += n
            left -= n
            at = 0
        }
        written.store(w + count, ordering: .releasing)
    }

    public func push(_ samples: [Float], count: Int) {
        samples.withUnsafeBufferPointer { push($0.baseAddress!, count: count) }
    }

    /// Audio thread: `frames` frames held one buffer per channel, interleaved into the ring.
    public func push(channels buffers: [UnsafeMutablePointer<Float>], frames: Int) {
        let channels = buffers.count
        let count = frames * channels
        guard count > 0 else { return }
        let w = written.load(ordering: .relaxed)
        if count > tapRingSamples - (w - read.load(ordering: .acquiring)) { return }
        let mask = tapRingSamples - 1
        var at = w
        for i in 0..<frames {
            for ch in 0..<channels {
                ring[at & mask] = buffers[ch][i]
                at += 1
            }
        }
        written.store(w + count, ordering: .releasing)
    }

    /// Stops the worker for this feed; a later begin starts it again.
    public func close() {
        timerLock.lock()
        let source = timer
        timer = nil
        timerLock.unlock()
        source?.cancel()
    }

    /// Worker: takes every sample written so far into its song's tap.
    public func drain() {
        lock.lock()
        defer { lock.unlock() }
        let end = written.load(ordering: .acquiring)
        var r = read.load(ordering: .relaxed)
        while r < end {
            let start = starts.withLock { $0.first }
            if let start, start.at <= r {
                starts.withLock { _ = $0.removeFirst() }
                tap = LiveTap(sampleRate: start.sampleRate, channels: start.channels)
                tapEntry = start.entryId
                continue
            }
            let stop = start.map { $0.at < end ? $0.at : end } ?? end
            var left = stop - r
            var at = r & (tapRingSamples - 1)
            while left > 0 {
                let n = min(left, tapRingSamples - at)
                tap?.push(UnsafeBufferPointer(start: ring + at, count: n))
                left -= n
                at = 0
            }
            r = stop
            read.store(r, ordering: .releasing)
        }
        // A song that starts with no samples yet.
        while true {
            let start = starts.withLock { $0.first }
            guard let start, start.at <= r else { break }
            starts.withLock { _ = $0.removeFirst() }
            tap = LiveTap(sampleRate: start.sampleRate, channels: start.channels)
            tapEntry = start.entryId
        }
    }

    /// Any thread: what the tap knows about this queue entry, or nil when it is not the song this
    /// deck is playing. `tagBpm`, the song's tag tempo, picks the octave of the tempo heard.
    public func reading(_ entryId: String?, tagBpm: Double? = nil) -> TapReading? {
        drain()
        lock.lock()
        defer { lock.unlock() }
        guard let current = tap, tapEntry == entryId else { return nil }
        return TapReading(heardMs: current.heardMs(), bodyLevelDb: current.bodyLevelDb(), tempoPrior: current.tempoPrior(tagBpm: tagBpm))
    }
}
