import OctoKit
import SwiftUI

// The library's menus as menu content: buttons, sub-menus and sections that a button's `Menu`
// and a long press's `.contextMenu` both show, every row with the same groups, words and states
// as the other apps. What a menu cannot hold (a name to type, a question, the song's info, the
// playlists to pick from a list) opens as an alert or a sheet once the menu closes.

/// A song a menu is about: the library's row for it (or one shaped like it), the plain song the
/// player takes, where the menu was opened, and the list's picks when it can pick songs.
struct SongSubject {
    var track: LibraryTrack
    var song: Song
    var context = SongMenuContext()
    var selection: SongSelection?
}

/// Songs to add to a playlist: given, or gathered from a collection once a playlist is picked.
enum AddSource {
    case tracks([LibraryTrack])
    case collection(CollectionTarget)
}

/// A collection a menu is about.
enum CollectionSubject {
    case album(LibraryAlbum)
    case artist(LibraryArtist)
    case playlist(PlaylistSummary)

    var target: CollectionTarget {
        switch self {
        case .album(let album): .album(album.id)
        case .artist(let artist): .artist(artist.id)
        case .playlist(let playlist): .playlist(playlist.id)
        }
    }

    var pinKind: PinKind {
        switch self {
        case .album: .album
        case .artist: .artist
        case .playlist: .playlist
        }
    }

    var itemId: String {
        switch self {
        case .album(let album): album.id
        case .artist(let artist): artist.id
        case .playlist(let playlist): playlist.id
        }
    }
}

/// A menu button with its SF Symbol.
private func item(_ title: String, _ icon: OctoIcon, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
    Button(title, systemImage: icon.symbol, role: role, action: action)
}

// MARK: Song menu

/// A song's menu, in its groups: playing it (a row of quick actions), keeping it, going to its
/// album or artist, sharing and looking into it, then `extras` (what the place it opens from
/// adds), and last, what takes it away.
struct SongMenuItems<Extras: View>: View {
    let subject: SongSubject
    let extras: Extras
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    @Environment(Downloads.self) private var downloads
    @Environment(Player.self) private var player
    @Environment(Accounts.self) private var accounts
    @Environment(ServerDownloads.self) private var serverDownloads

    private var track: LibraryTrack { subject.track }
    private var family: FamilyHub { accounts.family }
    private var song: Song { subject.song }
    /// The song as the queue takes it: a library song by its library id, a find as it is.
    private var queued: Song { track.isFound ? song : track.queueSong }
    private var state: LibraryState { actions.state }

    /// The rows that take the song away, the last group.
    private static var takesAway: Set<SongAction> { [.removeFromPlaylist, .deleteFromPhone, .removeFromMyLibrary, .deleteFromDisk] }

    init(subject: SongSubject, @ViewBuilder extras: () -> Extras) {
        self.subject = subject
        self.extras = extras()
    }

    var body: some View {
        let groups = songMenuGroups(offered)
        let last = groups.last.map { Self.takesAway.contains($0[0]) } == true ? groups.count - 1 : groups.count
        ForEach(Array(groups.prefix(last).enumerated()), id: \.offset) { index, group in
            if index == 0, group.first == .playNext {
                ControlGroup {
                    ForEach(group, id: \.self) { row($0) }
                }
            } else {
                Section {
                    ForEach(group, id: \.self) { row($0) }
                }
            }
        }
        Section { extras }
        if last < groups.count {
            Section {
                ForEach(groups[last], id: \.self) { row($0) }
            }
        }
    }

