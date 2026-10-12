import OctoKit
import SwiftUI
import UIKit

/// The full player. Every control sits on the cover's own drifting wash; the words take
/// whichever colour reads on it. Pull down anywhere to close.
struct NowPlayingView: View {
    let dismiss: () -> Void
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @State private var tone = CoverTone()
    @State private var scrubbing: Double?
    @State private var pull: CGFloat = 0
    @State private var lyricsOpen = false
    @State private var showsQueue = false
    @State private var showsTime = false
    @State private var starred: [String: Bool] = [:]
    @State private var appeared = false
    @State private var artDrag: CGFloat = 0
    @State private var artCrossed = false
    @State private var showsLyricsMenu = false

    var body: some View {
        // The safe area is read here, then the player covers the whole screen: the wash runs to
        // every edge and only the controls keep inside the safe area.
        GeometryReader { safe in
            let insets = safe.safeAreaInsets
            GeometryReader { screen in
                let cap = screen.size.height * 0.45
                let travel = min(cap, max(0, pull))
                let shrink = 1 - 0.06 * (travel / cap)
                ZStack {
                    CoverWash(coverArt: player.current?.coverArt, tone: tone)
                    VStack(spacing: 0) {
                        topLine
                        if lyricsOpen {
                            LyricsView(ink: tone.ink, muted: tone.muted)
                                .transition(.opacity)
                            LyricsBar(ink: tone.ink, close: { withAnimation(.easeInOut(duration: 0.36)) { lyricsOpen = false } },
                                      menu: { showsLyricsMenu = true })
                                .padding(.top, 12)
                                .padding(.bottom, 16)
                        } else {
                            art(in: screen.size)
                            controls
                                .offset(y: appeared ? 0 : 28)
                                .opacity(appeared ? 1 : 0)
                        }
                    }
                    .padding(.top, insets.top)
                    .padding(.bottom, max(insets.bottom, 12))
                    .padding(.horizontal, 24)
                    .foregroundStyle(tone.ink)
                }
                .frame(width: screen.size.width, height: screen.size.height)
                .clipShape(RoundedRectangle(cornerRadius: travel > 0 ? min(28, travel / cap * 5 * 28) : 0, style: .continuous))
                .scaleEffect(shrink)
                .offset(y: travel)
                .gesture(pullToClose(cap: cap))
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsQueue) { QueueSheet() }
        .sheet(isPresented: $showsLyricsMenu) {
            if let song = player.current { LyricsMenu(song: song) }
        }
        .task(id: player.current?.coverArt) { await readTone() }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.68).delay(0.08)) { appeared = true }
        }
        .statusBarHidden(false)
    }

    // MARK: Parts

    private var topLine: some View {
        ZStack {
            if let album = player.current?.album, showsAlbum {
                Button {
                    guard let song = player.current, let albumId = song.albumId, !song.isExternal else { return }
                    router.go(.album(Album(id: albumId, name: album, artist: song.artist ?? "", coverArt: song.coverArt)))
                    dismiss()
                } label: {
                    Text(album).font(.octoCaption).foregroundStyle(tone.muted).lineLimit(1)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 104)
                .accessibilityLabel("Open album")
            }
            HStack {
                Button(action: dismiss) {
                    Image(systemName: "chevron.down").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: .circle)
                .accessibilityLabel("Close player")
                Spacer()
                RoutePicker(tint: UIColor(tone.ink))
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Play on")
            }
        }
        .frame(height: 56)
    }

    /// Singles and songs found online show no album name.
    private var showsAlbum: Bool {
        guard let song = player.current, let album = song.album, !album.isEmpty else { return false }
        return !album.hasSuffix("- Single") && album.caseInsensitiveCompare(song.title) != .orderedSame
    }

    private func art(in size: CGSize) -> some View {
        GeometryReader { stage in
            let side = min(312, stage.size.width, stage.size.height - 16)
            Cover(id: player.current?.coverArt, size: side, radius: side * 0.03)
                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
                .shadow(color: .black.opacity(0.15), radius: 32, y: 16)
                .scaleEffect(player.isPlaying ? 1 : 0.84)
                .animation(.spring(response: 0.36, dampingFraction: 0.6), value: player.isPlaying)
                .offset(x: artDrag * 0.55)
                .opacity(1 - min(0.5, abs(artDrag) / max(1, size.width)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(skipGesture(width: size.width))
                .sensoryFeedback(.impact(weight: .light), trigger: artCrossed) { _, now in now }
                .id(player.current?.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 40)), removal: .opacity))
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            songRow
            Spacer().frame(height: 12)
            progress
            Spacer().frame(height: 12)
            transport
            Spacer().frame(height: 8)
            VolumeRow(ink: tone.ink)
            Spacer().frame(height: 12)
            actions
            Spacer().frame(height: 28)
        }
    }

    private var songRow: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Marquee(text: player.current?.title ?? "", font: .system(size: 24, weight: .bold), color: tone.ink)
                        .frame(height: 30)
                    if player.current?.explicitStatus == "explicit" { ExplicitMark(size: 16) }
                }
                Button {
                    guard let song = player.current, let artistId = song.artistId, !song.isExternal else { return }
                    router.go(.artist(id: artistId, name: song.artist ?? ""))
                    dismiss()
                } label: {
                    Text(player.current?.byline ?? "")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tone.artist)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            }
            .id(player.current?.id)
            .transition(.opacity)
            Spacer(minLength: 8)
            if let song = player.current {
                Button { Task { await toggleHeart(song) } } label: {
                    Image(systemName: isStarred(song) ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .shadow(color: isStarred(song) ? tone.ink.opacity(0.6) : .clear, radius: 6)
                        .symbolEffect(.bounce, value: isStarred(song))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Like")
                .accessibilityValue(isStarred(song) ? "In Liked songs" : "Not in Liked songs")
                Menu {
                    SongActions(song: song)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(tone.ink.opacity(0.6))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("More")
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 0) {
            LineSlider(value: player.elapsed, range: 0...max(player.duration, 1), ink: tone.ink,
                       onCommit: { player.seek(to: $0) }, dragging: $scrubbing)
            ZStack {
                HStack {
                    Text(time(scrubbing ?? player.elapsed))
                    Spacer()
                    Text("-" + time(max(player.duration - (scrubbing ?? player.elapsed), 0)))
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(tone.muted)
                HStack(spacing: 8) {
                    if let song = player.current { QualityBadge(song: song, ink: tone.ink) }
                    if player.speed != 1 {
                        Button { showsTime = true } label: {
                            Text(speedWords(player.speed)).font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 10).frame(height: 24)
                                .glassEffect(.clear, in: .capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Playback speed \(speedWords(player.speed))")
                    }
                }
            }
            .offset(y: -8)
        }
    }

    private var transport: some View {
        HStack {
            Button(action: player.previous) {
                Image(systemName: "backward.fill").font(.system(size: 34)).frame(width: 72, height: 72)
            }
            .buttonStyle(TransportButtonStyle(nudge: -8))
            .accessibilityLabel("Previous")
            Spacer()
            Button(action: player.toggle) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46))
                    .frame(width: 72, height: 72)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(TransportButtonStyle())
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            Spacer()
            Button(action: player.next) {
                Image(systemName: "forward.fill").font(.system(size: 34)).frame(width: 72, height: 72)
            }
            .buttonStyle(TransportButtonStyle(nudge: 8))
            .accessibilityLabel("Next")
            .disabled(!player.hasNext)
        }
        .padding(.horizontal, 8)
    }

    private var actions: some View {
        HStack(spacing: 20) {
            PlayerChromeButton(icon: "quote.bubble", label: "Lyrics", ink: tone.ink, lit: lyricsOpen) {
                withAnimation(.easeInOut(duration: 0.36)) { lyricsOpen.toggle() }
            }
            .accessibilityValue(lyricsOpen ? "Showing" : "Hidden")
            PlayerChromeButton(icon: "list.bullet", label: "Up next", ink: tone.ink) { showsQueue = true }
            PlayerChromeButton(icon: "moon", label: "Sleep timer", ink: tone.ink, lit: player.sleep != nil) { showsTime = true }
                .overlay(alignment: .topTrailing) { sleepPill }
                .popover(isPresented: $showsTime) {
                    TimeCard().presentationCompactAdaptation(.popover)
                }
            PlayerChromeButton(icon: "shuffle", label: "Shuffle", ink: tone.ink, lit: player.shuffled) { player.toggleShuffle() }
                .accessibilityValue(player.shuffled ? "On" : "Off")
            PlayerChromeButton(icon: player.repeatMode == .one ? "repeat.1" : "repeat", label: "Repeat", ink: tone.ink,
                               lit: player.repeatMode != .off) { player.cycleRepeat() }
                .accessibilityValue(player.repeatMode == .off ? "Off" : (player.repeatMode == .all ? "All songs" : "This song"))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var sleepPill: some View {
        if case .at(let date) = player.sleep {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("\(max(1, Int(date.timeIntervalSinceNow / 60) + 1))")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                    .background(OctoColor.accent, in: Capsule())
            }
            .offset(x: 6, y: -4)
        }
    }

    // MARK: Gestures

    /// The player follows the finger down, shrinks a little and rounds its corners; a quick
    /// flick or more than half the way closes it.
    private func pullToClose(cap: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { drag in
                guard drag.translation.height > abs(drag.translation.width) || pull > 0 else { return }
                pull = max(0, drag.translation.height * 0.82)
            }
            .onEnded { drag in
                let velocity = (drag.predictedEndTranslation.height - drag.translation.height) * 4
                if velocity > 1200 || (pull > cap / 2 && velocity > -150) {
                    dismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pull = 0 }
                }
            }
    }

    /// Sideways on the cover skips: past 88 points or a quick flick.
    private func skipGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { drag in
                guard abs(drag.translation.width) > abs(drag.translation.height) else { return }
                artDrag = drag.translation.width
                artCrossed = abs(drag.translation.width) > 88
            }
            .onEnded { drag in
                let fling = (drag.predictedEndTranslation.width - drag.translation.width) * 4
                if drag.translation.width < -88 || fling < -900 {
                    withAnimation(.easeOut(duration: 0.12)) { artDrag = -width / 2 }
                    player.next()
                } else if drag.translation.width > 88 || fling > 900 {
                    withAnimation(.easeOut(duration: 0.12)) { artDrag = width / 2 }
                    player.previous()
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { artDrag = 0 }
                artCrossed = false
            }
    }

    // MARK: Helpers

    private func readTone() async {
        guard let coverId = player.current?.coverArt, let client = session.client,
              let image = await Covers.shared.image(coverId, size: 300, client: client)
        else { return }
        let found = CoverTone.of(image)
        withAnimation(.easeInOut(duration: 0.5)) { tone = found }
    }

    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.isFinite ? seconds : 0).formatted(.time(pattern: .minuteSecond))
    }

    private func speedWords(_ speed: Float) -> String {
        String(format: speed == speed.rounded() ? "%.0fx" : (speed * 10 == (speed * 10).rounded() ? "%.1fx" : "%.2fx"), speed)
    }

    private func isStarred(_ song: Song) -> Bool { starred[song.id] ?? song.isStarred }

    private func toggleHeart(_ song: Song) async {
        guard let client = session.client else { return }
        let next = !isStarred(song)
        starred[song.id] = next
        do {
            if next { try await client.star(songId: song.id) } else { try await client.unstar(songId: song.id) }
        } catch {
            starred[song.id] = !next
            router.show(error.localizedDescription)
        }
    }
}
