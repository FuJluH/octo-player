import AVFoundation
import OctoKit
import Synchronization
import os

/// The rate every deck plays at; the mixer turns it into whatever the output wants.
let deckRate: Double = 48_000

/// What a deck's audio thread is told, and what it changes back: the song it plays, the one to
/// follow without a gap, whether it plays, and its volume.
struct DeckOrders {
    var current: DeckSource?
    var following: DeckSource?
    var playing = false
    var pauseAtEnd = false
    var volume: Float = 1
    /// Real time of sound waiting before a stream starts, and the pace it plays at.
    var startAfterMs = 1_000
    var speed: Float = 1
    /// Bumped by the audio thread each time it moves on to `following` by itself.
    var advances = 0
    /// Bumped by the audio thread each time a song ends with nothing to follow, or stops at its end.
    var endings = 0
}

/// The audio thread's side of a deck. Only the audio thread touches its fields once the deck
/// runs; the main side talks to it through `orders` (which the audio thread only tries to take,
/// never waits on) and reads what it reports from the atomics.
final class DeckRender: @unchecked Sendable {
    let orders = OSAllocatedUnfairLock(initialState: DeckOrders())
    let processor: DeckProcessor
    let stream: SoundStream?

    /// What the audio thread reports: the song time of the next frame, where it stands, and the
    /// frames it has handed out (to tell it is running).
    let songMsBits = Atomic<UInt64>(0)
    let phaseCode = Atomic<Int>(DeckState.idle.code)
    let rendered = Atomic<Int>(0)
    /// The song and the jump the audio thread last handed out sound of.
    let renderedSerial = Atomic<Int>(0)
    let renderedGeneration = Atomic<Int>(-1)

    private var held = DeckOrders()
    private var source: DeckSource?
    private var generation = -1
    private var started = false
    private var rebuffering = false
    private var newSong = true
    private var needsFlush = true
    private var songDone = false
    private var ended = false
    private var expectedFrame: Int64 = -1
    private var gain: Float = 0
    private var configured = false

    private static let block = 4096
    private let scratch: [UnsafeMutablePointer<Float>]
    private let tail: [UnsafeMutablePointer<Float>]
    private var tailCount = 0
    private var tailRead = 0
    private var outAt: [UnsafeMutablePointer<Float>]
    private var outs: [UnsafeMutablePointer<Float>]
    private var tailAt: [UnsafeMutablePointer<Float>]

    init(processor: DeckProcessor, stream: SoundStream?) {
        self.processor = processor
        self.stream = stream
        scratch = (0..<2).map { _ in .allocate(capacity: Self.block) }
        tail = (0..<2).map { _ in .allocate(capacity: Self.block * 2) }
        outAt = scratch
        outs = scratch
        tailAt = tail
    }

    deinit {
        for buffer in scratch + tail { buffer.deallocate() }
    }

    // MARK: The audio thread

    func render(_ frameCount: AVAudioFrameCount, _ list: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        let frames = Int(frameCount)
        guard buffers.count >= 2, let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
              let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
        outs[0] = left
        outs[1] = right
        if !configured {
            processor.configure(sampleRate: Int(deckRate), channels: 2)
            configured = true
        }
        if let fresh = orders.withLockIfAvailable({ $0 }) { held = fresh }
        if held.current !== source { takeSong(held.current) }

        var written = drainTail(at: 0, frames: frames)
        let target: Float = held.playing ? held.volume : 0
        if held.playing || gain > 0 {
            written += fill(from: written, frames: frames)
        } else if let source {
            source.ring.dropStale()
        }
        for ch in 0..<2 where written < frames { (outs[ch] + written).update(repeating: 0, count: frames - written) }
        applyGain(target, frames)
        rendered.add(frames, ordering: .relaxed)
        return noErr
    }

    private func takeSong(_ next: DeckSource?) {
        source = next
        generation = -1
        started = false
        rebuffering = false
        newSong = true
        needsFlush = true
        songDone = false
        ended = false
        expectedFrame = -1
        tailCount = 0
        tailRead = 0
        if next == nil { phaseCode.store(DeckState.idle.code, ordering: .relaxed) }
    }

