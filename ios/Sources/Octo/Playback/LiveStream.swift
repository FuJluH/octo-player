import AudioToolbox
import AVFoundation
import Foundation
import Observation
import OctoKit

/// A live station's bytes as they come, read in order by the live decoder.
protocol LiveByteSource: ByteSource {
    /// The next bytes as they come, up to `count`; none once the stream has ended.
    func next(_ count: Int) throws -> Data
}

/// What each live station named last, by its queue id, as its stream says (its ICY metadata):
/// the title and the address sent with it. An empty title stays, since it says the station names
/// nothing now.
@MainActor
@Observable
final class LiveTitleBoard {
    static let shared = LiveTitleBoard()

    private(set) var titles: [String: IcyMeta] = [:]
    /// Told after a title changes, for the lock screen.
    @ObservationIgnored var onChange: (() -> Void)?

    private init() {}

    func set(_ trackId: String, _ meta: IcyMeta?) {
        guard titles[trackId] != meta else { return }
        titles[trackId] = meta
        onChange?()
    }

    /// What the live player shows for the station `trackId` now.
    func shown(_ trackId: String) -> LiveShown? { liveShown(trackId, titles[trackId]) }

    /// Sets a title from a stream's own thread.
    nonisolated static func post(_ trackId: String, _ meta: IcyMeta?) {
        Task { @MainActor in shared.set(trackId, meta) }
    }
}

/// A live station's bytes as they arrive: no length and no end. Reads wait for them; the download
/// waits while a good stretch sits unread (a long pause), so the phone does not fill up. ICY
/// metadata is asked for and taken out of the sound, each title handed to `onTitle` once the
/// sound sent before it has been read. A stream that fails or ends is asked for again as
/// `LiveReconnect` says; then it has failed. A station
/// that answers with a playlist (by its type, or `#EXTM3U` at its start) stops at once and names
/// it in `playlistAddress`, for the opener to read as HLS.
final class LiveBytes: NSObject, LiveByteSource, URLSessionDataDelegate, @unchecked Sendable {
    private let condition = NSCondition()
    private let request: URLRequest
    private let onTitle: (@Sendable (IcyMeta?) -> Void)?
    private var buffer = Data()
    /// Sound bytes the stream has given, and those read out to play, across reconnects.
    private var soundIn: Int64 = 0
    private var soundRead: Int64 = 0
    /// Titles waiting for the sound sent before them to be read.
    private var titleQueue = IcyTitleQueue()
    private var failure: PlayError?
    private var cancelled = false
    private var held = false
    private var type: String?
    private var task: URLSessionDataTask?
    /// The ICY metadata reader for the connection in use, when the station sends metadata.
    private var icy: IcyReader?
    private var reconnect = LiveReconnect()
    /// Whether any sound came yet, on any connection.
    private var heardAny = false
    /// The address the connection in use answered from.
    private var answeredFrom: URL?
    /// The playlist the station answered with instead of a stream, if it did.
    private var playlist: URL?
    private lazy var session: URLSession = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 30
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    /// Unread bytes past this hold the download; under the lower mark it carries on.
    private static let holdAbove = 1 << 20
    private static let carryOnBelow = 256 << 10

    init(request: URLRequest, onTitle: (@Sendable (IcyMeta?) -> Void)? = nil) {
        var asked = request
        asked.setValue("1", forHTTPHeaderField: "Icy-MetaData")
        self.request = asked
        self.onTitle = onTitle
        super.init()
        onTitle?(nil)
        condition.withLock { connect() }
    }

    /// Opens a connection. Called with the lock held.
    private func connect() {
        icy = nil
        held = false
        reconnect.connected()
        let next = session.dataTask(with: request)
        task = next
        next.resume()
    }

    var contentType: String? { condition.withLock { type } }

    /// The playlist the station answered with instead of a stream, once it has.
    var playlistAddress: URL? { condition.withLock { playlist } }

    /// A live stream has no length.
    func length() throws -> Int64 { throw PlayError(.ioUnspecified, detail: "a live stream has no length") }

    /// A live stream is read in order only, through `next`.
    func read(at offset: Int64, into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        let data = try next(count)
        data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
        return data.count
    }

