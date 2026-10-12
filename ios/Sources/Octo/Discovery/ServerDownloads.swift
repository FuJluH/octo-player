import Foundation
import Observation
import OctoKit

/// What the server downloads sheet shows: the list, one download's log, or Find songs for one song.
enum SheetView: Equatable {
    case list
    case log(key: String)
    /// `id` is the song's id on the server; `title` names it until the server answers. `from` is the
    /// log it was opened from, if any.
    case find(id: String, title: String, from: String?)
}

/// The server downloads sheet on the signed-in Octo server: every download it is doing for this
/// person or did lately, each one's log, and Find songs. Only on a server that lists
/// octoAcquisitions at version 2. The list is followed while the app runs: often while the sheet is
/// open, every few seconds while something is on its way, and seldom otherwise. A library song's
/// copy replaced from Find songs is followed until it ends, and a line says how it went: with Undo
/// once replaced, which puts the old copy back.
@MainActor
@Observable
final class ServerDownloads {
    /// Whether the signed-in server keeps a log of its downloads.
    private(set) var supported = false
    /// Whether the server asks before a copy that is not better replaces the library's.
    private(set) var asksFirst = false
    /// What the sheet shows, or nil while it is closed.
    private(set) var view: SheetView?

    let watch: DownloadsWatch
    let logWatch: DownloadLogWatch
    let findWatch: FindSongsWatch
    let replacements = Replacements()

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let router: Router
    @ObservationIgnored private var signedInAs: String?

    init(session: Session, router: Router) {
        self.session = session
        self.router = router
        let client: @Sendable () async -> SubsonicClient? = { await MainActor.run { session.client } }
        watch = DownloadsWatch(source: ClientDownloads(client: client, upgradesListed: {
            await MainActor.run { session.profile?.lists(octoLibraryActions, version: 2) ?? false }
        }))
        logWatch = DownloadLogWatch(load: { key in
            guard let client = await client() else { throw OctoError.notFound("Not signed in") }
            return try await client.acquisition(key: key)
        })
        findWatch = FindSongsWatch(source: ClientFind(client: client))
        watch.upgradesRead = { [weak self] upgrades in
            guard let self else { return }
            for end in self.replacements.update(upgrades) { self.ended(end) }
        }
    }

    /// A new sign-in, another kept server, or the same one with its extensions read again: forgets
    /// everything, closes the sheet, and starts again when the server keeps a log.
    func sessionChanged() {
        let extensions = session.client == nil ? [] : (session.profile?.extensions ?? [])
        let key = session.client == nil ? nil : "\(session.activeId ?? "")|\(session.client?.baseURL.absoluteString ?? "")|\(extensions.joined(separator: ","))"
        guard key != signedInAs else { return }
        signedInAs = key
        watch.stop()
        watch.reset()
        replacements.clear()
        close()
        let logs = extensions.contains("\(octoAcquisitions):\(octoDownloadLogVersion)")
        let asks = logs && extensions.contains("\(octoAcquisitions):\(octoReplaceAnywayVersion)")
        findWatch.asksFirst = asks
        asksFirst = asks
        supported = logs
        if logs { watch.start() }
    }

    /// Whether the app is in front: behind it the list is asked for only at the slow pace, and an
    /// open log not at all.
    func setForeground(_ front: Bool) {
        let back = front && !watch.foreground
        watch.foreground = front
        logWatch.foreground = front
        if back { watch.wake() }
    }

    /// A song was asked for here: the list is asked again now.
    func wake() { watch.wake() }

    func open() {
        guard supported else { return }
        watch.open = true
        if view == nil { view = .list }
    }

    func close() {
        watch.open = false
        logWatch.close()
        findWatch.close()
        view = nil
    }

    func showList() {
        logWatch.close()
        findWatch.close()
        view = .list
    }

    func showLog(_ key: String) {
        findWatch.close()
        logWatch.follow(key)
        watch.open = true
        view = .log(key: key)
    }

    /// Opens the sheet on a song's newest download, by the id it was asked for with on the server,
    /// or on the list when the server has not listed it yet.
    func follow(_ serverId: String) {
        guard supported else { return }
        if let key = watch.keyFor(serverId) {
            showLog(key)
        } else {
            open()
            showList()
        }
    }

    /// Opens what the router asked for.
    func show(_ page: DownloadsSheetPage) {
        switch page {
        case .list(let focus):
            if let focus { follow(focus) } else { open(); showList() }
        case .log(let key): if supported { showLog(key) }
        case .find(let id, let title, let from): find(id, title: title, from: from)
        }
    }

    /// Find songs for a song by its id on the server.
    func find(_ serverId: String, title: String, from: String? = nil) {
        guard supported else { return }
        logWatch.close()
        watch.open = true
        findWatch.search(serverId)
        view = .find(id: serverId, title: title, from: from)
    }

