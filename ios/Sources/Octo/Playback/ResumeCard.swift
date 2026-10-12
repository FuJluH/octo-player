import OctoKit
import SwiftUI

/// A quiet offer at the top of Home to carry on from another device, when the server has a
/// newer queue saved by another app.
struct ResumeCard: View {
    @Environment(Player.self) private var player
    @Environment(\.octoReduceMotion) private var reduceMotion
    /// The last offer, kept while the card folds away.
    @State private var last: ResumeOffer?
    @State private var loading = false

    var body: some View {
        let offer = player.resumeOffer
        VStack(spacing: 0) {
            if let shown = offer ?? last, offer != nil {
                card(shown)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: offer?.id)
        .onChange(of: offer?.id, initial: true) { _, _ in
            if let offer { last = offer }
        }
    }

    private func card(_ shown: ResumeOffer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pick up where you left off on \(shown.device)")
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
            Text(shown.title)
                .font(.octoBody)
                .foregroundStyle(OctoColor.textPrimary)
                .lineLimit(1)
            if let artist = shown.artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(artist)
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.textSecondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                AccentButton("Resume", loading: loading) {
                    guard !loading else { return }
                    loading = true
                    Task {
                        await player.takeResumeOffer(shown)
                        loading = false
                    }
                }
                GlazeButton("Not now") { player.dismissResumeOffer(shown) }
            }
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .octoGlass(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
