import OctoKit
import SwiftUI
import UIKit

/// One song in the queue, with a key it keeps while it stays there: the same song twice is two
/// entries.
struct QueueEntry: Identifiable, Equatable {
    let id: String
    let position: Int
    let song: Song

    /// The queue's songs as entries, each keyed by its song and which time that song comes up.
    static func of(_ queue: [Song]) -> [QueueEntry] {
        var seen: [String: Int] = [:]
        return queue.enumerated().map { position, song in
            let time = seen[song.id, default: 0]
            seen[song.id] = time + 1
            return QueueEntry(id: "\(song.id)#\(time)", position: position, song: song)
        }
    }
}

/// Where an entry stands: already played, playing now, or still to come.
enum QueuePlace { case played, now, coming }

private let queueRowHeight: CGFloat = 56
private let comingFill = OctoColor.background.mix(with: OctoColor.accent, by: 0.05)
private let nowFill = Color(hex: 0x1A1A1B).mix(with: OctoColor.accent, by: 0.12)

/// Up next: the songs already played, the song on now in its own card, and the songs to come in
/// the order they play. A song to come can be dragged by its handle to another place (not while
/// shuffle is on) or swiped left to take it out; a long press on any song offers more.
struct QueueSheet: View {
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var data
    @State private var removed: Set<String> = []
    @State private var drag: QueueDrag?
    @State private var menuEntry: QueueEntry?
    @State private var showsMenu = false
    @State private var saving = false
    @State private var ticks = 0

    var body: some View {
        let entries = QueueEntry.of(player.queue).filter { !removed.contains($0.id) }
        let index = entries.firstIndex { $0.position == player.index } ?? 0
        let played = Array(entries.prefix(index))
        let now = entries.indices.contains(index) ? entries[index] : nil
        let coming = drawn(Array(entries.dropFirst(index + 1)))
        ScrollViewReader { reader in
            VStack(alignment: .leading, spacing: 0) {
                Text("Up next")
                    .font(.octoSection)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
                Text(summary(coming))
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .padding(.horizontal, 20)
                tools(reader, now: now, hasPlayed: !played.isEmpty, hasOthers: entries.count > 1)
                HuggingScroll {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(played) { entry in
                            playedRow(entry)
                        }
                        if let now {
                            nowRow(now)
                        }
                        if player.shuffled && !coming.isEmpty {
                            Text("Turn off shuffle to reorder")
                                .font(.octoCaption)
                                .foregroundStyle(OctoColor.textMuted)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                        }
                        if let heading = heading, !coming.isEmpty {
                            Text(heading)
                                .font(.octoCaption)
                                .foregroundStyle(OctoColor.textMuted)
                                .padding(.horizontal, 20)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                        }
                        ForEach(Array(coming.enumerated()), id: \.element.id) { offset, entry in
                            comingRow(entry, offset: offset, count: coming.count)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .coordinateSpace(name: "queue")
                }
            }
            .onAppear {
                guard let now else { return }
                DispatchQueue.main.async { reader.scrollTo(now.id, anchor: .top) }
            }
        }
        .sensoryFeedback(.selection, trigger: ticks)
        .onChange(of: player.queue) { _, _ in removed = [] }
        .glassPopup(isPresented: $showsMenu, title: "Song in the queue") {
            if let menuEntry { QueueRowMenu(entry: menuEntry, dismiss: { showsMenu = false }, remove: remove) }
        }
        .glassPopup(isPresented: $saving, title: "Save as playlist") {
            PopupNameForm(title: "New playlist", placeholder: "Playlist name", action: "Create") { name in
                save(name)
            }
        }
    }

    // MARK: Heading and tools

    /// "N songs · length" still to come.
    private func summary(_ coming: [QueueEntry]) -> String {
        let seconds = coming.reduce(0) { $0 + $1.song.duration }
        return "\(songsCount(coming.count)) · \(asLength(seconds))"
    }

    /// A heading over the songs to come, only for a list with a name.
    private var heading: String? {
        guard let seed = player.radioSeed else { return nil }
        return PlayerRule.queueSourceTitle(.played("\(seed.title) radio"))
    }

    private func tools(_ reader: ScrollViewProxy, now: QueueEntry?, hasPlayed: Bool, hasOthers: Bool) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                tool("Now playing", enabled: now != nil) {
                    guard let now else { return }
                    withAnimation(.octoTween(fixed: 300)) { reader.scrollTo(now.id, anchor: .top) }
                }
                tool("Clear", enabled: hasOthers) { clear() }
                tool("Remove played", enabled: hasPlayed) { removePlayed() }
                tool("Save as playlist", enabled: now != nil) { saving = true }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func tool(_ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.octoLabel)
                .foregroundStyle(enabled ? OctoColor.accent : OctoColor.textMuted)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(ToolPress())
        .disabled(!enabled)
    }

    // MARK: Rows

