import OctoKit
import SwiftUI
import UIKit

/// The icons the menus and rows use.
enum MenuIcon {
    static let playNext = "text.line.first.and.arrowtriangle.forward"
    static let addToQueue = "text.line.last.and.arrowtriangle.forward"
    static let radio = "dot.radiowaves.left.and.right"
    static let addToLibrary = "plus"
    static let check = "checkmark"
    static let download = "arrow.down.circle"
    static let downloading = "arrow.down.circle.dotted"
    static let downloaded = "arrow.down.circle.fill"
    static let addToPlaylist = "text.badge.plus"
    static let removeFromPlaylist = "text.badge.minus"
    static let select = "checkmark.circle"
    static let lossless = "waveform"
    static let shareFile = "square.and.arrow.up.on.square"
    static let share = "square.and.arrow.up"
    static let like = "heart"
    static let liked = "heart.fill"
    static let star = "star"
    static let starFilled = "star.fill"
    static let album = "square.stack"
    static let artist = "music.microphone"
    static let ringtone = "bell"
    static let delete = "trash"
    static let info = "info.circle"
    static let search = "magnifyingglass"
    static let play = "play.fill"
    static let shuffle = "shuffle"
    static let pin = "pin"
    static let rename = "pencil"
    static let filter = "line.3.horizontal.decrease"
    static let cloud = "cloud"
    static let folder = "folder"
}

/// Everything a song's menu offers, in its groups, for long presses on rows and cards and for
/// the player's More button. Rows that open more (adding to a playlist, rating, sharing a link)
/// open as their own menu; questions and the song's info open once the menu has closed.
struct SongActions: View {
    private let given: LibraryTrack?
    private let plain: Song
    var context = SongMenuContext()
    var selection: SongSelection?
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    @Environment(Downloads.self) private var downloads
    @Environment(Player.self) private var player

    /// The menu for a plain song, as the server lists it.
    init(song: Song, context: SongMenuContext = SongMenuContext(), selection: SongSelection? = nil) {
        given = nil
        plain = song
        self.context = context
        self.selection = selection
    }

    init(track: LibraryTrack, context: SongMenuContext = SongMenuContext(), selection: SongSelection? = nil) {
        given = track
        plain = track.asSong
        self.context = context
        self.selection = selection
    }

    private var state: LibraryState { actions.state }
    private var track: LibraryTrack { given ?? state.provisional(plain) }

