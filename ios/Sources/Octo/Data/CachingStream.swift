import AVFoundation
import Foundation
import OctoKit
import UniformTypeIdentifiers

/// Streams a server song through the saved songs: every range the player asks for is answered
/// from the phone when it is saved there, and otherwise fetched from the server (with the app's
/// trusted session) and saved as it plays, under the song's stable key. Keep the stream alive as
/// long as its asset.
final class CachingStream: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let scheme = "octo-saved"

    private let key: String
    private let headers: [String: String]
    private let cache: StreamCache
    private let queue = DispatchQueue(label: "app.winters.octo.saved-stream")
    private lazy var session = URLSession(configuration: .default, delegate: self,
                                          delegateQueue: { let q = OperationQueue(); q.underlyingQueue = queue; return q }())
    private var requests: [Int: (request: AVAssetResourceLoadingRequest, offset: Int64)] = [:]

    init(key: String, headers: [String: String], cache: StreamCache = .shared) {
        self.key = key
        self.headers = headers
        self.cache = cache
    }

    /// An asset that loads through this stream, from the song's signed address.
    func asset(for url: URL) -> AVURLAsset {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.scheme = Self.scheme + "-" + (parts.scheme ?? "https")
        let asset = AVURLAsset(url: parts.url!)
        asset.resourceLoader.setDelegate(self, queue: queue)
        return asset
    }

    func resourceLoader(_ loader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = request.request.url, var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme, scheme.hasPrefix(Self.scheme + "-")
        else { return false }
        parts.scheme = String(scheme.dropFirst(Self.scheme.count + 1))
        guard let source = parts.url else { return false }
        let held = Unchecked(request)
        Task { await self.answer(held, from: source) }
        return true
    }

    private func answer(_ held: Unchecked<AVAssetResourceLoadingRequest>, from source: URL) async {
        let request = held.value
        let start = request.dataRequest?.requestedOffset ?? 0
        let wantsAll = request.dataRequest?.requestsAllDataToEndOfResource ?? true
        let info = await cache.info(key)
        if let length = info?.length, let data = request.dataRequest {
            let end = wantsAll ? length : min(length, start + Int64(data.requestedLength))
            if end > start, await cache.savedRun(key, from: start) >= end - start,
               let bytes = await cache.read(key, offset: start, length: Int(end - start)) {
                let mimeType = info?.mimeType
                queue.async {
                    let request = held.value
                    if let content = request.contentInformationRequest { Self.describe(content, length: length, mimeType: mimeType) }
                    request.dataRequest?.respond(with: bytes)
                    request.finishLoading()
                }
                return
            }
        }
        var fetch = URLRequest(url: source)
        for (name, value) in headers { fetch.setValue(value, forHTTPHeaderField: name) }
        if let data = request.dataRequest {
            if wantsAll || request.contentInformationRequest != nil {
                fetch.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
            } else {
                fetch.setValue("bytes=\(start)-\(start + Int64(data.requestedLength) - 1)", forHTTPHeaderField: "Range")
            }
        }
        let ask = fetch
        queue.async {
            let task = self.session.dataTask(with: ask)
            self.requests[task.taskIdentifier] = (held.value, start)
            task.resume()
        }
    }

    private static func describe(_ content: AVAssetResourceLoadingContentInformationRequest, length: Int64, mimeType: String?) {
        if let mimeType, let type = UTType(mimeType: mimeType) { content.contentType = type.identifier }
        content.contentLength = length
        content.isByteRangeAccessSupported = true
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        for (id, waiting) in requests where waiting.request === request {
            requests[id] = nil
            session.getAllTasks { tasks in tasks.first { $0.taskIdentifier == id }?.cancel() }
        }
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        ServerTrust.shared.answer(challenge)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge)
        async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        ServerTrust.shared.answer(challenge)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse)
        async -> URLSession.ResponseDisposition {
        guard let waiting = requests[dataTask.taskIdentifier], let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode)
        else { return .cancel }
        let length = TrustedStream.totalLength(http)
        // A whole answer to a ranged ask starts at the top of the file.
        if http.statusCode == 200 { requests[dataTask.taskIdentifier]?.offset = 0 }
        await cache.describe(key, contentLength: length > 0 ? length : nil, mimeType: http.mimeType)
        if let content = waiting.request.contentInformationRequest {
            if let mime = http.mimeType, let type = UTType(mimeType: mime) { content.contentType = type.identifier }
            content.contentLength = length
            content.isByteRangeAccessSupported = http.statusCode == 206
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let waiting = requests[dataTask.taskIdentifier] else { return }
        waiting.request.dataRequest?.respond(with: data)
        let offset = waiting.offset
        requests[dataTask.taskIdentifier]?.offset = offset + Int64(data.count)
        let key = key
        let cache = cache
        Task { await cache.write(key, offset: offset, data: data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        ServerTrust.shared.redirected(request, first: task.originalRequest)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        ServerTrust.shared.noteEnd(of: task.originalRequest, error)
        guard let waiting = requests.removeValue(forKey: task.taskIdentifier) else { return }
        if let error, (error as? URLError)?.code != .cancelled {
            waiting.request.finishLoading(with: error)
        } else {
            waiting.request.finishLoading()
        }
        let cache = cache
        Task { await cache.save() }
    }
}
