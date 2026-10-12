import OctoKit
import SwiftUI

/// Up next: what has played, the song playing, and what follows. Drag to reorder, swipe to
/// remove, tap to play.
struct QueueSheet: View {
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        NavigationStack {
            ScrollViewReader { reader in
                List {
                    Section {
                        tools.listRowBackground(Color.clear).listRowSeparator(.hidden)
                        if player.shuffled {
                            Text("Turn off shuffle to reorder")
                                .font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                        }
                    }
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { position, song in
                        row(song, position: position)
                            .id(position)
                            .listRowBackground(position == player.index
                                               ? RoundedRectangle(cornerRadius: 12).fill(OctoColor.accent.opacity(0.18)).padding(.horizontal, 12).padding(.vertical, 2)
                                               : nil)
                            .opacity(position < player.index ? 0.5 : 1)
                            .moveDisabled(position <= player.index || player.shuffled)
                            .deleteDisabled(position == player.index)
                    }
                    .onMove { source, destination in
                        let upcoming = IndexSet(source.map { $0 - player.index - 1 }.filter { $0 >= 0 })
                        player.move(from: upcoming, to: max(0, destination - player.index - 1))
                    }
                    .onDelete { offsets in remove(offsets) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onAppear { reader.scrollTo(player.index, anchor: .top) }
            }
            .navigationTitle("Up next")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .alert("New playlist", isPresented: $naming) {
            TextField("Playlist name", text: $name)
            Button("Create") { Task { await save() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            ScrollView(.horizontal) {
                HStack(spacing: 16) {
                    tool("Clear", enabled: !player.upNext.isEmpty) {
                        let before = player.snapshot
                        player.clearUpcoming()
                        router.show("Queue cleared", action: "Undo") { player.restore(before) }
                    }
                    tool("Remove played", enabled: player.index > 0) {
                        let before = player.snapshot
                        player.removePlayed()
                        router.show("Played songs removed", action: "Undo") { player.restore(before) }
                    }
                    tool("Save as playlist", enabled: session.client != nil && !player.queue.isEmpty) {
                        name = ""
                        naming = true
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func tool(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(enabled ? OctoColor.accent : OctoColor.textMuted)
            .buttonStyle(.plain)
            .disabled(!enabled)
    }

    private var summary: String {
        let total = player.queue.reduce(0) { $0 + $1.duration }
        let count = player.queue.count
        return "\(count == 1 ? "1 song" : "\(count) songs") · \(total.spokenLength)"
    }

    private func row(_ song: Song, position: Int) -> some View {
        Button { player.jump(to: position) } label: {
            HStack(spacing: 12) {
                Cover(id: song.coverArt, size: 44, radius: OctoRadius.artS)
                    .overlay {
                        if position == player.index {
                            RoundedRectangle(cornerRadius: OctoRadius.artS).fill(.black.opacity(0.5))
                            NowPlayingBars(playing: player.isPlaying)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.title).font(.octoBodySmall).lineLimit(1)
                    Text(song.byline).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if position != player.index {
                Button { player.playNext([song]); remove(IndexSet([position])) } label: { Label("Play next", systemImage: "text.insert") }
                Button(role: .destructive) { remove(IndexSet([position])) } label: { Label("Remove from queue", systemImage: "minus.circle") }
            }
        }
    }

    private func remove(_ offsets: IndexSet) {
        let before = player.snapshot
        let upcoming = IndexSet(offsets.compactMap { $0 > player.index ? $0 - player.index - 1 : nil })
        player.remove(at: upcoming)
        router.show("Removed from the queue", action: "Undo") { player.restore(before) }
    }

    /// Songs added by radio are left out of a saved playlist.
    private func save() async {
        guard let client = session.client else { return }
        let picked = name.trimmingCharacters(in: .whitespaces)
        guard !picked.isEmpty else { return }
        do {
            try await client.createPlaylist(name: picked, songIds: player.queue.filter { !$0.isExternal }.map(\.id))
            router.show("Saved as \(picked)", done: true)
        } catch {
            router.show(error.localizedDescription)
        }
    }
}

/// The sleep timer and the playback speed, in one glass card.
struct TimeCard: View {
    @Environment(Player.self) private var player
    @State private var page = 0
    @State private var custom = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if page == 0 { sleepPage } else { speedPage }
        }
        .padding(18)
        .frame(width: 320)
        .animation(.snappy, value: page)
    }

    private var sleepPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sleep timer").font(.octoSection)
            if let sleep = player.sleep {
                HStack {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(words(sleep)).font(.system(size: 28, weight: .bold).monospacedDigit())
                    }
                    Spacer()
                    Button("Cancel") { player.setSleep(nil) }.buttonStyle(.glass)
                }
                if case .at(let date) = sleep {
                    HStack {
                        Button("+5 min") { player.setSleep(.at(date.addingTimeInterval(300))) }.buttonStyle(.glass)
                        Button("+10 min") { player.setSleep(.at(date.addingTimeInterval(600))) }.buttonStyle(.glass)
                    }
                }
            }
            grid([(5, "5 min"), (15, "15 min"), (30, "30 min"), (45, "45 min"), (60, "1 hour")]) { minutes in
                player.setSleep(.at(Date().addingTimeInterval(TimeInterval(minutes * 60))))
            }
            HStack {
                TextField("Minutes, 1 to 720", text: $custom).keyboardType(.numberPad)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Button("Start") {
                    if let minutes = Int(custom), (1...720).contains(minutes) {
                        player.setSleep(.at(Date().addingTimeInterval(TimeInterval(minutes * 60))))
                    }
                }
                .buttonStyle(.glass)
            }
            Text("Stop after").font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            grid([(1, "This song"), (2, "2 songs"), (3, "3 songs"), (5, "5 songs")]) { songs in
                player.setSleep(.afterSongs(songs))
            }
            Divider()
            Button { page = 1 } label: {
                HStack {
                    Text("Playback speed")
                    Spacer()
                    Text(String(format: "%.2gx", player.speed)).foregroundStyle(OctoColor.textMuted)
                    Image(systemName: "chevron.right").foregroundStyle(OctoColor.textMuted)
                }
                .font(.octoBodySmall)
            }
            .buttonStyle(.plain)
        }
    }

    private var speedPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { page = 0 } label: {
                Label("Sleep timer", systemImage: "chevron.left").font(.octoBodySmall)
            }
            .buttonStyle(.plain)
            HStack {
                Text("Speed").font(.octoSection)
                Spacer()
                if player.speed != 1 || !player.keepsPitch {
                    Button("Reset") { player.setSpeed(1); player.setKeepsPitch(true) }.buttonStyle(.glass)
                }
            }
            Text(String(format: "%.2fx", player.speed)).font(.system(size: 32, weight: .bold).monospacedDigit())
            Slider(value: Binding(get: { Double(player.speed) }, set: { value in
                var snapped = (value * 20).rounded() / 20
                for mark in [0.75, 1, 1.25, 1.5] where abs(snapped - mark) < 0.04 { snapped = mark }
                player.setSpeed(Float(snapped))
            }), in: 0.5...2)
            HStack {
                ForEach([0.75, 1.0, 1.25, 1.5], id: \.self) { mark in
                    Button(String(format: "%gx", mark)) { player.setSpeed(Float(mark)) }
                        .font(.octoCaption)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                }
            }
            Toggle(isOn: Binding(get: { player.keepsPitch }, set: { player.setKeepsPitch($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep pitch").font(.octoBodySmall)
                    Text(player.keepsPitch ? "Voices sound as usual at any speed." : "Pitch rises and falls with the speed, like a record.")
                        .font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
            }
            .tint(OctoColor.accent)
        }
    }

    private func grid(_ items: [(Int, String)], pick: @escaping (Int) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
            ForEach(items, id: \.0) { item in
                Button(item.1) { pick(item.0) }
                    .font(.octoBodySmall)
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.glass)
            }
        }
    }

    private func words(_ sleep: Player.SleepTimer) -> String {
        switch sleep {
        case .at(let date):
            let left = max(0, Int(date.timeIntervalSinceNow))
            return String(format: "%d:%02d", left / 60, left % 60)
        case .afterSongs(1): return "At the end of this song"
        case .afterSongs(let count): return "After \(count) songs"
        }
    }
}
