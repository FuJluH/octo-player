import AVKit
import OctoKit
import SwiftUI
import UIKit

/// The mini player, in the tab bar's glass accessory.
struct MiniPlayer: View {
    let open: () -> Void
    @Environment(Player.self) private var player
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: 10) {
            Cover(id: player.current?.coverArt, size: 34, radius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.title ?? "")
                    .font(.octoBodySmall.weight(.semibold))
                    .lineLimit(1)
                if placement != .inline {
                    Text(player.current?.byline ?? "")
                        .font(.octoCaption)
                        .foregroundStyle(OctoColor.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button(action: player.toggle) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            if placement != .inline {
                Button(action: player.next) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Next")
                .disabled(player.upNext.isEmpty)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }
}

/// The full player. The art sits on a wash of its own colours; every control is on glass.
struct NowPlayingView: View {
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var scrubbing: Double?
    @State private var showsQueue = false
    @State private var starred: [String: Bool] = [:]

    var body: some View {
        GeometryReader { frame in
            let art = min(frame.size.width - 48, frame.size.height * 0.45)
            ZStack {
                wash
                VStack(spacing: 22) {
                    Capsule()
                        .fill(.white.opacity(0.35))
                        .frame(width: 40, height: 5)
                        .padding(.top, 8)
                        .onTapGesture { dismiss() }
                    Spacer(minLength: 0)
                    BadgedCover(id: player.current?.coverArt, size: art, radius: OctoRadius.artL,
                                external: player.current?.isExternal ?? false)
                        .shadow(color: .black.opacity(0.45), radius: 30, y: 16)
                        .scaleEffect(player.isPlaying ? 1 : 0.88)
                        .animation(.spring(duration: 0.45, bounce: 0.25), value: player.isPlaying)
                    Spacer(minLength: 0)
                    titleRow
                    progress
                    controls
                    bottomRow
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 24)
            }
        }
        .gesture(DragGesture().onEnded { if $0.translation.height > 120 { dismiss() } })
        .sheet(isPresented: $showsQueue) { QueueView() }
    }

    private var wash: some View {
        ZStack {
            OctoColor.background
            Cover(id: player.current?.coverArt, size: 600, radius: 0)
                .blur(radius: 80)
                .scaleEffect(1.6)
                .opacity(0.65)
            LinearGradient(colors: [.black.opacity(0.1), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.current?.title ?? "")
                    .font(.octoHeadline)
                    .lineLimit(1)
                Text(player.current?.byline ?? "")
                    .font(.octoBody)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                if let source = player.current?.octoSuggestedBy {
                    Text("From \(source)")
                        .font(.octoCaption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            if let song = player.current {
                Button { Task { await toggleHeart(song) } } label: {
                    Image(systemName: isStarred(song) ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(isStarred(song) ? "Remove heart" : "Heart")
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { scrubbing ?? player.elapsed },
                    set: { scrubbing = $0 }),
                in: 0...max(player.duration, 1)
            ) { editing in
                if !editing, let target = scrubbing {
                    player.seek(to: target)
                    scrubbing = nil
                }
            }
            .tint(.white)
            HStack {
                Text(time(scrubbing ?? player.elapsed))
                Spacer()
                Text("-" + time(max(player.duration - (scrubbing ?? player.elapsed), 0)))
            }
            .font(.octoCaption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 24) {
            HStack(spacing: 28) {
                Button(action: player.previous) {
                    Image(systemName: "backward.fill").font(.system(size: 26)).frame(width: 64, height: 64)
                }
                .accessibilityLabel("Previous")
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 34))
                        .frame(width: 84, height: 84)
                        .contentTransition(.symbolEffect(.replace))
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button(action: player.next) {
                    Image(systemName: "forward.fill").font(.system(size: 26)).frame(width: 64, height: 64)
                }
                .accessibilityLabel("Next")
                .disabled(player.upNext.isEmpty)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .foregroundStyle(.white)
        }
    }

    private var bottomRow: some View {
        HStack {
            RoutePicker()
                .frame(width: 44, height: 44)
            Spacer()
            if player.radioSeed != nil {
                Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                    .font(.octoCaption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button { showsQueue = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 18, weight: .semibold)).frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Queue")
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.isFinite ? seconds : 0).formatted(.time(pattern: .minuteSecond))
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
        }
    }
}

/// What plays next: drag to reorder, swipe to remove, tap to jump.
struct QueueView: View {
    @Environment(Player.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let current = player.current {
                    Section("Now Playing") {
                        HStack(spacing: 12) {
                            Cover(id: current.coverArt, size: 46, radius: OctoRadius.artS)
                            VStack(alignment: .leading) {
                                Text(current.title).font(.octoBody).lineLimit(1)
                                Text(current.byline).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary).lineLimit(1)
                            }
                        }
                    }
                }
                Section(player.radioSeed == nil ? "Up Next" : "Up Next on Radio") {
                    ForEach(Array(player.upNext.enumerated()), id: \.offset) { offset, song in
                        Button { player.jump(to: player.index + 1 + offset) } label: {
                            HStack(spacing: 12) {
                                BadgedCover(id: song.coverArt, size: 46, radius: OctoRadius.artS, external: song.isExternal)
                                VStack(alignment: .leading) {
                                    Text(song.title).font(.octoBody).lineLimit(1)
                                    Text(song.byline).font(.octoBodySmall).foregroundStyle(OctoColor.textSecondary).lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onMove { player.move(from: $0, to: $1) }
                    .onDelete { player.remove(at: $0) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The system's AirPlay and Bluetooth picker.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor(OctoColor.accentHover)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
