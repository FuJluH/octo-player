import OctoKit
import SwiftUI
import UIKit

/// The top of the server page while the Octo server in use has a newer release: what is out and
/// what the server runs, its notes, and updating it, from the question before to the server
/// running the new release. Shows nothing while there is nothing to say.
struct ServerUpdateSection: View {
    @Environment(Session.self) private var session
    @Environment(\.openURL) private var openURL
    @State private var updates = ServerUpdates.shared
    @State private var confirming = false
    @State private var notes: [ServerRelease]?

    var body: some View {
        let panel = updates.panel
        Group {
            if panel != .hidden {
                SettingsGroup(title: "Server update", icon: "arrow.down.circle") { rows(panel) }
            }
        }
        .sheet(isPresented: Binding(get: { notes != nil }, set: { if !$0 { notes = nil } })) {
            ServerReleaseNotesSheet(releases: notes ?? [])
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .animation(.easeOut(duration: 0.2), value: panel)
    }

    @ViewBuilder
    private func rows(_ panel: ServerUpdatePanel) -> some View {
        switch panel {
        case .hidden:
            EmptyView()
        case .offer(let offer):
            UpdateHeadline(symbol: "arrow.down.circle.fill", tint: OctoColor.accent, title: offer.words)
            ActionRow(nil, title: "What's new") { notes = offer.notes }
            offerAction(offer)
            if let problem = updates.problem { NoteRow(problem, color: OctoColor.error) }
            ActionRow(nil, title: "Later", chevron: false) { updates.later() }
        case .running(let tag, let step):
            UpdateHeadline(symbol: nil, tint: OctoColor.accent, title: "Updating to Octo \(tag)",
                           detail: "Music from your server stops for a minute or two.")
            UpdateSteps(current: step)
        case .notBack:
            UpdateHeadline(symbol: "exclamationmark.triangle.fill", tint: OctoColor.error, title: "Your server has not come back.",
                           detail: "It has not answered for 15 minutes. Look at it from the dashboard, or on the computer it runs on.")
            dashboardRow
            ActionRow(nil, title: "Close", chevron: false) { updates.closeResult() }
        case .done(let tag):
            UpdateHeadline(symbol: "checkmark.circle.fill", tint: OctoColor.accent, title: "Your server now runs \(tag).")
            ActionRow(nil, title: "Done", chevron: false) { updates.closeResult() }
        case .failed(_, let words):
            UpdateHeadline(symbol: "exclamationmark.triangle.fill", tint: OctoColor.error, title: "The update did not finish.",
                           detail: words)
            dashboardRow
            ActionRow(nil, title: "Close", chevron: false) { updates.closeResult() }
        }
    }

    @ViewBuilder
    private func offerAction(_ offer: ServerUpdateOffer) -> some View {
        switch offer.action {
        case .updateNow:
            ActionRow(nil, title: "Update now", chevron: false, busy: updates.handing) { confirming = true }
                .confirmationDialog("Update Octo to \(offer.latest.tag)?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Update now") { updates.updateNow() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(offer.confirmWords)
                }
        case .noHelper:
            NoteRow("This server can be updated from its dashboard.")
            dashboardRow
        case .outdatedHelper(let command):
            NoteRow("The update helper on the server needs reinstalling before it can update Octo. Run this on the computer Octo runs on:")
            if let command { CommandRow(command: command) }
            dashboardRow
        }
    }

    private var dashboardRow: some View {
        ActionRow(nil, title: "Open dashboard", chevron: false) {
            if let client = session.client { openURL(ServerUpdateCalls.dashboard(client)) }
        }
    }
}

/// The panel's first row: an SF Symbol (or a spinner while working) and what is going on.
private struct UpdateHeadline: View {
    let symbol: String?
    let tint: Color
    let title: String
    var detail: String?

    var body: some View {
        RowFrame(entry: nil) {
            Group {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(tint).symbolRenderingMode(.hierarchical)
                } else {
                    ProgressView().controlSize(.regular).tint(tint)
                }
            }
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.octoBody).foregroundStyle(OctoColor.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The update's steps: those passed checked, the current one turning, those to come empty.
private struct UpdateSteps: View {
    let current: ServerUpdateStep

    var body: some View {
        RowFrame(entry: nil) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ServerUpdateStep.allCases, id: \.self) { step in
                    HStack(spacing: 12) {
                        mark(step).frame(width: 20, height: 20)
                        Text(step.words)
                            .font(.octoBodySmall)
                            .foregroundStyle(step <= current ? OctoColor.textPrimary : OctoColor.textMuted)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(step.words)
                    .accessibilityValue(step < current ? "Done" : step == current ? "Now" : "Next")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func mark(_ step: ServerUpdateStep) -> some View {
        if step < current {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(OctoColor.accent)
        } else if step == current {
            ProgressView().controlSize(.small).tint(OctoColor.accent)
        } else {
            Image(systemName: "circle").foregroundStyle(OctoColor.textMuted)
        }
    }
}

/// A command to run on the server's computer, to read or copy.
private struct CommandRow: View {
    let command: String
    @State private var copied = false

    var body: some View {
        RowFrame(entry: nil, minHeight: 0) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(OctoColor.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = command
                copied = true
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 15))
                    .frame(width: 22, height: 22)
                    .foregroundStyle(OctoColor.accent)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? "Copied" : "Copy command")
        }
    }
}

/// The notes of each release newer than the server runs, newest first.
struct ServerReleaseNotesSheet: View {
    let releases: [ServerRelease]
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What's new").font(.settingsLabel).foregroundStyle(OctoColor.textSecondary)
                ForEach(Array(releases.enumerated()), id: \.offset) { index, release in
                    releaseView(release).padding(.top, index == 0 ? 2 : 30)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func releaseView(_ release: ServerRelease) -> some View {
        Text("Octo \(release.tag)")
            .font(.octoTitle)
            .foregroundStyle(OctoColor.textPrimary)
            .accessibilityAddTraits(.isHeader)
        if let when = adminAgo(release.publishedUtc, nowMs: epochNowMs()) {
            Text("Released \(when.lowercasedFirst)").font(.octoCaption).foregroundStyle(OctoColor.textMuted).padding(.top, 2)
        }
        let blocks = serverReleaseNotes(release.notes)
        if blocks.isEmpty {
            Text("No notes for this release.").font(.octoBodySmall).foregroundStyle(OctoColor.textMuted).padding(.top, 14)
        } else {
            MarkdownView(blocks: blocks).padding(.top, 14)
        }
        if isGitHubLink(release.url), let page = release.url.flatMap(URL.init(string:)) {
            Button {
                openURL(page)
            } label: {
                Label("View on GitHub", systemImage: "arrow.up.right.square")
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
        }
    }
}

private extension String {
    /// "Yesterday" reads as "yesterday" after a word; a date keeps its look.
    var lowercasedFirst: String {
        guard let first, first.isUppercase else { return self }
        return first.lowercased() + dropFirst()
    }
}

/// The small mark on a row whose page has a server update waiting.
struct ServerUpdateBadge: View {
    var body: some View {
        Text("Update")
            .font(.octoCaption.weight(.semibold))
            .foregroundStyle(OctoColor.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(OctoColor.accent.opacity(0.18), in: Capsule())
            .accessibilityLabel("Server update available")
    }
}
