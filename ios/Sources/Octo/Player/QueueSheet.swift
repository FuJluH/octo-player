import OctoKit
import SwiftUI
import UIKit

/// One song in the queue, by the key it keeps while it stays there (the same song twice is two
/// entries), with where it came from.
struct QueueEntry: Identifiable, Equatable {
    let id: String
    let position: Int
    let song: Song
    let source: QueueSource

    /// The player's songs at these places, in the order given.
    @MainActor
    static func of(_ slots: [QueueSlot], _ player: Player) -> [QueueEntry] {
        slots.compactMap { slot in
            guard player.queue.indices.contains(slot.index) else { return nil }
            let source = player.items.indices.contains(slot.index) ? player.items[slot.index].source : QueueSource.none
            return QueueEntry(id: slot.key, position: slot.index, song: player.queue[slot.index], source: source)
        }
    }
}

/// Where an entry stands: already played, playing now, or still to come.
enum QueuePlace { case played, now, coming }

private let queueRowHeight: CGFloat = 56
private var comingFill: Color { OctoColor.background.mix(with: OctoColor.accent, by: 0.05) }
private var nowFill: Color { Color(hex: 0x1A1A1B).mix(with: OctoColor.accent, by: 0.12) }

/// Up next, in a sheet: the songs already played, the song on now in its own card, and the songs
/// to come in the order they play. A song to come can be dragged by its handle to another place
/// (not while shuffle is on) or swiped left to take it out; a long press on any song opens its
/// context menu.
struct QueueSheet: View {
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(\.dataServices) private var data
    @State private var removed: Set<String> = []
    @State private var drag: QueueDrag?
    @State private var saving = false
    @State private var ticks = 0
    @State private var position = ScrollPosition(edge: .top)
    @State private var scrollOffset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0
    @State private var viewport: CGRect = .zero

