import Foundation
import Observation
import OctoKit

/// How long the queue waits for the new server's library before coming back anyway.
private let libraryWaitMs: Int64 = 30_000

/// What the player does as the server in use changes. The player sets itself as
/// `ServerSwitch.player` while it runs.
@MainActor
protocol SwitchPlayer: AnyObject {
    /// Stops what plays for the server being left: the last song counts, casting ends and the
    /// player is emptied. Answers whether music was playing.
    func leave() async -> Bool
    /// Hands the queue over: the queue as it was left (or as saved) waits for `from` (its server
    /// gets it), and the one `to` left here becomes the saved queue. With nothing waiting for
    /// `to`, the queue is emptied, unless `keepWhenNone`, when it stays as it is. Answers whether
    /// the queue in use changed.
    func handOver(from: String, to: String, keepWhenNone: Bool) async -> Bool
    /// Another server came into use: its saved queue on the server is looked at for a Resume offer.
    func serverArrived()
    /// Brings the queue in use back into the player, paused where it was.
    func restore() async
    /// The queue in use did not change: the player carries on as it is.
    func keep() async
    /// The library changed under the car's browse tree.
    func libraryChanged()
}

/// How a switch asked for from the servers list went.
enum SwitchOutcome {
    /// In use now; `notice` says so, and plainly when music was stopped.
    case done(notice: String?)
    /// Its password is not kept here, or the server no longer takes it; the note says why, when
    /// there is something to say, and the form opens without one otherwise.
    case needsPassword(serverId: String, note: String?)
    case failed(String)
}

/// Moves the phone from one server to another: before the server in use changes, what was
/// playing stops and counts for the server it played from, its queue goes to that server and
/// waits on the phone for when it comes back; once the new server's library is in place, its own
/// queue comes back, paused. Signing in, switching, signing out and removing all go through it.
@MainActor
@Observable
final class ServerSwitch {
    /// The id of the server being switched to, while it is asked.
    private(set) var switching: String?

    @ObservationIgnored weak var player: SwitchPlayer?
    /// What else forgets a server taken off the list with "forget here": the queue waiting for
    /// it, recent playlists, live lists, server queue notes, admin addresses. Each part adds its own.
    @ObservationIgnored private var forgetters: [String: @MainActor (_ account: String) async -> Void] = [:]

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let sync: ServerSync
    @ObservationIgnored private let listening: ListeningSync
    @ObservationIgnored private let favorites: FavoriteSync
    @ObservationIgnored private let playlists: PlaylistSync
    @ObservationIgnored private var forgetDownloads: (@MainActor (_ sourceId: String) async -> Void)?
    @ObservationIgnored private var watch: Watch<String>?
    @ObservationIgnored private var before: String
    @ObservationIgnored private var handedOver = false
    @ObservationIgnored private var stoppedMusic = false

    init(session: Session, library: Library, sync: ServerSync, listening: ListeningSync, favorites: FavoriteSync,
         playlists: PlaylistSync) {
        self.session = session
        self.library = library
        self.sync = sync
        self.listening = listening
        self.favorites = favorites
        self.playlists = playlists
        before = session.inUse?.account ?? phoneLibrary
        session.leaving = { [weak self] from, to in await self?.leave(from, to) }
        // Recent playlists and live lists are kept by the server's id.
        onForget("recent_playlists") { account in LibraryState.forgetRecent(account) }
        onForget("live_lists") { account in LiveListStore.forget(account) }
        watch = Watch({ [weak session] in session?.inUse?.account ?? phoneLibrary }) { [weak self] now in
            guard let self else { return }
            let from = self.before
            self.before = now
            Task { await self.arrived(from, now) }
        }
    }

    /// Adds what else forgets a server taken off the list, under a name so it is added once.
    func onForget(_ name: String, _ forget: @escaping @MainActor (_ account: String) async -> Void) {
        forgetters[name] = forget
    }