    func next(_ count: Int) throws -> Data {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if cancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
            if !buffer.isEmpty {
                let taken = Data(buffer.prefix(count))
                buffer.removeFirst(taken.count)
                soundRead += Int64(taken.count)
                if let onTitle, !titleQueue.isEmpty {
                    for meta in titleQueue.due(read: soundRead) { onTitle(meta) }
                }
                if held && buffer.count < Self.carryOnBelow {
                    held = false
                    task?.resume()
                }
                return taken
            }
            if let failure { throw failure }
            condition.wait(until: Date().addingTimeInterval(0.5))
        }
    }

    func cancel() {
        condition.lock()
        cancelled = true
        task?.cancel()
        task = nil
        condition.broadcast()
        condition.unlock()
        session.invalidateAndCancel()
    }

    /// Fails for good. Called with the lock held.
    private func failNow(_ why: PlayError) {
        task = nil
        if failure == nil { failure = why }
        condition.broadcast()
    }

    /// The connection in use stopped: asks again after the next wait, or fails once the waits
    /// are used up or the answer refused the stream. Called with the lock held.
    private func lost(_ why: PlayError) {
        task = nil
        guard !cancelled, failure == nil else { return }
        switch reconnect.lost(status: why.code == .badHttpStatus ? why.httpStatus : nil) {
        case .fail:
            failNow(why)
        case .again(let wait):
            playbackLog.info("live stream lost (\(why.detail, privacy: .public)), again in \(wait, privacy: .public) s")
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + wait) { [weak self] in
                guard let self else { return }
                self.condition.withLock {
                    if !self.cancelled && self.failure == nil && self.task == nil { self.connect() }
                }
            }
        }
    }

    /// The station answered with a playlist: stops, naming it. Called with the lock held.
    private func answeredWithPlaylist() {
        playlist = answeredFrom ?? request.url
        failNow(PlayError(.parsingManifestUnsupported, detail: "a playlist"))
    }

    // MARK: Session delegate

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        ServerTrust.shared.answer(challenge)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        ServerTrust.shared.answer(challenge)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        condition.lock()
        defer { condition.unlock() }
        guard dataTask === task else {
            completionHandler(.cancel)
            return
        }
        answeredFrom = response.url
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            completionHandler(.cancel)
            lost(PlayError(.badHttpStatus, httpStatus: http.statusCode, detail: "HTTP \(http.statusCode)"))
            return
        }
        if !heardAny, isHlsPlaylistType(response.mimeType) {
            completionHandler(.cancel)
            answeredWithPlaylist()
            return
        }
        if let http = response as? HTTPURLResponse,
           let every = http.value(forHTTPHeaderField: "icy-metaint").flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
           every > 0 {
            icy = IcyReader(interval: every)
        }
        if type == nil { type = response.mimeType }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        var titles: [IcyMeta] = []
        condition.lock()
        guard dataTask === task else {
            condition.unlock()
            return
        }
        if !heardAny && startsLikePlaylist(data) {
            dataTask.cancel()
            answeredWithPlaylist()
            condition.unlock()
            return
        }
        if var reader = icy {
            let split = reader.feedMarked(data)
            icy = reader
            // Each title waits for the sound before it to be read, so it changes as its song
            // starts rather than as its bytes arrive.
            for mark in split.titles { titleQueue.hold(mark.meta, at: soundIn + Int64(mark.at)) }
            buffer.append(split.sound)
            soundIn += Int64(split.sound.count)
            reconnect.heard(split.sound.count)
            titles = titleQueue.due(read: soundRead)
        } else {
            buffer.append(data)
            soundIn += Int64(data.count)
            reconnect.heard(data.count)
        }
        heardAny = true
        if !held && buffer.count > Self.holdAbove {
            held = true
            dataTask.suspend()
        }
        condition.broadcast()
        condition.unlock()
        if let onTitle { for title in titles { onTitle(title) } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        condition.lock()
        defer { condition.unlock() }
        guard task === self.task else { return }
        if let error {
            let urlError = error as? URLError
            if urlError?.code == .cancelled { return }
            let code: PlayErrorCode = urlError?.code == .timedOut ? .networkConnectionTimeout : .networkConnectionFailed
            lost(PlayError(code, detail: urlError.map { "\($0.code.rawValue)" } ?? "network"))
        } else {
            lost(PlayError(.networkConnectionFailed, detail: "the stream ended"))
        }
    }
}

/// Turns a live station into sound as its bytes arrive: the stream is cut into packets as it
/// comes and decoded to the decks' rate. It has no length, and no place in it can be chosen.
final class LiveStreamDecoder: SongDecoding {
    let fileSampleRate: Double
    let channels: Int
    let durationMs: Int? = nil
    let codecMime: String?
    let bitDepth: Int? = nil
    let bitrate: Int?

    private let bytes: any LiveByteSource
    private let parser: PacketParser
    private var converter: AudioConverterRef?
    private let list: UnsafeMutableAudioBufferListPointer
    /// The packet handed to the converter, kept until it asks for the next one.
    private var packet = UnsafeMutableRawPointer.allocate(byteCount: 8_192, alignment: 16)
    private var packetRoom = 8_192
    private let packetDescription = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
    private var failure: PlayError?
    private var ended = false

