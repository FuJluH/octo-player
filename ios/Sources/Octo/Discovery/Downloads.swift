import Foundation
import Observation
import OctoKit

// When to look for downloads in the library after asking for one, on a server that does not say
// how its downloads are going: a little later, and once more for slow ones.
private let checkAfterMs: [Int64] = [2 * 60_000, 8 * 60_000]

// How often Octo's admin pages are read while downloads are on their way, for how long, and how
// many times the library is copied again for one finished song.
private let watchEveryMs: Int64 = 20_000
private let watchForMs: Int64 = 30 * 60_000
private let syncsPerSong = 3

/// Finds that have not come up for this long are let go.
private let forgetMs: Int64 = 30 * 24 * 60 * 60_000

/// How long a server that could not say how its downloads are going is believed, before it is
/// asked again (it may have been updated meanwhile).
private let recheckSupportMs: Int64 = 10 * 60_000

/// Downloading songs found online into the library. On Octo, starring a find from an Octo app
/// makes the server download it; once the library has the song, the find is linked to it (not
/// liked). A server that says how its downloads are going is asked every few seconds while any
/// is on its way; others are looked at again on a timer. The finds are kept in the library
/// database, under their server's source.
@MainActor
@Observable
final class Downloads {
    /// Every find asked for, by its id on the server, and how its download is going.
    private(set) var phases: [String: DownloadPhase] = [:]
    /// Each find now in the library, by its id on the server, and the library song it became. Nil
    /// until first read, so a row can tell a song that was already in the library from one that
    /// arrives while it is shown.
    private(set) var adoptions: [String: String]?
    /// Songs asked for from this phone on the server in use that have not reached the library.
    private(set) var asked: [AskedSong] = []
    /// Goes up by one each time downloads join the library, so pages that hold what the server
    /// said can ask again.
    private(set) var arrived = 0
    /// Whether the server in use lists its downloads, as far as is known.
    private(set) var lists = true

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let library: Library
    @ObservationIgnored private let sync: ServerSync
    @ObservationIgnored private let announce: @MainActor (String, Bool) -> Void
    /// Every find asked for, as the follower reads them, kept from the library database.
    @ObservationIgnored private var rows: [FindSong] = []
    /// Finds already in the library when last read, to tell which arrived since.
    @ObservationIgnored private var known: Set<String>?
    @ObservationIgnored private lazy var tracker = ProgressWatch(host: DownloadsHost(self))
    @ObservationIgnored private let arrivals = Arrivals()
    @ObservationIgnored private var following = false
    /// Counts the follows started, so a canceled one never touches a newer one's state.
    @ObservationIgnored private var followRun = 0
    @ObservationIgnored private var checks: Task<Void, Never>?
    @ObservationIgnored private var recheck: Task<Void, Never>?
    @ObservationIgnored private var support: [String: (yes: Bool, at: Int64)] = [:]
    @ObservationIgnored private var failedBefore = Set<String>()
    @ObservationIgnored private var lastSource: String?
    @ObservationIgnored private var findsWatch: Watch<Int>?

    /// A song Octo's admin pages list as downloaded.
    struct AdminDownload: Sendable {
        var title: String
        var artist: String
    }

    /// Octo's admin pages, once another part of the app can reach them: where they answer now for
    /// the server in use (nil when away from home or not on Octo), and the songs they list as
    /// downloaded there. A failed read throws.
    struct AdminPages {
        var locate: @MainActor () async -> URL?
        var downloaded: @MainActor (_ base: URL) async throws -> [AdminDownload]
    }

    @ObservationIgnored var adminPages: AdminPages?

    /// `announce` shows a line: the words, and whether it marks something done.
    init(session: Session, library: Library, sync: ServerSync, announce: @escaping @MainActor (String, Bool) -> Void) {
        self.session = session
        self.library = library
        self.sync = sync
        self.announce = announce
        lastSource = sourceInUse
        tracker.foreground = false
        tracker.changed = { [weak self] in Task { @MainActor in self?.liveChanged() } }
        findsWatch = Watch({ [weak library] in library?.findsVersion ?? 0 }) { [weak self] _ in
            Task { await self?.reload() }
        }
        sync.afterSync("finds") { [weak self] in await self?.afterSync() }
        Task { await reload() }
    }

    /// The source of the server in use, while one is signed in.
    private var sourceInUse: String? { session.client == nil ? nil : session.active?.sourceId }

