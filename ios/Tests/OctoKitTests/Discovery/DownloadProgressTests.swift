import Foundation
import Testing
@testable import OctoKit

private let now0: Int64 = 1_000_000_000_000

private func find(_ id: String, _ title: String, artist: String = "Kavinsky", requestedAt: Int64 = now0, adoptedId: String = "") -> FindSong {
    FindSong(id: id, sourceId: "server:octo", title: title, artist: artist, album: "OutRun", requestedAt: requestedAt, adoptedId: adoptedId)
}

private func entry(_ id: String, _ state: String, _ progress: Double? = nil, title: String = "Nightcall", artist: String = "Kavinsky",
                   error: String? = nil, libraryId: String? = nil, startedAt: String? = "2026-09-26T18:00:00Z") -> Acquisition {
    Acquisition(id: id, artist: artist, title: title, state: state, progress: progress, startedAt: startedAt, error: error, libraryId: libraryId)
}

/// A clock the tests move by hand; waiting on it moves it at once.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: Int64 = 0
    var now: Int64 { lock.withLock { now0 + elapsed } }
    func advance(_ ms: Int64) { lock.withLock { elapsed += ms } }
}

/// Stands in for the server and the library.
private final class FakeHost: AcquisitionHost, @unchecked Sendable {
    private let lock = NSLock()
    private var _finds: [FindSong]
    private var _calls: [String] = []
    private var _asked = 0
    var answer: (Int) throws -> [Acquisition]? = { _ in [] }
    var library: [String: String] = [:]
    var onSync: () -> Void = {}

    init(_ finds: FindSong...) { _finds = finds }

    var calls: [String] { lock.withLock { _calls } }
    var asked: Int {
        get { lock.withLock { _asked } }
        set { lock.withLock { _asked = newValue } }
    }

    func waiting() async -> [FindSong] { lock.withLock { _finds.filter { $0.adoptedId.isEmpty } } }

    func acquisitions() async throws -> [Acquisition]? {
        let count = lock.withLock { () -> Int in
            _asked += 1
            return _asked
        }
        return try answer(count)
    }

    func takeIn(_ libraryId: String) async throws -> String? {
        lock.withLock { _calls.append("take in \(libraryId)") }
        return library[libraryId]
    }

    func adopt(_ findId: String, _ trackId: String) async {
        lock.withLock { _calls.append("adopt \(findId) as \(trackId)") }
        adoptNow(findId, trackId)
    }

    func syncAndWait() async throws {
        lock.withLock { _calls.append("sync") }
        onSync()
    }

    func adoptNow(_ findId: String, _ trackId: String) {
        lock.withLock {
            if let at = _finds.firstIndex(where: { $0.id == findId }) { _finds[at].adoptedId = trackId }
        }
    }

    func row(_ findId: String) -> FindSong { lock.withLock { _finds.first { $0.id == findId }! } }

    func add(_ find: FindSong) { lock.withLock { _finds.append(find) } }

    var finds: [FindSong] { lock.withLock { _finds } }
}

private func watchOf(_ host: FakeHost, _ clock: TestClock) -> ProgressWatch {
    ProgressWatch(host: host, clock: { clock.now }, sleep: { ms in
        clock.advance(ms)
        await Task.yield()
    })
}

private struct Away: Error {}

@Suite struct DownloadProgressTests {
    @Test func serverStagesMapOntoWhatTheButtonShows() {
        #expect(phaseOf(entry("a", "queued")) == .queued)
        #expect(phaseOf(entry("a", "searching")) == .queued)
        #expect(phaseOf(entry("a", "downloading", 0.42)) == .downloading(0.42))
        #expect(phaseOf(entry("a", "downloading")) == .downloading(nil))
        #expect(phaseOf(entry("a", "verifying")) == .adding)
        #expect(phaseOf(entry("a", "importing")) == .adding)
        // Finished on the server is still being added until the library has it.
        #expect(phaseOf(entry("a", "done")) == .adding)
        #expect(phaseOf(entry("a", "failed", error: "No source had this song")) == .failed("No source had this song"))
        #expect(phaseOf(entry("a", "failed", error: " ")) == .failed("the server did not say why"))
        // A stage from a newer server waits like a queued one.
        #expect(phaseOf(entry("a", "teleporting")) == .queued)
    }

