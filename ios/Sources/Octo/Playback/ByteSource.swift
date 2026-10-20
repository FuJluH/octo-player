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

/// A song's whole saved copy on the phone. A read of it that fails passes the copy over: that
/// read and every one after it come from the server.
final class SavedCopy: ByteSource, @unchecked Sendable {
    private let file: LocalFile
    private let server: @Sendable () throws -> RemoteFile
    private let lock = NSLock()
    private var fallback: RemoteFile?
    private var cancelled = false

    init(_ file: LocalFile, server: @escaping @Sendable () throws -> RemoteFile) {
        self.file = file
        self.server = server
    }

    var contentType: String? { file.contentType }

    func length() throws -> Int64 { try file.length() }

    func read(at offset: Int64, into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        if let remote = lock.withLock({ fallback }) { return try remote.read(at: offset, into: buffer, count: count) }
        do {
            return try file.read(at: offset, into: buffer, count: count)
        } catch {
            let remote: RemoteFile = try lock.withLock {
                if cancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
                if let fallback { return fallback }
                let made = try server()
                fallback = made
                return made
            }
            return try remote.read(at: offset, into: buffer, count: count)
        }
    }

    func cancel() {
        let remote = lock.withLock {
            cancelled = true
            return fallback
        }
        remote?.cancel()
    }
}

