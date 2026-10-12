import AVFoundation
import Foundation
import OctoKit

/// Turns a song the system's media library holds (or any file its own reader can open) into
/// sound, through an asset reader. A jump starts a new reader at the place asked for.
final class AssetDecoder: SongDecoding {
    let fileSampleRate: Double
    let channels = 2
    let durationMs: Int?
    let codecMime: String?
    let bitDepth: Int?
    let bitrate: Int?

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let outputRate: Double
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// Interleaved stereo frames read but not yet handed out.
    private var held: [Float] = []
    private var heldAt = 0

    init(url: URL, outputRate: Double) throws {
        asset = AVURLAsset(url: url)
        let loaded = try blocking { [asset] in
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            guard let track = tracks.first else { throw PlayError(.parsingContainerUnsupported, detail: "no audio") }
            let duration = try await asset.load(.duration)
            let formats = try await track.load(.formatDescriptions)
            let rate = try await track.load(.estimatedDataRate)
            return Loaded(track: track, duration: duration, formats: formats, dataRate: rate)
        }
        track = loaded.track
        let seconds = loaded.duration.seconds
        durationMs = seconds.isFinite && seconds > 0 ? Int(seconds * 1000) : nil
        let description = loaded.formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let fileRate = description.flatMap { $0.mSampleRate > 0 ? $0.mSampleRate : nil }
        fileSampleRate = fileRate ?? (outputRate > 0 ? outputRate : 44_100)
        // A rate of 0 asks for the file's own rate.
        self.outputRate = outputRate > 0 ? outputRate : fileSampleRate
        codecMime = description.flatMap { Self.mime(of: $0.mFormatID) }
        bitDepth = description.flatMap { $0.mFormatID == kAudioFormatLinearPCM && $0.mBitsPerChannel > 0 ? Int($0.mBitsPerChannel) : nil }
        bitrate = loaded.dataRate > 0 ? Int(loaded.dataRate) : nil
        try start(at: .zero)
    }

    private struct Loaded: @unchecked Sendable {
        let track: AVAssetTrack
        let duration: CMTime
        let formats: [CMFormatDescription]
        let dataRate: Float
    }

    func read(into buffers: [UnsafeMutablePointer<Float>], frames: Int) throws -> Int {
        var written = 0
        while written < frames {
            if heldAt >= held.count {
                guard try refill() else { break }
            }
            let available = (held.count - heldAt) / 2
            let take = min(available, frames - written)
            held.withUnsafeBufferPointer { samples in
                for i in 0..<take {
                    buffers[0][written + i] = samples[heldAt + 2 * i]
                    if buffers.count > 1 { buffers[1][written + i] = samples[heldAt + 2 * i + 1] }
                }
            }
            heldAt += take * 2
            written += take
        }
        return written
    }

    func seek(toMs ms: Int) throws {
        try start(at: CMTime(value: CMTimeValue(max(0, ms)), timescale: 1000))
    }

    func close() {
        reader?.cancelReading()
        reader = nil
        output = nil
    }

    private func start(at time: CMTime) throws {
        reader?.cancelReading()
        held = []
        heldAt = 0
        let next: AVAssetReader
        do {
            next = try AVAssetReader(asset: asset)
        } catch {
            throw PlayError(.fileNotFound, detail: "\(error)")
        }
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
            AVSampleRateKey: outputRate,
            AVNumberOfChannelsKey: 2,
            AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size),
        ]
        let trackOutput = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        trackOutput.alwaysCopiesSampleData = false
        guard next.canAdd(trackOutput) else { throw PlayError(.decodingFormatUnsupported, detail: "reader output") }
        next.add(trackOutput)
        if time > .zero { next.timeRange = CMTimeRange(start: time, duration: .positiveInfinity) }
        guard next.startReading() else { throw PlayError(.decodingFailed, detail: "\(next.error.map { "\($0)" } ?? "start")") }
        reader = next
        output = trackOutput
    }

    /// Reads the next stretch from the reader; false at the end.
    private func refill() throws -> Bool {
        guard let output, let reader else { return false }
        guard let sample = output.copyNextSampleBuffer() else {
            if reader.status == .failed { throw PlayError(.decodingFailed, detail: "\(reader.error.map { "\($0)" } ?? "read")") }
            return false
        }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return try refill() }
        let length = CMBlockBufferGetDataLength(block)
        let count = length / MemoryLayout<Float>.size
        held = [Float](repeating: 0, count: count)
        heldAt = 0
        held.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
        }
        return count > 0 ? true : try refill()
    }

    private static func mime(of format: AudioFormatID) -> String? {
        switch format {
        case kAudioFormatFLAC: "audio/flac"
        case kAudioFormatAppleLossless: "audio/alac"
        case kAudioFormatMPEGLayer3: "audio/mpeg"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: "audio/mp4a-latm"
        case kAudioFormatLinearPCM: "audio/wav"
        default: nil
        }
    }
}

/// Runs async work from a thread that may wait, and hands back its answer.
func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let box = BlockingBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
        done.signal()
    }
    done.wait()
    guard let result = box.result else { throw PlayError(.unspecified, detail: "no answer") }
    return try result.get()
}

/// Where async work leaves its answer for a waiting thread.
private final class BlockingBox<T>: @unchecked Sendable {
    var result: Result<T, Error>?
}
