import Foundation
import Observation
import OctoKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the menus, the rows and the selection bar do beyond a single call: playing, radios,
/// likes and ratings, adding to playlists with their questions, links, deleting from disk and
/// finding better copies, and the questions, forms and sheets those open after a menu closes.
@MainActor
@Observable
final class LibraryActions {
    /// A yes or no question, asked as an alert.
    struct Question: Identifiable {
        let id = UUID()
        var title: String
        var message: String?
        var confirm: String
        var destructive = false
        var cancel = "Cancel"
        var onConfirm: @MainActor () -> Void
        var onCancel: (@MainActor () -> Void)?
    }

    /// A choice between answers, asked as an action sheet.
    struct Choice: Identifiable {
        let id = UUID()
        var title: String
        var message: String?
        var answers: [(label: String, run: @MainActor () -> Void)]
    }

    /// A name to type, asked as an alert with a field.
    struct NameForm: Identifiable {
        let id = UUID()
        var title: String
        var placeholder: String
        var button: String
        var initial: String = ""
        var onSave: @MainActor (String) -> Void
    }

    /// Something to hand to the phone's share sheet.
    struct ShareItem: Identifiable {
        let id = UUID()
        var items: [Any]
        var subject: String?
    }

    /// A song whose info sheet is open.
    struct InfoTarget: Identifiable {
        var track: LibraryTrack?
        var song: Song
        var id: String { track?.id ?? song.id }
    }

    var question: Question?
    var choice: Choice?
    var nameForm: NameForm?
    var songInfo: InfoTarget?
    var shareItem: ShareItem?
    /// A playlist to write as an M3U file, by the phone's file picker.
    var export: PlaylistExport?
    /// Songs being looked for at a better copy, by server id.
    private(set) var upgrading = Set<String>()
    /// A menu shown as a sheet, when asked for from outside.
    var drivenMenu: DrivenMenu?

    /// The one in use, for steps run from outside the pages.
    static weak var current: LibraryActions?

    @ObservationIgnored let state: LibraryState
    @ObservationIgnored private let player: Player
    @ObservationIgnored private let router: Router
    @ObservationIgnored private let session: Session

    init(state: LibraryState, player: Player, router: Router, session: Session) {
        self.state = state
        self.player = player
        self.router = router
        self.session = session
        Self.current = self
        let backups = LibraryBackups(actions: self)
        self.backups = backups
        Backups.shared.library = backups
    }

    /// The library's part of a backup, kept here since backups hold it weakly.
    @ObservationIgnored private var backups: LibraryBackups?

    private var library: Library { state.library }

    // MARK: Playing

    /// Plays library songs from one of them.
    func play(_ tracks: [LibraryTrack], from start: Int = 0, shuffled: Bool = false) {
        Task {
            var songs = await state.playable(tracks)
            guard !songs.isEmpty else { return }
            if shuffled {
                songs.shuffle()
                player.play(songs, from: 0)
            } else {
                let first = tracks.indices.contains(start) ? tracks[start].asSong.title : nil
                let index = songs.firstIndex { $0.title == first } ?? min(start, songs.count - 1)
                player.play(songs, from: max(index, 0))
            }
        }
    }

    func playNext(_ tracks: [LibraryTrack]) {
        Task {
            let songs = await state.playable(tracks)
            if !songs.isEmpty { player.playNext(songs) }
        }
    }

    func addToQueue(_ tracks: [LibraryTrack]) {
        Task {
            let songs = await state.playable(tracks)
            if !songs.isEmpty { player.append(songs) }
        }
    }

    /// Plays a song next, from a swipe or a screen reader, with an Undo that takes that one song
    /// back out.
    func playNextUndoable(_ song: Song) {
        let before = player.snapshot
        let had = player.current != nil
        player.playNext([song])
        if had { router.show("Playing next", action: "Undo") { [player] in player.restore(before) } }
    }

