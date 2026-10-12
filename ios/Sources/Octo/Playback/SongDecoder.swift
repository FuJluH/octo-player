import AudioToolbox
import AVFoundation
import Foundation
import OctoKit

/// What turns a song into sound: floats, one buffer per channel (one or two), at the rate the
/// decks play at. Reads may block while the bytes are on their way, so it runs on its own thread.
protocol SongDecoding: AnyObject {
    /// The rate of the file itself.
    var fileSampleRate: Double { get }
    /// The channels handed out: one or two.
    var channels: Int { get }
    /// The song's length in milliseconds, when known.
    var durationMs: Int? { get }
    /// What the file was found to be, for the quality badge.
    var codecMime: String? { get }
    var bitDepth: Int? { get }
    var bitrate: Int? { get }
    /// Up to `frames` frames into `buffers` (one per handed-out channel); 0 at the end.
    func read(into buffers: [UnsafeMutablePointer<Float>], frames: Int) throws -> Int
    /// Moves to a place in the song.
    func seek(toMs ms: Int) throws
    func close()
}

/// Turns a song's bytes into sound through the system's file reader.
final class SongDecoder: SongDecoding {
    /// The rate and channels of the file itself.
    let fileSampleRate: Double
    let fileChannels: Int
    /// The channels handed out: one or two.
    let channels: Int
    /// The rate handed out.
    let outputRate: Double
    /// The song's length in its own frames, when the file says.
    let fileFrames: Int64
    /// What the decoder found the file to be, for the quality badge.
    let codecMime: String?
    let bitDepth: Int?
    let bitrate: Int?

    private let box: SourceBox
    private var file: AudioFileID?
    private var ext: ExtAudioFileRef?
    private let list: UnsafeMutableAudioBufferListPointer

    /// The song's length in milliseconds, when known.
    var durationMs: Int? {
        guard fileFrames > 0, fileSampleRate > 0 else { return nil }
        return Int(Double(fileFrames) * 1000 / fileSampleRate)
    }

    init(source: ByteSource, mimeType: String?, outputRate: Double) throws {
        box = SourceBox(source)
        // The length comes first: the file is opened only once its size is known.
        _ = try source.length()

        var fileID: AudioFileID?
        let read: AudioFile_ReadProc = { client, position, count, buffer, actual in
            let box = Unmanaged<SourceBox>.fromOpaque(client).takeUnretainedValue()
            return box.read(position, count, buffer, actual)
        }
        let size: AudioFile_GetSizeProc = { client in
            Unmanaged<SourceBox>.fromOpaque(client).takeUnretainedValue().size()
        }
        let opened = AudioFileOpenWithCallbacks(Unmanaged.passUnretained(box).toOpaque(), read, nil, size, nil,
                                                Self.typeHint(mimeType ?? source.contentType), &fileID)
        guard opened == noErr, let fileID else { throw box.failure ?? Self.openError(opened) }
        file = fileID

        var extRef: ExtAudioFileRef?
        guard ExtAudioFileWrapAudioFileID(fileID, false, &extRef) == noErr, let extRef else {
            AudioFileClose(fileID)
            throw box.failure ?? PlayError(.decodingFormatUnsupported, detail: "no decoder")
        }
        ext = extRef

        var fileFormat = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        ExtAudioFileGetProperty(extRef, kExtAudioFileProperty_FileDataFormat, &formatSize, &fileFormat)
        fileSampleRate = fileFormat.mSampleRate > 0 ? fileFormat.mSampleRate : (outputRate > 0 ? outputRate : 44_100)
        // A rate of 0 asks for the file's own rate.
        self.outputRate = outputRate > 0 ? outputRate : fileSampleRate
        fileChannels = max(1, Int(fileFormat.mChannelsPerFrame))
        channels = min(fileChannels, 2)
        codecMime = Self.mime(of: fileFormat.mFormatID)

        var frames: Int64 = 0
        var framesSize = UInt32(MemoryLayout<Int64>.size)
        ExtAudioFileGetProperty(extRef, kExtAudioFileProperty_FileLengthFrames, &framesSize, &frames)
        fileFrames = frames

        var depth: Int32 = 0
        var depthSize = UInt32(MemoryLayout<Int32>.size)
        if AudioFileGetProperty(fileID, kAudioFilePropertySourceBitDepth, &depthSize, &depth) == noErr, depth != 0 {
            bitDepth = Int(abs(depth))
        } else {
            bitDepth = fileFormat.mFormatID == kAudioFormatLinearPCM && fileFormat.mBitsPerChannel > 0 ? Int(fileFormat.mBitsPerChannel) : nil
        }
        var rate: UInt32 = 0
        var rateSize = UInt32(MemoryLayout<UInt32>.size)
        bitrate = AudioFileGetProperty(fileID, kAudioFilePropertyBitRate, &rateSize, &rate) == noErr && rate > 0 ? Int(rate) : nil

        var client = AudioStreamBasicDescription(
            mSampleRate: self.outputRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32,
            mReserved: 0)
        list = AudioBufferList.allocate(maximumBuffers: channels)
        let set = ExtAudioFileSetProperty(extRef, kExtAudioFileProperty_ClientDataFormat,
                                          UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
        guard set == noErr else {
            close()
            throw PlayError(.decodingFormatUnsupported, detail: "client format \(set)")
        }
    }

    deinit {
        close()
        free(list.unsafeMutablePointer)
    }

    func close() {
        if let ext { ExtAudioFileDispose(ext) }
        ext = nil
        if let file { AudioFileClose(file) }
        file = nil
    }

    /// Up to `frames` frames into `buffers` (one per handed-out channel, each with room for
    /// `frames`); 0 at the end of the song.
    func read(into buffers: [UnsafeMutablePointer<Float>], frames: Int) throws -> Int {
        guard let ext, frames > 0 else { return 0 }
        for ch in 0..<channels {
            list[ch] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(buffers[ch]))
        }
        var count = UInt32(frames)
        let status = ExtAudioFileRead(ext, &count, list.unsafeMutablePointer)
        if status != noErr {
            if let failure = box.failure { throw failure }
            throw PlayError(.decodingFailed, detail: "read \(status)")
        }
        return Int(count)
    }

