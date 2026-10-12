import Observation
import OctoKit
import SwiftUI

/// A list's picked songs, kept by the page that shows the list. Nothing picked means the list is
/// not selecting; picking starts with one song, a tap toggles, and taking the last one off ends
/// it.
@MainActor
@Observable
final class SongSelection {
    private(set) var picks = Picks()

    var active: Bool { picks.active }
    var count: Int { picks.keys.count }

    func isPicked(_ key: String) -> Bool { picks.keys.contains(key) }
    func start(_ key: String) { picks = picks.start(key) }
    func toggle(_ key: String) { picks = picks.toggle(key) }
    func keepOnly(_ present: Set<String>) { picks = picks.keepOnly(present) }
    func clear() { picks = Picks() }
}

/// A list selecting songs, as the selection bar sees it: the picked songs, and a way to take
/// them off the page's playlist when it is one.
@MainActor
final class SelectionTarget: Identifiable {
    let id = UUID()
    let selection: SongSelection
    var list: [Pickable] = []
    var remove: (([Pickable]) -> Void)?

    init(selection: SongSelection) { self.selection = selection }

    /// The picked songs in the list's own order.
    func picked() -> [Pickable] { selection.picks.inOrder(list) }
}

/// The lists that can select right now. Only the one on screen is ever selecting, since
/// selecting starts from a row.
@MainActor
@Observable
final class SelectionBarState {
    private(set) var targets: [SelectionTarget] = []

    var selecting: SelectionTarget? { targets.first { $0.selection.active } }

    func attach(_ target: SelectionTarget) { targets.append(target) }
    func detach(_ target: SelectionTarget) { targets.removeAll { $0 === target } }
}

/// What the selection bar does that other parts of the app give it: the playlist picker,
/// downloading to the phone, the phone's files, and deleting from the server's disk. A part not
/// given leaves its button out, or dims it.
@MainActor
@Observable
final class SelectionActions {
    /// Opens the playlist picker for these library songs.
    var addToPlaylist: (([Song]) -> Void)?
    /// Downloads these library songs to the phone.
    var download: (([Song]) -> Void)?
    /// Whether a library song has a file on the phone.
    var onPhone: (Song) -> Bool = { _ in false }
    /// Shares the songs' files on the phone.
    var shareFiles: (([Song]) -> Void)?
    /// Deletes the songs' files from the phone.
    var deleteFromPhone: (([Song]) -> Void)?
    /// The songs of these the server would let this user delete from its disk.
    var deletableFromDisk: (([Song]) async -> [String])?
    /// Asks before deleting these songs from the server's disk.
    var askDeleteFromDisk: (([Song]) -> Void)?
    /// Likes or unlikes these library songs, and says whether a song is liked. When not given,
    /// the server is asked directly and the song's own star is read.
    var setLiked: (([Song], Bool) -> Void)?
    var isLiked: ((Song) -> Bool)?
}

extension EnvironmentValues {
    /// The selection of the list a row is in, or nil in a list that cannot select.
    @Entry var songSelection: SongSelection? = nil
}

extension View {
    /// Lets the songs inside be picked: rows read `songSelection`, and the selection bar appears
    /// while any are picked. `songs` is the list as shown; `onRemove` takes picked songs off the
    /// page's playlist. Leaving the page clears its picks.
    func selectableSongs(_ songs: [Pickable], onRemove: (([Pickable]) -> Void)? = nil) -> some View {
        modifier(SelectableSongs(songs: songs, onRemove: onRemove))
    }
}

private struct SelectableSongs: ViewModifier {
    let songs: [Pickable]
    let onRemove: (([Pickable]) -> Void)?
    @Environment(SelectionBarState.self) private var bar
    @State private var selection = SongSelection()
    @State private var target: SelectionTarget?

    func body(content: Content) -> some View {
        content
            .environment(\.songSelection, selection)
            // Going back while picking ends the picking and stays on the page.
            .backAction(selection.active ? { selection.clear() } : nil)
            .onAppear {
                let made = target ?? SelectionTarget(selection: selection)
                made.list = songs
                made.remove = onRemove
                target = made
                bar.attach(made)
            }
            .onDisappear {
                if let target { bar.detach(target) }
                selection.clear()
            }
            .onChange(of: songs.map(\.key)) { _, keys in
                target?.list = songs
                target?.remove = onRemove
                selection.keepOnly(Set(keys))
            }
    }
}

/// The bar that acts on picked songs, in place of the bottom bar while a list is picking. Back,
/// the close button, or taking the last song off ends the picking; so does any action. It rises
/// in with a fade from half its height below, and leaves the same way, still showing the last
/// picks.
struct SelectionBarHost: View {
    @Environment(SelectionBarState.self) private var bar
    @State private var last: SelectionTarget?

    var body: some View {
        let target = bar.selecting
        ZStack(alignment: .bottom) {
            Color.clear.allowsHitTesting(false)
            if target != nil, let shown = target ?? last {
                SelectionBar(target: shown)
                    .transition(.asymmetric(insertion: .modifier(active: RiseFade(shown: false), identity: RiseFade(shown: true)),
                                            removal: .modifier(active: RiseFade(shown: false), identity: RiseFade(shown: true))))
            }
        }
        .animation(.octo(OctoSprings.move), value: target?.id)
        .onChange(of: target?.id) { if let target { last = target } }
        .ignoresSafeArea(.keyboard)
    }
}