    func phase(_ songId: String) -> DownloadPhase { phases[songId] ?? .none }

    /// Called after a song or an album was asked for, so the server downloads list looks now.
    @ObservationIgnored var onAsk: (@MainActor () -> Void)?

    /// The finds whose download has arrived in the library.
    var adopted: Set<String> { Set(phases.filter { $0.value == .done }.keys) }

    /// Library songs that finds became, as last read, so a find's row can turn into its song.
    private(set) var librarySongs: [String: Song] = [:]
    /// The same songs as library rows.
    private(set) var libraryTracks: [String: LibraryTrack] = [:]
    @ObservationIgnored private var lookingUp = Set<String>()

    /// The library song a find became, as last read; nil until it has been read.
    func librarySong(_ id: String) -> Song? { librarySongs[id] }

    /// The library row a find became, as last read; nil until it has been read.
    func libraryTrack(_ id: String) -> LibraryTrack? { libraryTracks[id] }

    /// The same, for the pages that resolve what the server sent.
    func lastSeenLibrarySong(_ id: String) -> Song? { librarySongs[id] }

    /// Reads a library song a find became, once, so its row can turn into it.
    func lookUpLibrarySong(_ id: String) {
        guard librarySongs[id] == nil, !lookingUp.contains(id) else { return }
        lookingUp.insert(id)
        Task {
            defer { lookingUp.remove(id) }
            if let track = await library.track(id) {
                libraryTracks[id] = track
                librarySongs[id] = track.asSong
            }
        }
    }

    func state(_ songId: String) -> DownloadState { phase(songId).state }

    /// Whether the server keeps a log of its downloads that the downloads sheet can show.
    var keepsLog: Bool { session.profile?.lists(octoAcquisitions, version: 2) ?? false }

    /// A find's button is on screen until the answer is called, so its progress is asked for more
    /// often. A button on screen also means the app is in front.
    func showing(_ songId: String) -> @Sendable () -> Void {
        tracker.foreground = true
        return tracker.show(songId)
    }

    /// Whether the app is in front. The server is asked less often while it is not.
    func setForeground(_ front: Bool) { tracker.foreground = front }

    /// Asks the server to download one find. Answers whether it was asked. A download that failed
    /// is asked for again the same way.
    func request(_ song: Song) async -> Bool {
        guard song.isExternal, let client = session.client, let source = sourceInUse else { return false }
        do {
            try await client.star(songId: song.id)
        } catch {
            return false
        }
        await keep([song], source: source, requestedAt: epochNowMs())
        SearchModel.hintAdded()
        arrivals.askedSong(song.id, title: song.title)
        onAsk?()
        tracker.retry(song.id)
        follow()
        return true
    }

    /// Asks the server to download a whole album found online, and follows the songs from it that
    /// are listed.
    func requestAlbum(_ albumId: String, songs: [Song], title: String = "") async -> Bool {
        guard let client = session.client, let source = sourceInUse else { return false }
        do {
            try await client.star(albumId: albumId)
        } catch {
            return false
        }
        let finds = songs.filter(\.isExternal)
        await keep(finds, source: source, requestedAt: epochNowMs())
        SearchModel.hintAdded()
        onAsk?()
        let coming = finds.filter { state($0.id) != .done }
        let named = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (coming.first?.album ?? "") : title
        arrivals.askedAlbum(named, findIds: coming.map(\.id))
        for song in coming { tracker.retry(song.id) }
        follow()
        return true
    }

    /// A pull on a page: asks the server how its downloads are going now.
    func refreshProgress() async {
        if following {
            tracker.wake()
            return
        }
        if !watchedWaiting().isEmpty, await reportsProgress() { follow() }
    }

    /// At start and whenever another kept server comes into use: the last one's downloads are no
    /// longer asked about, and this one's own carry on being followed.
    func resume() async {
        if sourceInUse != lastSource {
            lastSource = sourceInUse
            checks?.cancel()
            checks = nil
            following = false
            followRun += 1
            refresh()
        }
        guard session.client != nil else { return }
        if !watchedWaiting().isEmpty, await reportsProgress() { follow() }
    }

    // MARK: Finds kept in the library database

    /// Keeps finds, or updates the ones kept with what the server says of them now, and marks them
    /// asked for.
    private func keep(_ songs: [Song], source: String, requestedAt: Int64) async {
        let now = epochNowMs()
        let finds = songs.map { $0.toFind(sourceId: source, now: now) }
        let store = library.store
        _ = try? await store.keepFinds(finds)
        for find in finds { try? await store.setRequested(find.id, at: requestedAt) }
        await reload()
    }

