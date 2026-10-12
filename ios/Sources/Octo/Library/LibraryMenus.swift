import Observation
import OctoKit
import SwiftUI
import UIKit

// The library's menus: glass pop-ups beside what was pressed, each with its pages (rate, add
// to a playlist, share a link, song info, questions and names), every row with the same groups,
// words and states as the other apps.

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

/// What a menu pop-up is about.
enum MenuSubject {
    case song(SongSubject)
    case album(LibraryAlbum)
    case artist(LibraryArtist)
    case playlist(PlaylistSummary)
    /// A playlist page's options; `deleted` runs once the playlist is gone.
    case playlistOptions(PlaylistSummary, serverOnly: Bool, deleted: (@MainActor () -> Void)?)
    case addToPlaylist(AddSource, startAt: String? = nil)
    case newPlaylist([LibraryTrack])
    /// A page's Share: a link to it, named by the title.
    case share(ShareTarget, title: String)
    case songInfo(SongSubject)

    var firstPage: MenuPage {
        switch self {
        case .song, .album, .artist, .playlist, .playlistOptions: .actions
        case .addToPlaylist(_, let startAt): .addToPlaylist(startAt: startAt)
        case .newPlaylist: .newPlaylist
        case .share: .share
        case .songInfo: .info
        }
    }

    /// What a screen reader calls the pop-up.
    var paneTitle: String {
        switch self {
        case .song: "Song menu"
        case .album, .artist, .playlist: "Menu"
        case .playlistOptions, .addToPlaylist, .newPlaylist: "Playlist"
        case .share: "Share"
        case .songInfo: "Song info"
        }
    }

    var heightShare: Double { PopupMeasures.heightShare }

    /// Whether asking for this while `self` is open opens it as the next page: the playlist
    /// pop-up's pages follow one another.
    func continues(_ next: MenuSubject) -> Bool {
        switch (self, next) {
        case (.playlistOptions, .addToPlaylist), (.playlistOptions, .newPlaylist), (.addToPlaylist, .newPlaylist): true
        default: false
        }
    }
}

/// The pages of a menu pop-up.
enum MenuPage: Equatable {
    case actions, rate, share, info, deleteFromDisk
    case addToPlaylist(startAt: String?)
    case addAsk, newPlaylist, rename, deletePlaylist, findHigherQuality
}

/// One menu pop-up while it is open: what it is about and the page it is on.
@MainActor
@Observable
final class MenuSession {
    let id = UUID()
    let subject: MenuSubject
    let pages: PopupPages<MenuPage>
    /// An add waiting on its question: the playlist and what adding would do.
    var pendingAdd: (playlist: PlaylistSummary, plan: AddPlan)?

    init(subject: MenuSubject, first: MenuPage) {
        self.subject = subject
        pages = PopupPages(first)
    }
}

/// A menu pop-up's current page.
struct LibraryMenuView: View {
    let session: MenuSession

    var body: some View {
        PopupPager(pages: session.pages) { page, canGoBack in
            MenuPageView(session: session, page: page, canGoBack: canGoBack)
        }
    }
}