/// Faded and half its height lower, or in place.
private struct RiseFade: ViewModifier {
    let shown: Bool
    @State private var height: CGFloat = 120

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : height / 2)
    }
}

private struct SelectionBar: View {
    let target: SelectionTarget
    @Environment(Player.self) private var player
    @Environment(Session.self) private var session
    @Environment(SelectionActions.self) private var actions
    @State private var onDisk: [String] = []

    var body: some View {
        let picked = target.picked()
        let songs = picked.map(\.song)
        let library = songs.filter { !$0.isExternal }
        let allLiked = !library.isEmpty && library.allSatisfy { actions.isLiked?($0) ?? $0.isStarred }
        let canDownload = actions.download != nil && library.contains { !actions.onPhone($0) }
        let allOnPhone = !picked.isEmpty && songs.allSatisfy { !$0.isExternal && actions.onPhone($0) }
        let allOnDisk = !library.isEmpty && library.count == songs.count && onDisk.count == library.count
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                BarButton(icon: .close, label: "Stop selecting") { target.selection.clear() }
                    .frame(width: 44)
                Text(selectedWords(picked.count))
                    .font(.octoBodySmall)
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
                if allOnPhone, let share = actions.shareFiles {
                    BarButton(icon: .shareFile, label: picked.count == 1 ? "Share file" : "Share files") { act { share(library) } }
                        .frame(width: 44)
                }
                if allOnPhone && allOnDisk {
                    Menu {
                        Section("Delete") {
                            Button("Delete from phone", systemImage: "iphone", role: .destructive) {
                                act { actions.deleteFromPhone?(library) }
                            }
                            Button("Delete from disk", systemImage: "externaldrive", role: .destructive) {
                                act { actions.askDeleteFromDisk?(library) }
                            }
                        }
                    } label: {
                        IconView(.delete, size: 22, color: .white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .menuOrder(.fixed)
                    .frame(width: 44)
                    .accessibilityLabel("Delete")
                } else if allOnPhone, let delete = actions.deleteFromPhone {
                    BarButton(icon: .delete, label: "Delete from phone") { act { delete(library) } }
                        .frame(width: 44)
                } else if allOnDisk, let ask = actions.askDeleteFromDisk {
                    BarButton(icon: .delete, label: "Delete from disk") { act { ask(library) } }
                        .frame(width: 44)
                }
            }
            HStack(spacing: 0) {
                BarButton(icon: .play, label: "Play") { act { player.play(songs, from: 0) } }
                BarButton(icon: .playNext, label: "Play next") { act { player.playNext(songs) } }
                BarButton(icon: .addToQueue, label: "Add to queue") { act { player.append(songs) } }
                BarButton(icon: .addToPlaylist, label: "Add to playlist", enabled: !library.isEmpty && actions.addToPlaylist != nil) {
                    act { actions.addToPlaylist?(library) }
                }
                BarButton(icon: .download, label: "Download", enabled: canDownload) {
                    act { actions.download?(library.filter { !actions.onPhone($0) }) }
                }
                BarButton(icon: allLiked ? .liked : .like, label: allLiked ? "Remove from Liked songs" : "Add to Liked songs",
                          enabled: !library.isEmpty) {
                    act { setLiked(library, like: !allLiked) }
                }
                if let remove = target.remove {
                    BarButton(icon: .removeFromPlaylist, label: "Remove from this playlist") { act { remove(picked) } }
                }
            }
        }
        .padding(6)
        .frame(maxWidth: ShellMeasures.maxWidth)
        .floatingGlass(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, ShellMeasures.sideMargin)
        .padding(.bottom, ShellMeasures.barBottomGap)
        .task(id: library.map(\.id)) {
            onDisk = await actions.deletableFromDisk?(library) ?? []
        }
    }

    /// Every action ends the picking once done.
    private func act(_ action: () -> Void) {
        action()
        target.selection.clear()
    }

    /// Likes every song, or takes the like off every one, touching only those that differ.
    private func setLiked(_ songs: [Song], like: Bool) {
        if let set = actions.setLiked {
            set(songs, like)
            return
        }
        guard let client = session.client else { return }
        let changing = songs.filter { $0.isStarred != like }
        Task {
            for song in changing {
                if like { try? await client.star(songId: song.id) } else { try? await client.unstar(songId: song.id) }
            }
        }
    }
}

/// One of the selection bar's buttons: an icon, named for screen readers. One that cannot act on
/// these songs is dimmed.
private struct BarButton: View {
    let icon: OctoIcon
    let label: String
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 22, color: enabled ? .white : OctoColor.textMuted.opacity(0.35))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(RectPress())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The platform's press highlight, kept to the button's rectangle.
private struct RectPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.white.opacity(configuration.isPressed ? 0.10 : 0))
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