    var body: some View {
        let groups = songMenuGroups(offered)
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            Section {
                ForEach(group, id: \.self) { action in row(action) }
            }
        }
    }

    private var song: Song { plain }

    private var offered: [SongAction] {
        var context = self.context
        if selection != nil { context.selecting = selection?.active ?? false }
        let place = menuPlace(context, albumId: track.albumId, artistId: track.artistId)
        let kept = state.kept.available ? state.kept.status(track.id) : nil
        return songActions(
            find: track.isFound,
            radio: true,
            share: state.canShare && track.serverSongId != nil,
            offline: state.kept.available && (!track.onPhone || kept != nil),
            place: place,
            phone: false,
            lastPlaylist: state.lastPlaylist != nil,
            upgrade: actions.canUpgrade(track),
            findSongs: downloads.keepsLog && track.serverSongId != nil,
            disk: actions.canDeleteFromDisk(track))
    }

    @ViewBuilder
    private func row(_ action: SongAction) -> some View {
        switch action {
        case .playNext:
            Button { player.playNext([song]) } label: { Label("Play next", systemImage: MenuIcon.playNext) }
        case .addToQueue:
            Button { player.append([song]) } label: { Label("Add to queue", systemImage: MenuIcon.addToQueue) }
        case .startRadio:
            Button { Task { await actions.startRadio([song]) } } label: { Label("Start radio", systemImage: MenuIcon.radio) }
        case .download:
            let state = downloads.state(song.id)
            Button { Task { _ = await downloads.request(song) } } label: {
                Label(downloadLabel(state), systemImage: state == .done ? MenuIcon.check : MenuIcon.addToLibrary)
            }
            .disabled(state != .none)
        case .requestCopy, .shareFile, .setAsSound, .deleteFromPhone, .removeFromMyLibrary:
            EmptyView()
        case .addToLastPlaylist:
            if let last = state.lastPlaylist {
                Button { Task { await actions.add([track], to: last) } } label: {
                    Label("Add to last playlist: \(last.name)", systemImage: MenuIcon.addToPlaylist)
                }
            }
        case .addToPlaylist:
            Menu {
                PlaylistPickerItems(tracks: [track])
            } label: {
                Label("Add to playlist", systemImage: MenuIcon.addToPlaylist)
            }
        case .removeFromPlaylist:
            Button {
                if let id = context.playlistId, let item = context.playlistItemId,
                   let playlist = state.playlists.first(where: { $0.id == id }) {
                    actions.remove([item], from: playlist)
                }
            } label: { Label("Remove from this playlist", systemImage: MenuIcon.removeFromPlaylist) }
        case .select:
            Button { selection?.start(context.selectKey ?? track.id) } label: { Label("Select", systemImage: MenuIcon.select) }
        case .keepOffline:
            let kept = state.kept.status(track.id)
            Button {
                switch kept?.status {
                case nil: state.kept.download([track.id])
                case .failed: state.kept.retry(track.id)
                default: state.kept.remove(track.id)
                }
            } label: {
                Label(keepOfflineLabel(kept?.status, byHand: kept?.byHand ?? false), systemImage: keptIcon(kept?.status))
            }
            .disabled(!keepOfflineEnabled(kept?.status, byHand: kept?.byHand ?? false))
        case .findFlac:
            Button { actions.findHigherQuality([track]) } label: { Label(findHigherQualityWords, systemImage: MenuIcon.lossless) }
        case .share:
            Menu {
                ShareLinkItems(ids: [song.id], title: track.title)
            } label: {
                Label("Share link", systemImage: MenuIcon.share)
            }
        case .like:
            let liked = state.likedIds.contains(track.id)
            Button { actions.toggleLike(track) } label: {
                Label(liked ? "Remove from Liked songs" : "Add to Liked songs", systemImage: liked ? MenuIcon.liked : MenuIcon.like)
            }
        case .rate:
            let rating = state.rating(of: track)
            Menu {
                RateItems(track: track, rating: rating)
            } label: {
                Label {
                    Text("Rate")
                    if let stars = starsLabel(rating) { Text(stars) }
                } icon: {
                    Image(systemName: rating > 0 ? MenuIcon.starFilled : MenuIcon.star)
                }
            }
        case .goToAlbum:
            Button {
                router.go(.album(Album(id: track.albumId, name: track.album, artist: track.artist, coverArt: track.coverId)))
            } label: { Label("Go to album", systemImage: MenuIcon.album) }
            .disabled(track.albumId.isEmpty)
        case .goToArtist:
            Button { router.go(.artist(id: track.artistId, name: track.artist)) } label: {
                Label("Go to artist", systemImage: MenuIcon.artist)
            }
            .disabled(track.artistId.isEmpty)
        case .deleteFromDisk:
            Button(role: .destructive) { actions.deleteFromDisk([track]) } label: {
                Label(deleteFromDiskWords, systemImage: MenuIcon.delete)
            }
        case .info:
            Button { actions.songInfo = LibraryActions.InfoTarget(track: track, song: song) } label: {
                Label("Song info", systemImage: MenuIcon.info)
            }
        case .findSongs:
            Button {
                if let id = track.serverSongId {
                    router.serverDownloads = .find(id: id, title: track.title, from: nil)
                } else {
                    router.show("This server has no copy of the song to look for")
                }
            } label: { Label("Find songs", systemImage: MenuIcon.search) }
        }
    }

    private func keptIcon(_ status: DownloadStatus?) -> String {
        switch status {
        case .queued, .downloading: MenuIcon.downloading
        case .done: MenuIcon.downloaded
        case nil, .failed: MenuIcon.download
        }
    }
}

/// The five stars for rating a song, side by side. A tap sets that many stars; tapping the star
/// the song already has takes the rating off.
struct RateItems: View {
    let track: LibraryTrack
    let rating: Int
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        ControlGroup {
            ForEach(1...5, id: \.self) { star in
                Button { actions.rate(track, nextRating(current: rating, tapped: star)) } label: {
                    Image(systemName: star <= rating ? MenuIcon.starFilled : MenuIcon.star)
                }
                .accessibilityLabel(star == 1 ? "1 star" : "\(star) stars")
                .accessibilityAddTraits(star == rating ? .isSelected : [])
            }
        }
        .controlGroupStyle(.palette)
    }
}

