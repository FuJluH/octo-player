import AVFoundation
import MediaToolbox
import OctoKit
import os

/// The audio side of the sound settings: every song plays through Octo's shaping, in order the
/// level (ReplayGain and the equalizer's preamp), the equalizer's filters, mono and balance,
/// then the limiter. Changes glide in over 30 ms, so nothing clicks.
///
/// There are two ways in. A song played by `AVPlayer` gets a tap on its audio track
/// (`songSetUp` then `makeTap(for:asset:)`). An engine that hands over decoded sound itself (a
/// deck) makes one `SoundStream` per deck and runs its buffers through it.
final class SoundProcessor: @unchecked Sendable {
    /// The settings every tap and stream follows.
    let settings = SoundSettingsBox()
    /// The album of the last song set up, for Smart loudness, shared by every tap and deck.
    private let albums = AlbumRun()
    /// The end of a song's sound passed to the tap of the song after it.
    private let handOff = SoundHandOff()
    /// The loudness last announced with `songStarted`, for taps made without their song.
    private let announced = OSAllocatedUnfairLock<SongLoudness?>(initialState: nil)
    private let announcedAlbums = AlbumRun()

    func update(_ next: SoundSettings) {
        settings.set(next)
    }

    /// Decides, in the order songs are set up to play, how a song's loudness is judged: the
    /// values its source keeps, and whether it follows a song from the same album. Call it for
    /// each song as it is queued to play, in play order.
    func songSetUp(_ song: Song) -> SongSetUp {
        let album = albumKey(albumId: song.albumId, albumTitle: song.album, albumArtist: nil, artist: song.artist)
        let follows = albums.follows(song.id.isEmpty ? nil : song.id, album)
        let stored = song.replayGain.flatMap {
            ReplayGainTags.stored(trackGain: $0.trackGain, trackPeak: $0.trackPeak, albumGain: $0.albumGain, albumPeak: $0.albumPeak)
        }
        return SongSetUp(songId: song.id, stored: stored, followsSameAlbum: follows)
    }

    /// The tap for a song's audio track. The song's loudness is fixed as the tap is made: the
    /// tags in its sound when they carry a gain, else the values its source keeps.
    func makeTap(for setUp: SongSetUp, asset: AVAsset) async -> MTAudioProcessingTap? {
        let tags = await Self.loudnessTags(of: asset)
        return makeTap(loudness: setUp.loudness(tags: tags))
    }

    /// A tap for a song not named, at the loudness last announced with `songStarted`.
    func makeTap() -> MTAudioProcessingTap? {
        makeTap(loudness: announced.withLock { $0 })
    }

    /// A song began playing: its loudness, for taps made without their song.
    func songStarted(id: String, albumId: String?, replayGain: ReplayGain?) {
        let follows = announcedAlbums.follows(id.isEmpty ? nil : id, albumId)
        let info = replayGain.flatMap {
            ReplayGainTags.stored(trackGain: $0.trackGain, trackPeak: $0.trackPeak, albumGain: $0.albumGain, albumPeak: $0.albumPeak)
        }
        announced.withLock { $0 = SongLoudness(info, followsSameAlbum: follows) }
    }

    /// A shaping stream for one deck of an engine that runs the sound itself. While
    /// `keepActive` says so (a crossfade is possible), the stream runs even with nothing to
    /// shape, passing the sound through unchanged.
    func makeStream(keepActive: @escaping @Sendable () -> Bool = { false }) -> SoundStream {
        SoundStream(step: ShapingStep(settings: settings, keepActive: keepActive))
    }