    /// Fills the output from the song, moving on to the following song without a gap.
    private func fill(from start: Int, frames: Int) -> Int {
        var written = start
        while written < frames {
            guard let source else { break }
            source.ring.dropStale()
            let gen = source.ring.generation.load(ordering: .acquiring)
            if gen != generation {
                // A jump: start again from the new place once enough is there.
                generation = gen
                started = false
                rebuffering = false
                needsFlush = true
                songDone = false
                ended = false
                expectedFrame = -1
                tailCount = 0
                tailRead = 0
            }
            if ended { break }
            if songDone {
                guard moveOn(from: source) else { break }
                continue
            }
            if !started {
                guard readyToStart(source) else {
                    phaseCode.store(source.failure != nil ? DeckState.ended.code : DeckState.buffering.code, ordering: .relaxed)
                    break
                }
                started = true
            }
            if needsFlush {
                if newSong, let setUp = source.setUp { stream?.setNextSong(setUp, tags: source.loudness) }
                // Each stream decides again whether the sound is shaped, by the settings now.
                processor.configure(sampleRate: Int(deckRate), channels: 2)
                newSong = false
                needsFlush = false
                let frame = source.ring.nextSongFrame() ?? Int64(Double(source.jumpMs.load(ordering: .relaxed)) * deckRate / 1000)
                processor.flush(streamStartMs: Double(frame) * 1000 / deckRate, entryId: source.item.entryId)
                expectedFrame = frame
            }
            let want = min(frames - written, Self.block)
            let pull = source.ring.pull(into: scratch, offset: 0, frames: want)
            if pull.frames > 0 {
                if let frame = pull.songFrame {
                    if expectedFrame >= 0 && abs(frame - expectedFrame) > 2 {
                        processor.moveSongTime(toMs: Double(frame) * 1000 / deckRate)
                    }
                    expectedFrame = frame + Int64(pull.frames)
                }
                outAt[0] = outs[0] + written
                outAt[1] = outs[1] + written
                written += processor.process(scratch, frames: pull.frames, output: outAt)
                renderedSerial.store(source.serial, ordering: .relaxed)
                renderedGeneration.store(gen, ordering: .relaxed)
                phaseCode.store(DeckState.ready.code, ordering: .relaxed)
                songMsBits.store(processor.songMs.bitPattern, ordering: .relaxed)
            }
            if pull.ended {
                songDone = true
                tailCount = processor.endOfStream(into: tail)
                tailRead = 0
                written += drainTail(at: written, frames: frames)
                continue
            }
            if pull.frames == 0 {
                // Ran dry: wait for more, the longer amount this time.
                if source.failure == nil && !source.decodedToEnd.load(ordering: .relaxed) {
                    started = false
                    rebuffering = true
                    phaseCode.store(DeckState.buffering.code, ordering: .relaxed)
                } else if source.failure != nil {
                    phaseCode.store(DeckState.ended.code, ordering: .relaxed)
                }
                break
            }
        }
        return written - start
    }

    /// Whether enough sound waits to start, by the start-after rule for streams.
    private func readyToStart(_ source: DeckSource) -> Bool {
        if source.decodedToEnd.load(ordering: .relaxed) { return true }
        let waiting = source.ring.waitingFrames
        guard waiting > 0 else { return false }
        let bufferedUs = Int(Double(waiting) * 1_000_000 / deckRate)
        let startAfter = source.isLocal ? 250 : held.startAfterMs
        // Never wait for more than most of what the ring holds.
        if waiting >= source.ring.capacity * PCMRing.chunkFrames * 3 / 4 { return true }
        return hasEnoughToStart(bufferedUs: bufferedUs, speed: held.speed, rebuffering: rebuffering, startAfterMs: startAfter)
    }

    /// The song ended: on to the following song, or stop. False when it cannot be decided now.
    private func moveOn(from source: DeckSource) -> Bool {
        if held.pauseAtEnd || held.following == nil {
            let noted = orders.withLockIfAvailable { orders -> Bool in
                guard orders.current === source else { return true }
                orders.endings += 1
                if orders.pauseAtEnd { orders.playing = false }
                return true
            }
            guard noted != nil else { return false }
            ended = true
            phaseCode.store(DeckState.ended.code, ordering: .relaxed)
            return false
        }
        let next = orders.withLockIfAvailable { orders -> DeckSource? in
            guard orders.current === source, let following = orders.following else { return nil }
            orders.current = following
            orders.following = nil
            orders.advances += 1
            return following
        }
        guard let next = next ?? nil else { return false }
        held.current = next
        held.following = nil
        takeSong(next)
        return true
    }

    private func drainTail(at offset: Int, frames: Int) -> Int {
        let take = min(tailCount - tailRead, frames - offset)
        guard take > 0 else { return 0 }
        for ch in 0..<2 { (outs[ch] + offset).update(from: tail[ch] + tailRead, count: take) }
        tailRead += take
        if tailRead >= tailCount {
            tailRead = 0
            tailCount = 0
        }
        return take
    }