/// The playlists to add songs to: "New playlist" first, then every playlist shown with this
/// server, those added to most recently first.
struct PlaylistPickerItems: View {
    let tracks: [LibraryTrack]
    /// Runs once a playlist or a new one is picked.
    var picked: (() -> Void)?
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        Button {
            actions.newPlaylist(with: tracks)
            picked?()
        } label: { Label("New playlist", systemImage: MenuIcon.addToLibrary) }
        Section {
            ForEach(actions.state.pickablePlaylists) { playlist in
                Button {
                    Task { await actions.add(tracks, to: playlist) }
                    picked?()
                } label: {
                    Label {
                        Text(playlist.name)
                        Text(songsCount(playlist.songCount))
                    } icon: {
                        Image(systemName: playlist.onServer ? MenuIcon.cloud : "music.note.list")
                    }
                }
                .accessibilityHint(playlist.onServer ? "On your server" : "")
            }
        }
    }
}

/// How long a shared link lasts, under the note that anyone with it can listen.
struct ShareLinkItems: View {
    let ids: [String]
    let title: String
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        Section("Anyone with the link can listen.") {}
        Section("Link expires") {
            ForEach(LibraryActions.Expiry.allCases, id: \.self) { expiry in
                Button(expiry.label) { Task { await actions.share(ids: ids, title: title, expiry: expiry) } }
            }
        }
    }
}

/// The song a menu is about, over its menu: small artwork, the title and the artist.
struct MenuHeader: View {
    let artwork: String?
    let title: String
    let line: String
    var round = false

    var body: some View {
        HStack(spacing: 12) {
            ArtCover(artwork: artwork, size: 40, radius: round ? 20 : OctoRadius.artS)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(2)
                Text(line).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(width: 288, alignment: .leading)
        .background(OctoColor.backgroundTertiary)
    }
}

// MARK: Collections

/// Everything an album's, artist's or playlist's menu offers, in its groups.
struct CollectionActions: View {
    let target: CollectionTarget
    var album: LibraryAlbum?
    var artist: LibraryArtist?
    var playlist: PlaylistSummary?
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router

    private var state: LibraryState { actions.state }

    var body: some View {
        let groups = collectionMenuGroups(offered)
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            Section {
                ForEach(group, id: \.self) { action in row(action) }
            }
        }
    }

    private var kind: String {
        switch target {
        case .album: "album"
        case .artist: "artist"
        case .playlist: "playlist"
        }
    }

    private var itemId: String {
        switch target {
        case .album(let id), .artist(let id), .playlist(let id): id
        }
    }

    private var offered: [CollectionAction] {
        let spot = state.pinSpot(kind: kind, id: itemId)
        switch target {
        case .album(let id):
            return albumActions(canDownload: state.kept.available, favorite: state.favoriteAlbumIds.contains(id), pin: spot,
                                radio: true, lossy: state.fileActions?.canUpgrade == true ? 1 : 0)
        case .artist(let id):
            return artistActions(radio: true, favorite: state.favoriteArtistIds.contains(id), pin: spot)
        case .playlist:
            return playlistActions(empty: (playlist?.songCount ?? 0) == 0, pin: spot)
        }
    }

    private func withSongs(_ use: @escaping @MainActor ([LibraryTrack]) -> Void) {
        Task {
            let tracks = await state.songs(of: target)
            if !tracks.isEmpty { use(tracks) }
        }
    }

    private var pinKey: String { searchKey(album?.title ?? artist?.name ?? playlist?.name ?? "") }