    private var offered: [SongAction] {
        var context = subject.context
        if let selection = subject.selection {
            context.selecting = selection.active
            if context.selectKey == nil { context.selectKey = track.id }
        }
        let place = menuPlace(context, albumId: track.albumId, artistId: track.artistId)
        let kept = state.kept(track.id)
        let ownSong = offersRemoveOn(personal: state.personalIds.contains(track.id), serverMarksPersonal: state.marksPersonal)
        return songActions(
            find: track.isFound,
            radio: true,
            share: state.canShare && state.data.controls.knownShareableSongId(track.id) != nil,
            offline: !track.isFound && (!track.onPhone || kept != nil),
            place: place,
            phone: track.onPhone,
            lastPlaylist: state.lastPlaylist != nil,
            upgrade: actions.canUpgrade(track),
            findSongs: downloads.keepsLog && (track.serverSongId != nil || track.isFound),
            disk: actions.canDeleteFromDisk(track),
            requestCopy: family.outside.offersRequest,
            removeFromMine: family.removesFromMine && track.serverSongId != nil && ownSong)
            // Phones have no way for an app to set a ringtone, a notification sound or an alarm.
            .filter { $0 != .setAsSound }
    }

    @ViewBuilder
    private func row(_ action: SongAction) -> some View {
        switch action {
        case .playNext:
            item("Play next", .playNext) { player.playNext([queued]) }
        case .addToQueue:
            item("Add to queue", .addToQueue) { player.append([queued]) }
        case .startRadio:
            item("Start radio", .radio) { Task { await actions.startRadio(track, song: queued) } }
        case .download:
            if let save = family.outside.addLabel {
                // A family member whose songs are saved rather than added.
                let saved = family.isSaved(track.id)
                item(saved ? "Remove from Saved" : save, saved ? .liked : .like) { family.toggleSaved(track.id, title: track.title) }
            } else {
                let adding = downloads.state(song.id)
                item(downloadLabel(adding), adding == .done ? .check : .addToLibrary) { Task { _ = await downloads.request(song) } }
                    .disabled(adding != .none)
            }
        case .requestCopy:
            item(FamilyText.requestACopy, .download) { family.ask(track.id, title: track.title) }
        case .removeFromMyLibrary:
            item(FamilyText.removeFromMyLibrary, .delete, role: .destructive) {
                family.removeFromMyLibrary(serverId: track.serverSongId, title: track.title)
            }
        case .setAsSound:
            EmptyView()
        case .addToLastPlaylist:
            if let last = state.lastPlaylist {
                item("Add to last playlist: \(last.name)", .addToPlaylist) { actions.add(.tracks([track]), to: last) }
            }
        case .addToPlaylist:
            AddToPlaylistMenu(source: .tracks([track]))
        case .removeFromPlaylist:
            item("Remove from this playlist", .removeFromPlaylist, role: .destructive) {
                if let id = subject.context.playlistId, let row = subject.context.playlistItemId,
                   let playlist = state.playlists.first(where: { $0.id == id }) {
                    actions.remove([row], from: playlist)
                }
            }
        case .select:
            item("Select", .select) { subject.selection?.start(subject.context.selectKey ?? track.id) }
        case .keepOffline:
            let kept = state.kept(track.id)
            item(keepOfflineLabel(kept?.status, byHand: kept?.byHand ?? false), keptIcon(kept?.status)) {
                actions.keepOfflineTapped(track)
            }
            .disabled(!keepOfflineEnabled(kept?.status, byHand: kept?.byHand ?? false))
        case .findFlac:
            item(findHigherQualityWords, .lossless) { actions.findHigherQuality([track]) }
        case .shareFile:
            item("Share file", .shareFile) { actions.shareFiles([track]) }
        case .share:
            Menu {
                ShareLinkItems(target: .song(track.id), title: track.title)
            } label: {
                Label("Share link", systemImage: OctoIcon.link.symbol)
            }
        case .like:
            let liked = actions.isLiked(track)
            // Liking changes the row in place; the menu stays open.
            item(liked ? "Remove from Liked songs" : "Add to Liked songs", liked ? .liked : .like) { actions.toggleLike(track) }
                .menuActionDismissBehavior(.disabled)
        case .rate:
            RateMenu(track: track)
        case .goToAlbum:
            item("Go to album", .album) {
                router.go(.album(Album(id: track.albumId, name: track.album, artist: track.artist, coverArt: coverId(of: track.artwork))))
            }
            .disabled(track.albumId.isEmpty)
        case .goToArtist:
            item("Go to artist", .artist) { router.go(.artist(id: track.artistId, name: track.artist)) }
                .disabled(track.artistId.isEmpty)
        case .deleteFromPhone:
            item("Delete from phone", .delete, role: .destructive) { actions.deleteFromPhone([track]) }
        case .deleteFromDisk:
            item(deleteFromDiskWords, .delete, role: .destructive) { actions.askDeleteFromDisk([track]) }
        case .info:
            item("Song info", .info) { actions.showInfo(subject) }
        case .findSongs:
            item("Find songs", .search) {
                // The song's copy on the signed-in server, the smallest id when it has several.
                Task {
                    if !(await serverDownloads.findTrack(track.id, title: track.title, library: actions.state.library)) {
                        router.show("This server has no copy of the song to look for")
                    }
                }
            }
        }
    }