    /// Plays the first seed then up to 50 songs like it, in place of the queue. Nothing found
    /// says so. `exclude` keeps songs out, like the rest of an album.
    func startRadio(_ seeds: [Song], exclude: Set<String> = []) async {
        guard let seed = seeds.first else { return }
        guard let client = session.client else {
            router.show("No similar songs found")
            return
        }
        let similar = ((try? await client.radio(from: seed.id, count: 50)) ?? [])
            .filter { $0.id != seed.id && !exclude.contains($0.id) }
        if similar.isEmpty {
            router.show("No similar songs found")
        } else {
            player.play([seed] + similar, from: 0, radio: seed)
        }
    }

    /// A radio from an album: its most played song here, else its first, then songs like the
    /// album, leaving the rest of the album out.
    func startAlbumRadio(_ albumId: String) async {
        let tracks = await library.albumTracks(albumId)
        let played = await library.playedTracks().filter { $0.track.albumId == albumId }
        guard let seed = byPlayCount(played, limit: 1).first ?? tracks.first else {
            router.show("No songs to start a radio from")
            return
        }
        let songs = await state.playable([seed])
        let exclude = Set(await state.playable(tracks).map(\.id))
        await startRadio(songs, exclude: exclude.subtracting(songs.map(\.id)))
    }

    /// A radio from an artist's most played song, or their first, then songs like theirs.
    func startArtistRadio(_ artistId: String) async {
        let played = await library.playedTracks().filter { $0.track.artistId == artistId }
        let tracks = await state.songs(of: .artist(artistId))
        guard let seed = byPlayCount(played, limit: 1).first ?? tracks.first else {
            router.show("No songs to start a radio from")
            return
        }
        await startRadio(await state.playable([seed]))
    }

    // MARK: Likes and ratings

    func isLiked(_ track: LibraryTrack) -> Bool { state.likedIds.contains(track.id) }

    func setLiked(_ tracks: [LibraryTrack], _ on: Bool, at time: Int64? = nil) {
        let songs = tracks.filter { !$0.isFound }
        guard !songs.isEmpty else { return }
        state.noteLiked(songs.map(\.id), on)
        Task { await state.writes.setLiked(songs, on, at: time) }
    }

    func toggleLike(_ track: LibraryTrack) { setLiked([track], !isLiked(track)) }

    func rate(_ track: LibraryTrack, _ rating: Int) {
        Task { await state.writes.setRating(track, rating) }
    }

    func setFavorite(album: LibraryAlbum, _ on: Bool) {
        state.noteFavorite(album: album.id, on)
        Task { await state.writes.setFavorite(album: album, on) }
    }

    func setFavorite(artist: LibraryArtist, _ on: Bool) {
        state.noteFavorite(artist: artist.id, on)
        Task { await state.writes.setFavorite(artist: artist, on) }
    }

    // MARK: Pins

    func pin(kind: String, id: String, key: String) {
        Task {
            if !(await state.writes.pin(kind: kind, id: id, key: key)) {
                router.show("Home holds up to \(pinLimit) pins. Unpin one first.")
            }
        }
    }

    func unpin(kind: String, id: String) { Task { await state.writes.unpin(kind: kind, id: id) } }

    func moveToFront(kind: String, id: String) { Task { await state.writes.moveToFront(kind: kind, id: id) } }

    // MARK: Adding to playlists

    /// Adds songs to a playlist, asking first when some are on it already.
    func add(_ tracks: [LibraryTrack], to playlist: PlaylistSummary) async {
        var seen = Set<String>()
        let library = tracks.filter { !$0.isFound && seen.insert($0.id).inserted }
        guard !library.isEmpty else { return }
        let onPlaylist = Set(await state.playlistTracks(playlist.id).map(\.track.id))
        let plan = planAdd(library.map(\.id), onPlaylist: onPlaylist)
        let byId = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let all = plan.songs.compactMap { byId[$0] }
        let fresh = plan.fresh.compactMap { byId[$0] }
        if !plan.asks {
            await addNow(all, to: playlist)
            return
        }
        let question = addAgainQuestion(playlist.name, plan)
        if plan.offersNewOnly {
            let newOnly: @MainActor () -> Void = { [weak self] in self?.addLater(fresh, to: playlist) }
            let every: @MainActor () -> Void = { [weak self] in self?.addLater(all, to: playlist) }
            choice = Choice(title: question, message: nil, answers: [(addNewOnes, newOnly), (addAgainChoice(plan), every)])
        } else {
            self.question = Question(title: question, confirm: addAgainChoice(plan)) { [weak self] in
                self?.addLater(all, to: playlist)
            }
        }
    }

