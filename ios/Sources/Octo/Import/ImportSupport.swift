import Foundation
import Network
import Observation
import OctoKit
import SafariServices
import ShareInbox
import UIKit
import UniformTypeIdentifiers

/// A list shared to Octo from another app, waiting for the Import page. A newer share replaces
/// one still waiting, and each is handed over once.
@MainActor
@Observable
final class ImportInbox {
    private(set) var waiting: SharedImport?
    /// Whether the Import page is on top of its stack, so a share does not open a second one.
    @ObservationIgnored var showing = false

    func offer(_ share: SharedImport) { waiting = share }

    func take() -> SharedImport? {
        defer { waiting = nil }
        return waiting
    }
}

/// Reads a list file up to Import's limit, 64 KiB at a time, stopping as soon as it goes past.
enum ImportFiles {
    /// The types the picker offers.
    static let pickTypes: [UTType] = [.plainText, .commaSeparatedText, .zip, .json]
        + [UTType(mimeType: "text/comma-separated-values")].compactMap { $0 }

    static func read(_ url: URL) -> ImportFileRead {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let read = ShareInbox.read(url) else { return .unreadable }
        return read.tooBig ? .tooBig : .bytes(read.bytes)
    }

    /// The type the system gives a file, by its ending.
    static func type(of url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType
    }

    /// Hands a read file or text to the Import page's model, with the words for what went wrong.
    @MainActor
    static func send(_ share: SharedImport, to model: ImportModel) {
        switch share {
        case .file(.bytes(let bytes), let name, let type):
            model.sendFile(name: importFileName(name, type: type), bytes: bytes)
        case .file(.tooBig, _, _):
            model.tell(ImportText.fileTooBig)
        case .file(.unreadable, _, _):
            model.tell("Octo could not read that file.")
        case .text(let text, let name):
            model.sendText(text, name: name ?? ImportText.pastedListName)
        }
    }
}

/// Opens an address for Import: TuneMyMusic in Safari, so its file lands in Downloads; a
/// sign-in in a browser inside Octo, so Octo stays awake to catch the answer.
@MainActor
enum ImportBrowser {
    static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        if tuneMyMusicUrl(address) != nil {
            UIApplication.shared.open(url)
            return
        }
        guard url.scheme == "https" || url.scheme == "http", let top = SystemShare.topController() else {
            UIApplication.shared.open(url)
            return
        }
        let browser = SFSafariViewController(url: url)
        browser.dismissButtonStyle = .close
        top.present(browser, animated: true)
    }

    /// Closes the sign-in browser once its answer is in.
    static func close() {
        guard let top = SystemShare.topController(), top is SFSafariViewController else { return }
        top.dismiss(animated: true)
    }
}

/// Catches the browser's return from a sign-in on this device: listens on the loopback address
/// at a free port and answers the one page that carries the answer.
final class LoopbackListener: LoopbackCatcher, @unchecked Sendable {
    let redirectUri: String
    private let listener: NWListener
    private let path: String
    private let lock = NSLock()
    private var answer: LoopbackAnswer?
    /// Timed out or closed: later waits end at once.
    private var ended = false
    private var waiters: [CheckedContinuation<LoopbackAnswer?, Never>] = []
    private let queue = DispatchQueue(label: "app.winters.octo.loopback")

    private init(listener: NWListener, host: String, port: UInt16, path: String) {
        self.listener = listener
        self.path = path
        let shown = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        redirectUri = "http://\(shown):\(port)\(path)"
    }

    /// A listener on `host` (a loopback address) at a free port, or nil when none starts.
    static func open(host: String, path: String) async -> LoopbackListener? {
        let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(bare), port: .any)
        parameters.acceptLocalOnly = true
        guard let listener = try? NWListener(using: parameters) else { return nil }
        let queue = DispatchQueue(label: "app.winters.octo.loopback.start")
        let port: UInt16? = await withCheckedContinuation { continuation in
            let once = Once()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: once.run { continuation.resume(returning: listener.port?.rawValue) }
                case .failed, .cancelled: once.run { continuation.resume(returning: nil) }
                default: break
                }
            }
            listener.newConnectionHandler = { $0.cancel() }
            listener.start(queue: queue)
        }
        guard let port else {
            listener.cancel()
            return nil
        }
        let catcher = LoopbackListener(listener: listener, host: host, port: port, path: path)
        listener.newConnectionHandler = { [weak catcher] connection in catcher?.serve(connection) }
        return catcher
    }

    func await(timeoutMs: Int) async -> LoopbackAnswer? {
        let timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
            self?.finish(nil)
        }
        defer { timeout.cancel() }
        return await withCheckedContinuation { continuation in
            lock.withLock {
                if let answer {
                    continuation.resume(returning: answer)
                } else if ended {
                    continuation.resume(returning: nil)
                } else {
                    waiters.append(continuation)
                }
            }
        }
    }

    func close() {
        listener.cancel()
        finish(nil)
    }

    private func finish(_ found: LoopbackAnswer?) {
        let waiting: [CheckedContinuation<LoopbackAnswer?, Never>] = lock.withLock {
            if let found { answer = found } else { ended = true }
            defer { waiters = [] }
            return waiters
        }
        for waiter in waiting { waiter.resume(returning: found) }
    }

    /// Reads one request's first line, answers it, and passes on a found answer.
    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            let text = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            let line = text.split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
            let (found, response) = LoopbackRules.respond(to: line, path: path)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            if let found {
                finish(found)
                Task { @MainActor in ImportBrowser.close() }
            }
        }
    }
}

/// Runs a block once, whichever thread asks first.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ block: () -> Void) {
        let first = lock.withLock {
            defer { done = true }
            return !done
        }
        if first { block() }
    }
}
