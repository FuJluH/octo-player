import Foundation
import OctoKit

/// Where a song's bytes come from, read from any place, a thread blocking until they are there.
protocol ByteSource: AnyObject, Sendable {
    /// The whole length, once known; blocks until then.
    func length() throws -> Int64
    /// Up to `count` bytes at `offset`; blocks until they are there. Fewer only at the end.
    func read(at offset: Int64, into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int
    /// The type the source says its bytes are, once known.
    var contentType: String? { get }
    /// Stops every read, now and later.
    func cancel()
}

/// A file on the phone.
final class LocalFile: ByteSource, @unchecked Sendable {
    private let handle: FileHandle
    private let size: Int64
    private let lock = NSLock()
    let contentType: String?

    init(url: URL, contentType: String? = nil) throws {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw PlayError(.fileNotFound, detail: url.lastPathComponent) }
        self.handle = handle
        size = Int64((try? handle.seekToEnd()) ?? 0)
        self.contentType = contentType
    }

    deinit { try? handle.close() }

    func length() throws -> Int64 { size }

    func read(at offset: Int64, into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard offset < size else { return 0 }
        try? handle.seek(toOffset: UInt64(offset))
        guard let data = try? handle.read(upToCount: count) else { throw PlayError(.ioUnspecified, detail: "file read") }
        data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
        return data.count
    }

    func cancel() {}
}

/// A song read from the server by parts: what is asked for downloads into a file of its own on
/// the phone, from the place a read needs onwards, so the player can jump about and a part read
/// once is not fetched again. What the songs kept on the phone already hold of it is read from
/// there, and the server is asked only for the parts missing. Each request is signed as it goes
/// out (`sign`), so no address is kept. A failed request is tried again after 0, 1 and 2
/// seconds; a refusal to load at all (no connection, no server) fails at once.
final class RemoteFile: NSObject, ByteSource, URLSessionDataDelegate, @unchecked Sendable {
    private let sign: @Sendable () throws -> URLRequest
    /// The name the song is saved under among the songs kept on the phone, when it is kept.
    private let savedKey: String?
    /// Whether the phone is online now; a failed request is not tried again while it is not.
    private let online: @Sendable () -> Bool
    private let condition = NSCondition()
    private var held = ByteRanges()
    private var total: Int64?
    private var failure: PlayError?
    private var cancelled = false
    private var type: String?
    private var responseHeaders: [String: [String]] = [:]

    /// The request downloading now: where it started, where it writes next.
    private var task: URLSessionDataTask?
    private var taskStart: Int64 = 0
    private var writeAt: Int64 = 0
    private var errorsInARow = 0
    /// Whether the server sends a part of the song when asked, once an answer showed it.
    private var sendsParts: Bool?
    /// The parts of the song the songs kept on the phone held as it opened. Once one cannot be
    /// read, none are used again.
    private var saved = ByteRanges()
    /// The last byte the request downloading now asks for, when it stops before the next saved
    /// part; nil for the rest of the song.
    private var taskEnd: Int64?

    private let file: URL
    private let handle: FileHandle
    private lazy var session: URLSession = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    /// How far ahead of the download a read may land before a new request starts there.
    private static let jumpAhead: Int64 = 512 * 1024
    /// How much of a saved part is taken from the saved songs at a time, at least.
    private static let savedStep: Int64 = 1024 * 1024