    private func playedRow(_ entry: QueueEntry) -> some View {
        QueueSongRow(song: entry.song)
            .opacity(0.5)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onTapGesture { player.jump(to: entry.position) }
            .onLongPressGesture { openMenu(entry) }
            .accessibilityAction(named: "Play") { player.jump(to: entry.position) }
            .accessibilityAction(named: "Song options") { openMenu(entry) }
            .id(entry.id)
    }

    private func nowRow(_ entry: QueueEntry) -> some View {
        QueueSongRow(song: entry.song)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(nowFill))
            .octoGlass(RoundedRectangle(cornerRadius: 12, style: .continuous), film: .clear)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onLongPressGesture { openMenu(entry) }
            .accessibilityAction(named: "Song options") { openMenu(entry) }
            .id(entry.id)
    }

    private func comingRow(_ entry: QueueEntry, offset: Int, count: Int) -> some View {
        let moving = drag?.key == entry.id
        return SwipeAway(enabled: drag == nil, onRemove: { remove(entry) }) {
            QueueSongRow(song: entry.song) {
                if !player.shuffled {
                    ReorderHandle()
                        .gesture(reorder(entry, offset: offset, count: count))
                }
            }
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(comingFill))
            .contentShape(Rectangle())
            .onTapGesture { player.jump(to: entry.position) }
            .onLongPressGesture { openMenu(entry) }
        }
        .elevation3Shape(moving)
        .offset(y: moving ? (drag?.lift ?? 0) : 0)
        .zIndex(moving ? 1 : 0)
        .accessibilityAction(named: "Play") { player.jump(to: entry.position) }
        .accessibilityAction(named: "Song options") { openMenu(entry) }
        .accessibilityAction(named: "Remove") { remove(entry) }
        .id(entry.id)
    }

    // MARK: Moving

    /// The songs to come as drawn: the one being dragged in the place it would land.
    private func drawn(_ coming: [QueueEntry]) -> [QueueEntry] {
        guard let drag, let from = coming.firstIndex(where: { $0.id == drag.key }) else { return coming }
        var rows = coming
        let row = rows.remove(at: from)
        rows.insert(row, at: min(max(drag.target, 0), rows.count))
        return rows
    }

    /// Dragging starts from the handle at once. The other rows move aside as the dragged one
    /// passes them; the queue changes only on the drop.
    private func reorder(_ entry: QueueEntry, offset: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("queue"))
            .onChanged { value in
                if drag == nil {
                    let upcoming = QueueEntry.of(player.queue).filter { $0.position > player.index }
                    let from = upcoming.firstIndex { $0.id == entry.id } ?? offset
                    drag = QueueDrag(key: entry.id, from: from, target: from, lift: 0)
                }
                guard var moving = drag else { return }
                let steps = Int((value.translation.height / queueRowHeight).rounded())
                let target = min(max(moving.from + steps, 0), count - 1)
                if target != moving.target {
                    ticks += 1
                    withAnimation(.octoSpring(1, 400)) { moving.target = target }
                }
                moving.lift = value.translation.height - CGFloat(target - moving.from) * queueRowHeight
                drag = moving
            }
            .onEnded { _ in
                guard let moving = drag else { return }
                drag = nil
                guard moving.target != moving.from else { return }
                player.move(from: IndexSet(integer: moving.from), to: moving.target > moving.from ? moving.target + 1 : moving.target)
            }
    }

    // MARK: Edits

    private func openMenu(_ entry: QueueEntry) {
        menuEntry = entry
        showsMenu = true
    }

    /// Takes the song out by its key: it leaves the list at once, then the queue.
    private func remove(_ entry: QueueEntry) {
        guard let position = QueueEntry.of(player.queue).first(where: { $0.id == entry.id })?.position,
              position > player.index
        else { return }
        let before = player.snapshot
        removed.insert(entry.id)
        player.remove(at: IndexSet(integer: position - player.index - 1))
        let after = player.queue
        router.undoable("Removed from the queue") { [player] in
            if player.queue == after { player.restore(before) }
        }
    }

    private func clear() {
        guard player.queue.count > 1 else { return }
        let before = player.snapshot
        let hadPlayed = player.index > 0
        player.clearUpcoming()
        if hadPlayed { player.removePlayed() }
        let after = player.queue
        router.undoable("Queue cleared") { [player] in
            if player.queue == after { player.restore(before) }
        }
    }

    private func removePlayed() {
        guard player.index > 0 else { return }
        let before = player.snapshot
        player.removePlayed()
        let after = player.queue
        router.undoable("Played songs removed") { [player] in
            if player.queue == after { player.restore(before) }
        }
    }

    /// A new playlist of the whole queue in play order.
    private func save(_ name: String) {
        saving = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let songs = player.queue
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard let data else { return }
        Task {
            let library = data.library
            var ids: [String] = []
            var links: [String: String] = [:]
            if let server = library.serverInUse,
               let found = try? await library.store.libraryLinks(server, songs.map(\.id)) {
                for link in found { links[link.serverId] = link.trackId }
            }
            for song in songs where !song.isExternal {
                if let id = links[song.id] { ids.append(id) } else if await library.track(song.id) != nil { ids.append(song.id) }
            }
            data.playlists.create(trimmed, trackIds: ids)
            router.show("Saved as \(trimmed)")
        }
    }
}