    /// Moves the volume toward `target` no faster than silence to full in 10 ms.
    private func applyGain(_ target: Float, _ frames: Int) {
        let step = Float(1 / (0.01 * deckRate))
        if gain == target {
            if gain != 1 {
                for ch in 0..<2 { for i in 0..<frames { outs[ch][i] *= gain } }
            }
            return
        }
        for i in 0..<frames {
            if gain < target { gain = min(target, gain + step) } else if gain > target { gain = max(target, gain - step) }
            outs[0][i] *= gain
            outs[1][i] *= gain
        }
    }
}

extension DeckState {
    var code: Int {
        switch self {
        case .idle: 0
        case .buffering: 1
        case .ready: 2
        case .ended: 3
        }
    }

    init(code: Int) {
        self = switch code {
        case 1: .buffering
        case 2: .ready
        case 3: .ended
        default: .idle
        }
    }
}

/// What a deck noticed since it was last asked.
enum DeckEvent {
    /// It moved on to the following song by itself, without a gap.
    case advanced(from: QueueItem, to: QueueItem)
    /// The song ended with nothing to follow, or stopped at its end.
    case ended(QueueItem, paused: Bool)
    /// The song could not play.
    case failed(QueueItem, PlayError)
}

/// One of the two players: a song loaded (and the one to follow it without a gap), playing
/// through Octo's sound processor and a speed and pitch stage into the mixer.
@MainActor
final class Deck {
    let name: String
    let render: DeckRender
    let node: AVAudioSourceNode
    let timePitch = AVAudioUnitTimePitch()
    var processor: DeckProcessor { render.processor }

    private(set) var current: DeckSource?
    private(set) var following: DeckSource?
    /// Songs let go, kept a moment so the audio thread is never the one to free them.
    private var retired: [(source: DeckSource, at: Date)] = []
    private var seenAdvances = 0
    private var seenEndings = 0
    private var reportedFailure: ObjectIdentifier?
    /// The delay between the song time the audio thread reports and what is heard, in ms.
    var outputDelayMs: Double = 0

    init(name: String, sound: SoundProcessor?, keepActive: @escaping @Sendable () -> Bool) {
        self.name = name
        let stream = sound?.makeStream(keepActive: keepActive)
        let processor = DeckProcessor(keepActive: keepActive, tap: LiveTapFeed(), stage: stream.map(SoundStage.init))
        let render = DeckRender(processor: processor, stream: stream)
        self.render = render
        node = Self.sourceNode(render)
    }

    /// The node the engine pulls the deck's sound from. Made outside the main actor: the audio
    /// thread calls it.
    nonisolated private static func sourceNode(_ render: DeckRender) -> AVAudioSourceNode {
        let format = AVAudioFormat(standardFormatWithSampleRate: deckRate, channels: 2)!
        return AVAudioSourceNode(format: format) { _, _, frameCount, list in
            render.render(frameCount, list)
        }
    }

    // MARK: What it holds

    var item: QueueItem? { current?.item }
    var followingItem: QueueItem? { following?.item }

    /// Loads a song, at `ms`, replacing whatever was loaded.
    func load(_ source: DeckSource) {
        let old = (current, following)
        current = source
        following = nil
        reportedFailure = nil
        render.orders.withLock {
            $0.current = source
            $0.following = nil
        }
        retire(old.0)
        retire(old.1)
    }

    /// The song to follow this one without a gap, or none.
    func setFollowing(_ source: DeckSource?) {
        let old = following
        following = source
        render.orders.withLock { $0.following = source }
        retire(old)
    }

    /// Empties the deck.
    func clear() {
        let old = (current, following)
        current = nil
        following = nil
        render.orders.withLock {
            $0.current = nil
            $0.following = nil
            $0.playing = false
        }
        retire(old.0)
        retire(old.1)
    }

    func seek(toMs ms: Int) {
        current?.seek(toMs: ms)
    }

    // MARK: Playing

    var playWhenReady: Bool {
        get { render.orders.withLock { $0.playing } }
        set { render.orders.withLock { $0.playing = newValue } }
    }

    var pauseAtEndOfSong: Bool {
        get { render.orders.withLock { $0.pauseAtEnd } }
        set { render.orders.withLock { $0.pauseAtEnd = newValue } }
    }

    var volume: Float {
        get { render.orders.withLock { $0.volume } }
        set { render.orders.withLock { $0.volume = newValue } }
    }

    var startAfterMs: Int {
        get { render.orders.withLock { $0.startAfterMs } }
        set { render.orders.withLock { $0.startAfterMs = newValue } }
    }

