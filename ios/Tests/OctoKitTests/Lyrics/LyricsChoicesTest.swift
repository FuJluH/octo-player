import Foundation
import Testing
@testable import OctoKit

@Suite struct LyricsChoicesTest {
    @Test func aSongNobodyChangedHasNoChoice() {
        #expect(LyricsChoices(MemoryValues()).current("lib:1") == LyricsChoice())
    }

    @Test func aPickIsKeptPerSongAcrossARestart() {
        let store = MemoryValues()
        let first = LyricsChoices(store)
        first.pick("lib:1", .online(4242))
        first.pick("lib:2", .own(.lyricsFile))
        let again = LyricsChoices(store)
        #expect(again.current("lib:1") == LyricsChoice(.online(4242)))
        #expect(again.current("lib:2") == LyricsChoice(.own(.lyricsFile)))
        #expect(again.current("lib:3") == LyricsChoice())
    }

    @Test func aNewPickReplacesTheLast() {
        let choices = LyricsChoices(MemoryValues())
        choices.pick("lib:1", .online(1))
        choices.pick("lib:1", .own(.server))
        #expect(choices.current("lib:1").pick == .own(.server))
    }

    @Test func hidingLastsAcrossARestartAndShowingKeepsThePick() {
        let store = MemoryValues()
        let first = LyricsChoices(store)
        first.pick("lib:1", .online(7))
        first.hide("lib:1")
        first.hide("lib:2")
        let again = LyricsChoices(store)
        #expect(again.current("lib:1") == LyricsChoice(.online(7), hidden: true))
        #expect(again.current("lib:2").hidden)
        again.show("lib:1")
        #expect(LyricsChoices(store).current("lib:1") == LyricsChoice(.online(7)))
        #expect(LyricsChoices(store).current("lib:2").hidden)
    }

    @Test func pickingLyricsForAHiddenSongShowsItAgain() {
        let choices = LyricsChoices(MemoryValues())
        choices.hide("lib:1")
        choices.pick("lib:1", .own(.songFile))
        #expect(choices.current("lib:1") == LyricsChoice(.own(.songFile)))
    }

    @Test func picksReadBackAsWritten() {
        let picks: [LyricsPick] = [.online(123), .own(.server), .own(.songFile), .own(.lyricsFile)]
        for pick in picks { #expect(decodePick(pick.encoded) == pick) }
        #expect(decodePick(nil) == nil)
        #expect(decodePick("online:abc") == nil)
        #expect(decodePick("own:Online") == nil)
        #expect(decodePick("own:Radio") == nil)
        #expect(decodePick("something") == nil)
    }

    @Test func lyricsNameTheirOwnPick() {
        let words = [LyricLine(text: "hi")]
        #expect(pickOf(Lyrics(synced: false, lines: words, source: .server)) == .own(.server))
        #expect(pickOf(Lyrics(synced: false, lines: words, source: .online, onlineId: 9)) == .online(9))
        #expect(pickOf(Lyrics(synced: false, lines: words, source: .online)) == nil)
    }

    @Test func aPickedAnswerStandsOnlyForItsPick() {
        let lyrics = Lyrics(synced: true, lines: [LyricLine(startMs: 0, text: "hi")], source: .online, onlineId: 5)
        let picked = CachedLyrics(savedAt: 0, lyrics: lyrics, askedOnline: true, lookupVersion: ONLINE_LOOKUP_VERSION, pick: "online:5")
        var usual = picked
        usual.pick = nil
        #expect(picked.standsFor("online:5", now: 0, onlineAllowed: true))
        #expect(!picked.standsFor("online:6", now: 0, onlineAllowed: true))
        #expect(!picked.standsFor(nil, now: 0, onlineAllowed: true))
        #expect(usual.standsFor(nil, now: 0, onlineAllowed: true))
        #expect(!usual.standsFor("online:5", now: 0, onlineAllowed: true))
        var empty = picked
        empty.lyrics = nil
        #expect(!empty.standsFor("online:5", now: 0, onlineAllowed: true))
    }
}

@Suite struct LyricsCandidatesTest {
    func timed(_ source: LyricsSource, _ words: String..., id: Int? = nil) -> Lyrics {
        Lyrics(synced: true, lines: words.enumerated().map { LyricLine(startMs: $0.offset * 1_000, text: $0.element) }, source: source, onlineId: id)
    }