    private func keptIcon(_ status: DownloadStatus?) -> OctoIcon {
        switch status {
        case .queued, .downloading: .downloading
        case .done: .downloaded
        case nil, .failed: .download
        }
    }
}

extension SongMenuItems where Extras == EmptyView {
    init(subject: SongSubject) { self.init(subject: subject) { EmptyView() } }
}

/// The song's rating as a sub-menu: its stars ticked, picking another sets it, picking the one it
/// has (or "No rating") takes it off.
struct RateMenu: View {
    let track: LibraryTrack
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        let rating = actions.state.rating(of: track)
        Picker(selection: Binding(get: { rating }, set: { actions.rate(track, nextRating(current: rating, tapped: $0)) })) {
            Text("No rating").tag(0)
            ForEach(1...5, id: \.self) { stars in
                Text(starsLabel(stars) ?? "").tag(stars)
            }
        } label: {
            Label("Rate", systemImage: (rating > 0 ? OctoIcon.starFilled : OctoIcon.star).symbol)
        }
        .pickerStyle(.menu)
    }
}

/// The playlists to add songs to, as a sub-menu: "New playlist" first, then every playlist shown
/// with this server, those added to most recently first, each with its song count.
struct AddToPlaylistMenu: View {
    let source: AddSource
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        Menu {
            item("New playlist", .addToLibrary) { actions.askNewPlaylist(source) }
            Section {
                ForEach(actions.state.pickablePlaylists) { playlist in
                    Button { actions.add(source, to: playlist) } label: {
                        Label(playlist.name, systemImage: (playlist.onServer ? OctoIcon.cloud : OctoIcon.playlists).symbol)
                        Text(songsCount(playlist.songCount))
                    }
                }
            }
        } label: {
            Label("Add to playlist", systemImage: OctoIcon.addToPlaylist.symbol)
        }
    }
}

/// How long a shared link lasts, under the note that anyone with it can listen. Picking one
/// makes the link, then hands it to the phone's share sheet. `heading` names what is shared when
/// the menu opens from a page's Share button. While a link is being made every choice is off,
/// and the one being made says so.
struct ShareLinkItems: View {
    let target: ShareTarget
    let title: String
    var heading: String?
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        if let heading {
            Section(heading) { Text("Anyone with the link can listen.") }
        } else {
            Text("Anyone with the link can listen.")
        }
        Section("Link expires") {
            ForEach(ShareExpiry.allCases, id: \.self) { expiry in
                let making = actions.makingLink
                Button { actions.makeLink(target, title: title, expiry: expiry) } label: {
                    if making == MakingLink(target: target, expiry: expiry) {
                        Label(expiry.label, systemImage: "hourglass")
                    } else {
                        Text(expiry.label)
                    }
                }
                .disabled(making != nil)
            }
        }
    }
}

// MARK: Collection menus

/// An album's, an artist's or a playlist's menu, in its groups: playing it (play, shuffle and
/// radio as a row of quick actions), keeping it, Home's pins, going to the artist, and last,
/// changing the playlist.
struct CollectionMenuItems: View {
    let subject: CollectionSubject
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router

    private var state: LibraryState { actions.state }
    private static let quick: Set<CollectionAction> = [.play, .shuffle, .startRadio]

