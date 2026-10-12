import OctoKit
import SwiftUI

/// Another device's queue the server holds, newer than this phone's.
struct ResumeOffer: Equatable, Sendable {
    /// Who saved it: the device's name trimmed, else "another device".
    var device: String
    var title: String
    var artist: String?
    /// When it was saved, as the server says it; answering records it.
    var changedAt: String
}

/// Where the resume card's offer comes from: the server play queue sync.
@MainActor
protocol ResumeOffers: AnyObject {
    var offer: ResumeOffer? { get }
    /// Puts the other device's queue in place of this one, paused where it was. False when none of
    /// its songs could be found.
    func take(_ offer: ResumeOffer) async -> Bool
    /// Records the offer as answered, so the same queue is not offered again.
    func dismiss(_ offer: ResumeOffer)
}

/// A quiet offer at the top of Home to carry on from another device, when the server has a newer
/// queue saved by another app.
struct ResumeCard: View {
    let source: ResumeOffers?
    @State private var loading = false
    /// The last offer, kept while the card folds away.
    @State private var last: ResumeOffer?

    var body: some View {
        let offer = source?.offer
        VStack(spacing: 0) {
            if let shown = offer {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pick up where you left off on \(shown.device)").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    Text(shown.title).font(.octoBody).foregroundStyle(.white).lineLimit(1)
                    if let artist = shown.artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(artist).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary).lineLimit(1)
                    }
                    HStack(spacing: 12) {
                        Button {
                            resume(shown)
                        } label: {
                            if loading { ProgressView().controlSize(.small) } else { Text("Resume") }
                        }
                        .buttonStyle(.glassProminent)
                        Button("Not now") { source?.dismiss(shown) }.buttonStyle(.glass)
                    }
                    .font(DiscoveryStyle.label)
                    .padding(.top, 12)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: offer)
        .onChange(of: offer, initial: true) { _, now in if let now { last = now } }
    }

    /// Ignored while already loading; a failure is only logged.
    private func resume(_ offer: ResumeOffer) {
        guard !loading, let source else { return }
        loading = true
        Task {
            _ = await source.take(offer)
            loading = false
        }
    }
}