private struct MenuPageView: View {
    let session: MenuSession
    let page: MenuPage
    let canGoBack: Bool
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        switch (session.subject, page) {
        case (.song(let subject), .actions):
            SongActionsPage(session: session, subject: subject)
        case (.song(let subject), .rate):
            RatePage(session: session, subject: subject)
        case (.song(let subject), .share):
            SharePage(session: session, target: .song(subject.track.id), title: subject.track.title, fromMenu: true)
        case (.song(let subject), .info), (.songInfo(let subject), .info):
            SongInfoPage(subject: subject, canGoBack: canGoBack) { session.pages.back() }
        case (.song(let subject), .deleteFromDisk):
            let words = actions.deleteFromDiskQuestion([subject.track])
            PopupQuestion(title: words.title, detail: words.body, confirm: "Delete") {
                actions.closeMenu(session)
                actions.deleteFromDisk([subject.track])
            } onCancel: { session.pages.back() }
        case (.song(let subject), .addToPlaylist(let startAt)):
            PlaylistPickerPage(session: session, source: .tracks([subject.track]), startAt: startAt, canGoBack: canGoBack)
        case (.album, .actions), (.artist, .actions), (.playlist, .actions):
            CollectionActionsPage(session: session)
        case (.album(let album), .addToPlaylist(let startAt)):
            PlaylistPickerPage(session: session, source: .collection(.album(album.id)), startAt: startAt, canGoBack: canGoBack)
        case (.artist(let artist), .addToPlaylist(let startAt)):
            PlaylistPickerPage(session: session, source: .collection(.artist(artist.id)), startAt: startAt, canGoBack: canGoBack)
        case (.playlist(let playlist), .addToPlaylist(let startAt)):
            PlaylistPickerPage(session: session, source: .collection(.playlist(playlist.id)), startAt: startAt, canGoBack: canGoBack)
        case (.album(let album), .findHigherQuality):
            FindHigherQualityPage(session: session, albumId: album.id)
        case (.playlist(let playlist), .rename), (.playlistOptions(let playlist, _, _), .rename):
            PopupNameForm(title: "Rename playlist", placeholder: "Playlist name", action: "Save",
                          onBack: canGoBack ? { session.pages.back() } : nil, onDone: { name in
                              actions.rename(playlist, to: name)
                              actions.closeMenu(session)
                          }, initial: playlist.name)
        case (.playlist(let playlist), .deletePlaylist):
            DeletePlaylistPage(session: session, playlist: playlist, canGoBack: canGoBack, deleted: nil)
        case (.playlistOptions(let playlist, _, let deleted), .deletePlaylist):
            DeletePlaylistPage(session: session, playlist: playlist, canGoBack: canGoBack, deleted: deleted)
        case (.playlistOptions(let playlist, let serverOnly, _), .actions):
            PlaylistOptionsPage(session: session, playlist: playlist, serverOnly: serverOnly)
        case (.addToPlaylist(let source, _), .addToPlaylist(let startAt)):
            PlaylistPickerPage(session: session, source: source, startAt: startAt, canGoBack: canGoBack)
        case (_, .addAsk):
            AddAskPage(session: session)
        case (.newPlaylist(let tracks), .newPlaylist):
            PopupNameForm(title: "New playlist", placeholder: "Playlist name", action: "Create",
                          onBack: canGoBack ? { session.pages.back() } : nil) { name in
                actions.createPlaylist(name: name, tracks: tracks)
                actions.closeMenu(session)
            }
        case (_, .newPlaylist):
            PopupNameForm(title: "New playlist", placeholder: "Playlist name", action: "Create",
                          onBack: canGoBack ? { session.pages.back() } : nil) { name in
                actions.createPlaylist(name: name, tracks: [])
                actions.closeMenu(session)
            }
        case (.share(let target, let title), .share):
            SharePage(session: session, target: target, title: title, fromMenu: canGoBack)
        default:
            GlassMenuPage { GlassMenuNote("Nothing to show") }
        }
    }
}

/// The header of a song's menu pages: its artwork, title and artist.
struct SongMenuHeader: View {
    let track: LibraryTrack

    var body: some View {
        GlassMenuHeader(title: track.title, subtitle: track.artist) {
            ArtCover(artwork: track.artwork, size: 40, radius: OctoRadius.artS)
        }
    }
}

// MARK: Song menu

private struct SongActionsPage: View {
    let session: MenuSession
    let subject: SongSubject
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    @Environment(Downloads.self) private var downloads
    @Environment(Player.self) private var player

    private var track: LibraryTrack { subject.track }
    private var song: Song { subject.song }
    /// The song as the queue takes it: a library song by its library id, a find as it is.
    private var queued: Song { track.isFound ? song : track.queueSong }
    private var state: LibraryState { actions.state }

