import OctoKit
import SwiftUI
import UIKit

/// The links the signed-in account shared: tapping one shares it again; each can be deleted.
struct SharesScreen: View {
    @Environment(ServerControls.self) private var controls
    @Environment(Session.self) private var session
    @State private var shares: LoadState<[ServerShare]> = .loading
    @State private var deleteProblem: String?
    @State private var deleting: ServerShare?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScreenTitle("Shared links")
                if let deleteProblem { PanelLine(text: deleteProblem, color: OctoColor.error) }
                switch shares {
                case .loading:
                    LoadingSpinner(size: 22).frame(maxWidth: .infinity).padding(.top, 24)
                case .failed(let words):
                    Text(words).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted).padding(.horizontal, 20)
                    GlazeButton("Try again", size: .medium) { Task { await load() } }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                case .ready(let list) where list.isEmpty:
                    Text("No shared links yet. Share a song or an album from its menu.")
                        .font(.octoBodySmall)
                        .foregroundStyle(OctoColor.textMuted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                case .ready(let list):
                    let now = epochNowMs()
                    ForEach(list) { share in row(share, now: now) }
                }
            }
            .padding(.top, 8 + detailTopGap)
        }
        .barClearance()
        .task { await load() }
        .opensWhenAsked("delete_link") { if case .ready(let list) = shares { deleting = list.first } }
    }

    private func row(_ share: ServerShare, now: Int64) -> some View {
        HStack(spacing: 0) {
            Button {
                SystemShare.present(text: share.url, subject: shareTitle(share))
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shareTitle(share)).font(.octoBodySmall).foregroundStyle(OctoColor.textPrimary).lineLimit(1)
                    Text(shareDetails(share, nowMs: now)).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(share.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button { deleting = share } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17))
                    .foregroundStyle(OctoColor.textMuted)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete link")
            .confirmationDialog("Delete this link?", isPresented: Binding(get: { deleting?.id == share.id }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete(share) }
            } message: {
                Text("\"\(shareTitle(share))\" stops working for everyone it was sent to.")
            }
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 60)
    }

    private func load() async {
        shares = .loading
        do {
            shares = .ready(try await controls.shares())
        } catch is CancellationError {
        } catch {
            shares = .failed(sharingUnavailable(error) ? "Sharing is switched off on this server." : userMessage(plainError(error)))
        }
    }

    private func delete(_ share: ServerShare) {
        deleteProblem = nil
        Task {
            do {
                try await controls.deleteShare(share.id)
                if case .ready(let list) = shares { shares = .ready(list.filter { $0.id != share.id }) }
            } catch {
                deleteProblem = "Couldn't delete that link. \(userMessage(plainError(error)))"
            }
        }
    }
}

/// The system's share sheet for a few words, such as a link.
@MainActor
enum SystemShare {
    static func present(text: String, subject: String) {
        let controller = UIActivityViewController(activityItems: [ShareText(text: text, subject: subject)], applicationActivities: nil)
        guard let top = topController() else { return }
        controller.popoverPresentationController?.sourceView = top.view
        top.present(controller, animated: true)
    }

    static func topController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
}

/// Plain text with a subject, for the share sheet.
private final class ShareText: NSObject, UIActivityItemSource {
    let text: String
    let subject: String

    init(text: String, subject: String) {
        self.text = text
        self.subject = subject
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { text }
    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? { text }
    func activityViewController(_ controller: UIActivityViewController, subjectForActivityType type: UIActivity.ActivityType?) -> String { subject }
}

/// A link to make: the server ids to share (songs, or one album) and the title for the card and
/// the link's description.
struct ShareRequest: Identifiable, Equatable {
    let id = UUID()
    let ids: [String]
    let title: String
}

/// The share card, in a sheet sized to it: the expiry choices, made into a link at once; the
/// card closes and the system's share sheet opens with the link.
struct ShareCard: View {
    let request: ShareRequest
    /// Closes the card, handing over the link to share once it has gone.
    let close: (String?) -> Void
    @Environment(ServerControls.self) private var controls
    @State private var making: ShareExpiry?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Share \"\(request.title)\"")
                .font(.octoLabel)
                .foregroundStyle(OctoColor.textPrimary)
                .lineLimit(2)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text("Anyone with the link can listen.")
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Text("Link expires")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OctoColor.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            ForEach(ShareExpiry.allCases, id: \.self) { expiry in
                Button { make(expiry) } label: {
                    HStack {
                        Text(expiry.label)
                            .font(.octoBodySmall)
                            .foregroundStyle(making == nil || making == expiry ? OctoColor.textPrimary : OctoColor.textMuted)
                        Spacer()
                        if making == expiry { LoadingSpinner(size: 18) }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(making != nil)
            }
            if let problem {
                Text(problem).font(.octoCaption).foregroundStyle(OctoColor.error).padding(.horizontal, 14).padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Makes the link with that expiry at once. Closing the card meanwhile does not stop it.
    private func make(_ expiry: ShareExpiry) {
        guard making == nil else { return }
        making = expiry
        problem = nil
        let controls = controls
        let request = request
        let close = close
        Task {
            do {
                let share = try await controls.createShare(request.ids, description: request.title, expiry: expiry)
                if share.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    problem = "The server made the link but did not say where it is."
                } else {
                    close(share.url)
                }
            } catch {
                problem = sharingUnavailable(error) ? "Sharing is switched off on this server." : userMessage(plainError(error))
            }
            making = nil
        }
    }
}

extension View {
    /// The app-wide share card, over everything, while a link is asked for.
    func shareCardHost() -> some View { modifier(ShareCardHost()) }
}

private struct ShareCardHost: ViewModifier {
    @Environment(Accounts.self) private var accounts
    /// The link made, shared once the card has gone.
    @State private var made: (url: String, title: String)?

    func body(content: Content) -> some View {
        @Bindable var accounts = accounts
        content.sheet(item: $accounts.sharing, onDismiss: shareMade) { request in
            ShareCard(request: request) { url in
                if let url { made = (url, request.title) }
                accounts.sharing = nil
            }
            .fittedSheet()
        }
    }

    private func shareMade() {
        guard let made else { return }
        self.made = nil
        SystemShare.present(text: made.url, subject: made.title)
    }
}

/// "Share link" for a library song, offered while the server shares and the song has a copy on it.
struct ShareSongButton: View {
    let song: Song
    @Environment(Accounts.self) private var accounts
    @Environment(ServerControls.self) private var controls
    @State private var serverId: String?

    var body: some View {
        Group {
            if controls.sharing, let serverId {
                Button {
                    accounts.share(ShareRequest(ids: [serverId], title: song.title))
                } label: {
                    Label("Share link", systemImage: "square.and.arrow.up")
                }
            }
        }
        .task(id: song.id) { serverId = await controls.shareableSongId(song.id) }
    }
}

/// The album page's quiet "Share", shown once the album maps to one on the server.
struct ShareAlbumButton: View {
    let albumId: String
    let title: String
    @Environment(Accounts.self) private var accounts
    @Environment(ServerControls.self) private var controls
    @State private var serverId: String?

    var body: some View {
        Group {
            if controls.sharing, let serverId {
                Button {
                    accounts.share(ShareRequest(ids: [serverId], title: title))
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OctoColor.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: albumId) { serverId = await controls.shareableAlbumId(albumId) }
    }
}
