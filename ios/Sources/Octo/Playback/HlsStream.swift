import Foundation
import OctoKit

/// A live HLS station's sound as it comes, for the live decoder: its playlist is read again as
/// it grows, each new segment fetched in turn and its sound taken out (from a transport stream,
/// or packed AAC or MP3). A playlist or segment that fails is asked for again after 1, 2, 4 and
/// 8 s; after that the station has failed. Encrypted and fragmented MP4 streams are refused.
final class HlsBytes: LiveByteSource, @unchecked Sendable {
    private let condition = NSCondition()
    private var buffer = Data()
    private var failure: PlayError?
    private var finished = false
    private var cancelled = false
    private var kind: HlsSound?
    private var reading: Task<Void, Never>?
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// Unread sound past this waits before the next segment is fetched.
    private static let holdAbove = 1 << 20

    init(url: URL) {
        reading = Task.detached(priority: .userInitiated) { [weak self] in await self?.read(from: url) }
    }

    var contentType: String? { condition.withLock { kind?.rawValue } }

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
        var last: Int?
        var retries = 0
        var pickedStream = false
        while !stopped {
            do {
                let text = String(decoding: try await fetch(playlist), as: UTF8.self)
                guard let parsed = parseHlsPlaylist(text, base: playlist) else {
                    throw PlayError(.parsingManifestMalformed, detail: "not an HLS playlist")
                }
                switch parsed {
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
                    let segments = hlsNextSegments(media, after: last)
                    for segment in segments {
                        await waitForRoom()
                        if stopped { return }
                        let data = try await fetch(segment.uri)
                        guard let found = hlsSegmentSound(data) else {
                            throw PlayError(.parsingContainerUnsupported, detail: "segment kind not read")
                        }
                        add(found.sound, found.kind)
                        last = segment.sequence
                        retries = 0
                    }
                    if media.ended {
                        condition.withLock {
                            finished = true
                            condition.broadcast()
                        }
                        return
                    }
                    // A playlist that grew is read again after one segment's time, one that did
                    // not after half of it.
                    let wait = segments.isEmpty ? media.targetSeconds / 2 : media.targetSeconds
                    try await Task.sleep(for: .milliseconds(Int(max(1, wait) * 1000)))
                }
            } catch {
                if stopped || error is CancellationError { return }
                let why = error as? PlayError ?? PlayError(.networkConnectionFailed, detail: "\((error as? URLError)?.code.rawValue ?? 0)")
                // A stream this app cannot read fails at once; a network failure is tried again.
                switch why.code {
                case .parsingManifestUnsupported, .parsingContainerUnsupported, .parsingManifestMalformed:
                    fail(why)
                    return
                case .badHttpStatus where !liveStatusRetries(why.httpStatus ?? 0):
                    fail(why)
                    return
                default:
                    break
                }
                guard retries < liveReconnectDelays.count else {
                    fail(why)
                    return
                }
                let wait = liveReconnectDelays[retries]
                retries += 1
                playbackLog.info("hls stream lost (\(why.detail, privacy: .public)), again in \(wait, privacy: .public) s")
                try? await Task.sleep(for: .milliseconds(Int(wait * 1000)))
            }
        }
    }

    private func fetch(_ url: URL) async throws -> Data {
        guard OnlineWatch.shared.online else { throw PlayError(.networkConnectionFailed, detail: "No connection") }
        let (data, response) = try await session.data(for: URLRequest(url: url))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw PlayError(.badHttpStatus, httpStatus: http.statusCode, detail: "HTTP \(http.statusCode)")
        }
        return data
    }
}
