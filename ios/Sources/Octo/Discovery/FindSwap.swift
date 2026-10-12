import OctoKit
import SwiftUI

/// A row for a song found online that turns into the library song it became, in the same place
/// and at the same height. Where the row has the add button, the check has its moment first; the
/// turn fades only for a row that showed the find, and not with reduced motion. Works for a song
/// as the server lists it and for a library row of a find.
struct FindSwap<Item, Content: View>: View {
    let find: Item
    /// The find's id on the server, which the downloads know it by.
    let serverId: String
    let offersAdd: Bool
    /// The library song a find became, by its library id, as last read; nil until read.
    let libraryItem: @MainActor (Downloads, String) -> Item?
    let key: (Item) -> String
    @ViewBuilder let content: (Item) -> Content
    @Environment(Downloads.self) private var downloads
    @Environment(\.octoReduceMotion) private var calm
    @State private var face: FindFace?
    @State private var sawFind = false

    var body: some View {
        let libraryId = downloads.adoptions?[serverId]
        let known: Bool? = downloads.adoptions.map { _ in libraryId != nil }
        let next = nextFindFace(face, adopted: known, offersAdd: offersAdd)
        let library = next == .library ? libraryId.flatMap { libraryItem(downloads, $0) } : nil
        let shown = library ?? find
        let fade = swapFadeMs(sawFind: sawFind || next == .find, calm: calm)
        ZStack {
            content(shown)
                .id(key(shown))
                .transition(.opacity)
        }
        .animation(fade > 0 ? .easeInOut(duration: Double(fade) / 1_000) : nil, value: key(shown))
        .onChange(of: next, initial: true) { _, value in
            face = value
            if value == .find { sawFind = true }
            // Looked up from the check on, so it is ready when the row turns.
            if value == .check || value == .library, let libraryId { downloads.lookUpLibrarySong(libraryId) }
        }
        .task(id: next == .check) {
            guard next == .check else { return }
            try? await Task.sleep(for: .milliseconds(checkHoldMs))
            guard !Task.isCancelled else { return }
            face = afterCheck(face)
        }
    }
}

extension FindSwap where Item == Song {
    /// A find as the server lists it.
    init(find: Song, offersAdd: Bool, @ViewBuilder content: @escaping (Song) -> Content) {
        self.init(find: find, serverId: find.id, offersAdd: offersAdd, libraryItem: { $0.librarySong($1) }, key: \.id, content: content)
    }
}

extension FindSwap where Item == LibraryTrack {
    /// A find as a library row.
    init(track: LibraryTrack, offersAdd: Bool, @ViewBuilder content: @escaping (LibraryTrack) -> Content) {
        self.init(find: track, serverId: track.nativeId, offersAdd: offersAdd, libraryItem: { $0.libraryTrack($1) }, key: \.id,
                  content: content)
    }
}

/// The mark just after a song's number in a list mixing library songs with songs found online: a
/// lit check for a song in the library, the add button for one that is not.
struct OwnershipMark: View {
    let song: Song
    @Environment(Downloads.self) private var downloads

    var body: some View {
        ZStack {
            if isOutsideLibrary(song, adopted: downloads.adopted) {
                AddToLibraryButton(song: song, size: 32, iconSize: 20)
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OctoColor.accent)
                    .frame(width: 20, height: 20)
                    .accessibilityLabel("In your library")
            }
        }
        .frame(width: 32)
    }
}