    /// Find songs for a song in the library or a found one: its copy on the signed-in server (the
    /// smallest id when it has several), or the found song's own id. False, with nothing opened,
    /// when the server has no copy of it; the song menu then says "This server has no copy of the
    /// song to look for".
    func findTrack(_ trackId: String, title: String, library: Library) async -> Bool {
        guard let id = await serverId(of: trackId, library: library) else { return false }
        find(id, title: title)
        return true
    }

    /// A song's id on the signed-in server.
    func serverId(of trackId: String, library: Library) async -> String? {
        if isFind(trackId) { return String(trackId.dropFirst(findPrefix.count)) }
        guard session.client != nil, let sourceId = session.active?.sourceId else { return nil }
        return await library.copies(trackId).filter { $0.sourceId == sourceId }.map(\.nativeId).min()
    }

    func searchAgain() {
        if case .find(let id, _, _) = view { findWatch.search(id) }
    }

    /// Fetches one copy from the Find songs search `search`. A queued pick opens its download's
    /// log; a server that asks first may answer with a question instead.
    func pick(_ search: String, _ copy: FoundCandidate) {
        Task { picked(search, await findWatch.pick(search, copy)) }
    }

    /// Answers the question yes: the pick goes again with anyway=true. A library song's copy then
    /// shows as replacing on its row, followed until it ends; any other pick goes on as usual.
    func replaceAnyway() {
        guard let asked = findWatch.question else { return }
        Task {
            guard let result = await findWatch.replaceAnyway(asked) else { return }
            if result.queued, let replacing = Replacing.of(asked) {
                replacements.start(replacing, upgrades: watch.upgrades)
                watch.wake()
            } else {
                picked(asked.search, result)
            }
        }
    }

    /// Leaves the library's copy as it is; nothing is sent.
    func keepMine(_ question: PickQuestion? = nil) { findWatch.keepMine(question) }

    func clear(_ key: String? = nil) { Task { await watch.clear(key) } }

    private func picked(_ search: String, _ result: PickResult) {
        guard result.queued else { return }
        watch.wake()
        guard case .find = view, findWatch.showing(search) else { return }
        if let key = result.key { showLog(key) } else { showList() }
    }

    /// A replacement ended. Replaced: a line with Undo, which puts the old copy back on the server
    /// it was replaced on. Kept: the server's words why, with the downloads one tap away.
    private func ended(_ end: ReplaceEnd) {
        switch end {
        case .replaced(let replacing):
            let server = session.activeId
            router.show(end.words, action: "Undo") { [weak self] in self?.putBack(replacing, on: server) }
        case .kept:
            router.show(end.words, action: "Show downloads") { [weak self] in
                self?.open()
                self?.showList()
            }
        }
    }

    /// Puts the replaced copy back, on the server it was replaced on, while it is still the one in
    /// use.
    private func putBack(_ replacing: Replacing, on server: String?) {
        // Once another server is in use, how it would go is not told at all.
        guard let client = session.client, session.activeId == server else { return }
        Task {
            do {
                let result = try await client.restoreReplacedCopy(id: replacing.songId)
                let said = result.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                router.show(said.isEmpty ? "Put back 1 song." : said)
            } catch {
                router.show(serverWords(error) ?? onlineFailureWords(error))
            }
        }
    }
}

/// The server's two lists, from the signed-in client.
private struct ClientDownloads: DownloadsSource {
    let client: @Sendable () async -> SubsonicClient?
    let upgradesListed: @Sendable () async -> Bool

    func acquisitions() async throws -> [Acquisition] { try await client()?.acquisitions() ?? [] }

    func upgrades() async throws -> [Upgrade] {
        guard await upgradesListed(), let client = await client() else { return [] }
        return try await client.upgradesAskedFor()
    }

    func clear(_ key: String?) async throws { try await client()?.clearAcquisitions(key: key) }
}

/// Find songs' three calls, from the signed-in client.
private struct ClientFind: FindSource {
    let client: @Sendable () async -> SubsonicClient?

    func start(_ id: String) async throws -> FoundSongs {
        guard let client = await client() else { throw OctoError.notFound("Not signed in") }
        return try await client.findSongs(id: id)
    }

    func get(_ search: String) async throws -> FoundSongs {
        guard let client = await client() else { throw OctoError.notFound("Not signed in") }
        return try await client.foundSongs(search: search)
    }

    func pick(_ search: String, _ copy: FoundCandidate, anyway: Bool?) async throws -> PickResult {
        guard let client = await client() else { return PickResult(pickSkipped, "Not signed in") }
        return try await client.pickFoundSong(search: search, copy: copy, anyway: anyway)
    }
}