    var body: some View {
        let groups = collectionMenuGroups(offered)
        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            if index == 0, group.first == .play {
                ControlGroup {
                    ForEach(group.filter(Self.quick.contains), id: \.self) { row($0) }
                }
                Section {
                    ForEach(group.filter { !Self.quick.contains($0) }, id: \.self) { row($0) }
                }
            } else {
                Section {
                    ForEach(group, id: \.self) { row($0) }
                }
            }
        }
        .onAppear { if case .album(let album) = subject { actions.loadAlbumFacts(album.id) } }
    }

    /// For an album whose songs are not read yet, Download and Find higher quality show while
    /// they might do something.
    private var offered: [CollectionAction] {
        let spot = state.pinSpot(kind: subject.pinKind.rawValue, id: subject.itemId)
        switch subject {
        case .album(let album):
            let facts = actions.albumFacts[album.id]
            let canDownload = facts.map { $0.serverOnly.contains { state.kept($0) == nil } } ?? true
            let lossy = facts?.lossy ?? (state.fileActions?.canUpgrade == true ? 1 : 0)
            return albumActions(canDownload: canDownload, favorite: state.favoriteAlbumIds.contains(album.id), pin: spot,
                                radio: true, lossy: lossy)
        case .artist(let artist):
            return artistActions(radio: true, favorite: state.favoriteArtistIds.contains(artist.id), pin: spot)
        case .playlist(let playlist):
            return playlistActions(empty: playlist.songCount == 0, pin: spot)
        }
    }

    @ViewBuilder
    private func row(_ action: CollectionAction) -> some View {
        let target = subject.target
        switch action {
        case .play:
            item("Play", .play) { actions.withSongs(of: target) { actions.play($0) } }
        case .shuffle:
            item("Shuffle", .shuffle) { actions.withSongs(of: target) { actions.play($0, shuffled: true) } }
        case .playNext:
            item("Play next", .playNext) { actions.withSongs(of: target) { actions.playNext($0) } }
        case .addToQueue:
            item("Add to queue", .addToQueue) { actions.withSongs(of: target) { actions.addToQueue($0) } }
        case .startRadio:
            item("Start radio", .radio) {
                Task {
                    switch target {
                    case .album(let id): await actions.startAlbumRadio(id)
                    case .artist(let id): await actions.startArtistRadio(id)
                    case .playlist: break
                    }
                }
            }
        case .addToPlaylist:
            AddToPlaylistMenu(source: .collection(target))
        case .download:
            item("Download", .download) { actions.downloadSongs(of: target) }
        case .findFlac:
            let lossy = actions.albumFacts[subject.itemId]?.lossy
            item(lossy.map(findHigherQualityLabel) ?? findHigherQualityWords, .lossless) {
                actions.askFindHigherQuality(albumId: subject.itemId)
            }
        case .addToFavorites, .removeFromFavorites:
            let on = action == .addToFavorites
            item(on ? "Add to favorites" : "Remove from favorites", on ? .like : .liked) {
                switch target {
                case .album(let id): actions.setFavorite(album: id, on)
                case .artist(let id): actions.setFavorite(artist: id, on)
                case .playlist: break
                }
            }
        case .pinToHome:
            item("Pin to Home", .pin) { actions.pin(subject.pinKind, subject.itemId) }
        case .unpin:
            item("Unpin", .pinned) { actions.unpin(subject.pinKind, subject.itemId) }
        case .moveToFront:
            item("Move to front", .pin) { actions.moveToFront(subject.pinKind, subject.itemId) }
        case .goToArtist:
            if case .album(let album) = subject {
                item("Go to artist", .artist) { router.go(.artist(id: album.artistId, name: album.artist)) }
                    .disabled(album.artistId.isEmpty)
            }
        case .rename:
            if case .playlist(let playlist) = subject {
                item("Rename", .rename) { actions.askRename(playlist) }
            }
        case .duplicate:
            if case .playlist(let playlist) = subject {
                item("Duplicate", .copy) { actions.duplicate(playlist) }
            }
        case .delete:
            if case .playlist(let playlist) = subject {
                item("Delete", .delete, role: .destructive) { actions.askDeletePlaylist(playlist) }
            }
        }
    }
}

