import OctoKit
import SwiftUI

/// A row for a song found online that turns into the library song it became, in the same place
/// and at the same height. Where the row has the add button, the check has its moment first; the
/// turn fades only for a row that showed the find, and not with reduced motion.
struct FindSwap<Content: View>: View {
    let find: Song
    let offersAdd: Bool
    @ViewBuilder let content: (Song) -> Content
    @Environment(Downloads.self) private var downloads
    @Environment(\.accessibilityReduceMotion) private var systemCalm
    @AppStorage(reduceMotionKey) private var appCalm = false
    @State private var face: FindFace?
    @State private var sawFind = false

    var body: some View {
        let libraryId = downloads.adoptions?[find.id]
        let known: Bool? = downloads.adoptions.map { _ in libraryId != nil }
        let next = nextFindFace(face, adopted: known, offersAdd: offersAdd)
        let library = next == .library ? libraryId.flatMap { downloads.librarySong($0) } : nil
        let shown = library ?? find
        let fade = swapFadeMs(sawFind: sawFind || next == .find, calm: appCalm || systemCalm)
        ZStack {
            content(shown)
                .id(shown.id)
                .transition(.opacity)
        }
        .animation(fade > 0 ? .easeInOut(duration: Double(fade) / 1_000) : nil, value: shown.id)
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