    private func addLater(_ tracks: [LibraryTrack], to playlist: PlaylistSummary) {
        Task { await addNow(tracks, to: playlist) }
    }

    /// Adds at the end and says so, with an Undo that takes exactly those rows back out.
    private func addNow(_ tracks: [LibraryTrack], to playlist: PlaylistSummary) async {
        let before = await state.playlistTracks(playlist.id)
        let start = (before.map(\.itemId).max() ?? 0) + 1
        let added = tracks.enumerated().map { PlaylistTrack(itemId: start + Int64($0.offset), track: $0.element) }
        state.setPlaylistEdit(playlist.id, before + added)
        state.markRecent(playlist.id)
        do {
            try await state.writes.appendToPlaylist(playlist.id, tracks: tracks)
        } catch {
            state.setPlaylistEdit(playlist.id, before)
            router.show(userMessage(error))
            return
        }
        router.show(addedMessage(playlist.name, tracks.count), action: "Undo") { [weak self] in
            guard let self else { return }
            Task {
                let now = await self.state.playlistTracks(playlist.id)
                let addedIds = Set(added.map(\.itemId))
                let kept = now.filter { !addedIds.contains($0.itemId) }
                self.state.setPlaylistEdit(playlist.id, kept)
                await self.state.writes.setPlaylistSongs(playlist.id, tracks: kept.map(\.track))
            }
        }
    }

    /// Asks for a name, then makes a playlist with the songs (each once) and says so.
    func newPlaylist(with tracks: [LibraryTrack]) {
        nameForm = NameForm(title: "New playlist", placeholder: "Playlist name", button: "Create") { [weak self] name in
            guard let self else { return }
            Task { await self.createPlaylist(name: name, tracks: tracks) }
        }
    }