    /// Reads the finds asked for again, and tells of any that reached the library since.
    private func reload() async {
        let found = (try? await library.store.requestedFinds()) ?? []
        rows = found.map(\.asFindSong)
        let adopted = Set(found.filter { !$0.adoptedId.isEmpty }.map(\.nativeId))
        if let before = known {
            let landed = adopted.subtracting(before)
            if !landed.isEmpty {
                arrived += 1
                for id in landed.sorted() { if let words = arrivals.landed(id) { announce(words, true) } }
            }
        }
        known = adopted
        refresh()
    }

    /// After each copy of the server's library: a download that has arrived is linked to its
    /// library song, and old finds are let go.
    private func afterSync() async {
        guard let source = sourceInUse else { return }
        let store = library.store
        let kept = session.servers.map(\.sourceId) + [source]
        // Finds in the saved queue stay, so the queue comes back whole.
        let queued = await QueueFile.standard.read()?.trackIds ?? []
        try? await store.pruneFinds(sourceId: source, kept: kept, before: epochNowMs() - forgetMs, queued: queued)
        let waiting = (try? await store.waitingFinds()) ?? []
        guard !waiting.isEmpty else { return }
        let keys = Array(Set(waiting.flatMap { titleKeys($0.title) }))
        let candidates = ((try? await store.tracksWithKeys(keys)) ?? []).filter { !isFind($0.id) }
        let adopted = OctoKit.adoptions(waiting, candidates)
        for find in waiting {
            if let track = adopted[find.id] { try? await store.adopt(find.id, trackId: track.id) }
        }
    }

    // MARK: Following

    /// The songs asked for lately on the server in use: another kept server's are followed once it
    /// is in use again.
    fileprivate func watchedWaiting() -> [FindSong] {
        guard let here = sourceInUse else { return [] }
        let now = epochNowMs()
        return rows.filter { $0.sourceId == here && $0.requestedAt > 0 && $0.adoptedId.isEmpty && now - $0.requestedAt < giveUpMs }
    }

    /// Follows the downloads asked for: by asking the server how they are going when it can say;
    /// otherwise by copying the library again once Octo's admin pages list one as finished, when
    /// they can be reached, or a little later, and once more after that for slow ones.
    private func follow() {
        if following {
            tracker.wake()
            return
        }
        checks?.cancel()
        followRun += 1
        let run = followRun
        checks = Task { [weak self] in
            guard let self else { return }
            if await self.reportsProgress() {
                guard !Task.isCancelled, run == self.followRun else { return }
                self.following = true
                let done = await self.tracker.run()
                // A newer run may have started meanwhile; only this run's own flag is cleared.
                if run == self.followRun { self.following = false }
                if done || Task.isCancelled { return }
            }
            guard !Task.isCancelled else { return }
            if let pages = self.adminPages, let base = await pages.locate() {
                await self.watch(base, pages)
            } else {
                await self.checkOnTimer()
            }
        }
    }

    /// Reads the admin pages until every download asked for has arrived, or for half an hour; a
    /// song listed there as finished has the library copied again, at most three times.
    private func watch(_ base: URL, _ pages: AdminPages) async {
        var syncs: [String: Int] = [:]
        let until = epochNowMs() + watchForMs
        while epochNowMs() < until {
            try? await Task.sleep(for: .milliseconds(watchEveryMs))
            if Task.isCancelled { return }
            let waiting = watchedWaiting()
            if waiting.isEmpty { return }
            guard let finished = try? await pages.downloaded(base) else { continue }
            let due = waiting.filter { find in finished.contains { sameRecording($0.title, $0.artist, find.title, find.artist) } }
                .filter { (syncs[$0.id] ?? 0) < syncsPerSong }
            if !due.isEmpty {
                for find in due { syncs[find.id, default: 0] += 1 }
                sync.syncNow()
            }
        }
    }

    private func checkOnTimer() async {
        var waited: Int64 = 0
        for at in checkAfterMs {
            try? await Task.sleep(for: .milliseconds(at - waited))
            if Task.isCancelled { return }
            waited = at
            sync.syncNow()
        }
    }

