import Foundation
import Testing
@testable import OctoKit

/// Something that waits until a test lets it go, and stops waiting when its task is stopped.
@MainActor
final class LyricsGate<T: Sendable> {
    private var waiting: [CheckedContinuation<T?, Never>] = []
    private var value: T?

    func wait() async -> T? {
        if let value { return value }
        return await withCheckedContinuation { waiting.append($0) }
    }

    func open(_ value: T) {
        self.value = value
        let all = waiting
        waiting = []
        for one in all { one.resume(returning: value) }
    }
}

/// Lets the tasks the main actor has queued run until there is nothing left for them to do.
@MainActor
func lyricsSettle() async {
    for _ in 0..<200 { await Task.yield() }
}

// What the lyrics view shows as songs change and the app goes to the background and back.
@MainActor
@Suite final class LyricsFeedTest {
    func words(_ text: String) -> Lyrics { Lyrics(synced: true, lines: [LyricLine(startMs: 0, text: text)], source: .server) }

    var answers: [String: LyricsAnswer] = [:]
    var waiting: [String: LyricsGate<LyricsAnswer>] = [:]
    var asked: [(String, Bool)] = []
    var network = LyricsGate<Bool>()
    var networkWaits = 0
    var sleeping: [CheckedContinuation<Void, Never>] = []
    var states: [LyricsState] = []
    var feed: LyricsFeed!

    struct Missing: Error {}

    func start(_ first: String?, watching: Bool) async {
        feed = LyricsFeed(
            lookUp: { [unowned self] id, resumed in
                asked.append((id, resumed))
                if let gate = waiting[id] { return await gate.wait() ?? .failed }
                guard let answer = answers[id] else { throw Missing() }
                return answer
            },
            networkBack: { [unowned self] in
                networkWaits += 1
                _ = await network.wait()
            },
            sleep: { [unowned self] _ in
                await withCheckedContinuation { sleeping.append($0) }
            },
            onState: { [unowned self] in states.append($0) }
        )
        feed.start(wanted: first.map { LyricsWanted($0) }, watched: watching)
        await lyricsSettle()
    }

    /// Lets the quiet retries after a failure run out.
    func passQuietRetries() async {
        for _ in 0..<QUIET_RETRIES {
            let all = sleeping
            sleeping = []
            for one in all { one.resume() }
            await lyricsSettle()
        }
    }

    var shown: LyricsState? { states.last }
    var lastAsked: (String, Bool)? { asked.last }

    @Test func aSongChangeWhileAwayShowsLoadingUntilTheViewIsBack() async {
        answers["a"] = .found(words("a"))
        answers["b"] = .found(words("b"))
        await start("a", watching: true)
        #expect(shown == .found("a", words("a")))
        feed.setWatched(false)
        await lyricsSettle()
        feed.setWanted(LyricsWanted("b"))
        await lyricsSettle()
        #expect(shown == .loading)
        #expect(!states.contains(.none))
        #expect(asked.count == 1 && asked[0] == ("a", true))
        feed.setWatched(true)
        await lyricsSettle()
        #expect(lastAsked.map { $0 == ("b", true) } == true)
        #expect(shown == .found("b", words("b")))
    }

    @Test func aSongChangeOnScreenShowsLoadingThenTheNewSong() async {
        answers["a"] = .found(words("a"))
        let gate = LyricsGate<LyricsAnswer>()
        waiting["b"] = gate
        await start("a", watching: true)
        feed.setWanted(LyricsWanted("b"))
        await lyricsSettle()
        #expect(shown == .loading)
        #expect(lastAsked.map { $0 == ("b", false) } == true)
        gate.open(.none)
        await lyricsSettle()
        #expect(shown == LyricsState.none)
    }

    @Test func aFailureIsAskedAgainQuietlyBeforeItShows() async {
        answers["a"] = .failed
        await start("a", watching: true)
        #expect(shown == .loading)
        answers["a"] = .found(words("a"))
        let all = sleeping
        sleeping = []
        for one in all { one.resume() }
        await lyricsSettle()
        #expect(shown == .found("a", words("a")))
        #expect(!states.contains { if case .failed = $0 { true } else { false } })
    }

    @Test func aFailureShowsAsFailedAndResumingLooksUpAgain() async {
        answers["a"] = .failed
        await start("a", watching: true)
        await passQuietRetries()
        #expect(shown == .failed("a"))
        #expect(!states.contains(.none))
        answers["a"] = .found(words("a"))
        feed.setWatched(false)
        await lyricsSettle()
        #expect(shown == .failed("a"))
        feed.setWatched(true)
        await lyricsSettle()
        #expect(lastAsked.map { $0 == ("a", true) } == true)
        #expect(shown == .found("a", words("a")))
    }

    @Test func aFailureIsTriedOnceMoreWhenTheNetworkComesBack() async {
        answers["a"] = .failed
        await start("a", watching: true)
        await passQuietRetries()
        #expect(shown == .failed("a"))
        #expect(asked.count == 1 + QUIET_RETRIES)
        network.open(true)
        await lyricsSettle()
        #expect(asked.count == 2 + QUIET_RETRIES)
        #expect(networkWaits == 1)
        #expect(shown == .failed("a"))
    }

    @Test func theRetryAfterTheNetworkComesBackCanFindThem() async {
        answers["a"] = .failed
        await start("a", watching: true)
        await passQuietRetries()
        answers["a"] = .found(words("a"))
        network.open(true)
        await lyricsSettle()
        #expect(shown == .found("a", words("a")))
    }

    @Test func resumingChecksANoneAgainWithoutBlankingIt() async {
        answers["a"] = LyricsAnswer.none
        await start("a", watching: true)
        #expect(shown == LyricsState.none)
        feed.setWatched(false)
        await lyricsSettle()
        let gate = LyricsGate<LyricsAnswer>()
        waiting["a"] = gate
        feed.setWatched(true)
        await lyricsSettle()
        #expect(lastAsked.map { $0 == ("a", true) } == true)
        #expect(shown == LyricsState.none)
        gate.open(.found(words("a")))
        await lyricsSettle()
        #expect(shown == .found("a", words("a")))
    }

    @Test func aLookupThatThrowsIsAFailureNotNone() async {
        await start("missing", watching: true)
        await passQuietRetries()
        #expect(shown == .failed("missing"))
    }

    @Test func nothingIsLookedUpWhileTheViewIsAway() async {
        answers["a"] = .found(words("a"))
        await start("a", watching: false)
        #expect(shown == .loading)
        #expect(asked.isEmpty)
    }

    @Test func closedAndHiddenLyricsAreNotLookedUp() async {
        await start(nil, watching: true)
        #expect(shown == .hidden)
        feed.setWanted(LyricsWanted("a", hidden: true))
        await lyricsSettle()
        #expect(shown == .hiddenForSong)
        #expect(asked.isEmpty)
    }
}
