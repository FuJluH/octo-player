import Observation
import OctoKit
import SwiftUI

/// A song in a list that can be picked, by the key it is picked by: its id, or its row on a
/// playlist page where a song can be there twice.
struct Pickable: Equatable {
    var key: String
    var track: LibraryTrack
}

/// One list's picks. The page that shows the list keeps it; the selection bar acts on it.
@MainActor
@Observable
final class SongSelection {
    private(set) var picks = Picks()
    /// The list as shown, for acting on the picks in its own order.
    @ObservationIgnored var list: [Pickable] = []
    /// Takes picked rows off the page's playlist, on a playlist page.
    @ObservationIgnored var remove: (([Pickable]) -> Void)?

    var active: Bool { picks.active }
    var count: Int { picks.keys.count }

    func isPicked(_ key: String) -> Bool { picks.keys.contains(key) }
    func start(_ key: String) { picks = picks.start(key) }
    func toggle(_ key: String) { picks = picks.toggle(key) }
    func keepOnly(_ present: Set<String>) { picks = picks.keepOnly(present) }
    func clear() { picks = Picks() }

    /// The picked songs in the list's own order.
    func picked() -> [Pickable] { picks.inOrder(list, key: \.key) }
}

/// The lists that can select right now; only the one on screen is ever selecting, since
/// selecting starts from a row.
@MainActor
@Observable
final class SelectionBoard {
    private var lists: [ObjectIdentifier: SongSelection] = [:]

    var selecting: SongSelection? { lists.values.first { $0.active } }

    func attach(_ selection: SongSelection) { lists[ObjectIdentifier(selection)] = selection }

    func detach(_ selection: SongSelection) {
        selection.clear()
        lists[ObjectIdentifier(selection)] = nil
    }
}

extension View {
    /// Lets the songs in this list be picked: rows read the selection, and the selection bar
    /// shows while any are picked. Leaving the list clears it; songs gone from the list are
    /// dropped from the picks; going back while picking clears the picks instead.
    func selectable(_ selection: SongSelection, songs: [Pickable], remove: (([Pickable]) -> Void)? = nil) -> some View {
        modifier(Selectable(selection: selection, songs: songs, remove: remove))
    }

    /// The selection bar over the floating bar while a list is picking songs.
    func selectionBarOver() -> some View { modifier(SelectionBarOver()) }
}

private struct Selectable: ViewModifier {
    let selection: SongSelection
    let songs: [Pickable]
    let remove: (([Pickable]) -> Void)?
    @Environment(SelectionBoard.self) private var board

    func body(content: Content) -> some View {
        selection.list = songs
        selection.remove = remove
        return content
            .onAppear { board.attach(selection) }
            .onDisappear { board.detach(selection) }
            .onChange(of: songs.count) { _, _ in selection.keepOnly(Set(songs.map(\.key))) }
            .backAction(selection.active ? { selection.clear() } : nil)
    }
}

private struct SelectionBarOver: ViewModifier {
    @Environment(SelectionBoard.self) private var board
    @State private var shown: SongSelection?

    func body(content: Content) -> some View {
        let selecting = board.selecting
        content
            .opacity(selecting == nil ? 1 : 0)
            .allowsHitTesting(selecting == nil)
            .overlay(alignment: .bottom) {
                if let selection = selecting ?? shown, selecting != nil {
                    SelectionBar(selection: selection)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.22), value: selecting == nil)
            .onChange(of: selecting.map(ObjectIdentifier.init)) { _, _ in if let selecting { shown = selecting } }
    }
}

/// What can be done with the picked songs, in place of the floating bar.
struct SelectionBar: View {
    let selection: SongSelection
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        let picked = selection.picked().map(\.track)
        let library = picked.filter { !$0.isFound }
        let state = actions.state
        let allLiked = !library.isEmpty && library.allSatisfy { state.likedIds.contains($0.id) }
        let canDownload = state.kept.available && library.contains { !$0.onPhone && state.kept.status($0.id) == nil }
        let disk = state.fileActions?.canRemove == true && !picked.isEmpty && library.count == picked.count
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                barButton("xmark", "Stop selecting", enabled: true) { selection.clear() }
                Text(selection.count == 1 ? "1 selected" : "\(selection.count) selected")
                    .font(.octoBodySmall)
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
                    .accessibilityAddTraits(.updatesFrequently)
                Spacer(minLength: 0)
                if disk {
                    barButton(MenuIcon.delete, deleteFromDiskWords, enabled: true) {
                        actions.deleteFromDisk(picked) { selection.clear() }
                    }
                }
            }
            HStack(spacing: 0) {
                barButton(MenuIcon.play, "Play", enabled: !picked.isEmpty) { done { actions.play(picked) } }
                barButton(MenuIcon.playNext, "Play next", enabled: !picked.isEmpty) { done { actions.playNext(picked) } }
                barButton(MenuIcon.addToQueue, "Add to queue", enabled: !picked.isEmpty) { done { actions.addToQueue(picked) } }
                Menu {
                    PlaylistPickerItems(tracks: library) { selection.clear() }
                } label: {
                    barIcon(MenuIcon.addToPlaylist, enabled: !library.isEmpty)
                }
                .disabled(library.isEmpty)
                .accessibilityLabel("Add to playlist")
                .frame(maxWidth: .infinity)
                if state.kept.available {
                    barButton(MenuIcon.download, "Download", enabled: canDownload) {
                        done { state.kept.download(library.filter { !$0.onPhone }.map(\.id)) }
                    }
                }
                barButton(allLiked ? MenuIcon.liked : MenuIcon.like, allLiked ? "Remove from Liked songs" : "Add to Liked songs",
                          enabled: !library.isEmpty) {
                    done {
                        if allLiked {
                            actions.setLiked(library, false)
                        } else {
                            actions.setLiked(library.filter { !state.likedIds.contains($0.id) }, true)
                        }
                    }
                }
                if let remove = selection.remove {
                    barButton(MenuIcon.removeFromPlaylist, "Remove from this playlist", enabled: !picked.isEmpty) {
                        let rows = selection.picked()
                        done { remove(rows) }
                    }
                }
            }
        }
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    /// Every action ends the selecting once done.
    private func done(_ run: () -> Void) {
        run()
        selection.clear()
    }

    private func barIcon(_ icon: String, enabled: Bool) -> some View {
        Image(systemName: icon)
            .font(.system(size: 19))
            .foregroundStyle(enabled ? Color.white : OctoColor.textMuted.opacity(0.35))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Rectangle())
    }

    private func barButton(_ icon: String, _ label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { barIcon(icon, enabled: enabled) }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(label)
            .frame(maxWidth: label == "Stop selecting" || label == deleteFromDiskWords ? 44 : .infinity)
    }
}
