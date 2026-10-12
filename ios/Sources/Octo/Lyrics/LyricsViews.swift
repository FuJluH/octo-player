import OctoKit
import SwiftUI
import UIKit

/// The song's words, in the look the listener picked. Synced lyrics follow the song (shifted by
/// the timing set for this song and this output); a tap on a line plays from it. After a scroll
/// by hand the lyrics follow the song again two seconds later.
struct LyricsView: View {
    let ink: Color
    let muted: Color
    @Environment(Player.self) private var player
    @Environment(LyricsStore.self) private var store
    @State private var answer: LyricsStore.Answer?
    @State private var heldUntil = Date.distantPast
    @State private var timePill: Int?

    var body: some View {
        Group {
            switch answer {
            case nil:
                ProgressView().tint(ink)
            case .some(.none):
                message("No lyrics for this song")
            case .some(.hidden):
                message("Lyrics are hidden for this song")
            case .some(.failed):
                Button { Task { await reload(force: true) } } label: { message("Couldn't load lyrics, tap to retry") }
                    .buttonStyle(.plain)
            case .some(.found(let lyrics, _)):
                if lyrics.line.allSatisfy({ $0.value.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    message("Instrumental")
                } else if !lyrics.synced || store.look == .plain {
                    plain(lyrics)
                } else {
                    synced(lyrics)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.05),
                                     .init(color: .black, location: 0.95), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .task(id: player.current?.id) { await reload(force: false) }
        .onChange(of: store.answers[player.current?.id ?? ""]) { _, new in if let new { answer = new } }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func reload(force: Bool) async {
        guard let song = player.current else { answer = LyricsStore.Answer.none; return }
        answer = nil
        answer = force ? await store.retry(song) : await store.answer(for: song)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.system(size: 16)).foregroundStyle(muted).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func plain(_ lyrics: StructuredLyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(lyrics.line.enumerated()), id: \.offset) { _, line in
                    if line.value.trimmingCharacters(in: .whitespaces).isEmpty {
                        Spacer().frame(height: 18)
                    } else {
                        Text(line.value)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(ink.opacity(0.85))
                            .lineSpacing(4)
                            .padding(.vertical, 2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 40)
        }
        .scrollIndicators(.hidden)
    }

    /// Flowing and Classic: the line being sung is lit and kept in place; tap to play from a line.
    private func synced(_ lyrics: StructuredLyrics) -> some View {
        GeometryReader { box in
            let flowing = store.look == .flowing
            let size = flowing ? min(36, max(22, box.size.width / 13)) : 20
            let offset = store.totalOffset(player.current?.id ?? "")
            TimelineView(.animation(paused: !player.isPlaying)) { time in
                let clock = player.position(at: time.date) - offset
                let current = lyrics.lineIndex(at: clock)
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: flowing ? size * 0.55 : 18) {
                            ForEach(Array(lyrics.line.enumerated()), id: \.offset) { index, line in
                                lineView(lyrics, index: index, line: line, current: current, clock: clock, size: size, flowing: flowing)
                                    .id(index)
                                    .onTapGesture { seek(to: line, in: lyrics, offset: offset) }
                                    .onLongPressGesture(minimumDuration: 0.4) { showTime(index) }
                                    .overlay(alignment: .topLeading) {
                                        if timePill == index, let start = line.start { pill(start, lyrics: lyrics, offset: offset) }
                                    }
                            }
                        }
                        .padding(.top, box.size.height * (flowing ? 0.33 : 0.45))
                        .padding(.bottom, box.size.height * 0.6)
                    }
                    .scrollIndicators(.hidden)
                    .simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { _ in
                        heldUntil = Date().addingTimeInterval(flowing ? 2 : 3)
                    })
                    .onChange(of: current) { _, line in
                        guard let line, Date() > heldUntil else { return }
                        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
                            reader.scrollTo(line, anchor: UnitPoint(x: 0, y: flowing ? 0.33 : 0.5))
                        }
                    }
                    .onAppear {
                        if let current { reader.scrollTo(current, anchor: UnitPoint(x: 0, y: flowing ? 0.33 : 0.5)) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lineView(_ lyrics: StructuredLyrics, index: Int, line: LyricsLine, current: Int?, clock: Double,
                          size: CGFloat, flowing: Bool) -> some View {
        let text = line.value.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            PauseDots(ink: ink, active: index == current)
        } else {
            let isCurrent = index == current
            let sung = current.map { index < $0 } ?? false
            let distance = Double(abs(index - (current ?? index)))
            let fill = isCurrent ? lineFill(lyrics, index: index, clock: clock) : (sung ? 1 : 0)
            let font = Font.system(size: flowing ? size : (isCurrent ? 28 : 20), weight: flowing ? .heavy : .bold)
            ZStack(alignment: .leading) {
                Text(text).font(font).foregroundStyle(ink.opacity(flowing ? (sung ? 0.45 : 0.55) : (isCurrent ? 0.5 : 0.35)))
                if isCurrent {
                    Text(text).font(font).foregroundStyle(ink.opacity(0.95))
                        .shadow(color: ink.opacity(0.35), radius: 8)
                        .mask(FillMask(fraction: fill))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .blur(radius: flowing ? min(3, distance * 0.8) : 0)
            .scaleEffect(isCurrent && flowing ? 1.02 : 1, anchor: .leading)
            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(min(0.3, distance * 0.05)), value: current)
            .contentShape(Rectangle())
        }
    }

    /// How far through a line the singing is, from its start to the next line's.
    private func lineFill(_ lyrics: StructuredLyrics, index: Int, clock: Double) -> Double {
        guard let start = lyrics.line[index].start else { return 1 }
        let ms = clock * 1000 + Double(lyrics.offset)
        let end = lyrics.line.dropFirst(index + 1).first { $0.start != nil }?.start ?? (start + 4000)
        let length = max(400, min(Double(end - start), 8000))
        return min(1, max(0, (ms - Double(start)) / length))
    }

    private func seek(to line: LyricsLine, in lyrics: StructuredLyrics, offset: Double) {
        guard let start = line.start else { return }
        let seconds = Double(start - lyrics.offset) / 1000 + offset
        player.seek(to: max(0, seconds))
        heldUntil = .distantPast
        UIAccessibility.post(notification: .announcement, argument: "Playing from \(minutes(seconds))")
    }

    private func showTime(_ index: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        timePill = index
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if timePill == index { timePill = nil }
        }
    }

    private func pill(_ start: Int, lyrics: StructuredLyrics, offset: Double) -> some View {
        Text(minutes(Double(start - lyrics.offset) / 1000 + offset))
            .font(.system(size: 11.5, weight: .bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(hex: 0x121214, opacity: 0.32), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
            .offset(y: -26)
            .transition(.opacity)
            .accessibilityLabel("Play from \(minutes(Double(start - lyrics.offset) / 1000 + offset))")
    }

    private func minutes(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}

/// A soft-edged sweep of light from the start of a line to `fraction` of it.
private struct FillMask: View {
    let fraction: Double

    var body: some View {
        GeometryReader { box in
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: max(0, fraction - 0.04)),
                                   .init(color: .clear, location: min(1, fraction + 0.04))],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: box.size.width)
        }
    }
}

/// A pause in the singing: three dots that bounce while it lasts.
private struct PauseDots: View {
    let ink: Color
    let active: Bool

    var body: some View {
        TimelineView(.animation(paused: !active)) { time in
            let t = time.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(ink.opacity(active ? 0.8 : 0.3))
                        .frame(width: 8, height: 8)
                        .offset(y: active ? -4 * abs(sin((t / 1.4 + Double(i) * 0.2) * .pi)) : 0)
                }
            }
        }
        .frame(height: 24)
        .accessibilityLabel("Instrumental")
    }
}

/// The lyrics menu: where the lyrics came from, other copies to choose from, timing, and
/// hiding them for this song.
struct LyricsMenu: View {
    let song: Song
    @Environment(LyricsStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .main

    enum Page { case main, timing, choose }

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .main: main
                case .timing: timing
                case .choose: LyricsChooser(song: song) { page = .main }
                }
            }
            .navigationTitle(page == .timing ? "Lyrics timing" : (page == .choose ? "Choose lyrics" : "Lyrics"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if page != .main {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { page = .main } label: { Image(systemName: "chevron.left") }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(page == .choose ? [.large] : [.medium, .large])
        .presentationBackground(.thinMaterial)
    }

    private var answer: LyricsStore.Answer? { store.answers[song.id] }

    private var main: some View {
        List {
            Section {
                Text(answer?.heading ?? "Looking for lyrics").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                Button { page = .choose } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(found ? "Choose other lyrics" : "Find lyrics", systemImage: "text.magnifyingglass")
                        Text("Every copy that can be found for this song").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    }
                }
                if case .found(let lyrics, _) = answer, lyrics.synced {
                    Button { page = .timing } label: { Label("Adjust timing", systemImage: "timer") }
                }
                if answer == .hidden {
                    Button { Task { try? await store.show(song) } } label: { Label("Show lyrics again", systemImage: "eye") }
                } else {
                    Button(role: .destructive) {
                        Task {
                            do {
                                try await store.hide(song)
                                dismiss()
                            } catch {
                                router.show(error.localizedDescription)
                            }
                        }
                    } label: {
                        Label("Hide lyrics for this song", systemImage: "eye.slash")
                    }
                }
            }
            Section("Look") {
                Picker("Look", selection: Binding(get: { store.look }, set: { store.look = $0 })) {
                    ForEach(LyricsStore.Look.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var found: Bool {
        if case .found = answer { return true }
        return false
    }

    private var timing: some View {
        List {
            Text("If the words light up late, tap Earlier. If early, tap Later.")
                .font(.octoBodySmall).foregroundStyle(OctoColor.textMuted)
            adjuster(title: "This song", detail: "For this song only, on every output.",
                     value: store.songOffset(song.id), move: { store.moveSong(song.id, steps: $0) })
            let output = store.output
            adjuster(title: output.name, detail: store.outputTiming.automatic ? "Automatic for this output." : "For everything on this output.",
                     value: store.outputTiming.ms, move: { store.moveOutput(steps: $0) },
                     reset: store.outputTiming.automatic ? nil : { store.resetOutput() })
        }
        .scrollContentBackground(.hidden)
    }

    private func adjuster(title: String, detail: String, value: Int, move: @escaping (Int) -> Void,
                          reset: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.octoBody)
                    Text(detail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
                Spacer()
                Text(String(format: "%+.2f s", Double(value) / 1000)).font(.octoBody.monospacedDigit())
            }
            HStack {
                Button("Earlier") { move(-1) }.buttonStyle(.glass)
                Button("Later") { move(1) }.buttonStyle(.glass)
                Spacer()
                if let reset { Button("Use automatic", action: reset).font(.octoBodySmall).buttonStyle(.plain).foregroundStyle(OctoColor.accent) }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Every copy of the song's lyrics that can be found, with a search for another title or artist.
struct LyricsChooser: View {
    let song: Song
    let done: () -> Void
    @Environment(LyricsStore.self) private var store
    @Environment(Router.self) private var router
    @State private var title = ""
    @State private var artist = ""
    @State private var copies: [LyricsCandidate] = []
    @State private var searching = false
    @State private var failed = false

    var body: some View {
        List {
            Section {
                TextField("Title", text: $title).submitLabel(.search).onSubmit { Task { await search() } }
                TextField("Artist", text: $artist).submitLabel(.search).onSubmit { Task { await search() } }
                Button("Search") { Task { await search() } }
            }
            Section(title == song.title && artist == song.byline ? "For this song" : "Search results") {
                if searching {
                    ProgressView()
                } else if failed {
                    Text("Couldn't reach the lyrics sources. Try again.").foregroundStyle(OctoColor.textMuted)
                } else if copies.isEmpty {
                    Text("Nothing found.").foregroundStyle(OctoColor.textMuted)
                }
                ForEach(copies) { copy in
                    Button { Task { await choose(copy) } } label: { row(copy) }
                        .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .task {
            title = song.title
            artist = song.byline
            await search()
        }
    }

    private func row(_ copy: LyricsCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(copy.source.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(1)
                    Text(kindWords(copy.kind)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                    if copy.sameSong { Text("This song").font(.octoCaption).foregroundStyle(OctoColor.accent) }
                }
                Text("\(copy.title) · \(copy.artist)").font(.octoBodySmall).lineLimit(1)
                ForEach(copy.preview.prefix(2), id: \.self) { line in
                    Text(line).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                }
            }
            Spacer()
            if copy.chosen { Image(systemName: "checkmark").foregroundStyle(OctoColor.accent) }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }

    private func kindWords(_ kind: String) -> String {
        switch kind {
        case "word": "Word by word"
        case "line": "Line by line"
        case "plain": "Not synced"
        case "instrumental": "Instrumental"
        default: kind
        }
    }

    private func search() async {
        searching = true
        failed = false
        defer { searching = false }
        do {
            copies = try await store.candidates(for: song, title: title, artist: artist)
        } catch {
            failed = true
        }
    }

    private func choose(_ copy: LyricsCandidate) async {
        do {
            try await store.choose(copy, for: song)
            done()
        } catch {
            router.show(error.localizedDescription)
        }
    }
}
