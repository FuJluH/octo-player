import Foundation
import Observation
import OctoKit

/// Library health's fixes and deleting songs from disk on the signed-in Octo server: what the
/// server lets this user do, which of the library's songs it has, and the steps sent to it one at
/// a time. Whatever changes, the library is copied again after, so a removed song leaves it and a
/// fixed one shows its new tags.
@MainActor
@Observable
final class LibraryFiles {
    /// What the server lets this user do to its files; nil for a server that offers none, or none
    /// signed in.
    private(set) var actions: FileActions?
    /// The library's source for that server, while it offers anything.
    private(set) var source: String?
    /// How far the run under way has got; nil while none is.
    private(set) var progress: (done: Int, total: Int)?
    /// What puts the last run back, until another run replaces it.
    private(set) var lastUndo: [FixStep] = []
    /// Bumped each time another server comes into use.
    private(set) var serverChanges = 0

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let sync: ServerSync
    @ObservationIgnored weak var router: Router?
    @ObservationIgnored private var stopping = false
    /// The run before this one, so runs go one after another.
    @ObservationIgnored private var queue: Task<FixOutcome, Never>?
    @ObservationIgnored private var watch: Watch<String?>?

    init(session: Session, library: Library, sync: ServerSync) {
        self.session = session
        self.library = library
        self.sync = sync
        watch = Watch({ [weak session] in session?.activeId }) { [weak self] _ in self?.serverChanged() }
        serverChanged()
    }

    private func serverChanged() {
        actions = nil
        source = nil
        lastUndo = []
        serverChanges += 1
        Task { await refresh() }
    }

    /// Reads again what the server lets this user do, as when a page about it opens: an admin may
    /// have changed it since sign-in.
    func refresh() async {
        guard let client = session.client, let extensions = session.profile?.extensions,
              listsLibraryActions(extensions) else { return }
        let asked = session.activeId
        guard let read = try? await client.fileActions(), session.activeId == asked else { return }
        actions = read
        source = library.serverInUse
    }

    /// The server's id for each of `trackIds` it has a copy of.
    func serverIds(_ trackIds: [String]) async -> [String: String] {
        guard !trackIds.isEmpty else { return [:] }
        var seen = Set<String>()
        let copies = (try? await library.store.copies(of: trackIds.filter { seen.insert($0).inserted })) ?? []
        return serverSongIds(copies, sourceId: source)
    }

    /// The library songs among `trackIds` that can be deleted from disk now.
    func deletable(_ trackIds: [String]) async -> [String] {
        guard actions?.canRemove == true else { return [] }
        let ids = await serverIds(trackIds)
        return trackIds.filter { ids[$0] != nil }
    }

    /// The server steps are planned for: the kept server signed in to now.
    func server() -> String? { session.activeId }

    /// Runs the steps one after another on the server `on` and says nothing; the caller tells how
    /// it went. A run that waited its turn while another server was signed in to is not sent.
    /// What puts it back is kept as the last change, unless this run is itself an undo.
    func run(_ steps: [FixStep], keepUndo: Bool = true, on: String?) async -> FixOutcome {
        let before = queue
        let task = Task { @MainActor [weak self] () -> FixOutcome in
            _ = await before?.value
            guard let self else { return FixOutcome() }
            return await self.runNow(steps, keepUndo: keepUndo, on: on)
        }
        queue = task
        return await task.value
    }

    private func runNow(_ steps: [FixStep], keepUndo: Bool, on: String?) async -> FixOutcome {
        guard !steps.isEmpty else { return FixOutcome() }
        stopping = false
        guard let on, let client = session.client else { return FixOutcome(failed: steps.map { ($0, "Not signed in") }) }
        guard session.activeId == on else { return FixOutcome(failed: steps.map { ($0, fixOtherServer) }) }
        progress = (0, steps.count)
        let outcome = await runFix(steps, send: { step in
            try await client.fileAction(step.id, action: step.action, with: step.with)
        }, progress: { [weak self] done, total in
            self?.progress = (done, total)
        }, stop: { [weak self] in
            self?.stopping ?? true
        }, failure: { userMessage($0) })
        progress = nil
        let still = server() == on
        if still, keepUndo, !outcome.undo.isEmpty { lastUndo = outcome.undo }
        if still, !outcome.done.isEmpty { _ = await sync.syncNowAndWait() }
        return outcome
    }

    func stop() { stopping = true }

    /// Runs the steps away from the page that asked, so leaving it does not cut a run short.
    /// `shown` hears how it went and answers whether it told the listener; when it did not, a line
    /// says it. Once another server is signed in to, how it went is not told at all.
    func launch(_ steps: [FixStep], undo: Bool = false, on: String?, shown: @escaping @MainActor (FixOutcome) -> Bool = { _ in false }) {
        Task {
            let outcome = undo ? await self.undo(steps, on: on) : await run(steps, on: on)
            if on != nil, server() != on { return }
            if !shown(outcome) { say(outcome.summary(), outcome, on: on) }
        }
    }

    /// Says how a run on the server `on` went, with an Undo when the server can put it back. The
    /// Undo goes to that same server, and only while it is still the one signed in to.
    func say(_ line: String, _ outcome: FixOutcome, on: String?) {
        let back = outcome.undo
        guard let on, canRunAll(actions, back) else {
            router?.show(line)
            return
        }
        router?.undoable(line) { [weak self] in
            guard let self else { return }
            guard self.server() == on else {
                self.router?.show(fixOtherServer)
                return
            }
            Task {
                let put = await self.undo(back, on: on)
                if self.server() == on { self.router?.show(put.summary()) }
            }
        }
    }

    /// Puts back what a run on the server `on` did, from its outcome's `undo`. Once it is put back,
    /// it is no longer the last change to undo.
    func undo(_ steps: [FixStep], on: String?) async -> FixOutcome {
        if lastUndo == steps { lastUndo = [] }
        return await run(steps, keepUndo: false, on: on)
    }

    /// The tags a download of a song would get.
    func lookUp(_ serverId: String) async throws -> SongLookup {
        guard let client = session.client else { return SongLookup(state: "failed", detail: "Not signed in") }
        return try await client.lookUpTags(serverId)
    }

    /// The songs in the server's trash.
    func trash() async throws -> LibraryTrash {
        guard let client = session.client else { throw OctoError.server(code: 0, message: "Not signed in") }
        return try await client.libraryTrash()
    }

    /// Deletes library songs from the server's disk, once asked, then says so with an Undo that puts
    /// them back from the server's trash. The server `on` is the one signed in to when it was asked;
    /// once another is, nothing is sent or said.
    func deleteFromDisk(_ trackIds: [String], title: String?, on: String?) {
        guard let on, server() == on else { return }
        Task {
            var seen = Set<String>()
            let ids = trackIds.filter { seen.insert($0).inserted }
            let copies = (try? await library.store.copies(of: ids)) ?? []
            let steps = OctoKit.deleteSteps(ids, copies: copies, sourceId: server() == on ? source : nil)
            guard !steps.isEmpty else { return }
            let outcome = await run(steps, on: on)
            guard server() == on else { return }
            let removed = outcome.removed
            let songs = ids.filter { id in copies.contains { $0.mergedId == id && removed.contains($0.nativeId) } }.count
            let line = outcome.failed.isEmpty && !outcome.rehearsed && !outcome.stopped ? deletedLine(songs, title: title) : outcome.summary()
            say(line, outcome, on: on)
        }
    }
}
