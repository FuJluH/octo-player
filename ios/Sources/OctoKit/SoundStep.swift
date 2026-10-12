import Foundation

/// The sound settings the audio path follows, swapped in whole. Each change bumps `version`,
/// so a stream can tell a change by comparing one number.
public final class SoundSettingsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: SoundSettings
    private var count = 0

    public init(_ settings: SoundSettings = SoundSettings()) {
        self.settings = settings
    }

    public func set(_ next: SoundSettings) {
        lock.lock()
        settings = next
        count += 1
        lock.unlock()
    }

    public var version: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    public func read() -> (version: Int, settings: SoundSettings) {
        lock.lock()
        defer { lock.unlock() }
        return (count, settings)
    }
}

/// Octo's shaping as one step of a player's audio path, for one stream of sound: a deck, or
/// one song's tap. Each runs its own, all following the same settings.
///
/// A song's loudness is handed over with `setNextSong` and taken up at the next `flush`, which
/// comes once the song before has played out, so the level changes exactly between the two
/// songs. Whether the step runs is decided when the stream is set up (`configure`): it runs
/// while the settings shape the sound, or always while `keepActive` says so, passing the sound
/// through unchanged until there is something to shape.
public final class ShapingStep: @unchecked Sendable {
    private let source: SoundSettingsBox
    private let keepActive: @Sendable () -> Bool
    private let lock = NSLock()
    private var pendingSong: SongLoudness?
    private var song: SongLoudness?
    private var shaper: SoundShaper?
    /// The settings version last taken up.
    private var seen: Int?
    public private(set) var isActive = false
    public private(set) var sampleRate = 48_000.0
    public private(set) var channels = 2
    /// Sound to play while the limiter's delay fills at the start of the stream, in place of
    /// silence: the end of the song before, handed over.
    private var lead: [[Float]] = []
    private var leadUsed = 0

    public init(settings: SoundSettingsBox, keepActive: @escaping @Sendable () -> Bool = { false }) {
        source = settings
        self.keepActive = keepActive
    }

    /// The loudness of the song that plays after the current one.
    public func setNextSong(_ next: SongLoudness) {
        lock.lock()
        pendingSong = next
        lock.unlock()
    }

    /// Sets up the step for a stream's format. Returns whether it runs; when it does not, the
    /// sound passes through untouched, bit for bit.
    @discardableResult
    public func configure(sampleRate: Double, channels: Int) -> Bool {
        self.sampleRate = sampleRate
        self.channels = channels
        isActive = source.read().settings.shapesSound || keepActive()
        return isActive
    }

    /// Runs once the song before has played out, and after a jump to another place. A new
    /// song's level holds from its very first sample; anything else that changed glides in.
    /// `lead` is the end of the song before, played while the delay fills.
    public func flush(lead: [[Float]]? = nil) {
        lock.lock()
        let newSong = pendingSong
        pendingSong = nil
        lock.unlock()
        if let newSong { song = newSong }
        guard isActive else { return }
        let kept = shaper.flatMap { $0.sampleRate == sampleRate && $0.channels == channels ? $0 : nil }
        let current = kept ?? SoundShaper(sampleRate: sampleRate, channels: channels)
        shaper = current
        current.clearHeld()
        let now = source.read()
        seen = now.version
        current.apply(now.settings, song: song, instant: kept == nil || newSong != nil)
        self.lead = (lead ?? []).count == channels ? (lead ?? []) : []
        leadUsed = 0
    }

    /// Shapes `frames` frames of `input` and writes what comes out to `output`, which may be
    /// the same buffers. Returns the frames written: fewer than went in only while the
    /// limiter's delay fills; `endOfStream` hands out the rest.
    public func process(_ input: [UnsafeMutablePointer<Float>], frames: Int, output: [UnsafeMutablePointer<Float>]) -> Int {
        guard frames > 0 else { return 0 }
        guard isActive, input.count == channels, output.count == channels else {
            for (from, to) in zip(input, output) where from != to { to.update(from: from, count: frames) }
            return frames
        }
        let current = shaperForStream()
        if source.version != seen {
            let now = source.read()
            seen = now.version
            current.apply(now.settings, song: song, instant: false)
        }
        return current.process(input, frames: frames, output: output)
    }

    /// Shapes `frames` frames in place, the same number out as in, for a path that cannot
    /// hand out more or fewer frames than it was given. While the delay fills at the start of
    /// a stream, the end of the song before plays (when it was handed over), else silence.
    public func process(_ buffers: [UnsafeMutablePointer<Float>], frames: Int) {
        guard isActive, buffers.count == channels, frames > 0 else { return }
        let written = process(buffers, frames: frames, output: buffers)
        guard written < frames else { return }
        shiftToEnd(buffers, frames: frames, written: written)
        let gap = frames - written
        let available = lead.first.map { $0.count - leadUsed } ?? 0
        let take = min(gap, available)
        guard take > 0 else { return }
        // The handed-over sound lands right before the first shaped frame.
        let start = gap - take
        for ch in 0..<channels {
            lead[ch].withUnsafeBufferPointer { from in
                guard let base = from.baseAddress else { return }
                (buffers[ch] + start).update(from: base + leadUsed, count: take)
            }
        }
        leadUsed += take
    }

    /// Hands out the sound still held back, at the end of a stream. `output` needs room for
    /// `latency` frames. Returns the frames written.
    public func endOfStream(into output: [UnsafeMutablePointer<Float>]) -> Int {
        guard isActive, let shaper, output.count == channels else { return 0 }
        return shaper.drain(output)
    }

    /// How many frames late the sound comes out while the step runs.
    public var latency: Int { isActive ? shaperForStream().latency : 0 }

    /// Forgets everything about the stream.
    public func reset() {
        shaper = nil
        song = nil
        seen = nil
        lead = []
        leadUsed = 0
    }

    private func shaperForStream() -> SoundShaper {
        if let shaper, shaper.sampleRate == sampleRate, shaper.channels == channels { return shaper }
        let made = SoundShaper(sampleRate: sampleRate, channels: channels)
        shaper = made
        return made
    }
}

/// Passes the last moment of one song's sound to the stream of the song after it, for paths
/// that give each song a stream of its own: what the limiter still held when the song ended
/// plays at the start of the next one, so nothing is lost or added between them. A hand-over
/// waits only `window` seconds, so a song started later does not open with an old one's end.
public final class SoundHandOff: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [[Float]] = []
    private var sampleRate = 0.0
    private var at = -Double.infinity
    public let window: Double

    public init(window: Double = 0.5) {
        self.window = window
    }

    /// Keeps `count` frames of `buffers`, one buffer per channel, from a song that just ended.
    public func put(_ buffers: [UnsafeMutablePointer<Float>], count: Int, sampleRate: Double, now: Double) {
        let kept = count > 0 ? buffers.map { Array(UnsafeBufferPointer(start: $0, count: count)) } : []
        lock.lock()
        frames = kept
        self.sampleRate = sampleRate
        at = now
        lock.unlock()
    }

    /// The sound handed over for a stream of this format, taken once, or nothing when there is
    /// none, it is for another format, or it waited too long.
    public func take(sampleRate: Double, channels: Int, now: Double) -> [[Float]]? {
        lock.lock()
        defer {
            frames = []
            lock.unlock()
        }
        guard !frames.isEmpty, frames.count == channels, self.sampleRate == sampleRate, now - at <= window, now >= at else { return nil }
        return frames
    }
}
