import OctoKit
import SwiftUI

/// The lyrics menu, the system menu of the lyrics bar's "..." button: where the lyrics came
/// from heads it, then other lyrics to choose, the timing, and hiding them for this song, or
/// showing them again.
struct LyricsMenuItems: View {
    let trackId: String?
    let openTiming: () -> Void
    let chooseOther: () -> Void
    @Environment(LyricsStore.self) private var store

    var body: some View {
        if let trackId {
            let state = store.state
            Section(sourceLine(state)) {
                if state == .hiddenForSong {
                    Button("Show lyrics again", systemImage: "eye") { Task { await store.show(trackId) } }
                    Button("Choose other lyrics", systemImage: "text.badge.checkmark", action: chooseOther)
                } else {
                    let lyrics = state.lyrics
                    Button(action: chooseOther) {
                        Label {
                            Text(lyrics == nil ? "Find lyrics" : "Choose other lyrics")
                            Text("Every copy that can be found for this song")
                        } icon: { Image(systemName: lyrics == nil ? "magnifyingglass" : "text.badge.checkmark") }
                    }
                    if let lyrics, lyrics.synced, !lyrics.instrumental {
                        let output = LyricsOutput.timing
                        let moved = timingSummary(LyricsSongTiming.shared.offset(trackId), output.ms, LyricsOutput.current.label,
                                                  outputAutomatic: output.automatic)
                        Button(action: openTiming) {
                            Label {
                                Text("Adjust timing")
                                Text(moved ?? "Move the words earlier or later")
                            } icon: { Image(systemName: "clock.arrow.2.circlepath") }
                        }
                    }
                    if lyrics != nil {
                        Button("Hide lyrics for this song", systemImage: "eye.slash") { Task { await store.hide(trackId) } }
                    }
                }
            }
        }
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

/// Lyrics timing, in a popover beside the lyrics bar's "..." button: its heading, then the
/// control.
struct TimingCard: View {
    let trackId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Lyrics timing")
                .font(.octoLabel)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            TimingControl(trackId: trackId)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
        .frame(width: 292)
    }
}

/// Moves the lyrics earlier or later a twentieth of a second a tap, while they keep playing
/// behind the card: for this song, and for every song on the output playing now.
struct TimingControl: View {
    let trackId: String
    @State private var songs = LyricsSongTiming.shared

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
            let timing = LyricsOutput.timing
            TimingAdjuster(title: output.label, about: LyricsOutputTiming.about(output.key, automatic: timing.automatic),
                           offsetMs: timing.ms, limitMs: LyricsOutputTiming.limitMs, step: { LyricsOutput.step($0) },
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
                Text(LyricsOutputTiming.signed(offsetMs))
                    .font(.octoSection.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.leading, 12)
                    .accessibilityLabel("\(title): \(LyricsOutputTiming.label(offsetMs))")
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
            AccessibilityNotification.Announcement("\(title): \(LyricsOutputTiming.label(now))").post()
        }
    }
}