/// A playlist page's options: rename it, save it to the server, download its songs, write it as
/// an M3U file, or delete it.
struct PlaylistOptionsItems: View {
    let playlist: PlaylistSummary
    /// Whether some of its songs are only on a server.
    let serverOnly: Bool
    /// Runs once the playlist is gone.
    let deleted: @MainActor () -> Void
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        Section(playlist.name) {
            item("Rename", .rename) { actions.askRename(playlist) }
            if actions.canSaveToServer(playlist) {
                item("Save to server", .cloud) { actions.saveToServer(playlist) }
            }
            if serverOnly {
                item("Download", .download) { actions.downloadSongs(of: .playlist(playlist.id)) }
            }
            item("Export as M3U", .share) { actions.exportPlaylist(playlist) }
        }
        Section {
            item("Delete", .delete, role: .destructive) { actions.askDeletePlaylist(playlist, deleted: deleted) }
        }
    }
}

/// A live list's options, from a long press on its line: edit its rules, rename it, copy it, save
/// the songs it holds now as a playlist, or delete it.
struct LiveListOptionsItems: View {
    let list: LiveList
    @Environment(LibraryActions.self) private var actions
    @Environment(LiveListStore.self) private var store
    @Environment(LiveLibrary.self) private var liveLibrary
    @Environment(Router.self) private var router

    var body: some View {
        Section(list.name) {
            item("Edit rules", .filter) { router.go(.liveListEditor(id: list.id)) }
            item("Rename", .rename) { actions.askRename(list, in: store) }
            item("Duplicate", .copy) { router.show(copiedMessage(store.duplicate(list).name)) }
            item("Save a copy as a playlist", .playlists) { Task { await saveCopy() } }
        }
        Section {
            item("Delete", .delete, role: .destructive) { actions.askDelete(list, in: store) }
        }
    }

    /// A playlist named as the live list with the songs it holds now; it does not follow the rules.
    private func saveCopy() async {
        if liveLibrary.version == 0 { await liveLibrary.read() }
        await liveLibrary.pick(list.query)
        let songs = liveLibrary.songs(list.query) ?? []
        guard !songs.isEmpty else {
            router.show(nothingToCopy(list.name))
            return
        }
        actions.state.data.playlists.create(list.name, trackIds: songs.map(\.id))
        router.show(liveCopyMessage(list.name, count: songs.count))
    }
}

// MARK: Sheets and alerts

/// A name asked for in an alert with its field: a new playlist's, or a new name for one.
struct NameRequest: Identifiable {
    let id = UUID()
    let title: String
    let action: String
    var initial = ""
    var placeholder = "Playlist name"
    let done: @MainActor (String) -> Void
}

/// The question when some songs are on the playlist already.
struct AddAsk: Identifiable {
    let id = UUID()
    let playlist: PlaylistSummary
    let plan: AddPlan
}

/// A question before something that cannot be taken back, or that goes to the server.
struct Question: Identifiable {
    let id = UUID()
    let title: String
    var detail: String?
    let confirm: String
    var destructive = true
    /// The server the question is about, when it goes to one: another coming into use cancels it.
    var server: String?
    let run: @MainActor () -> Void
}

extension View {
    /// The alert asking for a name, while `request` is set.
    func nameAlert(_ request: Binding<NameRequest?>) -> some View { modifier(NameAlert(request: request)) }

