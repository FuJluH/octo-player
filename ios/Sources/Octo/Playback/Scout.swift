import Foundation
import OctoKit
import os

/// The scout gives up on a stretch after this long and the plan does without it.
let scoutBudgetMs = 20_000

/// How much of a song the scout listens to: the end of the playing song and the start of the next.
let tailScoutMs = 60_000
let headScoutMs = 30_000

let playbackLog = Logger(subsystem: "app.winters.octo", category: "playback")

/// Decodes stretches of songs into their envelopes and analyses them, the way the player would
/// read them, on threads of their own (two at a time, so the next song's start never waits on
/// the playing song's end). Each can be cancelled, and each gives up after `scoutBudgetMs`.
final class Scout: @unchecked Sendable {
    private let workers: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .utility
        queue.name = "octo-scout"
        return queue
    }()
    private let lock = NSLock()
    private var released = false

    /// A stretch being read; `cancel` stops it and keeps its answer from coming.
    final class Job: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelledFlag = false
        fileprivate var token: OpenToken?

        var cancelled: Bool { lock.withLock { cancelledFlag } }

        func cancel() {
            let open = lock.withLock { () -> OpenToken? in
                cancelledFlag = true
                return token
            }
            open?.cancel()
        }
    }

    /// Reads `item` from `fromMs` to `toMs`, analyses what it heard there, and hands the
    /// analysis (or nil, when it could not) to `done` on the main actor.
    func read<T: Sendable>(_ item: QueueItem, context: StreamContext, fromMs: Int, toMs: Int,
                           analyze: @escaping @Sendable (SectionEnvelope) -> T,
                           done: @escaping @MainActor @Sendable (T?) -> Void) -> Job {
        run({ [weak self] job in
            let started = Date()
            let stop: @Sendable () -> Bool = { [weak self] in
                job.cancelled || (self?.isReleased ?? true) || Date().timeIntervalSince(started) * 1000 > Double(scoutBudgetMs)
            }
            do {
                return try Self.decodeSection(item, context: context, fromMs: fromMs, toMs: toMs, job: job, stop: stop).map(analyze)
            } catch is NotSeekable {
                playbackLog.info("automix: not scouting \(item.title, privacy: .public): the server sends this song only whole")
                return nil
            } catch {
                playbackLog.info("automix: scouting \(item.title, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }, done: done)
    }

    /// Runs `work` on a scout thread and hands its answer to `done` on the main actor, unless
    /// the job was cancelled first.
    func run<T: Sendable>(_ work: @escaping @Sendable (Job) -> T?, done: @escaping @MainActor @Sendable (T?) -> Void) -> Job {
        let job = Job()
        workers.addOperation {
            if job.cancelled { return }
            let answer = work(job)
            if job.cancelled { return }
            Task { @MainActor in
                if !job.cancelled { done(answer) }
            }
        }
        return job
    }

    private var isReleased: Bool { lock.withLock { released } }

    func release() {
        lock.withLock { released = true }
        workers.cancelAllOperations()
    }

    private static func decodeSection(_ item: QueueItem, context: StreamContext, fromMs: Int, toMs: Int, job: Job,
                                      stop: @Sendable () -> Bool) throws -> SectionEnvelope? {
        let token = OpenToken()
        job.token = token
        if job.cancelled { return nil }
        defer { token.cancel() }
        let open = SongOpener.opener(item, context: context, outputRate: 0, scouting: true)
        let song = try open(token)
        let decoder = song.decoder
        defer { decoder.close() }
        let rate = decoder.fileSampleRate
        if fromMs > 0 { try decoder.seek(toMs: fromMs) }
        let builder = EnvelopeBuilder(sampleRate: Int(rate.rounded()), channels: decoder.channels, startMs: fromMs)
        let block = 4096
        let buffers = (0..<decoder.channels).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: block) }
        let interleaved = UnsafeMutablePointer<Float>.allocate(capacity: block * decoder.channels)
        defer {
            for buffer in buffers { buffer.deallocate() }
            interleaved.deallocate()
        }
        var readMs = Double(fromMs)
        while !stop() {
            let frames = try decoder.read(into: buffers, frames: block)
            if frames == 0 { break }
            for i in 0..<frames {
                for ch in 0..<decoder.channels { interleaved[i * decoder.channels + ch] = buffers[ch][i] }
            }
            let wanted = min(frames, Int(((Double(toMs) - readMs) * rate / 1000).rounded(.up)))
            if wanted > 0 { builder.push(UnsafeBufferPointer(start: interleaved, count: wanted * decoder.channels)) }
            readMs += Double(frames) * 1000 / rate
            if readMs >= Double(toMs) { break }
        }
        if stop() { return nil }
        let envelope = builder.build()
        return envelope.db.isEmpty ? nil : envelope
    }
}
