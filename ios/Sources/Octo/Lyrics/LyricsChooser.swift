import OctoKit
import SwiftUI

/// What the chooser found for a song.
private enum Found: Equatable {
    case looking(String)
    case ready(String, CandidateSearch)
}

/// What a search by hand found.
private enum Searched: Equatable {
    case nothing
    case searching
    case ready([LyricsCandidate])
    case failed
}

/// The lyrics to choose from for the song playing, in a sheet: a search by hand at the top, for
/// a song whose title or artist is filed wrong, then the lyrics showing now in the darker pill,
/// then every other copy found. Each says where it is from, what its source calls it, and its
/// first lines. Picking one uses it for this song from then on and closes the sheet. With a
/// server that keeps lyrics choices for every app, the list and the search come from the
/// server, and a pick from it holds for every app.
struct LyricsChooserContent: View {
    let song: Song
    let dismiss: () -> Void
    @Environment(LyricsStore.self) private var store
    @State private var found: Found = .looking("")
    @State private var searched: Searched = .nothing
    @State private var notTaken = false
    @State private var query = ""
    @State private var looking: Task<Void, Never>?
    @State private var searching: Task<Void, Never>?

    var body: some View {
        ScrollView {
            list
                .padding(.top, 24)
                .padding(.bottom, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .task(id: song.id) { look() }
        // What was typed belongs to the song it was typed for.
        .onChange(of: song.id) { _, _ in query = "" }
    }

    private var facts: LyricsSong { LyricsSong(song.id, song.title, song.byline, song.album ?? "", song.duration * 1000) }

    @ViewBuilder
    private var list: some View {
        let showing = store.state.lyrics
        let ready: CandidateSearch? = if case .ready(let id, let search) = found, id == song.id { search } else { nil }
        let serverChoice = ready?.serverChoice
        let onServer = serverChoice != nil
        let current = showingPick(serverChoice, showing)
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose lyrics").font(.octoSection).foregroundStyle(.white).padding(.horizontal, 24)
            Text([song.title, song.byline].filter { !$0.isEmpty }.joined(separator: " by "))
                .font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                .padding(.horizontal, 24)
                .padding(.bottom, onServer ? 2 : 12)
            if onServer {
                Text("Lyrics picked from your server show on all your devices and apps.")
                    .font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            let onlineAllowed = ready?.onlineAllowed ?? true
            if onServer || onlineAllowed {
                let place = onServer ? "your server" : "LRCLIB"
                GlassInput(placeholder: onServer ? "Search by title, or artist - title" : "Search LRCLIB by title or artist",
                           text: $query, submitLabel: .search, onSubmit: {
                               hideKeyboard()
                               search(onServer: onServer)
                           }, leading: { EmptyView() }, trailing: {
                               Button {
                                   hideKeyboard()
                                   search(onServer: onServer)
                               } label: {
                                   IconView(.search, size: 20, color: OctoColor.textSecondary).frame(width: 40, height: 40)
                               }
                               .buttonStyle(NoPress())
                               .accessibilityLabel("Search")
                           })
                .padding(.horizontal, 16)
                switch searched {
                case .nothing: EmptyView()
                case .searching: quiet("Searching \(place)")
                case .failed: quiet("Could not reach \(place)")
                case .ready(let results):
                    section("Search results")
                    if results.isEmpty { quiet("Nothing found for that") }
                    ForEach(Array(results.enumerated()), id: \.offset) { index, candidate in
                        let isShowing = current != nil && candidate.pick == current
                        if index > 0 { OctoColor.hairline.frame(height: 1).padding(.horizontal, 30) }
                        CandidateRow(candidate: candidate, showing: isShowing, songTitle: song.title, byHand: true) {
                            pick(candidate, showing: isShowing)
                        }
                        .padding(.horizontal, 16)
                    }
                }
            } else {
                quiet("Online lyrics are off in Settings, so only your server and this phone are searched.")
            }
            section("For this song")
            if notTaken { quiet("Your server could not use those lyrics this time. Try again, or pick others.") }
            switch found {
            case .looking:
                quiet("Looking for lyrics")
            case .ready(let id, let search) where id == song.id:
                let choices = candidateList(search.found, current: current, showing: showing)
                if choices.items.isEmpty { quiet("No lyrics found for this song") }
                ForEach(Array(choices.items.enumerated()), id: \.offset) { index, candidate in
                    let isShowing = index == choices.showing
                    // No line touches the darker pill.
                    if index > 0 { (index - 1 != choices.showing ? OctoColor.hairline : Color.clear).frame(height: 1).padding(.horizontal, 30) }
                    CandidateRow(candidate: candidate, showing: isShowing, songTitle: song.title, byHand: false) {
                        pick(candidate, showing: isShowing)
                    }
                    .padding(.horizontal, 16)
                }
                if let missed = missedLine(search.missed) { quiet(missed) }
            case .ready:
                EmptyView()
            }
            Spacer().frame(height: 8)
        }
    }

    private func section(_ text: String) -> some View {
        Text(text)
            .font(.octoLabel)
            .foregroundStyle(OctoColor.textSecondary)
            .padding(.horizontal, 30)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(.octoCaption)
            .foregroundStyle(OctoColor.textMuted)
            .padding(.horizontal, 30)
            .padding(.vertical, 10)
    }

    /// Opening it starts a fresh look: any look and search under way stop, results and the note
    /// clear, and it shows "Looking for lyrics" until the list comes.
    private func look() {
        looking?.cancel()
        searching?.cancel()
        searched = .nothing
        notTaken = false
        let id = song.id
        let facts = self.facts
        found = .looking(id)
        looking = Task {
            let search = await store.candidatesFor(facts)
            guard !Task.isCancelled else { return }
            found = .ready(id, search)
        }
    }

    /// Searches the server's sources when it keeps lyrics choices for the song, or else the
    /// online library.
    private func search(onServer: Bool) {
        let words = query.trimmingCharacters(in: .whitespaces)
        searching?.cancel()
        guard !words.isEmpty else {
            searched = .nothing
            return
        }
        searched = .searching
        let id = song.id
        searching = Task {
            do {
                let results = onServer ? try await store.searchOnServer(id, words) : try await store.searchOnline(words)
                guard !Task.isCancelled, id == song.id else { return }
                searched = .ready(results)
            } catch {
                guard !Task.isCancelled else { return }
                searched = .failed
            }
        }
    }

    /// Uses the candidate for the song from now on: on this phone, or for a server choice, on
    /// the server for every app. Its timing starts as the new lyrics are written. A server choice
    /// the server could not take leaves the chooser open and says so.
    private func pick(_ candidate: LyricsCandidate, showing: Bool) {
        if showing {
            dismiss()
            return
        }
        let id = song.id
        guard case .onServer(let choice) = candidate.pick else {
            LyricsSongTiming.shared.reset(id)
            store.choose(id, candidate)
            dismiss()
            return
        }
        notTaken = false
        Task {
            do {
                try await store.chooseOnServer(id, choice)
                LyricsSongTiming.shared.reset(id)
                dismiss()
            } catch {
                notTaken = true
            }
        }
    }

    /// Which sources could not be reached this time, in plain words.
    private func missedLine(_ missed: Set<LyricsSource>) -> String? {
        var names: [String] = []
        if missed.contains(.server) { names.append("your server") }
        if missed.contains(.online) { names.append("LRCLIB") }
        if missed.contains(.songFile) || missed.contains(.lyricsFile) { names.append("the song's files") }
        return names.isEmpty ? nil : "Could not reach \(names.joined(separator: " or ")) this time."
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// One set of lyrics to choose: where it is from, what it is, and its first two lines. The one
/// showing now sits in the darker pill with a check.
private struct CandidateRow: View {
    let candidate: LyricsCandidate
    let showing: Bool
    let songTitle: String
    let byHand: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(candidateLabel(candidate)).font(.octoBodySmall).foregroundStyle(.white)
                    let detail = candidateDetail
                    if !detail.isEmpty {
                        Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(2)
                    }
                    let preview = candidate.kind == .instrumental ? ["Instrumental"] : candidate.preview
                    if !preview.isEmpty {
                        Text(preview.joined(separator: "\n")).font(.octoCaption).foregroundStyle(OctoColor.textSecondary).lineLimit(2)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showing { IconView(.check, size: 18, color: .white) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background { if showing { GlazeSelected(shape: chooserRowShape) } }
            .contentShape(chooserRowShape)
        }
        .buttonStyle(ChooserRowPress(shows: !showing))
        .accessibilityHint(showing ? "Keep these lyrics" : "Use these lyrics")
        .accessibilityValue(showing ? "Showing now" : "")
    }

    /// What a candidate is: for the server's "Automatic", what it does; for a copy from the
    /// online library or the server's sources, its title and artist when they differ from the
    /// song's (or it came from a search by hand), its album and length; then how it is timed.
    private var candidateDetail: String {
        var parts: [String] = []
        if candidate.pick == .onServer(LYRICS_AUTO) {
            parts.append(candidate.lyrics == nil ? "Let your server find the best match" : "Found by your server")
        }
        let copy = candidate.origin == .onlineMatch || candidate.origin == .onlineSearch || candidate.origin == .serverCopy
        if copy {
            let otherName = byHand || matchKey(candidate.title) != matchKey(songTitle)
            if otherName && !candidate.title.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append(candidate.artist.trimmingCharacters(in: .whitespaces).isEmpty ? candidate.title : "\(candidate.title) by \(candidate.artist)")
            }
            if !candidate.album.trimmingCharacters(in: .whitespaces).isEmpty { parts.append(candidate.album) }
            if candidate.durationMs >= 1000 { parts.append(asClock(max(candidate.durationMs, 0) / 1000)) }
        }
        if candidate.lyrics != nil || candidate.origin == .serverCopy, !candidate.kind.label.isEmpty {
            parts.append(candidate.kind.label)
        }
        return parts.joined(separator: " · ")
    }
}

/// The shape of a candidate's pill.
private let chooserRowShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

/// A row under the finger shows the quiet accent pill at once, in place of a ripple.
private struct ChooserRowPress: ButtonStyle {
    let shows: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background {
            if configuration.isPressed && shows { chooserRowShape.fill(OctoColor.menuPress) }
        }
    }
}
