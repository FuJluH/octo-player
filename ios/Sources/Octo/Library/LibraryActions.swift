import Foundation
import Observation
import OctoKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the menus, the rows and the selection bar do beyond a single call: playing, radios,
/// likes and ratings, adding to playlists, links, phone files, deleting from disk and finding
/// better copies. The menus are menu content (`LibraryMenus.swift`); what they cannot hold opens
/// from here as an alert or a sheet.
@MainActor
@Observable
final class LibraryActions {
    /// Something to hand to the phone's share sheet.
    struct ShareItem: Identifiable {
        let id = UUID()
        var items: [Any]
        var subject: String?
    }

    var shareItem: ShareItem?
    /// The link being made, while one is.
    private(set) var makingLink: MakingLink?
    /// A playlist to write as an M3U file, by the phone's file picker.
    var export: PlaylistExport?
    /// Songs being looked for at a better copy, by server id.
    private(set) var upgrading = Set<String>()
    /// A name being asked for.
    var naming: NameRequest?
    /// Songs on a playlist already, asked about before they go on again.
    var addAsk: AddAsk?
    /// A question before an action.
    var question: Question?
    /// The song whose info sheet is open.
    var info: InfoRequest?
    /// Picked songs to add to a playlist chosen on a sheet.
    var playlistPick: PlaylistPick?
    /// A menu laid out on a sheet.
    var menuPreview: MenuPreview?
    /// What album menus know of their songs, by album id.
    private(set) var albumFacts: [String: AlbumFacts] = [:]

    /// The one in use, for steps run from outside the pages.
    static weak var current: LibraryActions?

    @ObservationIgnored let state: LibraryState
    @ObservationIgnored let player: Player
    @ObservationIgnored let router: Router
    @ObservationIgnored let session: Session
    @ObservationIgnored weak var selectionBar: SelectionBarState?
    /// The library's part of a backup, kept here since backups hold it weakly.
    @ObservationIgnored private var backups: LibraryBackups?

    init(state: LibraryState, player: Player, router: Router, session: Session, selection: SelectionActions,
         selectionBar: SelectionBarState) {
        self.state = state
        self.player = player
        self.router = router
        self.session = session
        self.selectionBar = selectionBar
        Self.current = self
        state.files.router = router
        let backups = LibraryBackups(actions: self)
        self.backups = backups
        Backups.shared.library = backups
        fill(selection)
        #if DEBUG
        LibraryDrive.install(router: router)
        #endif
    }

    private var library: Library { state.library }
    private var data: DataServices { state.data }

    /// Gives the selection bar what the library does with picked songs.
    private func fill(_ selection: SelectionActions) {
        let state = state
        selection.addToPlaylist = { [weak self] songs in
            guard let self else { return }
            self.playlistPick = PlaylistPick(source: .tracks(state.tracks(for: songs)))
        }
        selection.download = { songs in
            state.offline.download(state.tracks(for: songs).filter { !$0.onPhone }.map(\.id))
        }
        selection.onPhone = { song in state.tracks(for: [song]).first?.onPhone ?? false }
        selection.shareFiles = { [weak self] songs in self?.shareFiles(state.tracks(for: songs)) }
        selection.deleteFromPhone = { [weak self] songs in self?.deleteFromPhone(state.tracks(for: songs)) }
        selection.deletableFromDisk = { [weak self] songs in
            guard let self else { return [] }
            return state.tracks(for: songs).filter(self.canDeleteFromDisk).map(\.id)
        }
        selection.askDeleteFromDisk = { [weak self] songs in self?.askDeleteFromDisk(state.tracks(for: songs)) }
        selection.setLiked = { [weak self] songs, on in self?.setLiked(state.tracks(for: songs), on) }
        selection.isLiked = { song in state.tracks(for: [song]).first.map { state.likedIds.contains($0.id) } ?? false }
    }

    // MARK: Menus

    /// Shows the song info sheet.
    func showInfo(_ subject: SongSubject) { info = InfoRequest(subject: subject) }

    /// Lays a menu out on a sheet.
    func previewMenu(_ content: MenuPreview.Content) { menuPreview = MenuPreview(content: content) }