    @discardableResult
    func createPlaylist(name: String, tracks: [LibraryTrack]) async -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var seen = Set<String>()
        let songs = tracks.filter { !$0.isFound && seen.insert($0.id).inserted }
        do {
            let id = try await state.writes.createPlaylist(name: trimmed, tracks: songs)
            if let id { state.markRecent(id) }
            if !songs.isEmpty { router.show(addedMessage(trimmed, songs.count)) }
            await state.refreshCaches()
            return id
        } catch {
            router.show(userMessage(error))
            return nil
        }
    }

    func rename(_ playlist: PlaylistSummary) {
        nameForm = NameForm(title: "Rename playlist", placeholder: "Playlist name", button: "Save", initial: playlist.name) { [weak self] name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let self, !trimmed.isEmpty else { return }
            Task { await self.state.writes.renamePlaylist(playlist.id, name: trimmed) }
        }
    }

    /// Asks before a playlist goes; one kept with the server goes from there too.
    func delete(_ playlist: PlaylistSummary, then: (@MainActor () -> Void)? = nil) {
        question = Question(
            title: "Delete \"\(playlist.name)\"?",
            message: playlist.onServer ? "It is deleted from your server too. The songs stay in your library." : "The songs stay in your library.",
            confirm: "Delete", destructive: true
        ) { [weak self] in
            Task {
                await self?.state.writes.deletePlaylist(playlist.id)
                then?()
            }
        }
    }

    /// A new playlist "<name> (copy)" with the same songs in the same order.
    func duplicate(_ playlist: PlaylistSummary) {
        Task {
            let tracks = await state.playlistTracks(playlist.id).map(\.track)
            let name = playlistCopyName(playlist.name)
            let silent = tracks
            do {
                let id = try await state.writes.createPlaylist(name: name, tracks: silent)
                if id != nil { router.show(copiedMessage(name)) }
            } catch {
                router.show(userMessage(error))
            }
        }
    }

    /// Takes rows out of a playlist, with one Undo that puts them all back in their places.
    func remove(_ itemIds: Set<Int64>, from playlist: PlaylistSummary) {
        Task {
            let before = await state.playlistTracks(playlist.id)
            let removed = before.filter { itemIds.contains($0.itemId) }
            guard !removed.isEmpty else { return }
            let kept = before.filter { !itemIds.contains($0.itemId) }
            state.setPlaylistEdit(playlist.id, kept)
            await state.writes.setPlaylistSongs(playlist.id, tracks: kept.map(\.track))
            let words = removed.count == 1 ? "Removed from \(playlist.name)" : "Removed \(removed.count) songs from \(playlist.name)"
            let state = self.state
            router.show(words, action: "Undo") {
                state.setPlaylistEdit(playlist.id, before)
                Task { await state.writes.setPlaylistSongs(playlist.id, tracks: before.map(\.track)) }
            }
        }
    }

    /// Moves a row into the place of the one it was dropped on.
    func move(_ itemId: Int64, onto targetId: Int64, in playlist: PlaylistSummary) {
        Task {
            var rows = await state.playlistTracks(playlist.id)
            guard itemId != targetId, let from = rows.firstIndex(where: { $0.itemId == itemId }),
                  let to = rows.firstIndex(where: { $0.itemId == targetId }) else { return }
            let row = rows.remove(at: from)
            rows.insert(row, at: to)
            state.setPlaylistEdit(playlist.id, rows)
            await state.writes.setPlaylistSongs(playlist.id, tracks: rows.map(\.track))
        }
    }

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

    // MARK: Links

    /// How long a shared link lasts.
    enum Expiry: CaseIterable {
        case never, day, week, month

        var label: String {
            switch self {
            case .never: "Never"
            case .day: "1 day"
            case .week: "1 week"
            case .month: "1 month"
            }
        }

        var lengthMs: Int64? {
            switch self {
            case .never: nil
            case .day: 86_400_000
            case .week: 7 * 86_400_000
            case .month: 30 * 86_400_000
            }
        }
    }

    /// Makes a shared link, then opens the phone's share sheet with it.
    func share(ids: [String], title: String, expiry: Expiry) async {
        guard let client = session.client else { return }
        do {
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            let link = try await client.makeShareLink(ids: ids, description: title, expiresAtMs: expiry.lengthMs.map { now + $0 })
            if link.url.trimmingCharacters(in: .whitespaces).isEmpty {
                router.show("The server made the link but did not say where it is.")
            } else {
                shareItem = ShareItem(items: [URL(string: link.url).map { $0 as Any } ?? link.url], subject: title)
            }
        } catch {
            if Self.sharingUnavailable(error) {
                state.sharingTurnedDown()
                router.show("Sharing is switched off on this server.")
            } else {
                router.show(userMessage(error))
            }
        }
    }

    /// Sharing is switched off (error 50 or 70), or the call is not there (HTTP 501).
    static func sharingUnavailable(_ error: Error) -> Bool {
        switch error as? OctoError {
        case .notFound: true
        case .server(let code, _): code == 50 || code == 70
        case .http(let status): status == 501
        default: false
        }
    }

    // MARK: Deleting from disk

    /// Whether the server lets this user delete this song's copy from its disk.
    func canDeleteFromDisk(_ track: LibraryTrack) -> Bool {
        state.fileActions?.canRemove == true && !track.isFound && (track.serverSongId != nil || !track.onPhone)
    }

    /// Asks before songs leave the server's disk; the answer goes to the server in use when it
    /// was asked, and switching server cancels the question.
    func deleteFromDisk(_ tracks: [LibraryTrack], then: (@MainActor () -> Void)? = nil) {
        let songs = tracks.filter { !$0.isFound }
        guard !songs.isEmpty, let asked = session.activeId else { return }
        let keepDays = state.fileActions?.keepDays ?? 0
        question = Question(
            title: deleteTitle(songs.count),
            message: deleteBody(deleteNames(songs.map(\.title)), keepDays: keepDays),
            confirm: "Delete", destructive: true
        ) { [weak self] in
            guard let self, self.session.activeId == asked, let client = self.session.client else { return }
            Task {
                var done = 0
                var problem: String?
                for track in songs {
                    guard let id = await self.state.serverId(track) else { continue }
                    do {
                        let result = try await client.fileAction(id, action: "remove")
                        if result.state == "applied" { done += 1 } else if problem == nil { problem = result.detail }
                    } catch {
                        if problem == nil { problem = userMessage(error) }
                    }
                }
                if done > 0 {
                    self.router.show(deletedLine(done, title: songs.count == 1 ? songs[0].title : nil))
                    self.state.sync.syncAgain()
                } else if let problem {
                    self.router.show(problem)
                }
                then?()
            }
        }
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
            if !lines.isEmpty { router.show(lines.joined(separator: ". ")) }
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
            question = Question(
                title: findHigherQualityAsk(asks.count, source: state.fileActions?.upgradeSource),
                message: keepsOriginalWords, confirm: findHigherQualityWords
            ) { self.findHigherQuality(asks) }
        }
    }
}

