import OctoKit
import SwiftUI

/// The song's words. Synced lyrics keep the line being sung in the middle, larger and bright;
/// tapping a line plays from it. After scrolling by hand the lyrics follow the song again three
/// seconds later. Plain lyrics are one scrolling column.
struct LyricsView: View {
    let ink: Color
    let muted: Color
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @State private var lyrics: StructuredLyrics?
    @State private var state: LoadState = .loading
    @State private var heldUntil = Date.distantPast

    enum LoadState { case loading, ready, none, failed }

    var body: some View {
        Group {
            switch state {
            case .loading:
                ProgressView().tint(ink).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .none:
                message("No lyrics for this song")
            case .failed:
                Button { Task { await load() } } label: { message("Couldn't load lyrics, tap to retry") }.buttonStyle(.plain)
            case .ready:
                if let lyrics { lines(lyrics) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                     .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .task(id: player.current?.id) { await load() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.system(size: 16)).foregroundStyle(muted).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func lines(_ lyrics: StructuredLyrics) -> some View {
        let current = lyrics.lineIndex(at: player.elapsed)
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: lyrics.synced ? 18 : 6) {
                    ForEach(Array(lyrics.line.enumerated()), id: \.offset) { position, line in
                        if line.value.trimmingCharacters(in: .whitespaces).isEmpty {
                            Spacer().frame(height: 18)
                        } else if lyrics.synced {
                            Button {
                                if let start = line.start { player.seek(to: Double(start + lyrics.offset) / 1000) }
                            } label: {
                                Text(line.value)
                                    .font(.system(size: position == current ? 28 : 20, weight: .bold))
                                    .foregroundStyle(ink.opacity(position == current ? 0.95 : 0.35))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .animation(.spring(response: 0.4, dampingFraction: 0.7), value: current)
                            }
                            .buttonStyle(.plain)
                            .id(position)
                        } else {
                            Text(line.value)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(ink.opacity(0.85))
                                .lineSpacing(4)
                        }
                    }
                }
                .padding(.vertical, 120)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(DragGesture().onChanged { _ in heldUntil = Date().addingTimeInterval(3) })
            .onChange(of: current) { _, line in
                guard let line, Date() > heldUntil else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { reader.scrollTo(line, anchor: .center) }
            }
            .onAppear { if let current { reader.scrollTo(current, anchor: .center) } }
        }
    }

    private func load() async {
        guard let song = player.current, let client = session.client else { state = .none; return }
        state = .loading
        do {
            let found = try await client.lyrics(songId: song.id)
            lyrics = found
            state = found?.line.isEmpty == false ? .ready : .none
        } catch OctoError.notFound {
            state = .none
        } catch {
            state = .failed
        }
    }
}

/// While lyrics show, the controls fold into one glass bar: the song, previous, play, next and
/// the lyrics switch, with the progress along its bottom edge.
struct LyricsBar: View {
    let ink: Color
    let close: () -> Void
    @Environment(Player.self) private var player

    var body: some View {
        HStack(spacing: 0) {
            Button(action: close) {
                HStack(spacing: 10) {
                    Cover(id: player.current?.coverArt, size: 40, radius: 10)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.current?.title ?? "").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                        Text(player.current?.byline ?? "").font(.system(size: 11)).opacity(0.6).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave lyrics")
            control("backward.fill", 22, "Previous", player.previous)
            control(player.isPlaying ? "pause.fill" : "play.fill", 26, player.isPlaying ? "Pause" : "Play", player.toggle)
            control("forward.fill", 22, "Next", player.next)
            PlayerChromeButton(icon: "quote.bubble.fill", label: "Lyrics", ink: ink, action: close)
                .accessibilityValue("Showing")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 64)
        .overlay(alignment: .bottom) {
            GeometryReader { box in
                ZStack(alignment: .leading) {
                    Capsule().fill(ink.opacity(0.18))
                    Capsule().fill(ink.opacity(0.7)).frame(width: box.size.width * player.progress)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 32)
            .padding(.bottom, 4)
        }
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, -12)
    }

    private func control(_ icon: String, _ size: CGFloat, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size)).frame(width: 40, height: 40)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