    @ViewBuilder
    private func row(_ action: CollectionAction) -> some View {
        switch action {
        case .play:
            Button { withSongs { actions.play($0) } } label: { Label("Play", systemImage: MenuIcon.play) }
        case .shuffle:
            Button { withSongs { actions.play($0, shuffled: true) } } label: { Label("Shuffle", systemImage: MenuIcon.shuffle) }
        case .playNext:
            Button { withSongs { actions.playNext($0) } } label: { Label("Play next", systemImage: MenuIcon.playNext) }
        case .addToQueue:
            Button { withSongs { actions.addToQueue($0) } } label: { Label("Add to queue", systemImage: MenuIcon.addToQueue) }
        case .startRadio:
            Button {
                Task {
                    switch target {
                    case .album(let id): await actions.startAlbumRadio(id)
                    case .artist(let id): await actions.startArtistRadio(id)
                    case .playlist: break
                    }
                }
            } label: { Label("Start radio", systemImage: MenuIcon.radio) }
        case .addToPlaylist:
            Menu {
                CollectionPlaylistItems(target: target)
            } label: { Label("Add to playlist", systemImage: MenuIcon.addToPlaylist) }
        case .download:
            Button { withSongs { state.kept.download($0.filter { !$0.onPhone }.map(\.id)) } } label: {
                Label("Download", systemImage: MenuIcon.download)
            }
        case .findFlac:
            Button {
                if case .album(let id) = target { actions.askFindHigherQuality(albumId: id) }
            } label: { Label(findHigherQualityWords, systemImage: MenuIcon.lossless) }
        case .addToFavorites, .removeFromFavorites:
            let on = action == .addToFavorites
            Button {
                if let album { actions.setFavorite(album: album, on) }
                if let artist { actions.setFavorite(artist: artist, on) }
            } label: {
                Label(on ? "Add to favorites" : "Remove from favorites", systemImage: on ? MenuIcon.like : MenuIcon.liked)
            }
        case .pinToHome:
            Button { actions.pin(kind: kind, id: itemId, key: pinKey) } label: { Label("Pin to Home", systemImage: MenuIcon.pin) }
        case .unpin:
            Button { actions.unpin(kind: kind, id: itemId) } label: { Label("Unpin", systemImage: MenuIcon.pin) }
        case .moveToFront:
            Button { actions.moveToFront(kind: kind, id: itemId) } label: { Label("Move to front", systemImage: MenuIcon.pin) }
        case .goToArtist:
            Button {
                if let album { router.go(.artist(id: album.artistId, name: album.artist)) }
            } label: { Label("Go to artist", systemImage: MenuIcon.artist) }
        case .rename:
            Button { if let playlist { actions.rename(playlist) } } label: { Label("Rename", systemImage: MenuIcon.rename) }
        case .duplicate:
            Button { if let playlist { actions.duplicate(playlist) } } label: { Label("Duplicate", systemImage: MenuIcon.addToPlaylist) }
        case .delete:
            Button(role: .destructive) { if let playlist { actions.delete(playlist) } } label: {
                Label("Delete", systemImage: MenuIcon.delete)
            }
        }
    }
}

/// The playlist picker for a whole collection: the songs are gathered once one is picked.
struct CollectionPlaylistItems: View {
    let target: CollectionTarget
    @Environment(LibraryActions.self) private var actions

    var body: some View {
        Button {
            Task { actions.newPlaylist(with: await actions.state.songs(of: target)) }
        } label: { Label("New playlist", systemImage: MenuIcon.addToLibrary) }
        Section {
            ForEach(actions.state.pickablePlaylists) { playlist in
                Button {
                    Task { await actions.add(await actions.state.songs(of: target), to: playlist) }
                } label: {
                    Label {
                        Text(playlist.name)
                        Text(songsCount(playlist.songCount))
                    } icon: {
                        Image(systemName: playlist.onServer ? MenuIcon.cloud : "music.note.list")
                    }
                }
            }
        }
    }
}

// MARK: Song info