    /// The downloads of a server source taken off the list, when no other kept account uses it.
    func onForgetDownloads(_ forget: @escaping @MainActor (_ sourceId: String) async -> Void) {
        forgetDownloads = forget
    }

    /// Makes another kept server the one in use, and says how it went. It runs on its own, so a
    /// page closed meanwhile never cuts it in half.
    func switchTo(_ id: String) async -> SwitchOutcome {
        if switching != nil { return .failed(serverSwitchBusy) }
        switching = id
        defer { switching = nil }
        stoppedMusic = false
        let from = session.inUse != nil ? session.active : nil
        if from?.id == id { return .done(notice: nil) }
        do {
            try await Task { @MainActor in try await self.session.switchTo(id) }.value
        } catch SignInFailure.needsPassword(let serverId, let note) {
            return .needsPassword(serverId: serverId, note: note)
        } catch {
            return .failed(error.localizedDescription)
        }
        let name = session.active?.name ?? ""
        return .done(notice: serverSwitchNotice(to: name, from: from?.name, stoppedMusic: stoppedMusic && from != nil))
    }

    /// The notice after signing in: the switch's, when another server was in use before.
    func signInNotice(previous: StoredServer?) -> String? {
        guard let now = session.active, previous?.id != now.id else { return nil }
        let notice = serverSwitchNotice(to: now.name, from: previous?.name, stoppedMusic: stoppedMusic && previous != nil)
        stoppedMusic = false
        return notice
    }

    /// Signs out of a kept server, the one in use included. It stays listed.
    func signOut(_ id: String) {
        Task {
            if session.inUse?.account == id, let from = session.active {
                await sync.stopCopy()
                await leave(from, nil)
            }
            session.signOut(id)
        }
    }

    /// Takes a server off the list, with its copy of the library. With `forgetHere`, what the
    /// phone keeps for it goes too; otherwise it stays in case the server is added again.
    func remove(_ id: String, forgetHere: Bool) {
        Task {
            guard let gone = session.servers.first(where: { $0.id == id }) else { return }
            if session.inUse?.account == id, let from = session.active {
                await sync.stopCopy()
                await leave(from, nil)
            }
            session.remove(id)
            await sync.forget(id)
            guard forgetHere else { return }
            listening.store.forget(id)
            favorites.forget(id)
            playlists.forget(id, sourceId: gone.sourceId)
            for forget in forgetters.values { await forget(id) }
            // Another kept account on the same address keeps the downloads.
            let shared = session.servers.contains { $0.sourceId == gone.sourceId }
            if !shared { await forgetDownloads?(gone.sourceId) }
        }
    }

    /// Before the server in use changes: what plays stops and counts for it, its queue goes to it
    /// and waits here, and the next one's comes in.
    private func leave(_ from: StoredServer, _ to: String?) async {
        let wasPlaying = await player?.leave() ?? false
        stoppedMusic = wasPlaying
        // The last song's play is noted for the server it played from.
        await listening.noted()
        let next = to ?? phoneLibrary
        _ = await player?.handOver(from: from.id, to: next, keepWhenNone: false)
        handedOver = true
        // The player waits for the next server's library on its own, even should another switch follow.
        Task { await self.bringBack(next, changed: true) }
    }

    /// After the server in use changed without a leave (none was in use): the phone's queue keeps
    /// playing, unless the server signed in to left one here.
    private func arrived(_ from: String, _ to: String) async {
        if handedOver {
            handedOver = false
            return
        }
        let changed = await player?.handOver(from: from, to: to, keepWhenNone: true) ?? false
        await bringBack(to, changed: changed)
    }

    /// Once the library of `to` is in place, its queue comes back into the player, and a car
    /// reads its tabs again.
    private func bringBack(_ to: String, changed: Bool) async {
        player?.serverArrived()
        guard let player else { return }
        let deadline = epochNowMs() + libraryWaitMs
        while library.ready != to && epochNowMs() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if changed { await player.restore() } else { await player.keep() }
        player.libraryChanged()
    }
}