    var body: some View {
        let played = QueueEntry.of(player.playedSlots, player).filter { !removed.contains($0.id) }
        let upcoming = QueueEntry.of(player.upNextSlots, player).filter { !removed.contains($0.id) }
        let now = upcoming.first
        let coming = drawn(Array(upcoming.dropFirst()))
        let runs = sourceRuns(coming) { $0.source }
        // A single unnamed list needs no heading under "Up next".
        let headed = runs.count > 1 || runs.first.map { $0.source != QueueSource.none } ?? false
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
                tools(reader, now: now, hasPlayed: !played.isEmpty, hasOthers: !played.isEmpty || !coming.isEmpty)
                QueueScroll(position: $position, onGeometry: scrolled) {
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
                        ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                            if headed {
                                Text(queueSourceTitle(run.source))
                                    .font(.octoCaption)
                                    .foregroundStyle(OctoColor.textMuted)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 12)
                                    .padding(.bottom, 4)
                            }
                            ForEach(run.items) { entry in
                                comingRow(entry, offset: coming.firstIndex(of: entry) ?? 0, count: coming.count)
                            }
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewport = $0 }
            }
            .padding(.top, 24)
            .frame(maxHeight: .infinity, alignment: .top)
            .onAppear {
                guard let now else { return }
                DispatchQueue.main.async { reader.scrollTo(now.id, anchor: .top) }
            }
        }
        .sensoryFeedback(.selection, trigger: ticks)
        .background {
            // While a row is dragged near the list's top or bottom, the list keeps scrolling, finger
            // moving or not.
            if drag != nil {
                TimelineView(.animation) { frame in
                    Color.clear.onChange(of: frame.date) { last, now in edgeScroll(now.timeIntervalSince(last)) }
                }
            }
        }
        .onChange(of: player.upNextSlots) { _, _ in removed = [] }
        .onChange(of: player.playedSlots) { _, _ in removed = [] }
        .opensWhenAsked("save_playlist") { if !player.upNextSlots.isEmpty { saving = true } }
    }

    // MARK: Heading and tools

    /// The listener's own songs still to come, "N songs · length", and how many Autoplay added.
    private func summary(_ coming: [QueueEntry]) -> String {
        let own = coming.filter { $0.source != .autoplay }
        let seconds = own.reduce(0) { $0 + $1.song.duration }
        let added = coming.count - own.count
        return "\(songsCount(own.count)) · \(asLength(seconds))" + (added > 0 ? " · \(added) from Autoplay" : "")
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
                    .namePopover(isPresented: $saving, title: "New playlist", placeholder: "Playlist name", action: "Create") { name in
                        save(name)
                    }
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
            .contentShape(.contextMenuPreview, Rectangle())
            .contentShape(Rectangle())
            .onTapGesture { player.jump(toKey: entry.id) }
            .contextMenu { QueueRowMenu(entry: entry, remove: remove) }
            .accessibilityAction(named: "Play") { player.jump(toKey: entry.id) }
            .id(entry.id)
    }

    private func nowRow(_ entry: QueueEntry) -> some View {
        QueueSongRow(song: entry.song)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(nowFill))
            .octoGlass(RoundedRectangle(cornerRadius: 12, style: .continuous), film: .clear)
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contextMenu { QueueRowMenu(entry: entry, remove: remove) }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .id(entry.id)
    }

    private func comingRow(_ entry: QueueEntry, offset: Int, count: Int) -> some View {
        let moving = drag?.key == entry.id
        return SwipeAway(enabled: drag == nil, onRemove: { remove(entry) }) {
            QueueSongRow(song: entry.song) {
                if entry.source == .autoplay {
                    Text("Autoplay").font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                }
                if !player.shuffled {
                    ReorderHandle()
                        .gesture(reorder(entry, offset: offset, count: count))
                }
            }
            .padding(.horizontal, 20)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(comingFill))
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { player.jump(toKey: entry.id) }
            .contextMenu { QueueRowMenu(entry: entry, remove: remove) }
        }
        .elevation3Shape(moving)
        .offset(y: moving ? (drag?.lift ?? 0) : 0)
        .zIndex(moving ? 1 : 0)
        .accessibilityAction(named: "Play") { player.jump(toKey: entry.id) }
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
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if drag == nil {
                    let from = player.upNextSlots.dropFirst().firstIndex { $0.key == entry.id }.map { $0 - 1 } ?? offset
                    drag = QueueDrag(key: entry.id, from: from, count: count, target: from, lift: 0, startOffset: scrollOffset,
                                     fingerY: value.location.y, travel: 0)
                }
                guard var moving = drag else { return }
                moving.fingerY = value.location.y
                moving.travel = value.translation.height
                place(moving)
            }
            .onEnded { _ in
                guard let moving = drag else { return }
                drag = nil
                guard moving.target != moving.from else { return }
                player.move(from: IndexSet(integer: moving.from), to: moving.target > moving.from ? moving.target + 1 : moving.target)
            }
    }

    /// Where the dragged row would land: the finger's travel plus how far the list has scrolled
    /// under it, in whole rows. Each new place ticks, and the rows around it move aside.
    private func place(_ given: QueueDrag) {
        var moving = given
        let travelled = moving.travel + (scrollOffset - moving.startOffset)
        let target = min(max(moving.from + Int((travelled / queueRowHeight).rounded()), 0), max(moving.count - 1, 0))
        moving.lift = travelled - CGFloat(target - moving.from) * queueRowHeight
        if target != moving.target {
            moving.target = target
            ticks += 1
            withAnimation(.octoSpring(1, 400)) { drag = moving }
        } else {
            drag = moving
        }
    }

    /// The list's scroll, as it stands.
    private func scrolled(_ geometry: ScrollGeometry) {
        scrollOffset = geometry.contentOffset.y + geometry.contentInsets.top
        maxOffset = max(0, geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
                        - geometry.containerSize.height)
    }

    /// One frame of scrolling while the dragged row is within 48 points of the list's top or
    /// bottom: up to five times half the list's height a second at the very edge, slowing to
    /// nothing 48 points in.
    private func edgeScroll(_ seconds: TimeInterval) {
        guard let moving = drag, viewport.height > 0, seconds > 0, seconds < 0.25 else { return }
        let fromTop = max(moving.fingerY - viewport.minY, 0)
        let fromBottom = max(viewport.maxY - moving.fingerY, 0)
        let speed: CGFloat
        if fromTop < Self.edge {
            speed = -edgeSpeed(fromTop)
        } else if fromBottom < Self.edge {
            speed = edgeSpeed(fromBottom)
        } else {
            return
        }
        let next = min(max(scrollOffset + speed * CGFloat(seconds), 0), maxOffset)
        guard abs(next - scrollOffset) > 0.01 else { return }
        scrollOffset = next
        position.scrollTo(y: next)
        place(moving)
    }

    private static let edge: CGFloat = 48

    private func edgeSpeed(_ distance: CGFloat) -> CGFloat {
        let share = 1 - min(max((distance + Self.edge) / (2 * Self.edge), 0), 1)
        return share * 10 * viewport.height * 0.5
    }

    // MARK: Edits

    /// Takes the song out by its key: it leaves the list at once, then the queue.
    private func remove(_ entry: QueueEntry) {
        removed.insert(entry.id)
        guard let undo = player.removeEntry(entry.id) else {
            removed.remove(entry.id)
            return
        }
        router.undoable("Removed from the queue") { [player] in _ = player.undo(undo) }
    }

    /// Everything but the song on now goes.
    private func clear() {
        guard let undo = player.clearUpcoming() else { return }
        router.undoable("Queue cleared") { [player] in _ = player.undo(undo) }
    }

    private func removePlayed() {
        guard let undo = player.removePlayed() else { return }
        router.undoable("Played songs removed") { [player] in _ = player.undo(undo) }
    }

    /// A new playlist of the queue in play order (played, on now, to come), leaving out what
    /// Autoplay added, stations and songs not in the library.
    private func save(_ name: String) {
        saving = false
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let ids = (player.playedSlots + player.upNextSlots).compactMap { slot -> String? in
            guard player.items.indices.contains(slot.index) else { return nil }
            let item = player.items[slot.index]
            guard item.source != .autoplay, !item.isFind, !item.trackId.hasPrefix("radio:"), !item.trackId.hasPrefix("file:")
            else { return nil }
            return item.trackId
        }
        guard let data else { return }
        data.playlists.create(trimmed, trackIds: ids)
        router.show("Saved as \(trimmed)")
    }
}