    /// How much is read from the station at a time.
    private static let readSize = 16_384

    init(bytes: any LiveByteSource, mimeType: String?, outputRate: Double) throws {
        self.bytes = bytes
        list = AudioBufferList.allocate(maximumBuffers: 2)
        // The type the station says it sends, read once its answer is in.
        var first = try bytes.next(Self.readSize)
        let parser = try PacketParser(hint: Self.typeHint(mimeType ?? bytes.contentType))
        self.parser = parser
        while parser.format == nil {
            guard !first.isEmpty else { throw PlayError(.parsingContainerMalformed, detail: "the stream ended at once") }
            try parser.parse(first)
            if parser.format == nil { first = try bytes.next(Self.readSize) }
        }
        guard var format = parser.format else { throw PlayError(.parsingContainerUnsupported, detail: "no format") }
        fileSampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        channels = min(max(1, Int(format.mChannelsPerFrame)), 2)
        codecMime = Self.mime(of: format.mFormatID)
        bitrate = parser.bitrate > 0 ? Int(parser.bitrate) : nil
        let rate = outputRate > 0 ? outputRate : fileSampleRate
        var client = AudioStreamBasicDescription(
            mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32,
            mReserved: 0)
        var made: AudioConverterRef?
        let status = AudioConverterNew(&format, &client, &made)
        guard status == noErr, let made else { throw PlayError(.decodingFormatUnsupported, detail: "converter \(status)") }
        converter = made
        if let cookie = parser.cookie {
            cookie.withUnsafeBytes { raw in
                _ = AudioConverterSetProperty(made, kAudioConverterDecompressionMagicCookie, UInt32(cookie.count), raw.baseAddress!)
            }
        }
    }

    deinit {
        close()
        free(list.unsafeMutablePointer)
        packet.deallocate()
        packetDescription.deallocate()
    }

    func close() {
        if let converter { AudioConverterDispose(converter) }
        converter = nil
        parser.close()
    }

    /// A live station plays from where it is now; there is no place to move to.
    func seek(toMs ms: Int) throws {}

    func read(into buffers: [UnsafeMutablePointer<Float>], frames: Int) throws -> Int {
        guard let converter, frames > 0, !ended else { return 0 }
        for ch in 0..<channels {
            list[ch] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4), mData: UnsafeMutableRawPointer(buffers[ch]))
        }
        list.unsafeMutablePointer.pointee.mNumberBuffers = UInt32(channels)
        var count = UInt32(frames)
        let input: AudioConverterComplexInputDataProc = { _, packets, data, descriptions, client in
            guard let client else { return -1 }
            return Unmanaged<LiveStreamDecoder>.fromOpaque(client).takeUnretainedValue().supply(packets, data, descriptions)
        }
        let status = AudioConverterFillComplexBuffer(converter, input, Unmanaged.passUnretained(self).toOpaque(), &count,
                                                     list.unsafeMutablePointer, nil)
        if count > 0 { return Int(count) }
        if let failure { throw failure }
        if status != noErr && !ended { throw PlayError(.decodingFailed, detail: "decode \(status)") }
        ended = true
        return 0
    }

    /// Hands the converter the next packet, reading more of the station when none waits. None at
    /// the end of the stream or after a failure.
    private func supply(_ packets: UnsafeMutablePointer<UInt32>, _ data: UnsafeMutablePointer<AudioBufferList>,
                        _ descriptions: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {
        while parser.isEmpty {
            do {
                let more = try bytes.next(Self.readSize)
                if more.isEmpty {
                    ended = true
                    packets.pointee = 0
                    return noErr
                }
                try parser.parse(more)
            } catch {
                failure = error as? PlayError ?? PlayError(.ioUnspecified, detail: "\(error)")
                packets.pointee = 0
                return -1
            }
        }
        let next = parser.take()
        if next.data.count > packetRoom {
            packet.deallocate()
            packet = UnsafeMutableRawPointer.allocate(byteCount: next.data.count, alignment: 16)
            packetRoom = next.data.count
        }
        next.data.copyBytes(to: packet.assumingMemoryBound(to: UInt8.self), count: next.data.count)
        data.pointee.mNumberBuffers = 1
        data.pointee.mBuffers.mData = packet
        data.pointee.mBuffers.mDataByteSize = UInt32(next.data.count)
        data.pointee.mBuffers.mNumberChannels = parser.format?.mChannelsPerFrame ?? 2
        if let descriptions {
            packetDescription.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: next.frames,
                                                                     mDataByteSize: UInt32(next.data.count))
            descriptions.pointee = packetDescription
            packets.pointee = 1
        } else {
            // Plain samples: as many packets as the bytes hold.
            let size = max(1, parser.format?.mBytesPerPacket ?? 1)
            packets.pointee = UInt32(next.data.count) / size
        }
        return noErr
    }

    private static func typeHint(_ mime: String?) -> AudioFileTypeID {
        switch mime?.lowercased() {
        case "audio/mpeg", "audio/mp3", "audio/mpeg3": kAudioFileMP3Type
        case "audio/aac", "audio/aacp", "audio/x-aac": kAudioFileAAC_ADTSType
        case "audio/mp4", "audio/m4a", "audio/x-m4a": kAudioFileM4AType
        default: 0
        }
    }

    private static func mime(of format: AudioFormatID) -> String? {
        switch format {
        case kAudioFormatMPEGLayer3, kAudioFormatMPEGLayer2, kAudioFormatMPEGLayer1: "audio/mpeg"
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2: "audio/mp4a-latm"
        case kAudioFormatLinearPCM: "audio/wav"
        default: nil
        }
    }
}

