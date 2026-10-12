import OctoKit
import SwiftUI

/// Browsing by folder: the phone's music as its files sit, and the server's folders, live.
struct FoldersPage: View {
    @Environment(Library.self) private var library
    @Environment(LibraryState.self) private var state
    @Environment(LibraryActions.self) private var actions
    @Environment(Session.self) private var session
    @Environment(DeviceLibrary.self) private var device
    @Environment(\.dismiss) private var dismiss
    @State private var phone: Collapsed<LibraryTrack>?
    @State private var phoneRead = false
    /// Where the page is: nil at the start, else a source and the folders gone into.
    @State private var trail: [Step] = []
    @State private var serverLevels: [String: Level] = [:]
    @State private var gathering = false
    @State private var note: String?

    /// One step into the folders.
    enum Step: Hashable {
        case phone
        case server
        case phoneFolder(String)
        case serverFolder(id: String, name: String)
    }

    /// One server level, as read.
    struct Level {
        var folders: [ServerFolderRef] = []
        var songs: [LibraryTrack] = []
        var failure: String?
        var read = false
    }

    private var hasPhone: Bool { (phone?.root.songCount ?? 0) > 0 }
    private var hasServer: Bool { session.client != nil }

    /// The steps from the start: with both sources the page starts at "Folders"; with one, inside it.
    private var path: [Step] {
        if hasPhone && hasServer { return trail }
        if hasPhone { return [.phone] + trail.drop { $0 == .phone } }
        if hasServer { return [.server] + trail.drop { $0 == .server } }
        return []
    }

    var body: some View {
        ScrollViewReader { proxy in
            LibraryList {
                // Until the phone's first scan and the library are read, nothing is known yet.
                if !phoneRead || !device.scannedOnce {
                    LibrarySpinner().padding(.top, detailTopGap)
                } else if !hasPhone && !hasServer {
                    ScreenTitle("Folders").padding(.top, detailTopGap).bigTitle()
                    EmptyLibraryNote(text: "Folders show here once there is music on this phone or a server is signed in.")
                } else {
                    folderHeader
                    content
                }
                Color.clear.frame(height: 20)
            }
            // A fresh list for each folder, so each one opens at its top.
            .id(path)
            .animation(.easeOut(duration: 0.25), value: state.order(.folderSongs))
            .topOnNewOrder(state.order(.folderSongs)) { proxy.scrollTo("songs", anchor: .top) }
        }
        .barClearance()
        .inlineTitle(shownNames.last ?? "Folders")
        .backAction(trail.isEmpty ? nil : { goUp() })
        .backStopsPicking()
        .selectableSongs(state.pickables(shownSongs))
        .libraryRefreshable { await rereadServer() }
        .task(id: library.stamp(.library)) {
            await readPhone()
            await rereadServer()
        }
        .task(id: path) { await readCurrentServerLevel() }
        .onChange(of: session.activeId) { _, _ in
            trail = []
            serverLevels = [:]
        }
    }

    private func readPhone() async {
        let tracks = await library.tracks().filter(\.onPhone)
        let tree = buildFolderTree(tracks, pathOf: { phonePath($0) }) { a, b in
            let ka = a.album.lowercased(), kb = b.album.lowercased()
            if ka != kb { return ka < kb }
            if a.albumId != b.albumId { return a.albumId < b.albumId }
            if a.albumOrder != b.albumOrder { return a.albumOrder < b.albumOrder }
            return a.sortKey < b.sortKey
        }
        phone = tree.collapsed()
        phoneRead = true
    }

    /// Where a phone song's file sits, as folder names.
    private func phonePath(_ track: LibraryTrack) -> [String] {
        guard let uri = track.uri, let url = URL(string: uri) else { return [] }
        return pathNames(url.deletingLastPathComponent().path)
    }

    private func goUp() {
        note = nil
        if !trail.isEmpty { trail.removeLast() } else { dismiss() }
    }

    // MARK: Header

    private var placeNames: [String] {
        path.map { step in
            switch step {
            case .phone: phone?.name.isEmpty == false ? phone!.name : "This phone"
            case .server: serverDisplayName
            case .phoneFolder(let name): name
            case .serverFolder(_, let name): name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled folder" : name
            }
        }
    }