    /// Reads a collection's songs, then acts on them when there are any.
    func withSongs(of target: CollectionTarget, _ use: @escaping @MainActor ([LibraryTrack]) -> Void) {
        let state = state
        Task {
            let tracks = await state.songs(of: target)
            if !tracks.isEmpty { use(tracks) }
        }
    }

    /// Downloads a collection's songs that are only on a server and not downloaded yet.
    func downloadSongs(of target: CollectionTarget) {
        let state = state
        let router = router
        withSongs(of: target) { tracks in
            let wanted = tracks.filter { !$0.onPhone && !$0.isFound && state.kept($0.id) == nil }
            if wanted.isEmpty {
                router.show("Every song here is on this phone already")
            } else {
                state.offline.download(wanted.map(\.id))
            }
        }
    }

    /// Reads what an album's menu needs from its songs, once until the library changes.
    func loadAlbumFacts(_ albumId: String) {
        guard albumFacts[albumId] == nil else { return }
        let library = library
        Task {
            let tracks = await library.albumTracks(albumId)
            albumFacts[albumId] = AlbumFacts(serverOnly: tracks.filter { !$0.onPhone }.map(\.id),
                                             lossy: tracks.filter(canUpgrade).count)
        }
    }

    /// Forgets what album menus knew, when the library changes.
    func forgetAlbumFacts() { if !albumFacts.isEmpty { albumFacts = [:] } }

    // MARK: Playing

    /// Plays library songs from one of them, by their library ids, so the player takes each one's
    /// best copy. `source` names the list they play from, like an album's title.
    func play(_ tracks: [LibraryTrack], from start: Int = 0, shuffled: Bool = false, source: String? = nil) {
        guard !tracks.isEmpty else { return }
        player.play(ids: tracks.map(\.id), from: start, name: source, shuffled: shuffled)
    }

    func playNext(_ tracks: [LibraryTrack]) {
        if !tracks.isEmpty { player.playNext(tracks.map(\.queueSong)) }
    }

    func addToQueue(_ tracks: [LibraryTrack]) {
        if !tracks.isEmpty { player.append(tracks.map(\.queueSong)) }
    }

    /// Plays a song next, from a swipe or a screen reader, with an Undo that takes that one song
    /// back out.
    func playNextUndoable(_ song: Song) {
        let router = router
        player.playNextUndoable([song]) { undo in
            router.show("Playing next", action: "Undo") { undo() }
        }
    }

    /// Plays the song then up to 50 songs like it, in place of the queue. A song found online the
    /// library has not met yet starts the player's own radio from it.
    func startRadio(_ track: LibraryTrack, song: Song) async {
        let known = await library.songs(ids: [track.id]).first
        if known == nil, track.isFound {
            await player.startRadio(from: song)
            return
        }
        await radio([known ?? track], exclude: [])
    }

    /// The artist page's radio: their songs as the page lists them, the most played first, at most
    /// 200 of them as seeds.
    func startRadio(seeds: [LibraryTrack]) async {
        await radio(Array(seeds.prefix(200)), exclude: [])
    }

    /// Plays `seed`, then songs like the seeds, in place of the queue, from "<title> radio".
    /// Nothing found says so and plays nothing.
    private func radio(_ seeds: [LibraryTrack], exclude: Set<String>) async {
        guard let seed = seeds.first else { return }
        let ids = await LibraryRadio(data: data).songsLike(seeds, count: 50, exclude: exclude, before: [seed.id])
        if ids.isEmpty {
            router.show("No similar songs found")
            return
        }
        player.play(ids: [seed.id] + ids, name: "\(seed.title) radio")
    }

    /// A radio from an album: its most played song here, else its first, then the album's songs as
    /// seeds; songs like the album play, leaving the rest of the album out.
    func startAlbumRadio(_ albumId: String) async {
        let tracks = await library.albumTracks(albumId)
        let played = await library.playedTracks().filter { $0.track.albumId == albumId }
        guard let seed = byPlayCount(played, limit: 1).first ?? tracks.first else {
            router.show("No songs to start a radio from")
            return
        }
        await radio([seed] + tracks.filter { $0.id != seed.id }, exclude: Set(tracks.map(\.id)))
    }

