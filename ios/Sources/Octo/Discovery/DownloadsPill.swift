import OctoKit
import SwiftUI

/// While songs are on their way into the library, a small glass pill with the download ring of the
/// song furthest along, the step it is on ("Downloading 42%", "Checking"), its name, and how many
/// more. A tap opens the server downloads sheet from anywhere; nothing opens by itself, and with
/// nothing on its way the pill is gone.
struct DownloadsPill: View {
    @Environment(ServerDownloads.self) private var serverDownloads
    @Environment(Downloads.self) private var downloads
    @Environment(\.octoReduceMotion) private var calm
    /// Moves on when the oldest ask counted runs out, so the count is worked out again.
    @State private var tick = 0

    var body: some View {
        let _ = tick
        let rows = serverDownloads.watch.rows
        let since = serverDownloads.watch.listedSince
        let now = msSince1970()
        let coming = pillCount(rows, downloads.asked, listedSince: since, now: now)
        ZStack {
            if coming > 0 && serverDownloads.supported {
                let lead = pillLead(rows)
                let more = lead != nil ? coming - 1 : 0
                let spoken = lead != nil ? pillSpoken(rows) : comingText(coming)
                let words = lead.map(stepWords) ?? comingText(coming)
                Button {
                    serverDownloads.showList()
                    serverDownloads.open()
                } label: {
                    HStack(spacing: 8) {
                        DownloadRing(phase: lead.map(ringPhase) ?? .queued, calm: calm)
                            .frame(width: 20, height: 20)
                        Text(words)
                            .font(.octoCaption)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .id(words)
                            .transition(.opacity)
                        if let lead {
                            Text(lead.title)
                                .font(.octoCaption)
                                .foregroundStyle(OctoColor.textSecondary)
                                .lineLimit(1)
                                .layoutPriority(-1)
                        }
                        if more > 0 {
                            Text("+\(more)")
                                .font(.octoCaption)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, more > 0 ? 6 : 14)
                    .frame(height: 36)
                    .frame(maxWidth: 280)
                    .contentShape(Capsule())
                    .animation(.easeInOut(duration: calm ? 0.08 : 0.16), value: words)
                }
                .buttonStyle(.plain)
                .glassEffect(Glass.octo.interactive(), in: .capsule)
                .clipShape(Capsule())
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: calm ? 0.1 : 0.2), value: more)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(spoken). Show server downloads")
                .accessibilityAddTraits(.isButton)
                .transition(.opacity)
            }
        }
        .task(id: "\(rows.count)|\(downloads.asked.count)|\(since ?? 0)|\(tick)") {
            guard let wait = pillRecheckMs(rows, downloads.asked, listedSince: since, now: msSince1970()) else { return }
            try? await Task.sleep(for: .milliseconds(wait + 50))
            if !Task.isCancelled { tick += 1 }
        }
    }
}