    private var serverDisplayName: String {
        serverName(isOcto: session.isOcto, type: session.profile?.info.type, host: session.client?.baseURL.host ?? "")
    }

    /// The path's names as the header shows them: "Folders" first only with both sources.
    private var shownNames: [String] {
        let names = ["Folders"] + placeNames
        return hasPhone && hasServer ? names : Array(names.dropFirst())
    }

    private var folderHeader: some View {
        let shown = shownNames
        return VStack(alignment: .leading, spacing: 0) {
            ScreenTitle(shown.last ?? "Folders").bigTitle()
            if shown.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                                if index > 0 { Text(" / ").font(.octoCaption).foregroundStyle(OctoColor.textSecondary) }
                                if index == shown.count - 1 {
                                    Text(name).font(.octoCaption).foregroundStyle(.white).id("end")
                                } else {
                                    Button(name) { goTo(depth: index, of: shown.count) }
                                        .font(.octoCaption)
                                        .foregroundStyle(OctoColor.textSecondary)
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { proxy.scrollTo("end", anchor: .trailing) }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.top, detailTopGap)
    }

    /// Back to a place on the path line.
    private func goTo(depth: Int, of count: Int) {
        let drop = count - 1 - depth
        note = nil
        trail = Array(trail.dropLast(min(drop, trail.count)))
    }

    // MARK: Levels

    @ViewBuilder
    private var content: some View {
        switch path.last {
        case nil:
            SectionTitle("On this phone")
            FolderRow(name: phone?.name.isEmpty == false ? phone!.name : "This phone",
                      subtitle: songsCount(phone?.root.songCount ?? 0)) { trail.append(.phone) }
            SectionTitle("On \(serverDisplayName)").padding(.top, 16)
            FolderRow(name: serverDisplayName, subtitle: "Browse the server by folder") { trail.append(.server) }
        case .phone, .phoneFolder:
            phoneLevel
        case .server, .serverFolder:
            serverLevel
        }
    }

    private var phoneNames: [String] {
        path.compactMap { if case .phoneFolder(let name) = $0 { name } else { nil } }
    }

    @ViewBuilder
    private var phoneLevel: some View {
        if let node = phone?.root.at(phoneNames) {
            let details = [node.folders.isEmpty ? nil : (node.folders.count == 1 ? "1 folder" : "\(node.folders.count) folders"),
                           songsCount(node.songCount)].compactMap { $0 }.joined(separator: " • ")
            VStack(alignment: .leading, spacing: 10) {
                Text(details).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                PlayShuffle(enabled: node.songCount > 0) { actions.play(node.allSongs()) } shuffle: { actions.play(node.allSongs(), shuffled: true) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            ForEach(Array(node.folders.enumerated()), id: \.offset) { index, folder in
                if index > 0 { LibraryHairline() }
                FolderRow(name: folder.name, subtitle: songsCount(folder.songCount)) { trail.append(.phoneFolder(folder.name)) }
            }
            folderSongs(node.songs)
        } else {
            MutedNote("This folder is no longer on the phone.")
        }
    }

    private var serverKey: String {
        if case .serverFolder(let id, _) = path.last { return id }
        return ""
    }

    @ViewBuilder
    private var serverLevel: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlayShuffle(enabled: !gathering, loading: gathering) { Task { await playAll(shuffled: false) } } shuffle: {
                Task { await playAll(shuffled: true) }
            }
            if let note {
                Text(note).font(.octoCaption).foregroundStyle(OctoColor.textMuted).padding(.top, 10)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        if session.client == nil {
            MutedNote("Sign in to your server to see this.")
        } else if let level = serverLevels[serverKey], level.read {
            if let failure = level.failure {
                VStack(spacing: 12) {
                    Text(failure).font(.octoBodySmall).foregroundStyle(OctoColor.textMuted)
                    GlazeButton("Try again", size: .medium) { Task { await readServerLevel(serverKey, force: true) } }
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            } else if level.folders.isEmpty && level.songs.isEmpty {
                MutedNote("Nothing in this folder.")
            } else {
                ForEach(Array(level.folders.enumerated()), id: \.offset) { index, folder in
                    if index > 0 { LibraryHairline() }
                    FolderRow(name: folder.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled folder" : folder.name) {
                        note = nil
                        trail.append(.serverFolder(id: folder.id, name: folder.name))
                    }
                }
                folderSongs(level.songs)
            }
        } else {
            LoadingSpinner(size: 28).frame(maxWidth: .infinity).padding(32)
        }
    }

    /// The songs shown at this level, in the chosen order.
    private var shownSongs: [LibraryTrack] {
        let order = state.order(.folderSongs)
        switch path.last {
        case .phone, .phoneFolder: return sortFolderSongs(phone?.root.at(phoneNames)?.songs ?? [], order)
        case .server, .serverFolder: return sortFolderSongs(serverLevels[serverKey]?.songs ?? [], order)
        case nil: return []
        }
    }

    @ViewBuilder
    private func folderSongs(_ songs: [LibraryTrack]) -> some View {
        if !songs.isEmpty {
            let list = shownSongs
            FirstRowMark()
            SortBar(name: "Songs", list: .folderSongs).padding(.top, 12).id("songs")
            ForEach(Array(list.enumerated()), id: \.element.id) { position, track in
                TrackRow(track: track) { actions.play(list, from: position) }
            }
        }
    }

    // MARK: Reading the server

    private func readCurrentServerLevel() async {
        switch path.last {
        case .server, .serverFolder: await readServerLevel(serverKey, force: false)
        default: break
        }
    }

    /// Reads a level the first time it is shown; levels read stay, so going back up shows them at once.
    private func readServerLevel(_ key: String, force: Bool) async {
        guard let client = session.client else { return }
        if !force, serverLevels[key]?.read == true { return }
        do {
            let listing = key.isEmpty ? try await client.folderTop() : try await client.folder(key)
            serverLevels[key] = Level(folders: listing.folders, songs: await resolve(listing.songs), read: true)
        } catch {
            serverLevels[key] = Level(failure: userMessage(error), read: true)
        }
    }

    /// The library's own songs where it holds them, so the phone's copy plays; finds otherwise.
    private func resolve(_ songs: [Song]) async -> [LibraryTrack] {
        let held = Dictionary((await library.libraryTracks(for: songs.filter { !$0.isExternal })).map { ($0.nativeId, $0) },
                              uniquingKeysWith: { a, _ in a })
        return songs.map { held[$0.id] ?? state.provisional($0) }
    }

    /// A pull reads every level read so far again.
    private func rereadServer() async {
        for key in serverLevels.keys { await readServerLevel(key, force: true) }
    }

    /// Gathers every song under the folder, at most 2,000 from at most 400 folders, then plays.
    private func playAll(shuffled: Bool) async {
        guard !gathering else { return }
        guard let client = session.client else {
            note = "Sign in to your server to play this."
            return
        }
        gathering = true
        defer { gathering = false }
        do {
            let key = serverKey
            let start = key.isEmpty ? try await client.folderTop() : try await client.folder(key)
            let gathered = try await gatherSongs(FolderContents(folders: start.folders.map(\.id), songs: start.songs),
                                                 limit: serverSongLimit, maxFolders: serverFolderLimit) { id in
                let listing = try await client.folder(id)
                return FolderContents(folders: listing.folders.map(\.id), songs: listing.songs)
            }
            if gathered.songs.isEmpty {
                note = "No songs in this folder."
                return
            }
            note = gathered.limitReached ? "Playing the first \(serverSongLimit.formatted()) songs in this folder." : nil
            actions.play(await resolve(gathered.songs), shuffled: shuffled)
        } catch {
            note = userMessage(error)
        }
    }
}

/// A folder line: the folder icon in the accent, the name, an optional line under it and a chevron.
private struct FolderRow: View {
    let name: String
    var subtitle: String?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 16) {
                IconView(.folder, size: 24, color: OctoColor.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.octoCaption).foregroundStyle(OctoColor.textMuted) }
                }
                Spacer(minLength: 0)
                IconView(.chevron, size: 22, color: OctoColor.textMuted)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(SqueezeStyle())
    }
}