    /// The alert asking whether songs on the playlist already go on it again.
    func addAskAlert(_ ask: Binding<AddAsk?>, add: @escaping @MainActor ([String], PlaylistSummary) -> Void) -> some View {
        alert(ask.wrappedValue.map { addAgainQuestion($0.playlist.name, $0.plan) } ?? "",
              isPresented: Binding(get: { ask.wrappedValue != nil }, set: { if !$0 { ask.wrappedValue = nil } }),
              presenting: ask.wrappedValue) { ask in
            if ask.plan.offersNewOnly {
                Button(addNewOnes) { add(ask.plan.fresh, ask.playlist) }
            }
            Button(addAgainChoice(ask.plan)) { add(ask.plan.songs, ask.playlist) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The alert asking a question, while `question` is set.
    func questionAlert(_ question: Binding<Question?>) -> some View {
        alert(question.wrappedValue?.title ?? "",
              isPresented: Binding(get: { question.wrappedValue != nil }, set: { if !$0 { question.wrappedValue = nil } }),
              presenting: question.wrappedValue) { asked in
            Button(asked.confirm, role: asked.destructive ? .destructive : nil) { asked.run() }
            Button("Cancel", role: .cancel) {}
        } message: { asked in
            if let detail = asked.detail { Text(detail) }
        }
    }
}

private struct NameAlert: ViewModifier {
    @Binding var request: NameRequest?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(request?.title ?? "", isPresented: Binding(get: { request != nil }, set: { if !$0 { request = nil } }),
                   presenting: request) { asked in
                TextField(asked.placeholder, text: $name)
                    .textInputAutocapitalization(.sentences)
                Button(asked.action) { asked.done(name) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: request?.id, initial: true) { _, _ in name = request?.initial ?? "" }
    }
}

/// The playlists to add songs to, on a sheet: for picked songs, where there is no menu to open.
/// Its questions (a new playlist's name, adding songs again) open over the sheet.
struct PlaylistPickerSheet: View {
    let source: AddSource
    @Environment(LibraryActions.self) private var actions
    @Environment(\.dismiss) private var dismiss
    @State private var naming: NameRequest?
    @State private var ask: AddAsk?
    @State private var checking: String?

    private var title: String {
        guard case .tracks(let tracks) = source, tracks.count > 1 else { return "Add to playlist" }
        return "Add \(grouped(tracks.count)) songs to a playlist"
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    naming = actions.newPlaylistRequest(source) { dismiss() }
                } label: {
                    Label("New playlist", systemImage: OctoIcon.addToLibrary.symbol)
                }
                Section {
                    ForEach(actions.state.pickablePlaylists) { playlist in
                        Button { pick(playlist) } label: {
                            PlaylistPickRow(playlist: playlist, checking: checking == playlist.id)
                        }
                        .disabled(checking != nil)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .nameAlert($naming)
        .addAskAlert($ask) { ids, playlist in
            dismiss()
            actions.addNow(ids, to: playlist)
        }
    }

    /// Adds at once when none is on the playlist yet; otherwise asks first.
    private func pick(_ playlist: PlaylistSummary) {
        checking = playlist.id
        Task {
            let plan = await actions.plan(source, to: playlist)
            checking = nil
            if plan.asks {
                ask = AddAsk(playlist: playlist, plan: plan)
            } else {
                dismiss()
                actions.addNow(plan.songs, to: playlist)
            }
        }
    }
}

/// One playlist to add to: its small cover, the name, the count and the cloud for one kept with
/// the server.
private struct PlaylistPickRow: View {
    let playlist: PlaylistSummary
    let checking: Bool

    var body: some View {
        HStack(spacing: 12) {
            PlaylistCover(playlist: playlist, size: 44, radius: 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.name).foregroundStyle(.primary).lineLimit(1)
                HStack(spacing: 4) {
                    Text(songsCount(playlist.songCount))
                    if playlist.onServer {
                        Image(systemName: OctoIcon.cloud.symbol).accessibilityLabel("On your server")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if checking { ProgressView() }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A menu laid out as a list on a sheet, for the drive's screenshots of what a menu holds.
struct MenuPreview: Identifiable {
    enum Content {
        case song(SongSubject)
        case collection(CollectionSubject)
        case playlistOptions(PlaylistSummary)
        case liveListOptions(LiveList)
    }

    let id = UUID()
    let content: Content
}

struct MenuPreviewSheet: View {
    let preview: MenuPreview

    var body: some View {
        NavigationStack {
            List {
                switch preview.content {
                case .song(let subject): SongMenuItems(subject: subject)
                case .collection(let subject): CollectionMenuItems(subject: subject)
                case .playlistOptions(let playlist): PlaylistOptionsItems(playlist: playlist, serverOnly: true, deleted: {})
                case .liveListOptions(let list): LiveListOptionsItems(list: list)
                }
            }
            .navigationTitle("Menu")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}