    @Test func theLibraryHasTheLastWord() {
        let asked = find("a", "Nightcall")
        #expect(phaseFor(asked, live: nil, now: now0) == .queued)
        #expect(phaseFor(asked, live: .downloading(0.5), now: now0) == .downloading(0.5))
        var adopted = asked
        adopted.adoptedId = "t1"
        #expect(phaseFor(adopted, live: .adding, now: now0) == .done)
        var notAsked = asked
        notAsked.requestedAt = 0
        #expect(phaseFor(notAsked, live: .adding, now: now0) == DownloadPhase.none)
        // A download asked for a day ago that never came can be asked for again.
        #expect(phaseFor(asked, live: nil, now: now0 + 25 * 60 * 60_000) == DownloadPhase.none)
    }

    @Test func thePlainStateKeepsAFailureAskable() {
        #expect(DownloadPhase.none.state == .none)
        #expect(DownloadPhase.queued.state == .requested)
        #expect(DownloadPhase.downloading(0.1).state == .requested)
        #expect(DownloadPhase.adding.state == .requested)
        #expect(DownloadPhase.done.state == .done)
        #expect(DownloadPhase.failed("x").state == .none)
    }

    @Test func pollCadence() {
        #expect(pollDelayMs(downloadingOnScreen: true, foreground: true) == 2_000)
        #expect(pollDelayMs(downloadingOnScreen: false, foreground: true) == 5_000)
        #expect(pollDelayMs(downloadingOnScreen: true, foreground: false) == 30_000)
        #expect(pollDelayMs(downloadingOnScreen: false, foreground: false) == 30_000)
    }

    @Test func entriesAreFoundByIdThenByTitle() {
        let night = find("dz-1", "Nightcall")
        #expect(acquisitionFor(night, [entry("dz-9", "queued"), entry("dz-1", "queued", title: "Other")])?.id == "dz-1")
        // A song of an album asked for at once, listed under another id.
        #expect(acquisitionFor(night, [entry("album-7", "downloading", title: "Nightcall (feat. Lovefoxxx)")])?.id == "album-7")
        // Not a remix, and not another artist's song.
        #expect(acquisitionFor(night, [entry("x", "queued", title: "Nightcall (Breakbot Remix)")]) == nil)
        #expect(acquisitionFor(night, [entry("x", "queued", artist: "London Grammar")]) == nil)
        // The newest entry wins when a song was asked for twice.
        let twice = [entry("dz-1", "failed", startedAt: "2026-09-26T17:00:00Z"), entry("dz-1", "queued", startedAt: "2026-09-26T18:00:00Z")]
        #expect(acquisitionFor(night, twice)?.state == "queued")
    }

    @Test func progressNeverGoesBackwards() async {
        let host = FakeHost(find("a", "Nightcall"))
        let answers: [Double?] = [0.3, 0.5, 0.2, nil, 0.7]
        host.answer = { count in [entry("a", "downloading", answers[min(count, answers.count) - 1])] }
        let watch = watchOf(host, TestClock())
        var seen: [DownloadPhase?] = []
        for _ in 0..<5 {
            _ = await watch.poll(canArrive: true)
            seen.append(watch.live["a"])
        }
        #expect(seen == [0.3, 0.5, 0.5, 0.5, 0.7].map { DownloadPhase.downloading($0) })
    }