    /// Whether the server in use says how its downloads are going: from what it listed at sign-in,
    /// or by asking, since it may have been updated since.
    private func reportsProgress() async -> Bool {
        guard let source = sourceInUse, let client = session.client else { return false }
        if session.extensions.contains("\(octoAcquisitions):1") {
            lists = true
            return true
        }
        let now = epochNowMs()
        if let known = support[source], known.yes || now - known.at < recheckSupportMs { return known.yes }
        // Out of reach, busy or refusing the sign-in: not noted, asked again next time.
        guard let yes = await client.supportsIfKnown(octoAcquisitions, version: 1) else { return false }
        noteSupport(source, yes)
        return yes
    }

    fileprivate func noteSupport(_ source: String, _ yes: Bool) {
        support[source] = (yes, epochNowMs())
        lists = yes
        refresh()
    }

    fileprivate func acquisitions() async throws -> [Acquisition]? {
        guard let client = session.client, let source = sourceInUse else { return nil }
        do {
            return try await client.acquisitions()
        } catch is OctoError {
            // An older server without the call: back to the old ways.
            noteSupport(source, false)
            return nil
        }
    }

    /// Brings one finished song into the library by its server id: the library song it became,
    /// when the server has it in the library now.
    fileprivate func takeIn(_ libraryId: String) async -> String? {
        await sync.takeInSong(libraryId)
    }

    /// Links a find to the library song it became. Downloading is not liking, so the song is not
    /// hearted; that stays the listener's call.
    fileprivate func adopt(_ serverId: String, _ trackId: String) async {
        let store = library.store
        guard let find = try? await store.find(findId(serverId)), find.adoptedId.isEmpty,
              (try? await store.track(trackId)) != nil
        else { return }
        try? await store.adopt(find.id, trackId: trackId)
        await reload()
    }

    /// Copies the library again and waits for it; songs that arrived are adopted along the way.
    fileprivate func syncAndWait() async {
        _ = await sync.syncNowAndWait()
    }

    // MARK: Phases

    private func liveChanged() {
        let failedNow = Set(tracker.live.compactMap { id, phase -> String? in
            if case .failed = phase { return id }
            return nil
        })
        // An album whose last song failed is settled too.
        for id in failedNow.subtracting(failedBefore) {
            if let words = arrivals.failed(id) { announce(words, false) }
        }
        failedBefore = failedNow
        refresh()
    }

    /// Works the phases out again, and again when the first ask still taken as on its way runs out.
    private func refresh() {
        let here = sourceInUse
        let mine = rows.filter { $0.sourceId == here }
        let inputs = PhaseInputs(rows: mine.filter { $0.requestedAt > 0 || !$0.adoptedId.isEmpty }, live: tracker.live,
                                 listedSince: tracker.listedSince, lists: lists, sourceId: here)
        let now = epochNowMs()
        let next = phasesOf(inputs, now: now)
        if next != phases { phases = next }
        var adopted: [String: String] = [:]
        for row in mine where !row.adoptedId.isEmpty { adopted[row.id] = row.adoptedId }
        if adoptions != adopted { adoptions = adopted }
        let nowAsked = askedSongs(rows, sourceId: here)
        if nowAsked != asked { asked = nowAsked }
        recheck?.cancel()
        if let wait = recheckMs(inputs, now: now) {
            recheck = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(wait))
                if !Task.isCancelled { self?.refresh() }
            }
        }
    }
}

/// The downloads follower's line to the rest of the app.
private final class DownloadsHost: AcquisitionHost, @unchecked Sendable {
    weak var downloads: Downloads?

    @MainActor init(_ downloads: Downloads) { self.downloads = downloads }

    func waiting() async -> [FindSong] { await MainActor.run { downloads?.watchedWaiting() ?? [] } }

    func acquisitions() async throws -> [Acquisition]? {
        guard let downloads = await MainActor.run(body: { self.downloads }) else { return nil }
        return try await downloads.acquisitions()
    }

    func takeIn(_ libraryId: String) async throws -> String? {
        guard let downloads = await MainActor.run(body: { self.downloads }) else { return nil }
        return await downloads.takeIn(libraryId)
    }

    func adopt(_ findId: String, _ trackId: String) async {
        guard let downloads = await MainActor.run(body: { self.downloads }) else { return }
        await downloads.adopt(findId, trackId)
    }

    func syncAndWait() async throws {
        guard let downloads = await MainActor.run(body: { self.downloads }) else { return }
        await downloads.syncAndWait()
    }
}