/// A row being dragged: which, from where among how many, where it would land, how far it sits
/// from that place under the finger, and the list's scroll and the finger when it started.
private struct QueueDrag: Equatable {
    let key: String
    let from: Int
    let count: Int
    var target: Int
    var lift: CGFloat
    let startOffset: CGFloat
    var fingerY: CGFloat
    var travel: CGFloat
}

/// The queue's list: as tall as its rows, or less when there is less room, then it scrolls. Its
/// scroll can be moved from code and is reported as it changes.
private struct QueueScroll<Content: View>: View {
    @Binding var position: ScrollPosition
    let onGeometry: (ScrollGeometry) -> Void
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        RowsHeight(height: height) {
            ScrollView(.vertical) {
                content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, geometry in onGeometry(geometry) }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }
}

/// Takes its rows' height, or less when less is offered.
private struct RowsHeight: Layout {
    let height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.first?.sizeThatFits(.unspecified).width ?? 0
        let ideal = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        let natural = max(ideal, height)
        return CGSize(width: width, height: min(natural, proposal.height ?? natural))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// A song in the queue: its cover (marked when it is not in the library), title and artist, and
/// what goes at its end.
struct QueueSongRow<Trailing: View>: View {
    let song: Song
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if isRadio(song.id) {
                // A station shows its logo, or the tile Octo draws for it.
                LiveCover(logo: radioDetailsOf(song.id).logo, coverArt: song.coverArt, name: song.title, size: 44, radius: 6)
            } else {
                BadgedCover(id: song.coverArt, size: 44, radius: 6, external: song.isExternal)
            }
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

/// The context menu for one song in the queue: what can be done with it where it stands. The
/// row itself, lifted above the menu, shows which song it is.
private struct QueueRowMenu: View {
    let entry: QueueEntry
    let remove: (QueueEntry) -> Void
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router

    var body: some View {
        let place = place
        Section {
            if place != .now {
                Button("Play next", systemImage: OctoIcon.playNext.symbol) { playNext() }
            }
            if place != .played {
                Button("Stop after this song", systemImage: OctoIcon.sleepTimer.symbol) { stopAfter(place) }
            }
        }
        if place != .now {
            Section {
                Button("Remove from queue", systemImage: OctoIcon.delete.symbol) { remove(entry) }
            }
        }
    }

    private var place: QueuePlace {
        if player.playedSlots.contains(where: { $0.key == entry.id }) { return .played }
        return player.upNextSlots.first?.key == entry.id ? .now : .coming
    }

    /// The same entry, moved to right after the song on now.
    private func playNext() {
        player.playEntryNext(entry.id)
    }

    private func stopAfter(_ place: QueuePlace) {
        if place == .now {
            player.sleepAtEndOfSong()
        } else {
            player.sleepAfter(key: entry.id, title: entry.song.title)
        }
        router.undoable("Stops after \(entry.song.title)") { [player] in player.cancelSleep() }
    }
}