    /// A radio from an artist: their most played song, else their first, then up to 200 of their
    /// songs as seeds; songs like theirs play, theirs among them.
    func startArtistRadio(_ artistId: String) async {
        let played = await library.playedTracks().filter { $0.track.artistId == artistId }
        let tracks = await state.songs(of: .artist(artistId))
        guard let seed = byPlayCount(played, limit: 1).first ?? tracks.first else {
            router.show("No songs to start a radio from")
            return
        }
        await radio([seed] + tracks.filter { $0.id != seed.id }.prefix(200), exclude: [seed.id])
    }

    // MARK: Likes, ratings, favorites and pins

    func isLiked(_ track: LibraryTrack) -> Bool { state.likedIds.contains(track.id) }

    /// Likes or unlikes library songs, touching only those that differ.
    func setLiked(_ tracks: [LibraryTrack], _ on: Bool) {
        for track in tracks where !track.isFound && isLiked(track) != on { data.likes.toggle(track.id) }
    }

    func toggleLike(_ track: LibraryTrack) {
        guard !track.isFound else { return }
        data.likes.toggle(track.id)
    }

    /// Takes a like away, with an Undo that puts it back in its place.
    func unlikeUndoable(_ track: LibraryTrack) {
        let router = router
        let likes = data.likes
        likes.unlike(track.id) { row in
            router.show("Removed from Liked songs", action: "Undo") { likes.restore(row) }
        }
    }

    func rate(_ track: LibraryTrack, _ rating: Int) {
        guard !track.isFound else { return }
        state.noteRating(track.id, rating)
        data.ratings.rate(track.id, rating)
    }

    func setFavorite(album id: String, _ on: Bool) { data.favorites.set(.album, id, favorite: on) }

    func setFavorite(artist id: String, _ on: Bool) { data.favorites.set(.artist, id, favorite: on) }

    func pin(_ kind: PinKind, _ id: String) {
        Task {
            if !(await data.pins.pin(kind, id)) { router.show("Home holds up to \(pinLimit) pins. Unpin one first.") }
        }
    }

    func unpin(_ kind: PinKind, _ id: String) { Task { await data.pins.unpin(kind, id) } }

    func moveToFront(_ kind: PinKind, _ id: String) { Task { await data.pins.moveToFront(kind, id) } }

    // MARK: Playlists

    /// What adding these songs to a playlist would do; only library songs go on a playlist.
    func planAdding(_ tracks: [LibraryTrack], to playlist: PlaylistSummary) async -> (AddPlan, [LibraryTrack]) {
        let library = tracks.filter { !$0.isFound }
        let onPlaylist = Set(await state.playlistTracks(playlist.id).map(\.track.id))
        return (planAdd(library.map(\.id), onPlaylist: onPlaylist), library)
    }

    /// What adding the songs to a playlist would do, reading a collection's songs first.
    func plan(_ source: AddSource, to playlist: PlaylistSummary) async -> AddPlan {
        await planAdding(await tracks(of: source), to: playlist).0
    }

    private func tracks(of source: AddSource) async -> [LibraryTrack] {
        switch source {
        case .tracks(let given): given
        case .collection(let target): await state.songs(of: target)
        }
    }

    /// Adds at once when none is on the playlist yet; otherwise asks first.
    func add(_ source: AddSource, to playlist: PlaylistSummary) {
        Task {
            let plan = await plan(source, to: playlist)
            if plan.asks {
                addAsk = AddAsk(playlist: playlist, plan: plan)
            } else if plan.songs.isEmpty {
                router.show("No library songs to add")
            } else {
                addNow(plan.songs, to: playlist)
            }
        }
    }

    /// Asks for a new playlist's name, then makes it with the songs.
    func askNewPlaylist(_ source: AddSource) { naming = newPlaylistRequest(source) }