    /// `readsSaved` false leaves the saved parts unread, as when the saved copy could not be
    /// played; what comes from the server is still saved over it.
    init(savedKey: String? = nil, readsSaved: Bool = true, online: @escaping @Sendable () -> Bool = { true },
         sign: @escaping @Sendable () throws -> URLRequest) throws {
        self.sign = sign
        self.savedKey = savedKey
        self.online = online
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("playing", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        file = folder.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        guard let handle = try? FileHandle(forUpdating: file) else { throw PlayError(.ioUnspecified, detail: "no room for the song") }
        self.handle = handle
        super.init()
        if readsSaved, let savedKey, let found = (try? blocking({ await StreamCache.shared.savedParts(savedKey) })) ?? nil {
            saved = found.ranges
            total = found.length
            type = found.mimeType
        }
    }

    deinit {
        try? handle.close()
        try? FileManager.default.removeItem(at: file)
    }

    var contentType: String? {
        condition.lock()
        defer { condition.unlock() }
        return type
    }

    /// The headers of the first answer, once there is one.
    var headers: [String: [String]] {
        condition.lock()
        defer { condition.unlock() }
        return responseHeaders
    }

    func length() throws -> Int64 {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if let total { return total }
            if cancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
            if let failure { throw failure }
            if task == nil { try start(from: saved.contiguous(from: 0)) }
            condition.wait(until: Date().addingTimeInterval(0.5))
        }
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if cancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
            if let total, offset >= total { return 0 }
            let end = total.map { min(offset + Int64(count), $0) } ?? offset + Int64(count)
            if held.covers(offset..<end) {
                return readHeld(offset, Int(end - offset), buffer)
            }
            if takeSaved(from: offset, to: end) { continue }
            if let failure { throw failure }
            if sendsParts == false {
                // A server that only sends the whole song: a look at its last bytes (for a tag)
                // finds none rather than waiting for all of it; anything else waits for the
                // download to get there.
                if let total, offset >= total - 128, offset > writeAt + Self.jumpAhead {
                    let length = Int(min(Int64(count), total - offset))
                    buffer.initializeMemory(as: UInt8.self, repeating: 0, count: length)
                    return length
                }
                if task == nil { try start(from: 0) }
            } else {
                // The first byte this read still needs.
                let gap = offset + held.contiguous(from: offset)
                let withinAsk = taskEnd.map { gap <= $0 } ?? true
                let reaching = task != nil && gap >= taskStart && gap <= writeAt + Self.jumpAhead && withinAsk
                if !reaching { try start(from: gap) }
            }
            condition.wait(until: Date().addingTimeInterval(0.5))
        }
    }

    /// Asks for the first byte alone and answers whether the server sends parts of a song.
    func answersRanges() -> Bool {
        guard var request = try? sign() else { return false }
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        let done = DispatchSemaphore(value: 0)
        final class Answer: @unchecked Sendable { var ranged = false }
        let answer = Answer()
        let probeSession = URLSession(configuration: .ephemeral, delegate: TrustDelegate(), delegateQueue: nil)
        defer { probeSession.finishTasksAndInvalidate() }
        let probe = probeSession.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                var headers: [String: [String]] = [:]
                for (key, value) in http.allHeaderFields { headers["\(key)"] = ["\(value)"] }
                answer.ranged = OctoKit.answersRanges(headers)
            }
            done.signal()
        }
        probe.resume()
        _ = done.wait(timeout: .now() + 20)
        probe.cancel()
        return answer.ranged
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

    /// The share of the song held, for a progress line.
    var heldBytes: Int64 {
        condition.lock()
        defer { condition.unlock() }
        return held.total
    }

    // MARK: Inside, with the condition held

    /// Copies what the saved songs hold at the first byte `offset` still needs into this song's
    /// own file: up to `end`, and at least `savedStep` when the saved part goes on that far.
    /// False when they hold nothing there. A saved part that cannot be read is passed over for
    /// the server's, and no saved part is used again.
    private func takeSaved(from offset: Int64, to end: Int64) -> Bool {
        guard let savedKey, !saved.ranges.isEmpty else { return false }
        let gap = offset + held.contiguous(from: offset)
        let run = saved.contiguous(from: gap)
        guard gap < end, run > 0 else { return false }
        let length = min(run, max(end - gap, Self.savedStep))
        guard let data = (try? blocking({ await StreamCache.shared.read(savedKey, offset: gap, length: Int(length)) })) ?? nil,
              !data.isEmpty
        else {
            saved = ByteRanges()
            return false
        }
        do {
            try handle.seek(toOffset: UInt64(gap))
            try handle.write(contentsOf: data)
        } catch {
            saved = ByteRanges()
            return false
        }
        held.insert(gap..<(gap + Int64(data.count)))
        return true
    }

    private func readHeld(_ offset: Int64, _ count: Int, _ buffer: UnsafeMutableRawPointer) -> Int {
        do {
            try handle.seek(toOffset: UInt64(offset))
            let data = try handle.read(upToCount: count) ?? Data()
            data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: data.count)
            return data.count
        } catch {
            return 0
        }
    }

    private func start(from offset: Int64) throws {
        task?.cancel()
        task = nil
        var request: URLRequest
        do {
            request = try sign()
        } catch let error as PlayError {
            failure = error
            condition.broadcast()
            throw error
        }
        // Only up to the next saved part, which is read from the phone.
        let end = streamCacheGapEnd(saved, from: offset)
        request.setValue("bytes=\(offset)-\(end.map(String.init) ?? "")", forHTTPHeaderField: "Range")
        request.timeoutInterval = 30
        let next = session.dataTask(with: request)
        task = next
        taskStart = offset
        taskEnd = end
        writeAt = offset
        next.resume()
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
        guard dataTask === task, let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            failure = PlayError(.badHttpStatus, httpStatus: http.statusCode, detail: "HTTP \(http.statusCode)")
            task = nil
            condition.broadcast()
            completionHandler(.cancel)
            return
        }
        if responseHeaders.isEmpty {
            for (key, value) in http.allHeaderFields { responseHeaders["\(key)"] = ["\(value)"] }
        }
        if type == nil { type = http.mimeType }
        if http.statusCode == 206, let range = http.value(forHTTPHeaderField: "Content-Range"),
           let whole = range.split(separator: "/").last.flatMap({ Int64($0) }) {
            if total == nil { total = whole }
            sendsParts = true
        } else {
            // The whole song came back from its start, whatever was asked.
            sendsParts = false
            writeAt = 0
            taskStart = 0
            taskEnd = nil
            if total == nil, http.expectedContentLength > 0 { total = http.expectedContentLength }
        }
        errorsInARow = 0
        if let savedKey {
            let length = total
            let mime = http.mimeType
            Task { await StreamCache.shared.describe(savedKey, contentLength: length, mimeType: mime) }
        }
        condition.broadcast()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        condition.lock()
        defer { condition.unlock() }
        guard dataTask === task else { return }
        do {
            try handle.seek(toOffset: UInt64(writeAt))
            try handle.write(contentsOf: data)
        } catch {
            failure = PlayError(.ioUnspecified, detail: "no room for the song")
            condition.broadcast()
            return
        }
        held.insert(writeAt..<(writeAt + Int64(data.count)))
        if let savedKey {
            // Saved as it plays, under the song's stable name, so it plays again without the network.
            let at = writeAt
            Task { await StreamCache.shared.write(savedKey, offset: at, data: data) }
        }
        writeAt += Int64(data.count)
        condition.broadcast()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        ServerTrust.shared.redirected(request, first: task.originalRequest)
    }

    func urlSession(_ session: URLSession, task finished: URLSessionTask, didCompleteWithError error: Error?) {
        ServerTrust.shared.noteEnd(of: finished.originalRequest, error)
        condition.lock()
        defer { condition.unlock() }
        guard finished === task else { return }
        task = nil
        let askedEnd = taskEnd
        taskEnd = nil
        if let error {
            let urlError = error as? URLError
            if urlError?.code == .cancelled { return }
            errorsInARow += 1
            if errorsInARow <= 3 && online() {
                // Tried again from where it got to, after a moment that grows each time.
                let wait = Double(min((errorsInARow - 1) * 1000, 5000)) / 1000
                let resumeAt = writeAt
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + wait) { [weak self] in
                    guard let self else { return }
                    self.condition.lock()
                    if !self.cancelled && self.task == nil && self.failure == nil { try? self.start(from: resumeAt) }
                    self.condition.unlock()
                }
            } else {
                let code: PlayErrorCode = urlError?.code == .timedOut ? .networkConnectionTimeout : .networkConnectionFailed
                failure = PlayError(code, detail: urlError.map { "\($0.code.rawValue)" } ?? "network")
            }
        } else if let askedEnd, writeAt > askedEnd {
            // The part asked for came whole; the saved part after it is read from the phone.
        } else if total == nil || writeAt < (total ?? 0) {
            // The answer ended: what came is all there is (a stream made on the way can be
            // shorter than it said it would be).
            if total == nil || held.covers(0..<writeAt) { total = writeAt }
        }
        condition.broadcast()
    }
}

/// Answers certificate questions the way the rest of the app does.
final class TrustDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        ServerTrust.shared.answer(challenge)
    }
}