/// A song read from the server by parts: what is asked for downloads into a file of its own on
/// the phone, from the place a read needs onwards, so the player can jump about and a part read
/// once is not fetched again. Each request is signed as it goes out (`sign`), so no address is
/// kept. A failed request is tried again after 0, 1 and 2 seconds; a refusal to load at all (no
/// connection, no server) fails at once.
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
    /// Whether what the saved songs know of this song was taken yet.
    private var savedLooked = false
    /// The saved copy could not be read: everything comes from the server.
    private var ignoreSaved = false
    /// The saved songs hold part of this song but not all: the server is asked before it opens
    /// whether it still sends the same file.
    private var savedPartly = false
    /// The server answered at least once.
    private var answered = false
    /// The player has had the length or bytes: from then on another file cannot take this one's
    /// place, and the song is opened again instead.
    private var served = false

    private let file: URL
    private let handle: FileHandle
    private lazy var session: URLSession = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        let config = URLSessionConfiguration.default.namingOcto(Session.appVersion)
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    /// How far ahead of the download a read may land before a new request starts there.
    private static let jumpAhead: Int64 = 512 * 1024

    init(savedKey: String? = nil, online: @escaping @Sendable () -> Bool = { true },
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
        lookAtSaved()
        while true {
            if let total {
                // A song saved in part is checked with the server first (when it can be reached):
                // the server may send another file for it now.
                if savedPartly && !answered && !ignoreSaved && failure == nil && !cancelled && online() {
                    if task == nil { try start(from: lengthAskFrom()) }
                    condition.wait(until: Date().addingTimeInterval(0.5))
                    continue
                }
                served = true
                return total
            }
            if cancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
            if let failure { throw failure }
            if task == nil { try start(from: lengthAskFrom()) }
            condition.wait(until: Date().addingTimeInterval(0.5))
        }
    }

    func read(at offset: Int64, into buffer: UnsafeMutableRawPointer, count: Int) throws -> Int {
        condition.lock()
        defer { condition.unlock() }
        lookAtSaved()
        served = true
        while true {
            if cancelled { throw PlayError(.ioUnspecified, detail: "stopped") }
            if let total, offset >= total { return 0 }
            let end = total.map { min(offset + Int64(count), $0) } ?? offset + Int64(count)
            if held.covers(offset..<end) {
                return readHeld(offset, Int(end - offset), buffer)
            }
            if let saved = readSaved(offset, end, buffer) { return saved }
            if held.covers(offset..<end) {
                return readHeld(offset, Int(end - offset), buffer)
            }
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
                let reaching = task != nil && offset >= taskStart && offset <= writeAt + Self.jumpAhead
                // The server is asked from where what is held (read from the saved songs) ends.
                if !reaching { try start(from: offset + held.contiguous(from: offset)) }
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
        let probeSession = URLSession(configuration: URLSessionConfiguration.ephemeral.namingOcto(Session.appVersion), delegate: TrustDelegate(),
                                      delegateQueue: nil)
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

    /// What the saved songs know of this song (its whole length and type) is taken once, so a song
    /// saved in part opens without the server.
    private func lookAtSaved() {
        guard !savedLooked, let savedKey else { return }
        savedLooked = true
        let info = (try? blocking { await StreamCache.shared.info(savedKey).map { Unchecked($0) } }) ?? nil
        if total == nil, let length = info?.value.length, length > 0 { total = length }
        if type == nil { type = info?.value.mimeType }
        if let total {
            let run = (try? blocking { await StreamCache.shared.savedRun(savedKey, from: 0) }) ?? 0
            savedPartly = run > 0 && run < total
        }
    }

    /// Where to ask the server from to learn the song's length: from its start, or, when the saved
    /// songs hold its start but not its length, from the last saved byte, so only what is missing
    /// comes down.
    private func lengthAskFrom() -> Int64 {
        guard let savedKey, !ignoreSaved else { return 0 }
        let run = (try? blocking { await StreamCache.shared.savedRun(savedKey, from: 0) }) ?? 0
        return max(0, run - 1)
    }

    /// Answers a read from the saved songs when they hold it. A read they hold all of is copied
    /// straight out; one they hold the start of has that start put with the bytes held here, so
    /// only the rest is asked of the server. A saved copy that cannot be read is passed over for
    /// the server's from then on.
    private func readSaved(_ offset: Int64, _ end: Int64, _ buffer: UnsafeMutableRawPointer) -> Int? {
        guard let savedKey, !ignoreSaved else { return nil }
        let run = (try? blocking { await StreamCache.shared.savedRun(savedKey, from: offset) }) ?? 0
        guard run > 0 else { return nil }
        let wanted = Int(end - offset)
        let length = Int(min(run, max(Int64(wanted), Self.savedPiece)))
        guard let data = (try? blocking({ await StreamCache.shared.read(savedKey, offset: offset, length: length) })) ?? nil,
              data.count == length
        else {
            ignoreSaved = true
            return nil
        }
        if length >= wanted {
            data.copyBytes(to: buffer.assumingMemoryBound(to: UInt8.self), count: wanted)
            return wanted
        }
        do {
            try handle.seek(toOffset: UInt64(offset))
            try handle.write(contentsOf: data)
            held.insert(offset..<(offset + Int64(length)))
        } catch {
            ignoreSaved = true
        }
        return nil
    }

    /// Asks again from where the download got to, after a moment that grows with each failure in
    /// a row: 0, 1, then 2 seconds.
    private func retryLater() {
        let wait = Double(min((errorsInARow - 1) * 1000, 5000)) / 1000
        let resumeAt = writeAt
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.condition.lock()
            if !self.cancelled && self.task == nil && self.failure == nil { try? self.start(from: resumeAt) }
            self.condition.unlock()
        }
    }

    /// How much of a saved stretch is put with the bytes held at once.
    private static let savedPiece: Int64 = 1 << 20

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
        request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        request.timeoutInterval = 30
        let next = session.dataTask(with: request)
        task = next
        taskStart = offset
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
            task = nil
            errorsInARow += 1
            // A refusal is asked again like a broken connection, except a place past the end.
            if http.statusCode != 416 && errorsInARow <= 3 && online() {
                retryLater()
            } else {
                failure = PlayError(.badHttpStatus, httpStatus: http.statusCode, detail: "HTTP \(http.statusCode)")
            }
            condition.broadcast()
            completionHandler(.cancel)
            return
        }
        let answer = streamShapeOf(status: http.statusCode, contentType: http.mimeType,
                                   contentRange: http.value(forHTTPHeaderField: "Content-Range"),
                                   contentLength: http.expectedContentLength)
        let changed = StreamShape(type: type, total: total).differs(from: answer)
        if changed {
            // Another file than the one begun or saved (a whole FLAC for a listed preview, say):
            // the saved copy goes with its length and type, and nothing held of it is read again.
            ignoreSaved = true
            if let savedKey {
                let length = answer.total
                let mime = http.mimeType
                Task { await StreamCache.shared.answered(savedKey, contentLength: length, mimeType: mime) }
            }
            if served {
                // The player has read the other file: it opens the song again.
                task = nil
                failure = PlayError(.sourceChanged, detail: "the server sent another file")
                condition.broadcast()
                completionHandler(.cancel)
                return
            }
            held = ByteRanges()
            total = nil
            type = nil
            responseHeaders = [:]
            sendsParts = nil
            if http.statusCode == 206 && taskStart > 0 {
                // The new file is read from its start.
                completionHandler(.cancel)
                task = nil
                try? start(from: 0)
                condition.broadcast()
                return
            }
        }
        answered = true
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
            if total == nil, http.expectedContentLength > 0 { total = http.expectedContentLength }
        }
        errorsInARow = 0
        // A changed file was described as the saved copy went, in that order.
        if let savedKey, !changed {
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
        if let error {
            let urlError = error as? URLError
            if urlError?.code == .cancelled { return }
            errorsInARow += 1
            if errorsInARow <= 3 && online() {
                retryLater()
            } else {
                let code: PlayErrorCode = urlError?.code == .timedOut ? .networkConnectionTimeout : .networkConnectionFailed
                failure = PlayError(code, detail: urlError.map { "\($0.code.rawValue)" } ?? "network")
            }
        } else if total == nil || writeAt < (total ?? 0) {
            // The answer ended: what came is all there is (a stream made on the way can be
            // shorter than it said it would be).
            if total == nil || held.covers(0..<writeAt) {
                total = writeAt
                // The saved copy takes the length the song really has, so it counts as whole.
                if let savedKey, held.covers(0..<writeAt) {
                    let length = writeAt
                    Task { await StreamCache.shared.describe(savedKey, contentLength: length, mimeType: nil) }
                }
            }
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