    @Test func asksOftenOnlyWhileADownloadIsOnScreen() async {
        let host = FakeHost(find("a", "Nightcall"))
        host.answer = { _ in [entry("a", "downloading", 0.5)] }
        let watch = watchOf(host, TestClock())
        _ = await watch.poll(canArrive: true)
        // Nothing on screen: every 5 seconds.
        #expect(watch.nextDelayMs() == 5_000)
        // On screen: every 2 seconds.
        let hide = watch.show("a")
        #expect(watch.nextDelayMs() == 2_000)
        // The app in the background: every 30 seconds, whatever is shown.
        watch.foreground = false
        #expect(watch.nextDelayMs() == 30_000)
        watch.foreground = true
        #expect(watch.nextDelayMs() == 2_000)
        hide()
        #expect(watch.nextDelayMs() == 5_000)
    }

    @Test func stopsWhenNothingIsLeftWaiting() async {
        let host = FakeHost(find("a", "Nightcall"))
        host.answer = { count in
            if count == 3 { host.adoptNow("a", "t1") }
            return [entry("a", "queued")]
        }
        let watch = watchOf(host, TestClock())
        #expect(await watch.run())
        #expect(host.asked == 3)
        #expect(watch.live.isEmpty)
    }

    @Test func aCanceledWatchStopsEvenWhileSongsWait() async {
        let host = FakeHost(find("a", "Nightcall"))
        host.answer = { _ in [entry("a", "downloading", 0.4)] }
        let watch = ProgressWatch(host: host, sleep: { _ in try? await Task.sleep(for: .seconds(60)) })
        let running = Task { await watch.run() }
        while host.asked == 0 { await Task.yield() }
        running.cancel()
        #expect(await running.value)
        #expect(host.asked == 1)
    }

    @Test func aFinishedSongIsFetchedThenSyncedThenAdopted() async {
        let host = FakeHost(find("a", "Roadgame"))
        host.answer = { _ in [entry("a", "done", title: "Roadgame", libraryId: "nd-77")] }
        host.library = ["nd-77": "server:octo:nd-77"]
        let clock = TestClock()
        let watch = watchOf(host, clock)
        var shown: [DownloadPhase] = []
        // What the button shows at each step of bringing the song in.
        host.onSync = { shown.append(phaseFor(host.row("a"), live: watch.live["a"], now: now0)) }
        #expect(await watch.run())
        #expect(host.calls == ["take in nd-77", "adopt a as server:octo:nd-77", "sync"])
        // Adopted before the full look, so the check shows at once.
        #expect(shown == [.done])
        #expect(phaseFor(host.row("a"), live: watch.live["a"], now: now0) == .done)
    }