    /// The name question for a new playlist; `made` runs once a name is given.
    func newPlaylistRequest(_ source: AddSource, made: (@MainActor () -> Void)? = nil) -> NameRequest {
        NameRequest(title: "New playlist", action: "Create") { [weak self] name in
            guard let self else { return }
            made?()
            Task { self.createPlaylist(name: name, tracks: await self.tracks(of: source)) }
        }
    }

    func askRename(_ playlist: PlaylistSummary) {
        naming = NameRequest(title: "Rename playlist", action: "Save", initial: playlist.name) { [weak self] name in
            self?.rename(playlist, to: name)
        }
    }

    /// Asks before a playlist goes; one kept with the server goes from there too. `deleted` runs
    /// once it is gone.
    func askDeletePlaylist(_ playlist: PlaylistSummary, deleted: (@MainActor () -> Void)? = nil) {
        question = Question(title: "Delete \"\(playlist.name)\"?",
                            detail: playlist.onServer ? "It is deleted from your server too. The songs stay in your library."
                                : "The songs stay in your library.",
                            confirm: "Delete") { [weak self] in
            self?.delete(playlist)
            deleted?()
        }
    }

    /// Asks a live list's new name.
    func askRename(_ list: LiveList, in store: LiveListStore) {
        let id = list.id
        naming = NameRequest(title: "Rename live list", action: "Save", initial: list.name, placeholder: "Live list name") { name in
            store.rename(id, to: name)
        }
    }

    /// Asks before a live list goes; its songs stay in the library.
    func askDelete(_ list: LiveList, in store: LiveListStore) {
        let id = list.id
        question = Question(title: "Delete \"\(list.name)\"?", detail: "The songs stay in your library.", confirm: "Delete") {
            store.remove(id)
        }
    }

    /// Adds songs at the end and says so, with an Undo that takes exactly those rows back out.
    func addNow(_ trackIds: [String], to playlist: PlaylistSummary) {
        guard !trackIds.isEmpty else { return }
        state.markRecent(playlist.id)
        let router = router
        let playlists = data.playlists
        playlists.add(playlist.id, trackIds: trackIds) { rows in
            router.show(addedMessage(playlist.name, rows.count), action: "Undo") {
                playlists.removeRows(playlist.id, itemIds: rows)
            }
        }
    }

