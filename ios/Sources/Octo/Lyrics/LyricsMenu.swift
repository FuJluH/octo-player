import OctoKit
import SwiftUI

/// What the lyrics menu shows: its options, or the timing control in their place.
enum LyricsMenuPage: Equatable { case options, timing }

/// The lyrics menu, a glass card beside the lyrics bar's "..." button: where the lyrics came
/// from, then other lyrics to choose, the timing, and hiding them for this song, or showing them
/// again. It opens on its first page each time; back goes back a page before closing.
struct LyricsMenuContent: View {
    let pages: PopupPages<LyricsMenuPage>
    let trackId: String?
    let dismiss: () -> Void
    let chooseOther: () -> Void
    @Environment(LyricsStore.self) private var store

    var body: some View {
        if let trackId {
            PopupPager(pages: pages) { page, _ in
                VStack(alignment: .leading, spacing: 0) {
                    switch page {
                    case .options: options(trackId)
                    case .timing:
                        GlassMenuBack(title: "Lyrics timing") { pages.back() }
                        TimingControl(trackId: trackId)
                    }
                }
                .frame(width: 280)
                .padding(6)
            }
        }
    }

    @ViewBuilder
    private func options(_ trackId: String) -> some View {
        let state = store.state
        let entries = entries(state, trackId)
        GlassMenuTitle(sourceLine(state))
        GlassMenuOptions(options: entries.map(\.0), selected: -1) { entries[$0].1() }
    }

    private func entries(_ state: LyricsState, _ trackId: String) -> [(Choice, () -> Void)] {
        if state == .hiddenForSong {
            return [
                (Choice("Show lyrics again"), {
                    Task { await store.show(trackId) }
                    dismiss()
                }),
                (Choice("Choose other lyrics"), chooseAway),
            ]
        }
        let lyrics = state.lyrics
        var list: [(Choice, () -> Void)] = [
            (Choice(lyrics == nil ? "Find lyrics" : "Choose other lyrics", detail: "Every copy that can be found for this song"), chooseAway),
        ]
        if let lyrics, lyrics.synced, !lyrics.instrumental {
            let output = LyricsOutput.timing
            let moved = timingSummary(LyricsSongTiming.shared.offset(trackId), output.ms, LyricsOutput.current.label,
                                      outputAutomatic: output.automatic)
            list.append((Choice("Adjust timing", detail: moved ?? "Move the words earlier or later"), { pages.open(.timing) }))
        }
        if lyrics != nil {
            list.append((Choice("Hide lyrics for this song"), {
                Task { await store.hide(trackId) }
                dismiss()
            }))
        }
        return list
    }

    private func chooseAway() {
        dismiss()
        chooseOther()
    }

    /// Where the lyrics came from, in plain words, at the top of the menu.
    private func sourceLine(_ state: LyricsState) -> String {
        switch state {
        case .found(_, let lyrics): lyrics.sourceLine()
        case .hiddenForSong: "Lyrics are hidden for this song"
        case .none: "No lyrics found for this song"
        case .failed: "Couldn't load lyrics"
        case .loading, .hidden: "Looking for lyrics"
        }
    }
}

/// Moves the lyrics earlier or later a twentieth of a second a tap, while they keep playing
/// behind the menu: for this song, and for every song on the output playing now.
struct TimingControl: View {
    let trackId: String
    @State private var songs = LyricsSongTiming.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            Text("If the words light up late, tap Earlier. If early, tap Later.")
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 12)
            TimingAdjuster(title: "This song", about: "For this song only, on every output.", offsetMs: songs.offset(trackId),
                           limitMs: TIMING_LIMIT_MS, step: { songs.step(trackId, $0) }, reset: { songs.reset(trackId) })
            OctoColor.hairline.frame(height: 1).padding(.horizontal, 14).padding(.vertical, 6)
            Spacer().frame(height: 8)
            let output = LyricsOutput.current
            let timing = settings.outputTiming(output.key)
            TimingAdjuster(title: output.label, about: outputTimingAbout(output.key, automatic: timing.automatic),
                           offsetMs: timing.ms, limitMs: OUTPUT_TIMING_LIMIT_MS, step: { LyricsOutput.step($0) },
                           reset: { LyricsOutput.reset() }, canReset: !timing.automatic, resetLabel: "Use automatic")
        }
    }
}

/// One lyrics timing to set: its name with the timing now beside it, a line on what it applies
/// to, then Earlier and Later a step a tap, and Reset under them, dimmed while there is nothing
/// to reset. Earlier always shows the words sooner.
struct TimingAdjuster: View {
    let title: String
    let about: String
    let offsetMs: Int
    let limitMs: Int
    let step: (Int) -> Void
    let reset: () -> Void
    var canReset: Bool?
    var resetLabel = "Reset"

    var body: some View {
        let resettable = canReset ?? (offsetMs != 0)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(title).font(.octoLabel).foregroundStyle(.white).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(signedTiming(offsetMs))
                    .font(.octoSection.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.leading, 12)
                    .accessibilityLabel("\(title): \(timingLabel(offsetMs))")
            }
            .padding(.horizontal, 14)
            Text(about)
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.top, 2)
                .padding(.bottom, 10)
            HStack(spacing: 8) {
                GlazeButton("Earlier", enabled: offsetMs > -limitMs, fillWidth: true) { step(-1) }
                GlazeButton("Later", enabled: offsetMs < limitMs, fillWidth: true) { step(1) }
            }
            .padding(.horizontal, 8)
            Button(action: reset) {
                Text(resetLabel)
                    .font(.octoLabel)
                    .foregroundStyle(OctoColor.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
            }
            .buttonStyle(NoPress())
            .disabled(!resettable)
            .opacity(resettable ? 1 : 0.4)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .onChange(of: offsetMs) { _, now in
            AccessibilityNotification.Announcement("\(title): \(timingLabel(now))").post()
        }
    }
}