    /// Moves to a place in the song.
    func seek(toMs ms: Int) throws {
        guard let ext else { return }
        let frame = Int64(Double(max(0, ms)) * fileSampleRate / 1000)
        let status = ExtAudioFileSeek(ext, frame)
        if status != noErr {
            if let failure = box.failure { throw failure }
            throw PlayError(.decodingFailed, detail: "seek \(status)")
        }
    }

    private static func typeHint(_ mime: String?) -> AudioFileTypeID {
        switch mime?.lowercased() {
        case "audio/flac", "audio/x-flac": kAudioFileFLACType
        case "audio/mpeg", "audio/mp3": kAudioFileMP3Type
        case "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/alac", "audio/mp4a-latm": kAudioFileM4AType
        case "audio/aac", "audio/aacp", "audio/x-aac": kAudioFileAAC_ADTSType
        case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave": kAudioFileWAVEType
        case "audio/aiff", "audio/x-aiff": kAudioFileAIFFType
        case "audio/x-caf": kAudioFileCAFType
        default: 0
        }
    }

    private static func mime(of format: AudioFormatID) -> String? {
        switch format {
        case kAudioFormatFLAC: "audio/flac"
        case kAudioFormatAppleLossless: "audio/alac"
        case kAudioFormatMPEGLayer3, kAudioFormatMPEGLayer2, kAudioFormatMPEGLayer1: "audio/mpeg"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2, kAudioFormatMPEG4AAC_LD, kAudioFormatMPEG4AAC_ELD:
            "audio/mp4a-latm"
        case kAudioFormatLinearPCM: "audio/wav"
        case kAudioFormatOpus: "audio/opus"
        default: nil
        }
    }

    private static func openError(_ status: OSStatus) -> PlayError {
        switch status {
        case kAudioFileUnsupportedFileTypeError: PlayError(.parsingContainerUnsupported, detail: "type")
        case kAudioFileUnsupportedDataFormatError: PlayError(.decodingFormatUnsupported, detail: "format")
        case kAudioFileInvalidFileError, kAudioFileInvalidPacketOffsetError, kAudioFileEndOfFileError:
            PlayError(.parsingContainerMalformed, detail: "file \(status)")
        default: PlayError(.parsingContainerMalformed, detail: "open \(status)")
        }
    }
}

/// The byte source as the system's file reader calls it, keeping the first failure.
private final class SourceBox {
    let source: ByteSource
    private(set) var failure: PlayError?

    init(_ source: ByteSource) { self.source = source }

    func size() -> Int64 { (try? source.length()) ?? 0 }

    func read(_ position: Int64, _ count: UInt32, _ buffer: UnsafeMutableRawPointer, _ actual: UnsafeMutablePointer<UInt32>) -> OSStatus {
        do {
            let got = try source.read(at: position, into: buffer, count: Int(count))
            actual.pointee = UInt32(got)
            return noErr
        } catch let error as PlayError {
            if failure == nil { failure = error }
            actual.pointee = 0
            return kAudioFileUnspecifiedError
        } catch {
            failure = failure ?? PlayError(.ioUnspecified, detail: "\(error)")
            actual.pointee = 0
            return kAudioFileUnspecifiedError
        }
    }
}