    @Test func theSecondSongAddedPlaysItselfWhenTapped() async {
        let uicideOnServer = "dAti9HX34pPuxG3bYPqDPJ", huntinOnServer = "cEi8RizCv3u1jOCzd6jCJL"
        let uicideSong = "server:octo:\(uicideOnServer)", huntinSong = "server:octo:\(huntinOnServer)"
        let uicide = find("uicide", "$UICIDE", artist: "$uicideboy$", requestedAt: now0)
        let huntin = find("huntin", "Huntin' Wabbitz", artist: "J. Cole", requestedAt: now0 + 6 * 60_000)
        let host = FakeHost(uicide)
        host.library = [uicideOnServer: uicideSong, huntinOnServer: huntinSong]
        let first = entry("uicide", "done", title: uicide.title, artist: uicide.artist, libraryId: uicideOnServer,
                          startedAt: "2026-09-27T12:00:00Z")
        host.answer = { _ in [first] }
        let clock = TestClock()
        let watch = watchOf(host, clock)
        // "$UICIDE" is added and arrives.
        #expect(await watch.run())
        // Six minutes on, "Huntin' Wabbitz" is added and arrives; the server still lists the first.
        clock.advance(6 * 60_000)
        host.add(huntin)
        let second = entry("huntin", "done", title: huntin.title, artist: huntin.artist, libraryId: huntinOnServer,
                           startedAt: "2026-09-27T12:06:00Z")
        host.answer = { _ in [first, second] }
        #expect(await watch.run())
        // Each find is linked to its own library song.
        #expect(host.row("uicide").adoptedId == uicideSong)
        #expect(host.row("huntin").adoptedId == huntinSong)
        // Tapping the second plays the list from it, by the finds' ids.
        let asked = ["uicide", "huntin"]
        let library: Set<String> = [uicideSong, huntinSong]
        let stored = Dictionary(host.finds.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let played = asked.map { id in stored[id].map { playsAs(findId: $0.id, adoptedId: $0.adoptedId, library: library) } }
        #expect(played == [uicideSong, huntinSong])
        let start = chosenStart(played, asked.firstIndex(of: "huntin")!)
        #expect(played.compactMap { $0 }[start] == huntinSong)
    }

    @Test func aFinishedSongWithoutALibraryIdWaitsForTheSync() async {
        let host = FakeHost(find("a", "Roadgame"))
        host.answer = { _ in [entry("a", "done", title: "Roadgame")] }
        let watch = watchOf(host, TestClock())
        var before: [DownloadPhase] = []
        host.onSync = {
            // Still being added while the library is looked at: no check yet.
            before.append(phaseFor(host.row("a"), live: watch.live["a"], now: now0))
            host.adoptNow("a", "t9")
        }
        #expect(await watch.run())
        #expect(host.calls == ["sync"])
        #expect(before == [.adding])
        #expect(phaseFor(host.row("a"), live: watch.live["a"], now: now0) == .done)
    }

    @Test func aSongTheLibraryHasNotTakenInIsTriedAFewTimesThenLeft() async {
        let host = FakeHost(find("a", "Roadgame"))
        host.answer = { _ in [entry("a", "done", title: "Roadgame")] }
        let watch = watchOf(host, TestClock())
        #expect(await watch.run())
        #expect(host.calls == Array(repeating: "sync", count: arrivalTries))
        // In the server's library: shown as in the library, not as on its way.
        #expect(watch.live["a"] == .done)
        #expect(phaseFor(host.row("a"), live: watch.live["a"], now: now0, listedSince: watch.listedSince) == .done)
    }

    @Test func aServerThatCannotSayFallsBackAtOnce() async {
        let host = FakeHost(find("a", "Nightcall"))
        host.answer = { _ in nil }
        let watch = watchOf(host, TestClock())
        #expect(await watch.run() == false)
        #expect(host.asked == 1)
        #expect(host.calls.isEmpty)
    }

    @Test func anUnreachableServerIsAskedAgainLater() async {
        let host = FakeHost(find("a", "Nightcall"))
        var down = true
        host.answer = { _ in
            if down { throw Away() }
            return [entry("a", "downloading", 0.2)]
        }
        let watch = watchOf(host, TestClock())
        if case .asked(let due) = await watch.poll(canArrive: true) { #expect(due.isEmpty) } else { Issue.record("not asked again") }
        down = false
        _ = await watch.poll(canArrive: true)
        #expect(watch.live["a"] == .downloading(0.2))
    }

    @Test func aFailureIsShownAndAskingAgainStartsAfresh() async {
        let host = FakeHost(find("a", "Nightcall"))
        let old = entry("a", "failed", error: "No source had this song", startedAt: "2026-09-26T17:00:00Z")
        var list = [old]
        host.answer = { _ in list }
        let watch = watchOf(host, TestClock())
        // Only a failure left: nothing to wait for.
        #expect(await watch.run())
        #expect(watch.live["a"] == .failed("No source had this song"))

        // Asked again: the old failure the server still lists is passed over.
        watch.retry("a")
        #expect(watch.live["a"] == nil)
        _ = await watch.poll(canArrive: true)
        #expect(watch.live["a"] == nil)
        list = [old, entry("a", "searching", startedAt: "2026-09-26T17:05:00Z")]
        _ = await watch.poll(canArrive: true)
        #expect(watch.live["a"] == .queued)
    }

    // MARK: The same rule as the downloads pill

    @Test func aDownloadTheServersListDoesNotShowIsNotQueued() {
        let asked = find("a", "Nightcall")
        let later = now0 + 1_000
        #expect(phaseFor(asked, live: nil, now: later, listedSince: now0 - 1) == .queued, "No list since the ask")
        #expect(phaseFor(asked, live: nil, now: later, listedSince: now0 + 500) == DownloadPhase.none, "A list asked for after the ask, without it")
        #expect(phaseFor(asked, live: nil, now: now0 + 60_000) == .queued, "No list coming back, within two minutes")
        #expect(phaseFor(asked, live: nil, now: now0 + 2 * 60_000) == DownloadPhase.none, "No list coming back, after two minutes")
        #expect(phaseFor(asked, live: nil, now: now0 + 60 * 60_000) == DownloadPhase.none, "An hour on, after a restart")
        #expect(phaseFor(asked, live: .downloading(0.3), now: later, listedSince: now0 + 500) == .downloading(0.3), "The server's news still wins")
        var landed = asked
        landed.adoptedId = "t1"
        #expect(phaseFor(landed, live: nil, now: later, listedSince: now0 + 500) == .done, "Landed")
    }

    @Test func aSongAskedWithItsAlbumWaitsForTheAlbum() {
        let asked = find("a", "Nightcall")
        #expect(phaseFor(asked, live: nil, now: now0 + 10 * 60_000, listedSince: now0 + 9 * 60_000, album: true) == .queued)
        #expect(phaseFor(asked, live: nil, now: now0 + 30 * 60_000, listedSince: now0 + 29 * 60_000, album: true) == DownloadPhase.none)
    }

    @Test func aServerThatListsNothingKeepsItsDownloadsQueuedUntilGivenUp() {
        let asked = find("a", "Nightcall")
        #expect(phaseFor(asked, live: nil, now: now0 + 3 * 60 * 60_000, lists: false) == .queued)
        #expect(phaseFor(asked, live: nil, now: now0 + 25 * 60 * 60_000, lists: false) == DownloadPhase.none)
    }

    @Test func songsAskedForWithTheirAlbumShareItsTime() {
        var one = find("a", "Nightcall")
        one.albumId = "al-1"
        var two = find("b", "Roadgame")
        two.albumId = "al-1"
        var alone = find("c", "Testarossa", requestedAt: now0 + 5)
        alone.albumId = "al-1"
        var other = find("d", "Odd Look")
        other.albumId = "al-2"
        #expect(askedWithAlbum([one, two, alone, other]) == ["a", "b"])
        #expect(askedSongs([one, two, alone, other], sourceId: "server:octo").map(\.album) == [true, true, false, false])
    }

    @Test func anotherServersListSaysNothingOfThisServersFinds() {
        let here = find("a", "Nightcall")
        var there = find("b", "Roadgame")
        there.sourceId = "server:other"
        let inputs = PhaseInputs(rows: [here, there], live: [:], listedSince: now0 + 500, lists: true, sourceId: "server:octo")
        let phases = phasesOf(inputs, now: now0 + 1_000)
        #expect(phases["a"] == DownloadPhase.none)
        #expect(phases["b"] == .queued, "Still within two minutes of its ask")
        #expect(recheckMs(inputs, now: now0 + 1_000) == Int64(2 * 60_000 - 1_000))
        #expect(recheckMs(PhaseInputs(rows: [here], live: [:], listedSince: now0 + 500, lists: true, sourceId: "server:octo"), now: now0 + 1_000) == nil)
    }

    @Test func theWatchSaysWhenItsNewestListWasAskedForAndAForgottenDownloadLeaves() async {
        let host = FakeHost(find("a", "Nightcall"))
        var list = [entry("a", "downloading", 0.4)]
        host.answer = { _ in list }
        let clock = TestClock()
        let watch = watchOf(host, clock)
        #expect(watch.listedSince == nil)
        _ = await watch.poll(canArrive: true)
        #expect(watch.listedSince == now0)
        #expect(phaseFor(host.row("a"), live: watch.live["a"], now: now0, listedSince: watch.listedSince) == .downloading(0.4))

        // The server restarted and forgot it.
        list = []
        clock.advance(pollMs)
        _ = await watch.poll(canArrive: true)
        #expect(watch.live["a"] == nil)
        #expect(phaseFor(host.row("a"), live: nil, now: clock.now, listedSince: watch.listedSince) == DownloadPhase.none)
    }

    @Test func aSongTheServerNeverTookShowsAddAfterTheFirstList() async {
        let host = FakeHost(find("a", "Nightcall", requestedAt: now0 - 1))
        let watch = watchOf(host, TestClock())
        _ = await watch.poll(canArrive: true)
        #expect(phaseFor(host.row("a"), live: watch.live["a"], now: now0, listedSince: watch.listedSince) == DownloadPhase.none)
    }
}

@Suite struct ArrivalsTests {
    @Test func aSongAskedForIsAnnouncedOnce() {
        let arrivals = Arrivals()
        arrivals.askedSong("1", title: "Nightcall")
        #expect(arrivals.landed("1") == "Nightcall is in your library")
        #expect(arrivals.landed("1") == nil)
    }

    @Test func aSongAskedForBeforeTheAppStartedArrivesQuietly() {
        #expect(Arrivals().landed("1") == nil)
    }

    @Test func anAlbumIsAnnouncedWhenItsLastSongLands() {
        let arrivals = Arrivals()
        arrivals.askedAlbum("OutRun", findIds: ["1", "2", "3"])
        #expect(arrivals.landed("2") == nil)
        #expect(arrivals.landed("1") == nil)
        #expect(arrivals.landed("3") == "OutRun is in your library")
    }

    @Test func anAlbumWithASongThatFailedSaysSo() {
        let arrivals = Arrivals()
        arrivals.askedAlbum("OutRun", findIds: ["1", "2", "3"])
        #expect(arrivals.landed("1") == nil)
        #expect(arrivals.failed("2") == nil)
        #expect(arrivals.landed("3") == "OutRun is in your library, but 1 song could not be downloaded")
    }

    @Test func anAlbumWhoseLastSongFailedIsSettledByTheFailure() {
        let arrivals = Arrivals()
        arrivals.askedAlbum("OutRun", findIds: ["1", "2", "3"])
        #expect(arrivals.failed("1") == nil)
        #expect(arrivals.landed("2") == nil)
        #expect(arrivals.failed("3") == "OutRun is in your library, but 2 songs could not be downloaded")
    }

    @Test func anAlbumWhereNothingCameSaysNothing() {
        let arrivals = Arrivals()
        arrivals.askedAlbum("OutRun", findIds: ["1", "2"])
        #expect(arrivals.failed("1") == nil)
        #expect(arrivals.failed("2") == nil)
    }

    @Test func aSongOfTheAlbumAskedForAgainStillCountsWithTheAlbum() {
        let arrivals = Arrivals()
        arrivals.askedAlbum("OutRun", findIds: ["1", "2"])
        #expect(arrivals.failed("1") == nil)
        arrivals.askedSong("1", title: "Nightcall")
        #expect(arrivals.landed("2") == nil)
        #expect(arrivals.landed("1") == "OutRun is in your library")
    }

    @Test func aSongAskedForAloneThenWithItsAlbumIsAnnouncedWithTheAlbum() {
        let arrivals = Arrivals()
        arrivals.askedSong("1", title: "Nightcall")
        arrivals.askedAlbum("OutRun", findIds: ["1", "2"])
        #expect(arrivals.landed("1") == nil)
        #expect(arrivals.landed("2") == "OutRun is in your library")
    }

    @Test func aFailedSongOnItsOwnSaysNothing() {
        let arrivals = Arrivals()
        arrivals.askedSong("1", title: "Nightcall")
        #expect(arrivals.failed("1") == nil)
    }
}

@Suite struct KeysTests {
    @Test func accentsAndCaseAreIgnored() {
        #expect(searchKey("Beyoncé") == "beyonce")
        #expect(searchKey(" Mötley Crüe ") == "motley crue")
    }

    @Test func leadingArticleIsDroppedForSorting() {
        #expect(sortKey("The Beatles") == "beatles")
        #expect(sortKey("A Tribe Called Quest") == "tribe called quest")
        // A name that is only an article, or merely starts with the letters, stays whole.
        #expect(sortKey("The") == "the")
        #expect(sortKey("Theory") == "theory")
    }

    @Test func naturalKeysOrderNumbersByValue() {
        let names = ["Album 10", "Album 2", "The Album 1", "Album 007", "album 2b"]
        #expect(names.sorted { naturalSortKey($0) < naturalSortKey($1) } == ["The Album 1", "Album 2", "album 2b", "Album 007", "Album 10"])
    }
}

@Suite struct MatchingTests {
    private func song(_ id: String, _ title: String, _ artist: String, seconds: Int = 180) -> Song {
        Song(id: id, title: title, artist: artist, album: title, duration: seconds, coverArt: id, suffix: "m4a")
    }

    @Test func aGuessedLengthCountsAsUnknown() {
        #expect(knownLengthMs(song("x", "A", "B", seconds: 180)) == 0)
        #expect(knownLengthMs(song("x", "A", "B", seconds: 0)) == 0)
        #expect(knownLengthMs(song("x", "A", "B", seconds: 215)) == 215_000)
    }

    @Test func titleKeysIncludeTheBareTitle() {
        #expect(titleKeys("One Dance (feat. Wizkid)") == ["one dance (feat. wizkid)", "one dance"])
    }

    @Test func titleKeysIncludeTheTitleAPersonWouldSay() {
        #expect(titleKeys("01 - Teardrop - Remastered 2011") == ["01 - teardrop - remastered 2011", "teardrop"])
    }

    @Test func lengthsOnlyCountWhenBothAreKnown() {
        #expect(!sameSong("Around the World", "Daft Punk", 238_000, "Around the World", "Daft Punk", 429_000))
        #expect(sameSong("Around the World", "Daft Punk", 0, "Around the World", "Daft Punk", 429_000))
        #expect(!sameSong("Nightcall - Live", "Kavinsky", 0, "Nightcall", "Kavinsky", 179_000))
    }

    @Test func oneIsrcOnBothSidesIsOneRecording() {
        let code = ["JPU901901234"]
        #expect(sameSong("紅蓮華", "LiSA", 239_000, "Gurenge", "LiSA", 239_000, isrcs: code, otherIsrcs: ["JP-U90-19-01234"]))
        #expect(sameRecording("紅蓮華", "LiSA", "Gurenge", "LiSA", isrcsA: code, isrcsB: code))
        #expect(sameSongAnyVersion("紅蓮華", "LiSA", "Gurenge", "LiSA", isrcsA: code, isrcsB: code))
        // A code on one side only, or none at all, leaves it to the titles.
        #expect(!sameSong("紅蓮華", "LiSA", 0, "Gurenge", "LiSA", 0, isrcs: code))
        #expect(!sameRecording("紅蓮華", "LiSA", "Gurenge", "LiSA"))
        // Different codes decide nothing: the titles still do.
        #expect(!sameSong("Nightcall - Live", "Kavinsky", 0, "Nightcall", "Kavinsky", 0, isrcs: ["FR0000000001"], otherIsrcs: ["FR0000000002"]))
        #expect(sameSong("Nightcall", "Kavinsky", 0, "Nightcall", "Kavinsky", 0, isrcs: ["FR0000000001"], otherIsrcs: ["FR0000000002"]))
    }

    @Test func anIsrcIndexFindsSongsByAnyOfTheirCodes() {
        struct Coded { let id: String; let isrc: [String] }
        let library = [Coded(id: "a", isrc: ["jp-u90-19-01234"]), Coded(id: "b", isrc: ["not a code"]),
                       Coded(id: "c", isrc: ["JPU902003065", "JPU901901234"])]
        let index = IsrcIndex(library, isrcs: \.isrc)
        #expect(index.candidates(["JPU901901234"]).map(\.id) == ["a", "c"])
        #expect(index.candidates(["not a code"]).isEmpty)
        #expect(index.candidates([]).isEmpty)
    }
}