/// Cuts a stream of bytes into packets with the system's stream parser, and learns the format
/// as it goes.
private final class PacketParser {
    private(set) var format: AudioStreamBasicDescription?
    private(set) var cookie: Data?
    private(set) var bitrate: UInt32 = 0
    private var stream: AudioFileStreamID?
    private var queue: [(data: Data, frames: UInt32)] = []
    private var head = 0

    init(hint: AudioFileTypeID) throws {
        let property: AudioFileStream_PropertyListenerProc = { client, stream, property, _ in
            Unmanaged<PacketParser>.fromOpaque(client).takeUnretainedValue().learned(stream, property)
        }
        let packets: AudioFileStream_PacketsProc = { client, bytes, count, data, descriptions in
            Unmanaged<PacketParser>.fromOpaque(client).takeUnretainedValue().add(bytes, count, data, descriptions)
        }
        var made: AudioFileStreamID?
        let status = AudioFileStreamOpen(Unmanaged.passUnretained(self).toOpaque(), property, packets, hint, &made)
        guard status == noErr, let made else { throw PlayError(.parsingContainerUnsupported, detail: "stream \(status)") }
        stream = made
    }

    var isEmpty: Bool { head >= queue.count }

    func take() -> (data: Data, frames: UInt32) {
        let next = queue[head]
        head += 1
        if head > 256 {
            queue.removeFirst(head)
            head = 0
        }
        return next
    }

    func parse(_ data: Data) throws {
        guard let stream else { return }
        let status = data.withUnsafeBytes { raw in
            AudioFileStreamParseBytes(stream, UInt32(data.count), raw.baseAddress, [])
        }
        switch status {
        case noErr: return
        case kAudioFileStreamError_UnsupportedFileType, kAudioFileStreamError_UnsupportedDataFormat:
            throw PlayError(.parsingContainerUnsupported, detail: "stream type \(status)")
        default:
            throw PlayError(.parsingContainerMalformed, detail: "stream \(status)")
        }
    }

    func close() {
        if let stream { AudioFileStreamClose(stream) }
        stream = nil
    }

    private func learned(_ stream: AudioFileStreamID, _ property: AudioFileStreamPropertyID) {
        switch property {
        case kAudioFileStreamProperty_ReadyToProducePackets:
            var description = AudioStreamBasicDescription()
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_DataFormat, &size, &description) == noErr {
                format = description
            }
            var cookieSize: UInt32 = 0
            var writable: DarwinBoolean = false
            if AudioFileStreamGetPropertyInfo(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &writable) == noErr,
               cookieSize > 0 {
                var bytes = [UInt8](repeating: 0, count: Int(cookieSize))
                if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_MagicCookieData, &cookieSize, &bytes) == noErr {
                    cookie = Data(bytes)
                }
            }
            var rate: UInt32 = 0
            var rateSize = UInt32(MemoryLayout<UInt32>.size)
            if AudioFileStreamGetProperty(stream, kAudioFileStreamProperty_BitRate, &rateSize, &rate) == noErr { bitrate = rate }
        default:
            break
        }
    }

    private func add(_ bytes: UInt32, _ count: UInt32, _ data: UnsafeRawPointer,
                     _ descriptions: UnsafeMutablePointer<AudioStreamPacketDescription>?) {
        if let descriptions {
            for index in 0..<Int(count) {
                let description = descriptions[index]
                let start = Int(description.mStartOffset)
                let size = Int(description.mDataByteSize)
                guard size > 0, start + size <= Int(bytes) else { continue }
                queue.append((Data(bytes: data + start, count: size), description.mVariableFramesInPacket))
            }
        } else if bytes > 0 {
            // Fixed-size packets (plain samples) come as one run.
            queue.append((Data(bytes: data, count: Int(bytes)), 0))
        }
    }
}