/// Everything known about a song, as plain labelled lines. Read once as it opens.
struct SongInfoSheet: View {
    let target: LibraryActions.InfoTarget
    @Environment(Library.self) private var library
    @Environment(Session.self) private var session
    @Environment(LibraryActions.self) private var actions
    @State private var lines: [InfoLine]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let lines {
                        HStack(spacing: 12) {
                            ArtCover(artwork: target.track?.artwork, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(target.song.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                                Text(target.song.byline).font(.octoCaption).foregroundStyle(OctoColor.textMuted).lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in SongInfoRow(line: line) }
                    } else {
                        Text("Reading the song")
                            .font(.octoCaption)
                            .foregroundStyle(OctoColor.textMuted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                }
                .padding(.bottom, 8)
            }
            .navigationTitle("Song info")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { lines = await read() }
    }

    private func read() async -> [InfoLine] {
        let song = target.song
        var facts = SongInfoFacts(title: song.title, artist: song.artist ?? song.byline, album: song.album ?? "")
        facts.year = song.year
        facts.genre = song.genre ?? ""
        facts.trackNo = song.track
        facts.discNo = song.discNumber
        facts.durationMs = Int64(song.duration) * 1_000
        facts.mimeType = mimeTypeOf(contentType: song.contentType, suffix: song.suffix)
        facts.bitrate = song.bitRate.map { $0 * 1_000 }
        facts.sampleRate = song.samplingRate
        facts.bitDepth = song.bitDepth
        facts.suggestedBy = song.octoSuggestedBy
        facts.explicit = song.explicitStatus.map { $0 == "explicit" }
        if let gain = song.replayGain {
            facts.trackGain = gain.trackGain
            facts.albumGain = gain.albumGain
            facts.trackPeak = gain.trackPeak
            facts.albumPeak = gain.albumPeak
        }
        guard let given = target.track, !given.isFound else {
            facts.source = .found
            return infoLines(facts)
        }
        let track = await actions.state.resolved(given)
        let copies = await library.copies(track.id)
        let server = copies.first { isServerSource($0.sourceId) }
        let details = await library.details(track.id)
        let played = await library.playedTracks().first { $0.track.id == track.id }
        let album = await library.album(track.albumId)
        facts.title = track.title
        facts.artist = track.artist
        facts.album = track.album
        facts.albumArtist = album?.artist
        facts.year = details.year ?? track.year
        facts.originalYear = details.originalYear
        facts.genre = track.genre
        facts.genres = details.genres
        facts.composer = details.composer
        facts.bpm = details.bpm
        facts.comment = details.comment
        facts.explicit = details.explicit ?? track.explicit
        facts.discTitle = details.discTitle
        facts.mbRecordingId = details.mbRecordingId
        facts.mbAlbumId = details.mbAlbumId
        facts.mbReleaseGroupId = details.mbReleaseGroupId
        facts.mbArtistIds = details.mbArtistIds
        facts.trackNo = track.trackNo
        facts.discNo = track.discNo
        facts.durationMs = track.durationMs
        facts.mimeType = server?.mimeType ?? track.mimeType
        facts.sizeBytes = server?.sizeBytes ?? track.sizeBytes
        facts.bitrate = server?.bitrate.map { $0 < 10_000 ? $0 * 1_000 : $0 } ?? facts.bitrate
        facts.sampleRate = server?.sampleRate ?? facts.sampleRate
        facts.bitDepth = server?.bitDepth ?? facts.bitDepth
        let gains = copies.first { $0.trackGain != nil || $0.albumGain != nil }
        if let gains {
            facts.trackGain = gains.trackGain.map(Double.init)
            facts.albumGain = gains.albumGain.map(Double.init)
            facts.trackPeak = gains.trackPeak.map(Double.init)
            facts.albumPeak = gains.albumPeak.map(Double.init)
        }
        facts.addedAtSeconds = track.addedAt
        facts.plays = played?.plays ?? 0
        facts.lastPlayedAt = played?.lastPlayedAt ?? 0
        facts.rating = actions.state.rating(of: track)
        facts.source = track.onPhone ? .phone(path: nil) : .server(name: serverName, downloadedTo: nil)
        return infoLines(facts)
    }

    /// "Octo" for an Octo server, else the server type with its first letter upper-cased, else
    /// the host.
    private var serverName: String? {
        if session.isOcto { return "Octo" }
        if let type = session.profile?.info.type, !type.isEmpty { return type.prefix(1).uppercased() + type.dropFirst() }
        return session.client?.baseURL.host
    }
}

/// One line of the info page: its label, its value, and a Copy button for copyable ones.
private struct SongInfoRow: View {
    let line: InfoLine
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(line.label)
                .font(.octoCaption)
                .foregroundStyle(OctoColor.textMuted)
                .frame(width: 92, alignment: .leading)
                .padding(.top, 2)
            Text(line.value)
                .font(.octoBodySmall)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if line.copyable {
                Button(copied ? "Copied" : "Copy") {
                    UIPasteboard.general.string = line.value
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        copied = false
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
    }
}
