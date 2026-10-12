import Foundation
import Testing
@testable import OctoKit

/// A folder of its own under the system's temporary folder, for one test.
func lyricsFolder() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("octo-test-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A clock a test moves by hand.
final class LyricsTestClock: @unchecked Sendable {
    var now = 1_000_000
}

struct LyricsOffline: Error {}

// What a lyrics lookup saves: "none" only when every source answered, and nothing at all when
// the lookup could not finish.
@MainActor
@Suite final class LyricsAnswersTest {
    let clock = LyricsTestClock()
    let cache = LyricsCache(lyricsFolder())
    lazy var answers = LyricsAnswers(cache) { [clock] in clock.now }
    var searches = 0
    let words = Lyrics(synced: true, lines: [LyricLine(startMs: 0, text: "Hello")], source: .server)
    let none = LyricsSearch(nil, complete: true, askedOnline: false)

    func ask(resumed: Bool = false, away: Bool = false, _ search: () async throws -> LyricsSearch) async throws -> LyricsAnswer {
        try await answers.answer("song", picked: nil, onlineAllowed: false, resumed: resumed, away: { away }) {
            searches += 1
            return try await search()
        }
    }

    @Test func anUnreachableSourceSavesNoNone() async throws {
        #expect(try await ask { throw LyricsOffline() } == .failed)
        #expect(cache.read("song") == nil)
        _ = try await ask { none }
        #expect(searches == 2)
    }

    @Test func aSearchWithASourceThatFailedSavesNoNone() async throws {
        #expect(try await ask { LyricsSearch(nil, complete: false, askedOnline: true) } == .failed)
        #expect(cache.read("song") == nil)
    }

    @Test func aTimedOutLookupSavesNoNone() async throws {
        #expect(try await ask { throw URLError(.timedOut) } == .failed)
        #expect(cache.read("song") == nil)
    }

    @Test func aCancelledLookupSavesNothing() async {
        let answers = self.answers
        let lookup = Task {
            try await answers.answer("song", picked: nil, onlineAllowed: false, resumed: false, away: { false }) {
                try await Task.sleep(for: .seconds(30))
                return LyricsSearch(nil, complete: true, askedOnline: false)
            }
        }
        lookup.cancel()
        let result = await lookup.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(cache.read("song") == nil)
    }

    @Test func aFailureLeavesTheOlderAnswerAsItWas() async throws {
        _ = try await ask { none }
        let first = cache.read("song")
        clock.now += NONE_FOUND_FOR_MS + 1
        #expect(try await ask { throw LyricsOffline() } == .failed)
        #expect(cache.read("song") == first)
    }

    @Test func aRealNoneIsStillSavedForADay() async throws {
        #expect(try await ask { none } == .none)
        let saved = cache.read("song")
        #expect(saved?.lyrics == nil)
        #expect(saved?.unsure == false)
        clock.now += NONE_FOUND_FOR_MS - 1
        #expect(try await ask { throw LyricsOffline() } == .none)
        #expect(searches == 1)
        clock.now += 2
        _ = try await ask { none }
        #expect(searches == 2)
    }

    @Test func foundLyricsAreSaved() async throws {
        #expect(try await ask { LyricsSearch(words, complete: true, askedOnline: false) } == .found(words))
        #expect(cache.read("song")?.lyrics == words)
    }

    @Test func aServerNoneThatMayHaveRunOutOfTimeIsBelievedBriefly() async throws {
        var unsure = none
        unsure.unsure = true
        #expect(try await ask { unsure } == .none)
        #expect(cache.read("song")?.unsure == true)
        clock.now += SHORT_NONE_FOR_MS - 1
        _ = try await ask { throw LyricsOffline() }
        #expect(searches == 1)
        clock.now += 2
        _ = try await ask { LyricsSearch(words, complete: true, askedOnline: false) }
        #expect(searches == 2)
    }

    @Test func aNoneFoundWhileAwayIsAskedAgainOnReturn() async throws {
        _ = try await ask(away: true) { none }
        #expect(cache.read("song")?.away == true)
        _ = try await ask { throw LyricsOffline() }
        #expect(searches == 1)
        #expect(try await ask(resumed: true) { LyricsSearch(words, complete: true, askedOnline: false) } == .found(words))
        #expect(searches == 2)
    }

    @Test func aNoneFoundOnScreenIsNotAskedAgainOnReturn() async throws {
        _ = try await ask { none }
        _ = try await ask(resumed: true) { throw LyricsOffline() }
        #expect(searches == 1)
    }

    @Test func lyricsFoundWhileAwayStandOnReturn() async throws {
        _ = try await ask(away: true) { LyricsSearch(words, complete: true, askedOnline: false) }
        #expect(try await ask(resumed: true) { throw LyricsOffline() } == .found(words))
        #expect(searches == 1)
    }
}

// Lyrics files beside a song, and the saved answers on the phone.
@Suite struct LyricsStorageTest {
    @Test func lyricsFilesShareTheSongsName() {
        #expect(lyricsFileNames("01 Song.flac") == ["01 Song.lrc", "01 Song.LRC"])
        #expect(lyricsFileNames("a.b.mp3") == ["a.b.lrc", "a.b.LRC"])
        #expect(lyricsFileNames("noextension").isEmpty)
    }

    @Test func filesThatAreNotUtf8AreReadAsLatin() {
        #expect(decodeText(Array("Café".utf8)) == "Café")
        #expect(decodeText([0x43, 0x61, 0x66, 0xE9]) == "Café")
        #expect(decodeText([0x93, 0x48, 0x69, 0x94]) == "\u{201C}Hi\u{201D}")
    }

    @Test func aLyricsFileBesideTheSongIsRead() throws {
        let folder = lyricsFolder()
        try Data("[00:01.00]hello".utf8).write(to: folder.appendingPathComponent("01 Song.lrc"))
        #expect(lyricsFileBeside(folder.appendingPathComponent("01 Song.flac")) == "[00:01.00]hello")
        #expect(lyricsFileBeside(folder.appendingPathComponent("02 Other.flac")) == nil)
    }

    @Test func serverLyricsWithoutWordsAreAskedAgain() {
        let lines = Lyrics(synced: true, lines: [LyricLine(startMs: 1_000, text: "line")], source: .server)
        var words = lines
        words.lines = [LyricLine(startMs: 1_000, text: "word", words: [LyricWord(startMs: 1_000, endMs: nil, text: "word", from: 0, to: 4)])]
        let fresh = CachedLyrics(savedAt: 0, lyrics: lines, askedOnline: true, lookupVersion: ONLINE_LOOKUP_VERSION)
        var old = fresh
        old.lookupVersion = 3
        #expect(!old.stillGood(now: 1, onlineAllowed: true))
        #expect(fresh.stillGood(now: SERVER_RECHECK_MS - 1, onlineAllowed: true))
        #expect(!fresh.stillGood(now: SERVER_RECHECK_MS, onlineAllowed: true))
        var worded = fresh
        worded.lyrics = words
        worded.lookupVersion = 3
        #expect(worded.stillGood(now: 365 * NONE_FOUND_FOR_MS, onlineAllowed: true))
        var songFile = fresh
        songFile.lyrics?.source = .songFile
        #expect(songFile.stillGood(now: 365 * NONE_FOUND_FOR_MS, onlineAllowed: true))
    }

    @Test func cachedAnswersKeepAndExpire() {
        let cache = LyricsCache(lyricsFolder())
        let lyrics = Lyrics(synced: true, lines: [LyricLine(startMs: 1_000, text: "Café 日本")], source: .songFile)
        cache.write("device:1", CachedLyrics(savedAt: 0, lyrics: lyrics))
        #expect(cache.read("device:1")?.lyrics == lyrics)
        #expect(cache.read("find:other") == nil)

        #expect(CachedLyrics(savedAt: 0, lyrics: lyrics).stillGood(now: 365 * NONE_FOUND_FOR_MS, onlineAllowed: true))

        let none = CachedLyrics(savedAt: 0, lyrics: nil, askedOnline: true)
        #expect(none.stillGood(now: NONE_FOUND_FOR_MS - 1, onlineAllowed: true))
        #expect(!none.stillGood(now: NONE_FOUND_FOR_MS, onlineAllowed: true))

        let offlineNone = CachedLyrics(savedAt: 0, lyrics: nil, askedOnline: false)
        #expect(offlineNone.stillGood(now: 1, onlineAllowed: false))
        #expect(!offlineNone.stillGood(now: 1, onlineAllowed: true))
        var plain = lyrics
        plain.synced = false
        #expect(!CachedLyrics(savedAt: 0, lyrics: plain, askedOnline: false).stillGood(now: 1, onlineAllowed: true))

        let oldPlain = CachedLyrics(savedAt: 0, lyrics: plain, askedOnline: true)
        #expect(!oldPlain.stillGood(now: 1, onlineAllowed: true))
        var newPlain = oldPlain
        newPlain.lookupVersion = ONLINE_LOOKUP_VERSION
        #expect(newPlain.stillGood(now: 1, onlineAllowed: true))

        var onlineWords = lyrics
        onlineWords.source = .online
        let looseOnline = CachedLyrics(savedAt: 0, lyrics: onlineWords, askedOnline: true, lookupVersion: 2)
        #expect(!looseOnline.stillGood(now: 1, onlineAllowed: true))
        var current = looseOnline
        current.lookupVersion = ONLINE_LOOKUP_VERSION
        #expect(current.stillGood(now: 1, onlineAllowed: true))
        var fileWords = looseOnline
        fileWords.lyrics = lyrics
        #expect(fileWords.stillGood(now: 1, onlineAllowed: true))
    }

    @Test func savedAnswersAreNamedBySha1() {
        #expect(SHA1.hex("abc") == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(SHA1.hex("") == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    }

    @Test func droppingASongsAnswerLooksItUpAgain() {
        let cache = LyricsCache(lyricsFolder())
        let entry = CachedLyrics(savedAt: 1, lyrics: Lyrics(synced: true, lines: [LyricLine(startMs: 1_000, text: "pinned")], source: .server, serverPick: "kugou:1"), askedOnline: true)
        cache.write("s", entry)
        cache.write("other", entry)
        #expect(cache.read("s")?.lyrics?.serverPick == "kugou:1")
        cache.drop("s")
        #expect(cache.read("s") == nil)
        #expect(cache.read("other") == entry)
        cache.drop("never")
    }
}