    var server: LyricsCandidate { LyricsCandidate(.own(.server), .server, timed(.server, "server")) }
    var songFile: LyricsCandidate { LyricsCandidate(.own(.songFile), .songFile, timed(.songFile, "tag")) }
    var lrcFile: LyricsCandidate { LyricsCandidate(.own(.lyricsFile), .lyricsFile, timed(.lyricsFile, "lrc")) }

    func online(_ id: Int, _ origin: CandidateOrigin, _ words: String) -> LyricsCandidate {
        LyricsCandidate(.online(id), origin, timed(.online, words, id: id), title: "Song", artist: "Artist")
    }

    var match: LyricsCandidate { online(10, .onlineMatch, "match") }
    var searchA: LyricsCandidate { online(11, .onlineSearch, "search a") }
    var searchB: LyricsCandidate { online(12, .onlineSearch, "search b") }

    @Test func theSourcesComeInOrderWhateverOrderTheyArrive() {
        let list = candidateList([searchA, match, searchB, lrcFile, songFile, server], current: nil, showing: nil)
        #expect(list.items.map(\.pick) == [server, songFile, lrcFile, match, searchA, searchB].map(\.pick))
        #expect(list.showing == -1)
    }

    @Test func theChosenOneComesFirst() {
        let list = candidateList([server, songFile, lrcFile, match, searchA, searchB], current: .online(12), showing: searchB.lyrics)
        #expect(list.items.map(\.pick) == [searchB, server, songFile, lrcFile, match, searchA].map(\.pick))
        #expect(list.showing == 0)
    }

    @Test func withoutAKnownPickTheShowingLyricsAreFoundByTheirWords() {
        let showing = timed(.online, "search a")
        let list = candidateList([server, match, searchA], current: nil, showing: showing)
        #expect(list.items.map(\.pick) == [searchA, server, match].map(\.pick))
        #expect(list.showing == 0)
    }

    @Test func aCopyFoundTwiceShowsOnce() {
        let again = online(10, .onlineSearch, "match")
        var sameAsServer = lrcFile
        sameAsServer.lyrics = timed(.lyricsFile, "server")
        let duplicateRecord = online(13, .onlineSearch, "match")
        let list = candidateList([again, server, sameAsServer, match, duplicateRecord, searchA], current: nil, showing: nil)
        #expect(list.items.map(\.pick) == [server, match, searchA].map(\.pick))
        #expect(list.items[1].origin == .onlineMatch)
    }

    @Test func theShowingLyricsStayInTheListWhenNoSourceOffersThem() {
        let showing = timed(.online, "picked before", id: 99)
        let list = candidateList([server, songFile], current: .online(99), showing: showing)
        #expect(list.items.map(\.pick) == [.online(99), server.pick, songFile.pick])
        #expect(list.items.first?.origin == .onlineMatch)
        #expect(list.showing == 0)
    }

    @Test func lyricsWithNoWordsAreLeftOut() {
        var empty = songFile
        empty.lyrics = Lyrics(synced: false, lines: [LyricLine(text: " ")], source: .songFile)
        #expect(candidateList([empty, server], current: nil, showing: nil).items.map(\.pick) == [server.pick])
    }

    @Test func thePreviewIsTheFirstTwoLinesWithWords() {
        let lyrics = Lyrics(synced: true, lines: [
            LyricLine(startMs: 0, text: ""), LyricLine(startMs: 1, text: " One "), LyricLine(startMs: 2, text: "Two"), LyricLine(startMs: 3, text: "Three"),
        ], source: .server)
        var candidate = server
        candidate.lyrics = lyrics
        #expect(candidate.preview == ["One", "Two"])
    }
}