    private func makeTap(loudness: SongLoudness?) -> MTAudioProcessingTap? {
        let step = ShapingStep(settings: settings)
        if let loudness { step.setNextSong(loudness) }
        let context = TapContext(step: step, handOff: handOff)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, maxFrames, format in
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .prepare(format.pointee, maxFrames: Int(maxFrames))
            },
            unprepare: { _ in },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, buffers, flagsOut, nil, framesOut) == noErr else { return }
                Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .process(buffers, frames: Int(framesOut.pointee), flags: flagsOut.pointee)
            })
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        if status != noErr { Unmanaged.passUnretained(context).release() }
        return status == noErr ? tap : nil
    }

    /// The loudness tags a song's file carries, as far as the system reads them: ID3 user text
    /// frames, MP4 free-form tags and Vorbis comments.
    private static func loudnessTags(of asset: AVAsset) async -> ReplayGainInfo? {
        guard let items = try? await asset.load(.metadata), !items.isEmpty else { return nil }
        var tags: [LoudnessTag] = []
        for item in items {
            guard let key = item.key as? String, let value = try? await item.load(.stringValue) else { continue }
            let space = item.keySpace?.rawValue ?? ""
            if space == AVMetadataKeySpace.id3.rawValue {
                guard key == "TXXX" else { continue }
                let extra = try? await item.load(.extraAttributes)
                tags.append(.id3UserText(description: extra?[.info] as? String, value: value))
            } else if space == "itlk" || key.hasPrefix("----:") {
                // Free-form tags come as "com.apple.iTunes.NAME" (or "----:com.apple.iTunes:NAME").
                let bare = key.hasPrefix("----:") ? String(key.dropFirst(5)) : key
                let separator = bare.contains(":") ? ":" : "."
                guard let cut = bare.range(of: separator, options: .backwards) else { continue }
                tags.append(.mp4FreeForm(domain: String(bare[..<cut.lowerBound]), name: String(bare[cut.upperBound...]), value: value))
            } else {
                tags.append(.vorbisComment(key: key, value: value))
            }
        }
        return ReplayGainTags.read(tags)
    }
}

/// How a song's loudness is judged, decided when it was set up to play.
struct SongSetUp: Sendable {
    let songId: String
    /// The values its source keeps, checked like tags.
    let stored: ReplayGainInfo?
    let followsSameAlbum: Bool

    /// The song's loudness, given the tags its sound carries.
    func loudness(tags: ReplayGainInfo?) -> SongLoudness {
        SongLoudness(ReplayGainTags.choose(stream: tags, stored: stored), followsSameAlbum: followsSameAlbum)
    }
}

/// One deck's sound shaping, for an engine that hands Octo its decoded sound buffer by buffer
/// (planar floats, full scale at 1). In use:
///
/// - `setNextSong` as each song is set up on the deck; it is taken up at the next `flush`.
/// - `configure` with the stream's format; whether the stream runs is decided here.
/// - `flush` when a song starts (once the one before has played out) and after every seek.
/// - `process` for each buffer, in place (the same number of frames out, a moment late) or
///   from input to output (fewer frames out while the limiter's delay fills).
/// - `endOfStream` at the end of a song, for the frames still held back.
///
/// The crossfade's own stage, when there is one, runs on what comes out.
final class SoundStream: @unchecked Sendable {
    private let step: ShapingStep

    init(step: ShapingStep) {
        self.step = step
    }

    /// The song that plays next on this deck: how it was set up (`SoundProcessor.songSetUp`)
    /// and the loudness tags its file carries, when the engine read them.
    func setNextSong(_ setUp: SongSetUp, tags: ReplayGainInfo? = nil) {
        step.setNextSong(setUp.loudness(tags: tags))
    }

    /// Sets up for a stream's format; returns whether the stream is shaped.
    @discardableResult
    func configure(sampleRate: Double, channels: Int) -> Bool {
        step.configure(sampleRate: sampleRate, channels: channels)
    }

    func flush() {
        step.flush()
    }

    /// Shapes buffers in place, the same number of frames out as in.
    func process(_ channels: [UnsafeMutablePointer<Float>], frames: Int) {
        step.process(channels, frames: frames)
    }