/// A playlist to write to a file the person picks.
struct PlaylistExport: Identifiable {
    let id = UUID()
    var name: String
    var text: String
}

/// The questions, forms and sheets the menus open, shown over everything.
struct LibraryPresenter: ViewModifier {
    @Environment(LibraryActions.self) private var actions
    @Environment(Router.self) private var router
    @Environment(Library.self) private var library
    @Environment(Session.self) private var session
    @State private var typed = ""

    func body(content: Content) -> some View {
        sheets(questions(content
            .task(id: library.stamp(.library, .likes, .favorites, .pins, .playlists)) { await actions.state.refreshCaches() }
            .onChange(of: library.stamp(.playlists)) { _, _ in actions.state.playlistsRead() }
            .task(id: session.activeId) { await actions.state.serverChanged() }))
    }

    private func questions(_ content: some View) -> some View {
        content
            .alert(actions.question?.title ?? "", isPresented: present(\.question), presenting: actions.question) { question in
                Button(question.confirm, role: question.destructive ? .destructive : nil) { question.onConfirm() }
                Button(question.cancel, role: .cancel) { question.onCancel?() }
            } message: { question in
                if let message = question.message { Text(message) }
            }
            .confirmationDialog(actions.choice?.title ?? "", isPresented: present(\.choice), titleVisibility: .visible,
                                presenting: actions.choice) { choice in
                ForEach(Array(choice.answers.enumerated()), id: \.offset) { _, answer in
                    Button(answer.label) { answer.run() }
                }
            } message: { choice in
                if let message = choice.message { Text(message) }
            }
            .alert(actions.nameForm?.title ?? "", isPresented: present(\.nameForm), presenting: actions.nameForm) { form in
                TextField(form.placeholder, text: $typed)
                    .textInputAutocapitalization(.sentences)
                Button(form.button) { form.onSave(typed.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: actions.nameForm?.id) { _, _ in typed = actions.nameForm?.initial ?? "" }
    }

    private func sheets(_ content: some View) -> some View {
        @Bindable var actions = actions
        return content
            .sheet(item: $actions.songInfo) { target in
                SongInfoSheet(target: target)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $actions.drivenMenu) { menu in DrivenMenuSheet(menu: menu) }
            .sheet(item: $actions.shareItem) { item in
                ActivitySheet(items: item.items, subject: item.subject)
                    .presentationDetents([.medium, .large])
            }
            .fileExporter(isPresented: present(\.export), document: actions.export.map { M3uDocument(text: $0.text) },
                          contentType: .m3uPlaylist, defaultFilename: actions.export.map { playlistFileName($0.name) }) { result in
                if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                    router.show("Could not export the playlist")
                }
                actions.export = nil
            }
    }

    private func present<T>(_ path: ReferenceWritableKeyPath<LibraryActions, T?>) -> Binding<Bool> {
        Binding(get: { actions[keyPath: path] != nil }, set: { if !$0 { actions[keyPath: path] = nil } })
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
