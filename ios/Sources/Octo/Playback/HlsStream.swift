import Foundation
import OctoKit

/// A live HLS station's sound as it comes, for the live decoder: its playlist is read again as
/// it grows, each new segment fetched in turn and its sound taken out (from a transport stream,
/// or packed AAC or MP3). A playlist that fails, or stops growing for three of its target times,
/// is asked for again after 1, 2, 4 and 8 s; after that the station has failed. Once sound has
/// played, a segment that fails or cannot be read is passed over. Encrypted and fragmented MP4
/// streams are refused, and so is a stream that changes format part way. A plain playlist of
/// whole streams is handed back (`plainEntry`) for the opener to play its first stream.
final class HlsBytes: LiveByteSource, @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var failure: PlayError?
    private var finished = false
    private var cancelled = false
    private var kind: HlsSound?
    private var plain: URL?
    private var reading: Task<Void, Never>?
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    /// Unread sound past this waits before the next segment is fetched.
    private static let holdAbove = 1 << 20
    /// The largest playlist and segment read.
    private static let playlistBytes = 1 << 20
    private static let segmentBytes = 8 << 20

    init(url: URL) {
        reading = Task.detached(priority: .userInitiated) { [weak self] in await self?.read(from: url) }
    }

    var contentType: String? { condition.withLock { kind?.rawValue } }

    /// The first stream of a plain playlist read where HLS was expected, once found.
    var plainEntry: URL? { condition.withLock { plain } }

    func length() throws -> Int64 { throw PlayError(.ioUnspecified, detail: "a live stream has no length") }

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
                return taken
            }
            if let failure { throw failure }
            if finished { return Data() }
            condition.wait(until: Date().addingTimeInterval(0.5))
        }
    }

    func cancel() {
        condition.withLock {
            cancelled = true
            condition.broadcast()
        }
        reading?.cancel()
        session.invalidateAndCancel()
    }

    private var stopped: Bool { condition.withLock { cancelled } }

    private func fail(_ error: PlayError) {
        condition.withLock {
            if failure == nil { failure = error }
            condition.broadcast()
        }
    }

    private func add(_ sound: Data, _ found: HlsSound) {
        condition.withLock {
            if kind == nil { kind = found }
            buffer.append(sound)
            condition.broadcast()
        }
    }

    /// Waits while a good stretch sits unread.
    private func waitForRoom() async {
        while !stopped && condition.withLock({ buffer.count > Self.holdAbove }) {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func read(from start: URL) async {
        var playlist = start
        var follower = HlsFollower()
        var reconnect = LiveReconnect()
        var pickedStream = false
        /// The format of the first sound played, which every later segment must keep.
        var format: (kind: HlsSound, signature: UInt32?)?
        while !stopped {
            do {
                let text = String(decoding: try await fetch(playlist, limit: Self.playlistBytes), as: UTF8.self)
                guard let parsed = parseHlsPlaylist(text, base: playlist) else {
                    throw PlayError(.parsingManifestMalformed, detail: "not an HLS playlist")
                }
                switch parsed {
                case .plain(let entries):
                    guard format == nil, let first = entries.first else {
                        throw PlayError(.parsingManifestMalformed, detail: "an empty playlist")
                    }
                    condition.withLock { plain = first }
                    fail(PlayError(.parsingManifestUnsupported, detail: "a plain playlist"))
                    return
                case .master(let variants, let audio):
                    guard !pickedStream, let stream = hlsPickStream(variants, audio: audio) else {
                        throw PlayError(.parsingManifestUnsupported, detail: "no stream to play")
                    }
                    pickedStream = true
                    playlist = stream
                    continue
                case .media(let media):
                    if media.encrypted { throw PlayError(.parsingManifestUnsupported, detail: "encrypted HLS") }
                    if media.fragmentedMp4 { throw PlayError(.parsingContainerUnsupported, detail: "fragmented MP4 HLS") }
                    switch follower.step(media, now: msSince1970()) {
                    case .finished:
                        condition.withLock {
                            finished = true
                            condition.broadcast()
                        }
                        return
                    case .stalled:
                        throw PlayError(.networkConnectionFailed, detail: "the playlist stopped growing")
                    case .fetch(let segments, let reloadSeconds):
                        for segment in segments {
                            await waitForRoom()
                            if stopped { return }
                            let found: (sound: Data, kind: HlsSound)?
                            do {
                                found = hlsSegmentSound(try await fetch(segment.uri, limit: Self.segmentBytes))
                            } catch {
                                // Once sound has played, a segment that fails is passed over.
                                guard format != nil, !(error is CancellationError) else { throw error }
                                follower.fetched(segment)
                                continue
                            }
                            guard let found else {
                                guard format != nil else { throw PlayError(.parsingContainerUnsupported, detail: "segment kind not read") }
                                follower.fetched(segment)
                                continue
                            }
                            let signature = hlsSoundFormat(found.sound, kind: found.kind)
                            if let format {
                                let changed = format.kind != found.kind
                                    || (format.signature != nil && signature != nil && format.signature != signature)
                                if changed { throw PlayError(.decodingFormatUnsupported, detail: "the stream changed format") }
                            } else {
                                format = (found.kind, signature)
                            }
                            add(found.sound, found.kind)
                            follower.fetched(segment)
                            reconnect.recovered()
                        }
                        try await Task.sleep(for: .milliseconds(Int(max(1, reloadSeconds) * 1000)))
                    }
                }
            } catch {
                if stopped || error is CancellationError { return }
                let why = error as? PlayError ?? PlayError(.networkConnectionFailed, detail: "\((error as? URLError)?.code.rawValue ?? 0)")
                switch why.code {
                case .parsingManifestUnsupported, .parsingContainerUnsupported, .decodingFormatUnsupported:
                    fail(why)
                    return
                case .parsingManifestMalformed where format == nil:
                    // Not a stream at all; once sound has played, a bad reading is tried again.
                    fail(why)
                    return
                default:
                    break
                }
                switch reconnect.lost(status: why.code == .badHttpStatus ? why.httpStatus : nil) {
                case .fail:
                    fail(why)
                    return
                case .again(let wait):
                    playbackLog.info("hls stream lost (\(why.detail, privacy: .public)), again in \(wait, privacy: .public) s")
                    try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
                }
            }
        }
    }

    /// The bytes at `url`, at most `limit` of them.
    private func fetch(_ url: URL, limit: Int) async throws -> Data {
        guard OnlineWatch.shared.online else { throw PlayError(.networkConnectionFailed, detail: "No connection") }
        let (bytes, response) = try await session.bytes(for: URLRequest(url: url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PlayError(.badHttpStatus, httpStatus: http.statusCode, detail: "HTTP \(http.statusCode)")
        }
        if response.expectedContentLength > Int64(limit) { throw PlayError(.parsingContainerMalformed, detail: "too large") }
        var data = Data()
        data.reserveCapacity(Int(max(0, min(response.expectedContentLength, Int64(limit)))))
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw PlayError(.parsingContainerMalformed, detail: "too large") }
        }
        return data
    }
}