    /// Shapes `input` into `output` (which may be the same buffers); returns the frames written.
    func process(_ input: [UnsafeMutablePointer<Float>], frames: Int, output: [UnsafeMutablePointer<Float>]) -> Int {
        step.process(input, frames: frames, output: output)
    }

    /// Shapes a buffer of planar floats in place.
    func process(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let channels = (0..<Int(buffer.format.channelCount)).map { data[$0] }
        step.process(channels, frames: Int(buffer.frameLength))
    }

    /// Writes the frames still held back to `output` at the end of a song; returns how many.
    func endOfStream(into output: [UnsafeMutablePointer<Float>]) -> Int {
        step.endOfStream(into: output)
    }

    /// Whether this stream is shaped, as decided by the last `configure`.
    var isActive: Bool { step.isActive }

    /// How many frames late the shaped sound comes out.
    var latency: Int { step.latency }

    func reset() {
        step.reset()
    }
}

/// One song's tap on the audio thread. Its stream starts again at every jump in the sound
/// (the start, a seek, a resume), which forgets what the limiter held; at the song's end the
/// held sound passes to the next song's tap.
private final class TapContext: @unchecked Sendable {
    private let step: ShapingStep
    private let handOff: SoundHandOff
    private var supported = false
    private var started = false
    private var sampleRate = 48_000.0
    private var channelCount = 0
    /// The buffers being shaped, reused so the audio thread makes nothing new.
    private var channelData: [UnsafeMutablePointer<Float>] = []
    /// Room for what the limiter still holds when the song ends.
    private var tail: [UnsafeMutablePointer<Float>] = []
    private static let tailRoom = 4_096

    init(step: ShapingStep, handOff: SoundHandOff) {
        self.step = step
        self.handOff = handOff
    }

    deinit {
        for buffer in tail { buffer.deallocate() }
    }

    func prepare(_ format: AudioStreamBasicDescription, maxFrames: Int) {
        let channels = Int(format.mChannelsPerFrame)
        supported = format.mFormatID == kAudioFormatLinearPCM
            && format.mFormatFlags & kAudioFormatFlagIsFloat != 0
            && format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            && format.mBitsPerChannel == 32
            && channels > 0
        guard supported else { return }
        sampleRate = format.mSampleRate
        channelCount = channels
        step.configure(sampleRate: sampleRate, channels: channels)
        if tail.count != channels {
            for buffer in tail { buffer.deallocate() }
            tail = (0..<channels).map { _ in
                let buffer = UnsafeMutablePointer<Float>.allocate(capacity: Self.tailRoom)
                buffer.initialize(repeating: 0, count: Self.tailRoom)
                return buffer
            }
        }
        if let first = tail.first {
            channelData = Array(repeating: first, count: channels)
        }
    }

    func process(_ list: UnsafeMutablePointer<AudioBufferList>, frames: Int, flags: MTAudioProcessingTapFlags) {
        guard supported else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        guard buffers.count == channelCount else { return }
        for (index, buffer) in buffers.enumerated() {
            guard let data = buffer.mData else { return }
            channelData[index] = data.assumingMemoryBound(to: Float.self)
        }
        if flags & MTAudioProcessingTapFlags(kMTAudioProcessingTapFlag_StartOfStream) != 0 || !started {
            let lead = started ? nil : handOff.take(sampleRate: sampleRate, channels: channelCount, now: ProcessInfo.processInfo.systemUptime)
            started = true
            step.flush(lead: lead)
        }
        if frames > 0 { step.process(channelData, frames: frames) }
        if flags & MTAudioProcessingTapFlags(kMTAudioProcessingTapFlag_EndOfStream) != 0, step.latency <= Self.tailRoom {
            let count = step.endOfStream(into: tail)
            handOff.put(tail, count: count, sampleRate: sampleRate, now: ProcessInfo.processInfo.systemUptime)
        }
    }
}
