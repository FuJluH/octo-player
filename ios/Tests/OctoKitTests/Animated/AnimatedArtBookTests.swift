import Foundation
import Testing
@testable import OctoKit

/// Values a test changes while the book reads them from its own tasks.
private final class Shared<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func change(_ body: (inout Value) -> Void) { lock.withLock { body(&stored) } }
}

/// A gate the server's answer waits at until the test opens it.
private actor Gate {
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        open = true
        for one in waiting { one.resume() }
        waiting = []
    }
}

@Suite struct AnimatedArtBookTests {
    let art = AnimatedArt(square: AnimatedClip(video: "https://cdn.example.com/s.m3u8"))

    @Test func twoAsksAtOnceShareOneCall() async {
        let gate = Gate()
        let asked = Shared<[String]>([])
        let started = Shared(0)
        let art = self.art
        let book = AnimatedArtBook(offered: { true }, ask: { id in
            asked.change { $0.append(id) }
            started.change { $0 += 1 }
            await gate.wait()
            return .found(art)
        })
        async let first = book.art("al-1")
        async let second = book.art("al-1")
        while started.value == 0 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(50))
        await gate.release()
        #expect(await first == art)
        #expect(await second == art)
        #expect(asked.value == ["al-1"])
        // Kept: no second call.
        #expect(await book.art("al-1") == art)
        #expect(asked.value == ["al-1"])
    }

    @Test func noneIsKeptToo() async {
        let calls = Shared(0)
        let book = AnimatedArtBook(offered: { true }, ask: { _ in
            calls.change { $0 += 1 }
            return .none
        })
        #expect(await book.art("al-1") == nil)
        #expect(await book.art("al-1") == nil)
        #expect(calls.value == 1)
        #expect(book.peek("al-1") == .hasNone)
    }

    @Test func anOutageIsNotKeptAndTheAlbumIsAskedAgainLater() async {
        let clock = Shared<Int64>(0)
        let answer = Shared(AnimatedArtAnswer.notNow)
        let calls = Shared(0)
        let book = AnimatedArtBook(offered: { true }, ask: { _ in
            calls.change { $0 += 1 }
            return answer.value
        }, now: { clock.value })
        #expect(await book.art("al-1") == nil)
        #expect(book.peek("al-1") == .unknown)
        // Left alone for a while.
        #expect(await book.art("al-1") == nil)
        #expect(calls.value == 1)
        clock.value += animatedNotNowPauseMs + 1
        answer.value = .found(art)
        #expect(await book.art("al-1") == art)
        #expect(calls.value == 2)
    }

    @Test func aServerWithoutTheExtensionIsNeverAsked() async {
        let calls = Shared(0)
        let checks = Shared(0)
        let art = self.art
        let book = AnimatedArtBook(offered: {
            checks.change { $0 += 1 }
            return false
        }, ask: { _ in
            calls.change { $0 += 1 }
            return .found(art)
        })
        #expect(await book.art("al-1") == nil)
        #expect(await book.art("al-2") == nil)
        #expect(calls.value == 0)
        #expect(checks.value == 1)
    }

    @Test func aServerWithArtOffIsLeftAloneForAWhile() async {
        let clock = Shared<Int64>(0)
        let calls = Shared(0)
        let book = AnimatedArtBook(offered: { true }, ask: { _ in
            calls.change { $0 += 1 }
            return .off
        }, now: { clock.value })
        #expect(await book.art("al-1") == nil)
        #expect(await book.art("al-2") == nil)
        #expect(calls.value == 1)
        clock.value += animatedServerOffPauseMs + 1
        #expect(await book.art("al-2") == nil)
        #expect(calls.value == 2)
    }

    @Test func aServerThatCouldNotSayIsCheckedAgainAMinuteLater() async {
        let clock = Shared<Int64>(0)
        let listed = Shared<Bool?>(nil)
        let calls = Shared(0)
        let art = self.art
        let book = AnimatedArtBook(offered: { listed.value }, ask: { _ in
            calls.change { $0 += 1 }
            return .found(art)
        }, now: { clock.value })
        #expect(await book.art("al-1") == nil)
        listed.value = true
        #expect(await book.art("al-1") == nil)
        clock.value += animatedServerUnknownPauseMs + 1
        #expect(await book.art("al-1") == art)
        #expect(calls.value == 1)
    }

    @Test func artFromGetAlbumIsUsedWithoutAsking() async {
        let calls = Shared(0)
        let book = AnimatedArtBook(offered: { true }, ask: { _ in
            calls.change { $0 += 1 }
            return .none
        })
        book.note("al-1", art)
        #expect(book.peek("al-1") == .has(art))
        #expect(await book.art("al-1") == art)
        // getAlbum without art says nothing.
        book.note("al-2", nil)
        #expect(book.peek("al-2") == .unknown)
        #expect(calls.value == 0)
    }

    @Test func theNextSongsAlbumIsAskedAhead() async {
        let asked = Shared<[String]>([])
        let art = self.art
        let book = AnimatedArtBook(offered: { true }, ask: { id in
            asked.change { $0.append(id) }
            return .found(art)
        })
        await book.ahead(albumsToAsk(playing: "al-now", next: ["al-next", "al-later"])).value
        #expect(asked.value.sorted() == ["al-next", "al-now"])
        #expect(book.peek("al-next") == .has(art))
        // Known albums are not asked again.
        await book.ahead(["al-now", "al-next"]).value
        #expect(asked.value.count == 2)
    }

    @Test func eachAnswerCountsAndTells() async {
        let told = Shared(0)
        let book = AnimatedArtBook(offered: { true }, ask: { _ in .none })
        book.changed = { told.change { $0 += 1 } }
        _ = await book.art("al-1")
        book.note("al-2", art)
        #expect(book.version == 2)
        #expect(told.value == 2)
    }

    @Test func onlyTheLatestAlbumsAreKept() {
        let book = AnimatedArtBook(offered: { true }, ask: { _ in .none })
        for i in 0...AnimatedArtBook.kept { book.note("al-\(i)", art) }
        #expect(book.peek("al-0") == .unknown)
        #expect(book.peek("al-1") == .has(art))
        #expect(book.peek("al-\(AnimatedArtBook.kept)") == .has(art))
    }

    @Test func theSettingDecidesWhereTheLoopGoes() {
        let tall = AnimatedClip(video: "https://cdn.example.com/t.m3u8")
        var both = art
        both.tall = tall
        #expect(AnimatedArtSetting.square.inPlayer(both) == .cover(art.square!))
        #expect(AnimatedArtSetting.fullScreen.inPlayer(both) == .backdrop(tall))
        // No tall loop: full screen falls back to the square one.
        #expect(AnimatedArtSetting.fullScreen.inPlayer(art) == .cover(art.square!))
        #expect(AnimatedArtSetting.off.inPlayer(both) == .none)
        #expect(AnimatedArtSetting.square.inPlayer(AnimatedArt(tall: tall)) == .none)
        #expect(AnimatedArtSetting.square.inPlayer(nil) == .none)
        #expect(AnimatedArtSetting.fullScreen.onAlbumPage(both) == art.square)
        #expect(AnimatedArtSetting.off.onAlbumPage(both) == nil)
        #expect(AnimatedArtSetting.from(key: nil) == .square)
        #expect(AnimatedArtSetting.from(key: "full_screen") == .fullScreen)
        #expect(AnimatedArtSetting.from(key: "spinning") == .square)
        #expect(AnimatedArtSetting.prefKey == "animated_art")
        #expect(AnimatedArtSetting.allCases.map(\.key) == ["square", "full_screen", "off"])
    }

    @Test func noWordForMovementIsUsed() {
        let words = ([AnimatedArtSetting.title, AnimatedArtSetting.about]
            + AnimatedArtSetting.allCases.flatMap { [$0.label, $0.detail] }).joined(separator: " ").lowercased()
        #expect(!words.contains("moving"))
        #expect(!words.contains("motion"))
    }

    @Test func aLoopPlaysOnlyWhenSeen() {
        #expect(loopPlay(seen: true, powerSave: false, reduceMotion: false) == .play)
        #expect(loopPlay(seen: false, powerSave: false, reduceMotion: false) == .hold)
        #expect(loopPlay(seen: true, powerSave: true, reduceMotion: false) == .hold)
        #expect(loopPlay(seen: true, powerSave: false, reduceMotion: true) == .stillOnly)
    }

    @Test func wordsOverALightShadeAreDark() {
        // Short n' Sweet's pink, and a pale blue: white cannot be read on them.
        #expect(loopShadeInk(0xFFE6_B0C8).dark)
        #expect(loopShadeInk(0xFFBF_D9F2).dark)
        // A dark brown and a deep blue keep white words.
        #expect(!loopShadeInk(0xFF1A_0904).dark)
        #expect(!loopShadeInk(0xFF1B_2A6B).dark)
    }

    @Test func aSongsAlbumIsAskedForByTheServersOwnId() {
        let here = "server:192.168.50.119:5294"
        // The queue's library id for the album: the server's id without the source.
        #expect(animatedAlbum("\(here):599sUgxg94Qb416qnZCpE3", serverInUse: here) == .server("599sUgxg94Qb416qnZCpE3"))
        // An id as the server hands it is its own.
        #expect(animatedAlbum("599sUgxg94Qb416qnZCpE3", serverInUse: here) == .server("599sUgxg94Qb416qnZCpE3"))
        // Another server's album is never sent to this one.
        #expect(animatedAlbum("server:music.example.com:al-1", serverInUse: here) == .none)
        // An album the library made, or the phone's, is found through its songs.
        #expect(animatedAlbum("\(here):album:abc", serverInUse: here) == .lookUp)
        #expect(animatedAlbum("device:al-9", serverInUse: here) == .lookUp)
        // No server, no album: nothing is asked.
        #expect(animatedAlbum("al-1", serverInUse: nil) == .none)
        #expect(animatedAlbum(nil, serverInUse: here) == .none)
        #expect(animatedAlbum(" ", serverInUse: here) == .none)
    }

    @Test func theAlbumsToAskAreThePlayingOnesThenTheNext() {
        #expect(albumsToAsk(playing: "a", next: ["b", "c"]) == ["a", "b"])
        #expect(albumsToAsk(playing: "a", next: ["a", "c"], ahead: 2) == ["a", "c"])
        #expect(albumsToAsk(playing: nil, next: [" ", nil, "c"], ahead: 3) == ["c"])
    }
}