    var body: some View {
        GlassMenuPage {
            SongMenuHeader(track: track)
            GlassMenuSeparator()
        } content: {
            GlassMenuGroups(groups: songMenuGroups(offered)) { action in row(action) }
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
        return songActions(
            find: track.isFound,
            radio: true,
            share: state.canShare && track.serverSongId != nil,
            offline: !track.isFound && (!track.onPhone || kept != nil),
            place: place,
            phone: track.onPhone,
            lastPlaylist: state.lastPlaylist != nil,
            upgrade: actions.canUpgrade(track),
            findSongs: downloads.keepsLog && (track.serverSongId != nil || track.isFound),
            disk: actions.canDeleteFromDisk(track))
            // Phones have no way for an app to set a ringtone, a notification sound or an alarm.
            .filter { $0 != .setAsSound }
    }

    private func close(then run: () -> Void) {
        actions.closeMenu(session)
        run()
    }

    @ViewBuilder
    private func row(_ action: SongAction) -> some View {
        switch action {
        case .playNext:
            GlassMenuAction(.playNext, "Play next") { close { player.playNext([queued]) } }
        case .addToQueue:
            GlassMenuAction(.addToQueue, "Add to queue") { close { player.append([queued]) } }
        case .startRadio:
            GlassMenuAction(.radio, "Start radio") { close { Task { await actions.startRadio(queued) } } }
        case .download:
            let state = downloads.state(song.id)
            GlassMenuAction(state == .done ? .check : .addToLibrary, downloadLabel(state), enabled: state == .none) {
                Task { _ = await downloads.request(song) }
            }
        case .requestCopy, .removeFromMyLibrary, .setAsSound:
            EmptyView()
        case .addToLastPlaylist:
            if let last = state.lastPlaylist {
                GlassMenuAction(.addToPlaylist, "Add to last playlist: \(last.name)") {
                    session.pages.open(.addToPlaylist(startAt: last.id))
                }
            }
        case .addToPlaylist:
            GlassMenuAction(.addToPlaylist, "Add to playlist", opensPage: true) { session.pages.open(.addToPlaylist(startAt: nil)) }
        case .removeFromPlaylist:
            GlassMenuAction(.removeFromPlaylist, "Remove from this playlist") {
                close {
                    if let id = subject.context.playlistId, let item = subject.context.playlistItemId,
                       let playlist = state.playlists.first(where: { $0.id == id }) {
                        actions.remove([item], from: playlist)
                    }
                }
            }
        case .select:
            GlassMenuAction(.select, "Select") {
                close { subject.selection?.start(subject.context.selectKey ?? track.id) }
            }
        case .keepOffline:
            let kept = state.kept(track.id)
            GlassMenuAction(keptIcon(kept?.status), keepOfflineLabel(kept?.status, byHand: kept?.byHand ?? false),
                            enabled: keepOfflineEnabled(kept?.status, byHand: kept?.byHand ?? false)) {
                actions.keepOfflineTapped(track)
            }
        case .findFlac:
            GlassMenuAction(.lossless, findHigherQualityWords) { close { actions.findHigherQuality([track]) } }
        case .shareFile:
            GlassMenuAction(.shareFile, "Share file") { close { actions.shareFiles([track]) } }
        case .share:
            GlassMenuAction(.share, "Share link", opensPage: true) { session.pages.open(.share) }
        case .like:
            let liked = actions.isLiked(track)
            GlassMenuAction(liked ? .liked : .like, liked ? "Remove from Liked songs" : "Add to Liked songs") {
                actions.toggleLike(track)
            }
        case .rate:
            let rating = state.rating(of: track)
            GlassMenuAction(rating > 0 ? .starFilled : .star, "Rate", detail: starsLabel(rating), opensPage: true) {
                session.pages.open(.rate)
            }
        case .goToAlbum:
            GlassMenuAction(.album, "Go to album", enabled: !track.albumId.isEmpty) {
                close { router.go(.album(Album(id: track.albumId, name: track.album, artist: track.artist, coverArt: coverId(of: track.artwork)))) }
            }
        case .goToArtist:
            GlassMenuAction(.artist, "Go to artist", enabled: !track.artistId.isEmpty) {
                close { router.go(.artist(id: track.artistId, name: track.artist)) }
            }
        case .deleteFromPhone:
            GlassMenuAction(.delete, "Delete from phone", destructive: true) { close { actions.deleteFromPhone([track]) } }
        case .deleteFromDisk:
            GlassMenuAction(.delete, deleteFromDiskWords, opensPage: true, destructive: true) { session.pages.open(.deleteFromDisk) }
        case .info:
            GlassMenuAction(.info, "Song info", opensPage: true) { session.pages.open(.info) }
        case .findSongs:
            GlassMenuAction(.search, "Find songs") {
                close {
                    if let id = track.serverSongId ?? (track.isFound ? song.id : nil) {
                        router.serverDownloads = .find(id: id, title: track.title, from: nil)
                    } else {
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

/// Five stars: a tap sets that many, a tap on the star the song has takes the rating off. The
/// page stays open so the stars show the choice.
private struct RatePage: View {
    let session: MenuSession
    let subject: SongSubject
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        let rating = actions.state.rating(of: subject.track)
        GlassMenuPage {
            GlassMenuBack(title: "Rate") { session.pages.back() }
            SongMenuHeader(track: subject.track)
        } content: {
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Button { actions.rate(subject.track, nextRating(current: rating, tapped: star)) } label: {
                        IconView(star <= rating ? .starFilled : .star, size: 30, color: star <= rating ? .white : OctoColor.textMuted)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScale())
                    .accessibilityLabel(star == 1 ? "1 star" : "\(star) stars")
                    .accessibilityAddTraits(star == rating ? .isSelected : [])
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 10)
        }
    }
}

/// How long a shared link lasts, under the note that anyone with it can listen. Picking one
/// makes the link, then hands it to the phone's share sheet.
private struct SharePage: View {
    let session: MenuSession
    let target: ShareTarget
    let title: String
    let fromMenu: Bool
    @Environment(LibraryActions.self) private var actions
    @State private var making: ShareExpiry?
    @State private var failure: String?

    var body: some View {
        GlassMenuPage {
            if fromMenu {
                GlassMenuBack(title: "Share link") { session.pages.back() }
            } else {
                GlassMenuHeading("Share \"\(title)\"")
            }
        } content: {
            GlassMenuNote("Anyone with the link can listen.")
            GlassMenuTitle("Link expires")
            ForEach(ShareExpiry.allCases, id: \.self) { expiry in
                Button { make(expiry) } label: {
                    HStack {
                        Text(expiry.label)
                            .font(.octoBodySmall)
                            .foregroundStyle(making == nil || making == expiry ? Color.white : OctoColor.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if making == expiry { Spinner(size: 16) }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 46)
                    .contentShape(GlassMenu.optionShape)
                }
                .buttonStyle(.plain)
                .disabled(making != nil)
            }
            if let failure { GlassMenuNote(failure, color: OctoColor.error) }
        }
    }

    private func make(_ expiry: ShareExpiry) {
        making = expiry
        failure = nil
        Task {
            let words = await actions.share(target, title: title, expiry: expiry)
            making = nil
            if let words { failure = words } else { actions.closeMenu(session) }
        }
    }
}

// MARK: Collection menus

private struct CollectionActionsPage: View {
    let session: MenuSession
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    /// For an album: how many of its songs are only on a server and not kept, and how many the
    /// server could replace with a better copy.
    @State private var serverOnly = 0
    @State private var lossy = 0

    private var state: LibraryState { actions.state }

    private var target: CollectionTarget {
        switch session.subject {
        case .album(let album): .album(album.id)
        case .artist(let artist): .artist(artist.id)
        case .playlist(let playlist): .playlist(playlist.id)
        default: .album("")
        }
    }

    private var kind: PinKind {
        switch target {
        case .album: .album
        case .artist: .artist
        case .playlist: .playlist
        }
    }

    private var itemId: String {
        switch target {
        case .album(let id), .artist(let id), .playlist(let id): id
        }
    }

    var body: some View {
        GlassMenuPage {
            header
            GlassMenuSeparator()
        } content: {
            GlassMenuGroups(groups: collectionMenuGroups(offered)) { action in row(action) }
        }
        .task(id: itemId) {
            guard case .album(let id) = target else { return }
            let tracks = await state.library.albumTracks(id)
            serverOnly = tracks.filter { !$0.onPhone && state.kept($0.id) == nil }.count
            lossy = tracks.filter(actions.canUpgrade).count
        }
    }

    @ViewBuilder
    private var header: some View {
        switch session.subject {
        case .album(let album):
            GlassMenuHeader(title: album.title, subtitle: album.artist) {
                ArtCover(artwork: album.artwork, size: 40, radius: OctoRadius.artS)
            }
        case .artist(let artist):
            GlassMenuHeader(title: artist.name, subtitle: albumsCount(artist.albumCount)) {
                ArtCover(artwork: artist.artwork, size: 40, radius: 20)
            }
        case .playlist(let playlist):
            GlassMenuHeader(title: playlist.name, subtitle: songsCount(playlist.songCount)) {
                PlaylistCover(playlist: playlist, size: 40, radius: OctoRadius.artS)
            }
        default:
            EmptyView()
        }
    }

    private var offered: [CollectionAction] {
        let spot = state.pinSpot(kind: kind.rawValue, id: itemId)
        switch session.subject {
        case .album(let album):
            return albumActions(canDownload: serverOnly > 0, favorite: state.favoriteAlbumIds.contains(album.id), pin: spot,
                                radio: true, lossy: lossy)
        case .artist(let artist):
            return artistActions(radio: true, favorite: state.favoriteArtistIds.contains(artist.id), pin: spot)
        case .playlist(let playlist):
            return playlistActions(empty: playlist.songCount == 0, pin: spot)
        default:
            return []
        }
    }

    /// Closes the menu, then acts on the collection's songs once they are read.
    private func withSongs(_ use: @escaping @MainActor ([LibraryTrack]) -> Void) {
        actions.closeMenu(session)
        let target = target
        Task {
            let tracks = await state.songs(of: target)
            if !tracks.isEmpty { use(tracks) }
        }
    }

    private func close(then run: () -> Void) {
        actions.closeMenu(session)
        run()
    }

    @ViewBuilder
    private func row(_ action: CollectionAction) -> some View {
        switch action {
        case .play:
            GlassMenuAction(.play, "Play") { withSongs { actions.play($0) } }
        case .shuffle:
            GlassMenuAction(.shuffle, "Shuffle") { withSongs { actions.play($0, shuffled: true) } }
        case .playNext:
            GlassMenuAction(.playNext, "Play next") { withSongs { actions.playNext($0) } }
        case .addToQueue:
            GlassMenuAction(.addToQueue, "Add to queue") { withSongs { actions.addToQueue($0) } }
        case .startRadio:
            GlassMenuAction(.radio, "Start radio") {
                let target = target
                close {
                    Task {
                        switch target {
                        case .album(let id): await actions.startAlbumRadio(id)
                        case .artist(let id): await actions.startArtistRadio(id)
                        case .playlist: break
                        }
                    }
                }
            }
        case .addToPlaylist:
            GlassMenuAction(.addToPlaylist, "Add to playlist", opensPage: true) { session.pages.open(.addToPlaylist(startAt: nil)) }
        case .download:
            GlassMenuAction(.download, "Download") {
                withSongs { tracks in state.offline.download(tracks.filter { !$0.onPhone }.map(\.id)) }
            }
        case .findFlac:
            GlassMenuAction(.lossless, findHigherQualityLabel(lossy), opensPage: true) { session.pages.open(.findHigherQuality) }
        case .addToFavorites, .removeFromFavorites:
            let on = action == .addToFavorites
            GlassMenuAction(on ? .like : .liked, on ? "Add to favorites" : "Remove from favorites") {
                close {
                    switch target {
                    case .album(let id): actions.setFavorite(album: id, on)
                    case .artist(let id): actions.setFavorite(artist: id, on)
                    case .playlist: break
                    }
                }
            }
        case .pinToHome:
            GlassMenuAction(.pin, "Pin to Home") { close { actions.pin(kind, itemId) } }
        case .unpin:
            GlassMenuAction(.pin, "Unpin") { close { actions.unpin(kind, itemId) } }
        case .moveToFront:
            GlassMenuAction(.pin, "Move to front") { close { actions.moveToFront(kind, itemId) } }
        case .goToArtist:
            GlassMenuAction(.artist, "Go to artist") {
                close { if case .album(let album) = session.subject { router.go(.artist(id: album.artistId, name: album.artist)) } }
            }
        case .rename:
            GlassMenuAction(.rename, "Rename", opensPage: true) { session.pages.open(.rename) }
        case .duplicate:
            GlassMenuAction(.addToPlaylist, "Duplicate") {
                close { if case .playlist(let playlist) = session.subject { actions.duplicate(playlist) } }
            }
        case .delete:
            GlassMenuAction(.delete, "Delete", opensPage: true, destructive: true) { session.pages.open(.deletePlaylist) }
        }
    }
}

/// The question before an album's lossy songs go to the server to be looked for at a better copy.
private struct FindHigherQualityPage: View {
    let session: MenuSession
    let albumId: String
    @Environment(LibraryActions.self) private var actions
    @State private var asks: [LibraryTrack]?

    var body: some View {
        Group {
            if let asks {
                PopupQuestion(title: findHigherQualityAsk(asks.count, source: actions.state.fileActions?.upgradeSource),
                              detail: keepsOriginalWords, confirm: findHigherQualityWords) {
                    actions.closeMenu(session)
                    actions.findHigherQuality(asks)
                } onCancel: { session.pages.back() }
            } else {
                GlassMenuPage { GlassMenuNote("Gathering the songs") }
            }
        }
        .task { asks = await actions.state.library.albumTracks(albumId).filter(actions.canUpgrade) }
    }
}

// MARK: Playlist pop-up

/// A playlist page's options.
private struct PlaylistOptionsPage: View {
    let session: MenuSession
    let playlist: PlaylistSummary
    let serverOnly: Bool
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        GlassMenuPage {
            GlassMenuHeading(playlist.name)
        } content: {
            GlassMenuAction(.rename, "Rename", opensPage: true) { session.pages.open(.rename) }
            if actions.canSaveToServer(playlist) {
                GlassMenuAction(.cloud, "Save to server") {
                    actions.closeMenu(session)
                    actions.saveToServer(playlist)
                }
            }
            if serverOnly {
                GlassMenuAction(.download, "Download") {
                    actions.closeMenu(session)
                    let state = actions.state
                    Task { state.offline.download(await state.playlistTracks(playlist.id).map(\.track).filter { !$0.onPhone }.map(\.id)) }
                }
            }
            GlassMenuAction(.share, "Export as M3U") {
                actions.closeMenu(session)
                actions.exportPlaylist(playlist)
            }
            GlassMenuAction(.delete, "Delete", opensPage: true, destructive: true) { session.pages.open(.deletePlaylist) }
        }
    }
}

/// Asks before a playlist goes; one kept with the server goes from there too.
private struct DeletePlaylistPage: View {
    let session: MenuSession
    let playlist: PlaylistSummary
    let canGoBack: Bool
    let deleted: (@MainActor () -> Void)?
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        PopupQuestion(title: "Delete \"\(playlist.name)\"?",
                      detail: playlist.onServer ? "It is deleted from your server too. The songs stay in your library."
                          : "The songs stay in your library.",
                      confirm: "Delete") {
            actions.closeMenu(session)
            actions.delete(playlist)
            deleted?()
        } onCancel: {
            if canGoBack { session.pages.back() } else { actions.closeMenu(session) }
        }
    }
}

/// The playlists to add songs to: "New playlist" first (it turns into a name field in place),
/// then every playlist shown with this server, those added to most recently first.
private struct PlaylistPickerPage: View {
    let session: MenuSession
    let source: AddSource
    let startAt: String?
    let canGoBack: Bool
    @Environment(LibraryActions.self) private var actions
    @State private var tracks: [LibraryTrack]?
    @State private var naming = false
    @State private var checking = false

    private var title: String {
        let count = tracks?.count ?? 1
        return count == 1 ? "Add to playlist" : "Add \(grouped(count)) songs to a playlist"
    }

    var body: some View {
        GlassMenuPage {
            if canGoBack { GlassMenuBack(title: title) { session.pages.back() } } else { GlassMenuHeading(title) }
        } content: {
            if tracks == nil {
                GlassMenuNote("Gathering the songs")
            } else if checking {
                GlassMenuNote("Checking the playlist")
            } else {
                if naming {
                    PopupNameField(placeholder: "Playlist name", action: "Create") { name in
                        actions.createPlaylist(name: name, tracks: tracks ?? [])
                        actions.closeMenu(session)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                } else {
                    GlassMenuAction(.addToLibrary, "New playlist") { naming = true }
                }
                ForEach(actions.state.pickablePlaylists) { playlist in
                    PlaylistPickRow(playlist: playlist) { pick(playlist) }
                }
            }
        }
        .task {
            switch source {
            case .tracks(let given): tracks = given
            case .collection(let target): tracks = await actions.state.songs(of: target)
            }
            if let startAt, let playlist = actions.state.playlists.first(where: { $0.id == startAt }) {
                checking = true
                pick(playlist)
            }
        }
    }

    /// Adds at once when none is on the playlist yet; otherwise asks first.
    private func pick(_ playlist: PlaylistSummary) {
        let given = tracks ?? []
        Task {
            let (plan, _) = await actions.planAdding(given, to: playlist)
            checking = false
            if plan.asks {
                session.pendingAdd = (playlist, plan)
                session.pages.open(.addAsk)
            } else {
                actions.closeMenu(session)
                actions.addNow(plan.songs, to: playlist)
            }
        }
    }
}

/// One playlist to add to: its small cover, the name, the count and the cloud for one kept with
/// the server.
private struct PlaylistPickRow: View {
    let playlist: PlaylistSummary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                PlaylistCover(playlist: playlist, size: 36, radius: 6)
                VStack(alignment: .leading, spacing: 0) {
                    Text(playlist.name).font(.octoBodySmall).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(songsCount(playlist.songCount)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                        if playlist.onServer {
                            IconView(.cloud, size: 12, color: OctoColor.textMuted).accessibilityLabel("On your server")
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 52)
            .contentShape(GlassMenu.optionShape)
        }
        .buttonStyle(MenuPressStyle())
        .accessibilityElement(children: .combine)
    }
}

/// The question when some songs are on the playlist already.
private struct AddAskPage: View {
    let session: MenuSession
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        if let pending = session.pendingAdd {
            let question = addAgainQuestion(pending.playlist.name, pending.plan)
            if pending.plan.offersNewOnly {
                VStack(alignment: .leading, spacing: 0) {
                    Text(question).font(.octoBody).foregroundStyle(.white).lineLimit(3).accessibilityAddTraits(.isHeader)
                    HStack(spacing: 10) {
                        AccentButton(addNewOnes) { add(pending.plan.fresh, pending.playlist) }
                        GlazeButton(addAgainChoice(pending.plan)) { add(pending.plan.songs, pending.playlist) }
                    }
                    .padding(.top, 18)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(width: GlassMenu.width, alignment: .leading)
            } else {
                PopupQuestion(title: question, confirm: addAgainChoice(pending.plan)) {
                    add(pending.plan.songs, pending.playlist)
                } onCancel: { session.pages.back() }
            }
        }
    }

    private func add(_ ids: [String], _ playlist: PlaylistSummary) {
        actions.closeMenu(session)
        actions.addNow(ids, to: playlist)
    }
}

/// A row under the finger shows the quiet pressed pill, as the menu's own rows do.
struct MenuPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { if configuration.isPressed { GlassMenu.optionShape.fill(OctoColor.menuPress) } }
    }
}