    /// Makes a playlist with the songs (each once) and says so.
    @discardableResult
    func createPlaylist(name: String, tracks: [LibraryTrack]) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var seen = Set<String>()
        let songs = tracks.filter { !$0.isFound && seen.insert($0.id).inserted }
        let id = data.playlists.create(trimmed, trackIds: songs.map(\.id))
        if !songs.isEmpty {
            state.markRecent(id)
            router.show(addedMessage(trimmed, songs.count))
        }
        return id
    }

    func rename(_ playlist: PlaylistSummary, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        data.playlists.rename(playlist.id, trimmed)
    }

    func delete(_ playlist: PlaylistSummary) { data.playlists.delete(playlist.id) }

    /// A new playlist "<name> (copy)" with the same songs in the same order.
    func duplicate(_ playlist: PlaylistSummary) {
        Task {
            let ids = await state.playlistTracks(playlist.id).map(\.track.id)
            let name = playlistCopyName(playlist.name)
            data.playlists.create(name, trackIds: ids)
            router.show(copiedMessage(name))
        }
    }

    /// Takes rows out of a playlist, with one Undo that puts them all back in their places.
    func remove(_ itemIds: [Int64], from playlist: PlaylistSummary) {
        guard !itemIds.isEmpty else { return }
        let router = router
        let playlists = data.playlists
        playlists.removeAll(playlist.id, itemIds: itemIds) { rows in
            let words = rows.count == 1 ? "Removed from \(playlist.name)" : "Removed \(rows.count) songs from \(playlist.name)"
            router.show(words, action: "Undo") { playlists.restoreAll(playlist.id, rows: rows) }
        }
    }

    /// Moves a row into the place of the one it was dropped on.
    func move(_ itemId: Int64, onto targetId: Int64, in playlist: PlaylistSummary) {
        guard itemId != targetId else { return }
        data.playlists.move(playlist.id, itemId: itemId, targetId: targetId)
    }

    /// Makes a playlist kept only on the phone on the server too.
    func saveToServer(_ playlist: PlaylistSummary) { data.playlists.saveToServer(playlist.id) }

    /// Whether a playlist can be saved to the server: one is signed in and it is not there yet.
    func canSaveToServer(_ playlist: PlaylistSummary) -> Bool { session.client != nil && !playlist.onServer }

    /// Writes a playlist as an M3U file where the person picks.
    func exportPlaylist(_ playlist: PlaylistSummary) {
        Task {
            let tracks = await state.playlistTracks(playlist.id).map(\.track)
            let lines = tracks.map { track in
                M3uLine(seconds: Int(track.durationMs / 1_000), artist: track.artist, title: track.title,
                        location: track.uri.flatMap { $0.hasPrefix("http") ? nil : $0 } ?? fallbackLocation(artist: track.artist, title: track.title))
            }
            export = PlaylistExport(name: playlist.name, text: writeM3u(lines))
        }
    }

    // MARK: Downloads to the phone

    /// The download row's action: download, retry, or remove a download asked for by hand.
    func keepOfflineTapped(_ track: LibraryTrack) {
        switch state.kept(track.id)?.status {
        case nil: state.offline.download([track.id])
        case .failed: state.offline.retry(track.id)
        default: removeDownload(track.id)
        }
    }

    /// Lets go of a download, with an Undo that brings the file back.
    func removeDownload(_ trackId: String) {
        let router = router
        state.offline.remove(trackId) { restore in
            router.show("Download removed", action: "Undo") { restore() }
        }
    }

    // MARK: Links

    /// Makes a shared link and opens the phone's share sheet with it. Answers the words of a
    /// failure, or nil once the sheet is on its way. Only one link is made at a time: asking
    /// while one is being made does nothing.
    func share(_ target: ShareTarget, title: String, expiry: ShareExpiry) async -> String? {
        guard makingLink == nil else { return nil }
        makingLink = MakingLink(target: target, expiry: expiry)
        defer { makingLink = nil }
        let controls = data.controls
        guard session.inUse != nil else { return userMessage(OctoError.server(code: 0, message: noServerSignedIn)) }
        let id: String? = switch target {
        case .song(let trackId): await controls.shareableSongId(trackId)
        case .album(let albumId): await controls.shareableAlbumId(albumId)
        }
        guard let id else { return "This server has no copy of it to share." }
        do {
            let link = try await controls.createShare([id], description: title, expiry: expiry)
            guard !link.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return "The server made the link but did not say where it is."
            }
            shareItem = ShareItem(items: [link.url], subject: title)
            return nil
        } catch {
            return sharingUnavailable(error) ? "Sharing is switched off on this server." : userMessage(error)
        }
    }

    /// Makes a shared link from a menu; a failure says why.
    func makeLink(_ target: ShareTarget, title: String, expiry: ShareExpiry) {
        Task {
            if let words = await share(target, title: title, expiry: expiry) { router.show(words) }
        }
    }

    // MARK: Phone files

    /// Hands the songs' phone files to the share sheet; songs from the Music app's library are
    /// copied out first.
    func shareFiles(_ tracks: [LibraryTrack]) {
        let ids = tracks.filter(\.onPhone).map(\.id)
        guard !ids.isEmpty else { return }
        Task {
            let urls = await data.device.shareFiles(ids)
            if urls.isEmpty {
                router.show("Could not share the file")
            } else {
                shareItem = ShareItem(items: urls, subject: tracks.count == 1 ? tracks[0].title : nil)
            }
        }
    }

    /// Deletes the songs' phone files, asking first. On a yes the songs leave the queue, then
    /// their files go; when none could go, the queue is put back as it was. One delete at a time:
    /// another asked for while one runs is let go.
    func deleteFromPhone(_ tracks: [LibraryTrack]) {
        let songs = tracks.filter(\.onPhone)
        guard !songs.isEmpty, !deletingFromPhone else { return }
        question = Question(title: songs.count == 1 ? "Delete this song from the phone?" : "Delete \(songs.count) songs from the phone?",
                            detail: songs.count == 1 ? "Its file is removed for good" : "Their files are removed for good",
                            confirm: "Delete") { [weak self] in
            guard let self, !self.deletingFromPhone else { return }
            self.deletingFromPhone = true
            let ids = songs.map(\.id)
            let undo = self.player.removeSongs(Set(ids))
            Task {
                let outcome = await self.data.device.delete(ids)
                if outcome.removed == 0, let undo { self.player.undo(undo) }
                if let words = outcome.words { self.router.show(words) }
                self.deletingFromPhone = false
            }
        }
    }

    /// Whether a delete from the phone is under way.
    @ObservationIgnored private var deletingFromPhone = false

    // MARK: Deleting from disk

    /// Whether the server lets this user delete this song's copy from its disk.
    func canDeleteFromDisk(_ track: LibraryTrack) -> Bool {
        state.fileActions?.canRemove == true && !track.isFound && (track.serverSongId != nil || !track.onPhone)
    }

    /// The question before songs leave the server's disk, and its words.
    func deleteFromDiskQuestion(_ tracks: [LibraryTrack]) -> (title: String, body: String) {
        let songs = tracks.filter { !$0.isFound }
        return (deleteTitle(songs.count), deleteBody(deleteNames(songs.map(\.title)), keepDays: state.fileActions?.keepDays ?? 0))
    }

    /// Asks before songs leave the server's disk.
    func askDeleteFromDisk(_ tracks: [LibraryTrack]) {
        let songs = tracks.filter { !$0.isFound }
        guard !songs.isEmpty else { return }
        let words = deleteFromDiskQuestion(songs)
        let asked = state.files.server()
        question = Question(title: words.title, detail: words.body, confirm: "Delete", server: asked) { [weak self] in
            self?.deleteFromDisk(songs, on: asked)
        }
    }

    /// Deletes songs from the server's disk, then says so with an Undo; the answer goes to the
    /// server in use when it was asked, and switching server drops it.
    func deleteFromDisk(_ tracks: [LibraryTrack], on: String? = nil) {
        let songs = tracks.filter { !$0.isFound }
        guard !songs.isEmpty else { return }
        state.files.deleteFromDisk(songs.map(\.id), title: songs.count == 1 ? songs[0].title : nil, on: on ?? state.files.server())
    }

    // MARK: Better copies

    /// Whether the server could look for a better copy: an Octo server that can, for a library
    /// song whose server copy loses detail and is not looked for already.
    func canUpgrade(_ track: LibraryTrack) -> Bool {
        guard state.fileActions?.canUpgrade == true, !track.isFound, let id = track.serverSongId, !upgrading.contains(id) else {
            return false
        }
        guard let mime = track.mimeType, mime.lowercased().hasPrefix("audio/") else { return false }
        return !isLosslessMime(mime)
    }

    /// Asks the server to look for a better copy of each song, at most 50 at a time.
    func findHigherQuality(_ tracks: [LibraryTrack]) {
        guard let client = session.client else { return }
        let asks = tracks.filter(canUpgrade)
        guard !asks.isEmpty else { return }
        for track in asks { if let id = track.serverSongId { upgrading.insert(id) } }
        Task {
            var queued = 0
            var refused: [(String, String)] = []
            for track in asks.prefix(50) {
                guard let id = track.serverSongId else { continue }
                do {
                    let result = try await client.fileAction(id, action: "upgrade")
                    if result.state == "queued" { queued += 1 } else { refused.append((track.title, result.detail ?? "the server did not say why")) }
                } catch {
                    refused.append((track.title, userMessage(error)))
                }
            }
            var lines: [String] = []
            if queued > 0 { lines.append("Looking for higher quality for \(songsCount(queued))") }
            if refused.count == 1 {
                lines.append("Could not look for higher quality for \(refused[0].0): \(refused[0].1)")
            } else if refused.count > 1 {
                lines.append("Could not look for higher quality for \(songsCount(refused.count)): \(refused[0].1)")
            }
            let over = asks.count - 50
            if over > 0 { lines.append("At most 50 songs at a time, so \(songsCount(over)) \(over == 1 ? "was" : "were") left out") }
            if !lines.isEmpty { sayUpgrade(lines.joined(separator: ". ")) }
        }
    }

    /// A line about higher quality copies, with "Show" opening the server downloads when the
    /// server keeps their log.
    private func sayUpgrade(_ text: String) {
        let logs = session.client != nil && (session.profile?.extensions ?? []).contains("\(octoAcquisitions):\(octoDownloadLogVersion)")
        if logs {
            let router = router
            router.show(text, action: "Show") { router.showServerDownloads() }
        } else {
            router.show(text)
        }
    }

    /// Asks before an album's songs go to the server to be looked for at a better copy.
    func askFindHigherQuality(albumId: String) {
        Task {
            let asks = await library.albumTracks(albumId).filter(canUpgrade)
            if asks.isEmpty {
                router.show("Every song here is being looked for already")
                return
            }
            question = Question(title: findHigherQualityAsk(asks.count, source: state.fileActions?.upgradeSource),
                                detail: keepsOriginalWords, confirm: findHigherQualityWords, destructive: false) {
                self.findHigherQuality(asks)
                self.albumFacts[albumId] = nil
            }
        }
    }
}

