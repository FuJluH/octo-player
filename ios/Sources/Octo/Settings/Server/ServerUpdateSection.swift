import OctoKit
import SwiftUI
import UIKit

/// The server's own update, at the top of the server page: shown only when a newer Octo is out,
/// while an update is under way, or once one started here has ended. A card lightly washed in the
/// accent: what is out and what the server runs, then Update now (or the dashboard), What's new
/// and Later; while updating, its steps; at the end, how it went.
struct ServerUpdateSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(Router.self) private var router
    @State private var updates = ServerUpdates.shared
    @State private var confirming = false
    @State private var notes: [ServerRelease]?

    var body: some View {
        let panel = updates.panel
        Group {
            if panel != .hidden {
                card(panel)
                    .transition(.opacity)
            }
        }
        .animation(.octoTween(fixed: 200), value: panel)
        .alert(ServerUpdateWords.confirmTitle, isPresented: $confirming, presenting: offerTag(panel)) { _ in
            Button("Cancel", role: .cancel) {}
            Button("Update now") { updates.updateNow() }
        } message: { tag in
            Text(ServerUpdateWords.confirmDetail(tag))
        }
        .sheet(isPresented: Binding(get: { notes != nil }, set: { if !$0 { notes = nil } })) {
            ServerReleaseNotesSheet(releases: notes ?? [])
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func card(_ panel: ServerUpdatePanel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch panel {
            case .hidden:
                EmptyView()
            case .available(let offer):
                available(offer)
            case .updating(let tag, let steps):
                PanelTitle(ServerUpdateWords.updatingTitle(tag))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in StepRow(step: step) }
                }
                .padding(.top, 6)
                Text(ServerUpdateWords.musicStops)
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.top, 6)
            case .finished(let outcome):
                PanelTitle(ServerUpdateWords.outcomeTitle(outcome))
                if let detail = ServerUpdateWords.outcomeDetail(outcome) { Line(detail) }
                FlowRow(spacing: 8) {
                    if case .done = outcome {
                        AccentButton("Done", size: .medium) { updates.closeOutcome() }
                    } else {
                        AccentButton("Open dashboard", size: .medium, action: openDashboard)
                        GlazeButton("Close", size: .medium) { updates.closeOutcome() }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OctoColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func available(_ offer: ServerUpdateOffer) -> some View {
        PanelTitle(ServerUpdateWords.headline(offer))
        Line(ServerUpdateWords.detail(offer))
        if let way = ServerUpdateWords.way(offer.way) { Line(way) }
        if offer.way == .helperOutdated, !offer.reinstallCommand.trimmingCharacters(in: .whitespaces).isEmpty {
            CommandRow(command: offer.reinstallCommand) { router.done("Copied") }
        }
        if let failure = offer.lastFailure { Problem(ServerUpdateWords.lastFailure(failure)) }
        if let problem = offer.problem { Problem(problem) }
        FlowRow(spacing: 8) {
            if offer.way == .now {
                AccentButton("Update now", size: .medium, loading: offer.starting) { confirming = true }
            } else {
                AccentButton("Open dashboard", size: .medium, action: openDashboard)
            }
            GlazeButton("What's new", size: .medium) { notes = offer.newer }
            GlazeButton("Later", size: .medium, enabled: !offer.starting) { updates.later() }
        }
        .padding(.top, 8)
    }

    private func offerTag(_ panel: ServerUpdatePanel) -> String? {
        if case .available(let offer) = panel { return offer.latest.tag }
        return nil
    }

    private func openDashboard() {
        if let url = updates.dashboard() { openURL(url) }
    }
}

/// The card's first line, read as a heading.
private struct PanelTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.octo(16, .semibold, .body))
            .foregroundStyle(OctoColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A line of the card's words.
private struct Line: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.octoBodySmall)
            .foregroundStyle(OctoColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Why something stopped, in the error color.
private struct Problem: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.octoCaption)
            .foregroundStyle(OctoColor.error)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// One step of the update: a check once done, a spinner while on it, and a faint dot before it.
private struct StepRow: View {
    let step: ServerUpdateStepLine

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                switch step.state {
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OctoColor.accent)
                case .now:
                    ProgressView().controlSize(.small).tint(OctoColor.textPrimary)
                case .waiting:
                    Circle().fill(OctoColor.textMuted.opacity(0.5)).frame(width: 6, height: 6)
                }
            }
            .frame(width: 18, height: 18)
            .accessibilityHidden(true)
            Text(step.words)
                .font(.octoBodySmall)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.words)
        .accessibilityValue(step.state == .done ? "Done" : step.state == .now ? "Under way" : "Waiting")
    }

    private var color: Color {
        switch step.state {
        case .done: OctoColor.textSecondary
        case .now: OctoColor.textPrimary
        case .waiting: OctoColor.textMuted
        }
    }
}

/// A command to run on the server, in a fixed-width face, to select or copy.
private struct CommandRow: View {
    let command: String
    let copied: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(OctoColor.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            GlazeButton("Copy", size: .small) {
                UIPasteboard.general.string = command
                copied()
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Every release since the one the server runs, newest first, with its notes.
struct ServerReleaseNotesSheet: View {
    let releases: [ServerRelease]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("What's new on your server").font(.settingsLabel).foregroundStyle(OctoColor.textSecondary)
                ForEach(Array(releases.enumerated()), id: \.offset) { index, release in
                    Text(ServerUpdateWords.releaseTitle(release))
                        .font(.octoTitle)
                        .foregroundStyle(OctoColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, index == 0 ? 2 : 30)
                        .padding(.bottom, 14)
                        .accessibilityAddTraits(.isHeader)
                    let blocks = serverReleaseNotes(release.notes)
                    if blocks.isEmpty {
                        Text("No notes for this release.").font(.octoBodySmall).foregroundStyle(OctoColor.textMuted)
                    } else {
                        MarkdownView(blocks: blocks)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// The small dot on a row whose page has a server update waiting.
struct ServerUpdateDot: View {
    var body: some View {
        Circle()
            .fill(OctoColor.accent)
            .frame(width: 8, height: 8)
            .accessibilityLabel(ServerUpdateWords.mark)
    }
}
