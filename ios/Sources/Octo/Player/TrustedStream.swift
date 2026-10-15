import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Streams a song through ServerTrust when Apple's player could not reach it on its own: a
/// server with a certificate the person trusted, or one that asks for the phone's certificate.
/// The song's address gets a scheme only this loader answers, and every range the player asks
/// for is fetched with the app's own session.
final class TrustedStream: NSObject, AVAssetResourceLoaderDelegate, URLSessionDataDelegate, @unchecked Sendable {
    static let scheme = "octo-trusted"

    private let headers: [String: String]
    private let queue = DispatchQueue(label: "app.winters.octo.trusted-stream")
    private lazy var session = URLSession(configuration: .default, delegate: self,
                                          delegateQueue: { let q = OperationQueue(); q.underlyingQueue = queue; return q }())
    private var requests: [Int: AVAssetResourceLoadingRequest] = [:]

    init(headers: [String: String]) {
        self.headers = headers
    }

    /// An asset that loads through this stream. Keep the stream alive as long as the asset.
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
        var fetch = URLRequest(url: parts.url!)
        for (name, value) in headers { fetch.setValue(value, forHTTPHeaderField: name) }
        if let data = request.dataRequest {
            let start = data.requestedOffset
            if data.requestsAllDataToEndOfResource || request.contentInformationRequest != nil {
                fetch.setValue("bytes=\(start)-", forHTTPHeaderField: "Range")
            } else {
                fetch.setValue("bytes=\(start)-\(start + Int64(data.requestedLength) - 1)", forHTTPHeaderField: "Range")
            }
        }
        let task = session.dataTask(with: fetch)
        requests[task.taskIdentifier] = request
        task.resume()
        return true
    }

    func resourceLoader(_ loader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        for (id, waiting) in requests where waiting === request {
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
        guard let request = requests[dataTask.taskIdentifier], let http = response as? HTTPURLResponse else { return .cancel }
        if let info = request.contentInformationRequest {
            if let mime = http.mimeType, let type = UTType(mimeType: mime) {
                info.contentType = type.identifier
            }
            info.contentLength = Self.totalLength(http)
            info.isByteRangeAccessSupported = http.statusCode == 206
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        requests[dataTask.taskIdentifier]?.dataRequest?.respond(with: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        ServerTrust.shared.redirected(request, first: task.originalRequest)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        ServerTrust.shared.noteEnd(of: task.originalRequest, error)
        guard let request = requests.removeValue(forKey: task.taskIdentifier) else { return }
        if let error, (error as? URLError)?.code != .cancelled {
            request.finishLoading(with: error)
        } else {
            request.finishLoading()
        }
    }

    /// The whole file's length: from Content-Range on a partial answer, else Content-Length.
    static func totalLength(_ response: HTTPURLResponse) -> Int64 {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
            return total
        }
        return response.expectedContentLength
    }
}
