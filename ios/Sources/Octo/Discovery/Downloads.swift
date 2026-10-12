import Foundation
import Observation
import OctoKit

// When to look for downloads in the library after asking for one, on a server that does not say
// how its downloads are going: a little later, and once more for slow ones.
private let checkAfterMs: [Int64] = [2 * 60_000, 8 * 60_000]

/// Finds that have not come up for this long are let go.
private let forgetMs: Int64 = 30 * 24 * 60 * 60_000

/// How long a server that could not say how its downloads are going is believed, before it is
/// asked again (it may have been updated meanwhile).
private let recheckSupportMs: Int64 = 10 * 60_000

private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }

/// Downloading songs found online into the library. On Octo, starring a find from an Octo app
/// makes the server download it; once the library has the song, the find is linked to it (not
/// liked). A server that says how its downloads are going is asked every few seconds while any
/// is on its way; others are looked at again on a timer.
@MainActor
@Observable
final class Downloads {
    /// Every find asked for, and how its download is going.
    private(set) var phases: [String: DownloadPhase] = [:]
    /// Each find now in the library, by the library song it became. Nil until first read, so a
    /// row can tell a song that was already in the library from one that arrives while it is shown.
    private(set) var adoptions: [String: String]?
    /// Songs asked for from this phone on the server in use that have not reached the library.
    private(set) var asked: [AskedSong] = []
    /// Goes up by one each time downloads join the library, so pages that hold what the server
    /// said can ask again.
    private(set) var arrived = 0
    /// Whether the server in use lists its downloads, as far as is known.
    private(set) var lists = true

    @ObservationIgnored private let session: Session
    @ObservationIgnored private let announce: @MainActor (String, Bool) -> Void
    @ObservationIgnored private var rows: [FindSong] = []
    @ObservationIgnored private lazy var tracker = ProgressWatch(host: DownloadsHost(self))
    @ObservationIgnored private let arrivals = Arrivals()
    @ObservationIgnored private var following = false
    @ObservationIgnored private var checks: Task<Void, Never>?
    @ObservationIgnored private var recheck: Task<Void, Never>?
    @ObservationIgnored private var support: [String: (yes: Bool, at: Int64)] = [:]
    @ObservationIgnored private var failedBefore = Set<String>()
    @ObservationIgnored private var lastSource: String?

