import ShareInbox
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Share to Octo": takes a list shared from another app (text, a link, or a CSV or text file),
/// leaves it in the inbox Octo shares with this extension, and asks for Octo to open on Import.
/// A file wins over text, as other apps often add a line of text to a file.
@objc(OctoShareViewController)
final class OctoShareViewController: UIViewController {
    private let state = ShareState()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(state: state) { [weak self] in self?.finish() })
        host.view.backgroundColor = .clear
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        Task { await take() }
    }

    private func take() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let subject = items.lazy.compactMap { $0.attributedTitle?.string ?? $0.attributedContentText?.string }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let providers = items.flatMap { $0.attachments ?? [] }
        guard let inbox = OctoAppGroup.inbox() else {
            state.show(.failed)
            return
        }
        if let file = await Self.firstFile(providers) {
            do {
                try inbox.put(.file(name: file.name, type: file.type, tooBig: file.tooBig), bytes: file.tooBig ? nil : file.bytes)
                await handOn()
            } catch {
                state.show(.failed)
            }
            return
        }
        guard let text = await Self.firstText(providers), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.show(.nothing)
            return
        }
        do {
            let trimmed = subject?.trimmingCharacters(in: .whitespacesAndNewlines)
            // A link shared with its own address as the subject has no name of its own.
            let name = trimmed == text.trimmingCharacters(in: .whitespacesAndNewlines) ? nil : trimmed
            try inbox.put(.text(text, subject: name))
            await handOn()
        } catch {
            state.show(.failed)
        }
    }

    /// Asks for Octo to open on Import; when it cannot be opened from here, says it waits there.
    private func handOn() async {
        if await openOcto() {
            finish()
        } else {
            state.show(.waiting)
        }
    }

    /// Opens Octo through the app this extension runs in.
    private func openOcto() async -> Bool {
        guard let url = URL(string: "octo://import") else { return false }
        var responder: UIResponder? = self
        while let next = responder {
            if let application = next as? UIApplication {
                return await application.open(url, options: [:])
            }
            responder = next.next
        }
        return false
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: Reading the share

    private struct SharedFile: Sendable {
        var name: String?
        var type: String?
        var bytes: Data
        var tooBig: Bool
    }

    /// The first CSV or text file shared, read up to Import's limit.
    private static func firstFile(_ providers: [NSItemProvider]) async -> SharedFile? {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let kind: UTType? = if provider.hasItemConformingToTypeIdentifier(UTType.commaSeparatedText.identifier) {
                .commaSeparatedText
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                .plainText
            } else {
                nil
            }
            guard let kind else { continue }
            let name = provider.suggestedName
            let read: (bytes: Data, tooBig: Bool)? = await withCheckedContinuation { continuation in
                _ = provider.loadFileRepresentation(forTypeIdentifier: kind.identifier) { url, _ in
                    // The copy lasts only while this runs, so it is read here.
                    continuation.resume(returning: url.flatMap { ShareInbox.read($0) })
                }
            }
            guard let read else { continue }
            let fileName = name.map { name in
                name.contains(".") ? name : kind.preferredFilenameExtension.map { "\(name).\($0)" } ?? name
            }
            return SharedFile(name: fileName, type: kind.preferredMIMEType, bytes: read.bytes, tooBig: read.tooBig)
        }
        return nil
    }

    /// The shared text, or a shared link as text.
    private static func firstText(_ providers: [NSItemProvider]) async -> String? {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                let link: String? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url?.absoluteString) }
                }
                if let link { return link }
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                let text: String? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: text) }
                }
                if let text { return text }
            }
        }
        return nil
    }
}

/// Kept so the linker keeps this file, and the view controller the system looks up by name.
@_cdecl("octo_share_extension")
public func octoShareExtension() {}

/// What the card says once the share is read.
@MainActor
@Observable
final class ShareState {
    enum Shown {
        case reading, waiting, nothing, failed
    }

    private(set) var shown: Shown = .reading

    func show(_ next: Shown) { shown = next }
}

/// The small card the share sheet shows while Octo takes the list.
private struct ShareCard: View {
    let state: ShareState
    let done: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            if let line {
                Text(line)
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.shown == .reading {
                ProgressView().tint(.white)
            } else {
                Button("Done", action: done)
                    .font(.system(size: 15, weight: .semibold))
                    .buttonStyle(.glassProminent)
                    .tint(Color(red: 0x97 / 255, green: 0xB1 / 255, blue: 0xB9 / 255))
            }
        }
        .padding(24)
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.35).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var title: String {
        switch state.shown {
        case .reading: "Sending to Octo"
        case .waiting: "Sent to Octo"
        case .nothing: "Octo can't read that"
        case .failed: "Octo couldn't take that"
        }
    }

    private var line: String? {
        switch state.shown {
        case .reading: nil
        case .waiting: "Open Octo and it reads the list in Import."
        case .nothing: "Share a list as text, a link, or a CSV or text file."
        case .failed: "Try again, or open the file in Octo instead."
        }
    }
}
