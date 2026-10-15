import Foundation
import Observation
import OctoKit

/// What a check page's sheet shows. Each fix is planned as it opens, so what it shows is what it
/// does, even if the library changes meanwhile.
enum HealthSheet {
    /// One set of copies put right, keeping `keep` (nil for the best).
    case duplicate(title: String, group: DuplicateGroup<SourceTrack>, keep: SourceTrack?)
    /// Every finding's fix, shown before it runs.
    case fixAll(HealthCheck, FixPreview)
    /// One split album joined.
    case join(title: String, words: String, steps: [FixStep])
    /// Songs with no length, asked of Find higher quality.
    case upgrade([LibraryTrack])
    /// Songs looked up, then what was found, to pick from.
    case lookUp
    /// Steps on their way to the server.
    case running
    /// How it went; `server` is the one the run went to, where its Undo goes too.
    case done(FixOutcome, server: String?)

    var isRunningOrDone: Bool {
        switch self {
        case .running, .done: true
        default: false
        }
    }
}

/// One song looked up: the library song, its id on the server, and what came back, or why nothing
/// did.
struct LookedUp {
    var track: LibraryTrack
    var serverId: String
    var lookup: SongLookup?
    var problem: String?

    /// What it would change, each picked or not to begin with.
    var changes: [(TagChange, Bool)] { lookup.flatMap { $0.found ? $0.changes() : nil } ?? [] }
}

/// Songs being looked up: those done so far, out of how many. Each look-up is a new `round`, so
/// what was ticked in the last one is forgotten.
struct Lookups {
    var songs: [LookedUp] = []
    var total = 0
    var finished = false
    var round = 0
}

/// Library health on the phone: the checks, run again whenever the library changes, and the fixes
/// the signed-in Octo server allows, which run there one song at a time.
@MainActor
@Observable
final class HealthModel {
    /// Nil until the first check is done.
    private(set) var health: PhoneHealth?
    /// Each library song's id on the server, for those it has.
    private(set) var serverIds: [String: String] = [:]
    private(set) var sheet: HealthSheet?
    /// Bumped each time the sheet shows something new.
    private(set) var sheetRevision = 0
    private(set) var lookups = Lookups()

    @ObservationIgnored private(set) var files: LibraryFiles?
    @ObservationIgnored private var actions: LibraryActions?
    @ObservationIgnored private var looking: Task<Void, Never>?
    @ObservationIgnored private var gone = false

    func attach(_ actions: LibraryActions) {
        guard self.actions == nil else { return }
        self.actions = actions
        files = actions.state.files
        // An admin may have changed what the server allows since sign-in.
        Task { await actions.state.files.refresh() }
    }

    var offers: HealthOffers { healthOffers(files?.actions) }
    var source: String? { files?.source }

    /// Checks the library again, away from the main thread.
    func check(_ library: Library) async {
        let tracks = await library.tracks()
        let albums = await library.albums()
        let store = library.store
        // Only copies in the library: another kept server's are not.
        var copies: [SourceTrack] = []
        for id in (try? await store.sourceIds()) ?? [] {
            copies += ((try? await store.sourceTracks(id)) ?? []).filter { !$0.mergedId.isEmpty }
        }
        let found = copies
        let shown = await Task.detached(priority: .userInitiated) { phoneHealth(tracks, albums: albums, copies: found) }.value
        health = shown
        serverIds = serverSongIds(shown.copies, sourceId: files?.source)
    }

    /// Another server in use: a plan or a look-up holds the last one's song ids, so it closes; a
    /// run already sent says how it went.
    func serverChanged() {
        looking?.cancel()
        lookups = Lookups(round: lookups.round + 1)
        if let sheet, !sheet.isRunningOrDone { self.sheet = nil }
        if let health { serverIds = serverSongIds(health.copies, sourceId: files?.source) }
    }

    func open(_ next: HealthSheet) {
        sheet = next
        sheetRevision += 1
    }

    /// Closing stops a look-up; a run already sent carries on and says how it went once done.
    func close() {
        looking?.cancel()
        sheet = nil
    }

    /// The page went away: how a run goes is said in a line from now on.
    func leave() { gone = true }

    /// Sends the steps, showing how far they have got, then how it went. They go to the server
    /// `on` they were planned on: the one signed in to now, or for an Undo, the one the run it
    /// puts back went to.
    func run(_ steps: [FixStep], undo: Bool = false, on: String? = nil) {
        guard !steps.isEmpty, let files else { return }
        open(.running)
        let server = on ?? files.server()
        files.launch(steps, undo: undo, on: server) { [weak self] outcome in
            guard let self, !self.gone, case .running = self.sheet else { return false }
            self.open(.done(outcome, server: server))
            return true
        }
    }

    func stop() { files?.stop() }

    /// Puts back the last fix or delete, and says how that went.
    func undoLast() {
        guard let files, canRunAll(files.actions, files.lastUndo) else { return }
        run(files.lastUndo, undo: true)
    }

    /// Looks the songs up one at a time, at most a batch, for one review.
    func lookUp(_ songs: [(LibraryTrack, String)]) {
        looking?.cancel()
        guard !songs.isEmpty, let files else { return }
        lookups = Lookups(total: songs.count, round: lookups.round + 1)
        open(.lookUp)
        looking = Task {
            for (track, serverId) in songs {
                if Task.isCancelled { return }
                let found: LookedUp
                do {
                    found = LookedUp(track: track, serverId: serverId, lookup: try await files.lookUp(serverId))
                } catch {
                    if isCancellation(error) { return }
                    found = LookedUp(track: track, serverId: serverId, problem: userMessage(error))
                }
                lookups.songs.append(found)
            }
            lookups.finished = true
        }
    }

    /// Stops looking up; what was found so far can still be written.
    func stopLookUp() {
        looking?.cancel()
        lookups.finished = true
    }

    /// The songs among these a higher quality copy could replace.
    func upgradable(_ songs: [LibraryTrack]) -> [LibraryTrack] { songs.filter { actions?.canUpgrade($0) == true } }

    func upgrade(_ songs: [LibraryTrack]) {
        actions?.findHigherQuality(songs)
        sheet = nil
    }

    /// Plays a check's songs from the one tapped.
    func play(_ songs: [LibraryTrack], from track: LibraryTrack) {
        var seen = Set<String>()
        let once = songs.filter { seen.insert($0.id).inserted }
        actions?.play(once, from: once.firstIndex { $0.id == track.id } ?? 0, source: "Library health")
    }
}