    /// The pace: speed (tempo) and pitch as a multiple of the original.
    private(set) var pace = Pace(speed: 1, pitch: 1)

    func setPace(_ next: Pace) {
        pace = next
        timePitch.rate = next.speed
        timePitch.pitch = next.pitch > 0 ? 1200 * log2(next.pitch) : 0
        timePitch.bypass = next.speed == 1 && next.pitch == 1
        render.orders.withLock { $0.speed = next.speed }
    }

    var skipSilence = false {
        didSet {
            current?.skipSilence.store(skipSilence, ordering: .relaxed)
            following?.skipSilence.store(skipSilence, ordering: .relaxed)
        }
    }

    var state: DeckState {
        guard let current else { return .idle }
        if current.failure != nil { return .ended }
        // Sound of an earlier song or from before a jump says nothing of this one yet.
        guard soundIsCurrent else { return .buffering }
        return DeckState(code: render.phaseCode.load(ordering: .relaxed))
    }

    /// Whether the last sound handed out was of this song, since its latest jump.
    private var soundIsCurrent: Bool {
        guard let current else { return false }
        return render.renderedSerial.load(ordering: .relaxed) == current.serial
            && render.renderedGeneration.load(ordering: .relaxed) == current.ring.generation.load(ordering: .relaxed)
    }

    var isPlaying: Bool { playWhenReady && state == .ready }

    /// Whether the song has enough sound waiting to start playing now, by the start-after rule.
    var hasEnoughToStart: Bool {
        guard let current, current.failure == nil else { return false }
        if state == .ready || current.decodedToEnd.load(ordering: .relaxed) { return true }
        let waiting = current.ring.waitingFrames
        guard waiting > 0 else { return false }
        if waiting >= current.ring.capacity * PCMRing.chunkFrames * 3 / 4 { return true }
        let bufferedUs = Int(Double(waiting) * 1_000_000 / deckRate)
        return OctoKit.hasEnoughToStart(bufferedUs: bufferedUs, speed: pace.speed, rebuffering: false,
                                        startAfterMs: current.isLocal ? 250 : startAfterMs)
    }

    /// Where the song is, as heard.
    var positionMs: Int {
        guard let current else { return 0 }
        guard soundIsCurrent else { return current.jumpMs.load(ordering: .relaxed) }
        let ms = Double(bitPattern: render.songMsBits.load(ordering: .relaxed))
        let latency = Double(processor.latency) * 1000 / deckRate + outputDelayMs * Double(pace.speed)
        return max(0, Int(ms - latency))
    }

    /// The song's length as the deck measured it, when it has.
    var durationMs: Int? { current?.measuredMs }

    // MARK: Events

    /// What happened since the last look.
    func poll() -> [DeckEvent] {
        var events: [DeckEvent] = []
        let (renderCurrent, renderFollowing, advances, endings, paused) = render.orders.withLock {
            ($0.current, $0.following, $0.advances, $0.endings, !$0.playing)
        }
        if advances != seenAdvances {
            seenAdvances = advances
            if let from = current, let to = renderCurrent, to !== from {
                current = to
                following = renderFollowing
                retire(from)
                reportedFailure = nil
                events.append(.advanced(from: from.item, to: to.item))
            }
        }
        if endings != seenEndings {
            seenEndings = endings
            if let current { events.append(.ended(current.item, paused: paused)) }
        }
        if let current, let failure = current.failure, reportedFailure != ObjectIdentifier(current) {
            reportedFailure = ObjectIdentifier(current)
            events.append(.failed(current.item, failure))
        }
        let now = Date()
        retired.removeAll { entry in now.timeIntervalSince(entry.at) > 3 }
        return events
    }

    private func retire(_ source: DeckSource?) {
        guard let source else { return }
        source.close()
        retired.append((source, Date()))
    }
}

/// The sound processor's stream as a deck's sound stage.
final class SoundStage: DeckSoundStage {
    let stream: SoundStream

    init(_ stream: SoundStream) {
        self.stream = stream
    }

    @discardableResult
    func configure(sampleRate: Double, channels: Int) -> Bool { stream.configure(sampleRate: sampleRate, channels: channels) }
    func flush() { stream.flush() }
    func process(_ input: [UnsafeMutablePointer<Float>], frames: Int, output: [UnsafeMutablePointer<Float>]) -> Int {
        stream.process(input, frames: frames, output: output)
    }
    func endOfStream(into output: [UnsafeMutablePointer<Float>]) -> Int { stream.endOfStream(into: output) }
    var latency: Int { stream.latency }
}