    private static var storeURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("finds.json")
    }

    /// `announce` shows a line: the words, and whether it marks something done.
    init(session: Session, announce: @escaping @MainActor (String, Bool) -> Void) {
        self.session = session
        self.announce = announce
        if let data = try? Data(contentsOf: Self.storeURL), let saved = try? JSONDecoder().decode([FindSong].self, from: data) {
            rows = saved
        }
        lastSource = session.activeId
        tracker.foreground = false
        tracker.changed = { [weak self] in Task { @MainActor in self?.liveChanged() } }
        refresh()
    }

    func phase(_ songId: String) -> DownloadPhase { phases[songId] ?? .none }

    /// The finds whose download has arrived in the library.
    var adopted: Set<String> { Set(phases.filter { $0.value == .done }.keys) }

    /// Library songs that finds became, as last read, so a find's row can turn into its song.
    private(set) var librarySongs: [String: Song] = [:]
    @ObservationIgnored private var lookingUp = Set<String>()

    /// The library song a find became, as last read; nil until it has been read.
    func librarySong(_ id: String) -> Song? { librarySongs[id] }

    /// The same, for the pages that resolve what the server sent.
    func lastSeenLibrarySong(_ id: String) -> Song? { librarySongs[id] }

    /// Reads a library song a find became, once, so its row can turn into it.
    func lookUpLibrarySong(_ id: String) {
        guard librarySongs[id] == nil, !lookingUp.contains(id), let client = session.client else { return }
        lookingUp.insert(id)
        Task {
            defer { lookingUp.remove(id) }
            if let song = try? await client.song(id), !song.isExternal { librarySongs[id] = song }
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
        guard song.isExternal, let client = session.client, let source = session.activeId else { return false }
        do {
            try await client.star(songId: song.id)
        } catch {
            return false
        }
        keep(song, source: source, requestedAt: nowMs())
        SearchModel.hintAdded()
        arrivals.askedSong(song.id, title: song.title)
        tracker.retry(song.id)
        follow()
        return true
    }

    /// Asks the server to download a whole album found online, and follows the songs from it that
    /// are listed.
    func requestAlbum(_ albumId: String, songs: [Song], title: String = "") async -> Bool {
        guard let client = session.client, let source = session.activeId else { return false }
        do {
            try await client.star(albumId: albumId)
        } catch {
            return false
        }
        let now = nowMs()
        let finds = songs.filter(\.isExternal)
        for song in finds { keep(song, source: source, requestedAt: now) }
        SearchModel.hintAdded()
        let coming = finds.filter { state($0.id) != .done }
        arrivals.askedAlbum(title.isEmpty ? (coming.first?.album ?? "") : title, findIds: coming.map(\.id))
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
        if session.activeId != lastSource {
            lastSource = session.activeId
            checks?.cancel()
            checks = nil
            refresh()
        }
        guard session.client != nil else { return }
        prune()
        if !watchedWaiting().isEmpty, await reportsProgress() { follow() }
    }

    // MARK: Finds kept on the phone

    /// Keeps a find, or updates the one kept, with what the server says of it now.
    private func keep(_ song: Song, source: String, requestedAt: Int64? = nil) {
        if let index = rows.firstIndex(where: { $0.id == song.id && $0.sourceId == source }) {
            if let requestedAt { rows[index].requestedAt = requestedAt }
        } else {
            rows.append(FindSong(id: song.id, sourceId: source, title: song.title, artist: song.artist ?? "", album: song.album ?? "",
                                 albumId: song.albumId, durationMs: knownLengthMs(song), requestedAt: requestedAt ?? 0))
        }
        save()
        refresh()
    }

    /// Finds not asked for, or asked for and gone, for longer than a month are let go; finds of a
    /// server no longer kept go too.
    private func prune() {
        let now = nowMs()
        let kept = Set(session.servers.map(\.id))
        let before = rows.count
        rows.removeAll { !kept.contains($0.sourceId) || (now - $0.requestedAt > forgetMs && $0.adoptedId.isEmpty) }
        if rows.count != before {
            save()
            refresh()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rows) { try? data.write(to: Self.storeURL, options: .atomic) }
    }

    // MARK: Following

    /// The songs asked for lately on the server in use: another kept server's are followed once
    /// it is in use again.
    fileprivate func watchedWaiting() -> [FindSong] {
        guard let here = session.activeId else { return [] }
        let now = nowMs()
        return rows.filter { $0.sourceId == here && $0.requestedAt > 0 && $0.adoptedId.isEmpty && now - $0.requestedAt < giveUpMs }
    }

    /// Follows the downloads asked for: by asking the server how they are going when it can say;
    /// otherwise by looking at the library again a little later, and once more after that.
    private func follow() {
        if following {
            tracker.wake()
            return
        }
        checks?.cancel()
        checks = Task { [weak self] in
            guard let self else { return }
            if await self.reportsProgress() {
                self.following = true
                let done = await self.tracker.run()
                self.following = false
                if done { return }
            }
            await self.checkOnTimer()
        }
    }

    private func checkOnTimer() async {
        var waited: Int64 = 0
        for at in checkAfterMs {
            try? await Task.sleep(for: .milliseconds(at - waited))
            if Task.isCancelled { return }
            waited = at
            try? await lookInLibrary()
        }
    }

    /// Whether the server in use says how its downloads are going: from what it listed at sign-in,
    /// or by asking, since it may have been updated since.
    private func reportsProgress() async -> Bool {
        guard let source = session.activeId, let client = session.client else { return false }
        if session.profile?.lists(octoAcquisitions) == true {
            lists = true
            return true
        }
        let now = nowMs()
        if let known = support[source], known.yes || now - known.at < recheckSupportMs { return known.yes }
        do {
            _ = try await client.acquisitions()
            noteSupport(source, true)
            return true
        } catch is OctoError {
            noteSupport(source, false)
            return false
        } catch {
            // Out of reach: not noted, asked again next time.
            return false
        }
    }

    fileprivate func noteSupport(_ source: String, _ yes: Bool) {
        support[source] = (yes, nowMs())
        lists = yes
        refresh()
    }

    fileprivate func acquisitions() async throws -> [Acquisition]? {
        guard let client = session.client, let source = session.activeId else { return nil }
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
    fileprivate func takeIn(_ libraryId: String) async throws -> String? {
        guard let client = session.client else { return nil }
        let song = try await client.song(libraryId)
        return song.isExternal ? nil : song.id
    }

    /// Links a find to the library song it became. Downloading is not liking, so the song is not
    /// hearted; that stays the listener's call.
    fileprivate func adopt(_ findId: String, _ trackId: String) {
        guard let source = session.activeId,
              let index = rows.firstIndex(where: { $0.id == findId && $0.sourceId == source }),
              rows[index].adoptedId.isEmpty
        else { return }
        rows[index].adoptedId = trackId
        save()
        arrived += 1
        if let words = arrivals.landed(findId) { announce(words, true) }
        refresh()
    }

    /// Looks for the songs still waiting in the server's library: the same song by the same artist,
    /// of about the same length when both are known.
    fileprivate func lookInLibrary() async throws {
        guard let client = session.client else { return }
        for find in watchedWaiting() {
            let found = try await client.search("\(find.artist) \(find.title)", artists: 0, albums: 0, songs: 20)
            let library = found.song.filter { !$0.isExternal }
            let byTitle = TitleIndex(library, title: \.title, artist: { $0.artist ?? "" })
            if let match = byTitle.candidates(find.title, find.artist).first(where: {
                sameSong(find.title, find.artist, find.durationMs, $0.title, $0.artist ?? "", knownLengthMs($0))
            }) {
                adopt(find.id, match.id)
            }
        }
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
        let here = session.activeId
        let mine = rows.filter { $0.sourceId == here }
        let inputs = PhaseInputs(rows: mine.filter { $0.requestedAt > 0 || !$0.adoptedId.isEmpty }, live: tracker.live,
                                 listedSince: tracker.listedSince, lists: lists, sourceId: here)
        let now = nowMs()
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
        return try await downloads.takeIn(libraryId)
    }

    func adopt(_ findId: String, _ trackId: String) async { await MainActor.run { downloads?.adopt(findId, trackId) } }

    func syncAndWait() async throws {
        guard let downloads = await MainActor.run(body: { self.downloads }) else { return }
        try await downloads.lookInLibrary()
    }
}