/// A row being dragged: which, from where, where it would land, and how far it sits from that
/// place under the finger.
private struct QueueDrag: Equatable {
    let key: String
    let from: Int
    var target: Int
    var lift: CGFloat
}

/// A song in the queue: its cover (marked when it is not in the library), title and artist, and
/// what goes at its end.
struct QueueSongRow<Trailing: View>: View {
    let song: Song
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            BadgedCover(id: song.coverArt, size: 44, radius: 6, external: song.isExternal)
            VStack(alignment: .leading, spacing: 0) {
                SongTitleLine(song.title, explicit: song.isExplicit, font: .octo(14, .regular), color: .white)
                Text(song.byline)
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(height: queueRowHeight)
    }
}

extension QueueSongRow where Trailing == EmptyView {
    init(song: Song) { self.init(song: song, trailing: { EmptyView() }) }
}

/// The handle a song to come is dragged by: two short lines.
private struct ReorderHandle: View {
    var body: some View {
        VStack(spacing: 6) {
            Capsule().fill(OctoColor.textMuted).frame(width: 18, height: 2)
            Capsule().fill(OctoColor.textMuted).frame(width: 18, height: 2)
        }
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
        .accessibilityLabel("Reorder")
    }
}

/// A row that can be swiped left to take it out: a red wash with a bin shows behind it. Past
/// 56 points, or a flick, and it goes.
private struct SwipeAway<Content: View>: View {
    let enabled: Bool
    let onRemove: () -> Void
    @ViewBuilder var content: Content
    @State private var offset: CGFloat = 0
    @State private var axis: DragAxis = .undecided

    var body: some View {
        content
            .offset(x: offset)
            .background(alignment: .trailing) {
                if offset < 0 {
                    ZStack(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xEF4444, opacity: 0.25))
                        IconView(.delete, size: 22, color: .white)
                            .padding(.trailing, 24)
                            .accessibilityLabel("Remove")
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard enabled else { return }
                        if axis == .undecided { axis = dragAxis(value.translation.width, value.translation.height, slop: 12) }
                        guard axis == .horizontal else { return }
                        offset = min(0, value.translation.width)
                    }
                    .onEnded { value in
                        let taken = axis
                        axis = .undecided
                        guard taken == .horizontal, enabled else { return }
                        if value.translation.width <= -56 || value.velocity.width <= -125 {
                            withAnimation(.octoTween(fixed: 160)) { offset = -600 }
                            onRemove()
                        } else {
                            withAnimation(.octoSpring(0.8, 400)) { offset = 0 }
                        }
                    }
            )
    }
}

/// A tool under the heading: no shape of its own, a soft wash under the finger.
private struct ToolPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed { Capsule().fill(OctoColor.menuPress) }
            }
    }
}

extension View {
    /// The raised card shadow, while `on`.
    @ViewBuilder
    fileprivate func elevation3Shape(_ on: Bool) -> some View {
        if on { elevation3() } else { self }
    }
}

/// The menu for one song in the queue: what can be done with it where it stands.
private struct QueueRowMenu: View {
    let entry: QueueEntry
    let dismiss: () -> Void
    let remove: (QueueEntry) -> Void
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        let place = place
        GlassMenuPage {
            GlassMenuHeader(title: entry.song.title, subtitle: entry.song.byline) {
                BadgedCover(id: entry.song.coverArt, size: 40, radius: 6, external: entry.song.isExternal)
            }
            GlassMenuSeparator()
        } content: {
            if place != .now {
                GlassMenuAction(.playNext, "Play next") {
                    playNext()
                    dismiss()
                }
            }
            if place != .played {
                GlassMenuAction(.sleepTimer, "Stop after this song") {
                    stopAfter(place)
                    dismiss()
                }
            }
            if place != .now {
                GlassMenuSeparator()
                GlassMenuAction(.delete, "Remove from queue") {
                    remove(entry)
                    dismiss()
                }
            }
        }
    }

    private var position: Int? { QueueEntry.of(player.queue).first { $0.id == entry.id }?.position }

    private var place: QueuePlace {
        guard let position else { return .coming }
        return position < player.index ? .played : position == player.index ? .now : .coming
    }

    /// The same entry, moved to right after the song on now.
    private func playNext() {
        guard let position, position != player.index else { return }
        var songs = player.queue
        let song = songs.remove(at: position)
        let current = position < player.index ? player.index - 1 : player.index
        songs.insert(song, at: current + 1)
        player.restore(Player.QueueSnapshot(songs: songs, index: current))
    }

    private func stopAfter(_ place: QueuePlace) {
        guard let position else { return }
        let sleep = PlayerSleep.shared
        if place == .now {
            sleep.stopAfter(songs: 1, player)
        } else {
            sleep.stopAfter(ahead: position - player.index, title: entry.song.title, player)
        }
        router.undoable("Stops after \(entry.song.title)") { [player] in sleep.cancel(player) }
    }
}