/// What a link is made to: a library song or a library album, by library id.
enum ShareTarget: Hashable {
    case song(String)
    case album(String)
}

/// A link being made: what to, and how long it is to last.
struct MakingLink: Equatable {
    let target: ShareTarget
    let expiry: ShareExpiry
}

/// The song an info sheet is about.
struct InfoRequest: Identifiable {
    let id = UUID()
    let subject: SongSubject
}

/// Songs to add to a playlist picked on a sheet.
struct PlaylistPick: Identifiable {
    let id = UUID()
    let source: AddSource
}

/// What an album's menu knows of its songs: those only on a server, and how many a server could
/// look for at a better copy.
struct AlbumFacts {
    var serverOnly: [String]
    var lossy: Int
}

/// A playlist to write to a file the person picks.
struct PlaylistExport: Identifiable {
    let id = UUID()
    var name: String
    var text: String
}

/// The system pieces the library hands work to, over everything: its alerts, the song info and
/// playlist sheets, the share sheet and the file picker for exports. It also keeps the menus'
/// playlists, ratings and album facts fresh.
struct LibraryPresenter: ViewModifier {
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @Environment(Session.self) private var session

    func body(content: Content) -> some View {
        @Bindable var actions = actions
        return content
            .task(id: library.stamp(.library, .playlists, .ratings)) {
                actions.forgetAlbumFacts()
                await actions.state.refreshCaches()
            }
            .task(id: session.activeId) {
                // A question about another server's files no longer has anywhere to go.
                if let asked = actions.question?.server, asked != session.activeId { actions.question = nil }
                await actions.state.serverChanged()
            }
            .nameAlert($actions.naming)
            .addAskAlert($actions.addAsk) { ids, playlist in actions.addNow(ids, to: playlist) }
            .questionAlert($actions.question)
            .sheet(item: $actions.info) { request in SongInfoSheet(subject: request.subject) }
            .sheet(item: $actions.playlistPick) { pick in PlaylistPickerSheet(source: pick.source) }
            .sheet(item: $actions.menuPreview) { preview in MenuPreviewSheet(preview: preview) }
            .sheet(item: $actions.shareItem) { item in
                ActivitySheet(items: item.items, subject: item.subject)
                    .presentationDetents([.medium, .large])
            }
            .fileExporter(isPresented: Binding(get: { actions.export != nil }, set: { if !$0 { actions.export = nil } }),
                          document: actions.export.map { M3uDocument(text: $0.text) },
                          contentType: .m3uPlaylist, defaultFilename: actions.export.map { playlistFileName($0.name) }) { result in
                if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                    router.show("Could not export the playlist")
                }
                actions.export = nil
            }
    }
}

/// A playlist file as the phone's file picker writes it.
struct M3uDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.m3uPlaylist]
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.map { playlistText($0) } ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

/// The phone's share sheet.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    var subject: String?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let subject { sheet.setValue(subject, forKey: "subject") }
        return sheet
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
